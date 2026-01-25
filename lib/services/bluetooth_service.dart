import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/constants.dart';

class BluetoothService {
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;
  Timer? _scanTimer;

  StreamController<bool>? _bluetoothStateController;
  StreamController<bool>? _karrassDetectedController;

  /// Ensure stream controllers are open, recreate if closed
  void _ensureControllersOpen() {
    if (_bluetoothStateController == null || _bluetoothStateController!.isClosed) {
      _bluetoothStateController = StreamController<bool>.broadcast();
    }
    if (_karrassDetectedController == null || _karrassDetectedController!.isClosed) {
      _karrassDetectedController = StreamController<bool>.broadcast();
    }
  }

  Stream<bool> get bluetoothStateStream {
    _ensureControllersOpen();
    return _bluetoothStateController!.stream;
  }

  Stream<bool> get karassDetectedStream {
    _ensureControllersOpen();
    return _karrassDetectedController!.stream;
  }

  bool _isScanning = false;
  bool _isAdvertising = false;
  bool _continuousScanning = false;

  // BLE Peripheral for advertising
  final FlutterBlePeripheral _blePeripheral = FlutterBlePeripheral();

  Future<void> init() async {
    // Ensure controllers are open
    _ensureControllersOpen();

    // Cancel any existing subscription before creating new one
    await _adapterSubscription?.cancel();

    // Listen to Bluetooth adapter state
    _adapterSubscription = FlutterBluePlus.adapterState.listen(
      (state) {
        final isOn = state == BluetoothAdapterState.on;
        _ensureControllersOpen();
        _bluetoothStateController?.add(isOn);

        // If Bluetooth turns off, stop scanning and advertising
        if (!isOn) {
          _stopScanLoop();
          stopBeaconing();
        }
      },
      onError: (e) {
        debugPrint('Bluetooth adapter state error: $e');
        _ensureControllersOpen();
        _bluetoothStateController?.add(false);
      },
    );
  }

  /// Request all necessary permissions for Bluetooth
  Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      // Android 12+ requires these permissions at runtime
      // Note: We use neverForLocation flag in AndroidManifest, so we don't need location permission
      final bluetoothScan = await Permission.bluetoothScan.request();
      final bluetoothConnect = await Permission.bluetoothConnect.request();
      final bluetoothAdvertise = await Permission.bluetoothAdvertise.request();

      final allGranted = bluetoothScan.isGranted &&
          bluetoothConnect.isGranted &&
          bluetoothAdvertise.isGranted;

      if (!allGranted) {
        debugPrint('Bluetooth permissions not fully granted');
        debugPrint('Scan: $bluetoothScan, Connect: $bluetoothConnect, Advertise: $bluetoothAdvertise');
      }

      return allGranted;
    } else if (Platform.isIOS) {
      // iOS handles Bluetooth permissions automatically via system prompts
      // when CBCentralManager/CBPeripheralManager is initialized.
      // We only need to request location permission explicitly.
      final location = await Permission.locationWhenInUse.request();

      if (!location.isGranted) {
        debugPrint('iOS: Location permission not granted: $location');
        return false;
      }

      // For Bluetooth on iOS, we return true and let the native code
      // trigger the Bluetooth permission dialog when needed
      return true;
    }
    return true;
  }

  /// Check if permissions are granted
  Future<bool> hasPermissions() async {
    if (Platform.isAndroid) {
      // No location needed on Android - we use neverForLocation flag
      return await Permission.bluetoothScan.isGranted &&
          await Permission.bluetoothConnect.isGranted &&
          await Permission.bluetoothAdvertise.isGranted;
    } else if (Platform.isIOS) {
      // On iOS, only check location. Bluetooth permission is handled by the system
      // automatically when we try to use CBCentralManager/CBPeripheralManager
      return await Permission.locationWhenInUse.isGranted;
    }
    return true;
  }

  Future<bool> isBluetoothOn() async {
    try {
      final state = await FlutterBluePlus.adapterState.first.timeout(
        const Duration(seconds: 5),
        onTimeout: () => BluetoothAdapterState.unknown,
      );
      return state == BluetoothAdapterState.on;
    } catch (e) {
      debugPrint('Error checking Bluetooth state: $e');
      return false;
    }
  }

  Future<bool> isSupported() async {
    return await FlutterBluePlus.isSupported;
  }

  Future<void> requestBluetoothOn() async {
    try {
      await FlutterBluePlus.turnOn();
    } catch (e) {
      debugPrint('Error turning on Bluetooth: $e');
    }
  }

  /// Start continuous scanning with automatic restart
  Future<void> startContinuousScanning() async {
    if (_continuousScanning) return;

    // Check and request permissions first
    if (!await hasPermissions()) {
      final granted = await requestPermissions();
      if (!granted) {
        debugPrint('Cannot start scanning - permissions not granted');
        return;
      }
    }

    _continuousScanning = true;
    await _startScanCycle();
  }

  /// Internal method to run one scan cycle
  Future<void> _startScanCycle() async {
    if (!_continuousScanning) return;

    await _doScan();

    // Schedule next scan after interval
    _scanTimer?.cancel();
    _scanTimer = Timer(BluetoothConfig.scanInterval, () {
      if (_continuousScanning) {
        _startScanCycle();
      }
    });
  }

  /// Perform a single scan
  Future<void> _doScan() async {
    if (_isScanning) return;
    _isScanning = true;

    try {
      debugPrint('Starting BLE scan...');

      // Cancel any existing subscription
      await _scanSubscription?.cancel();

      // Listen to scan results
      _scanSubscription = FlutterBluePlus.scanResults.listen(
        (results) {
          for (final result in results) {
            if (_isKarassBeacon(result)) {
              debugPrint('Karass beacon detected: ${result.device.platformName}');
              _ensureControllersOpen();
              _karrassDetectedController?.add(true);
              // Don't break - continue listening for more
            }
          }
        },
        onError: (e) {
          debugPrint('Scan results error: $e');
        },
      );

      // Start scanning
      await FlutterBluePlus.startScan(
        timeout: BluetoothConfig.scanDuration,
        androidUsesFineLocation: true,
      );

      debugPrint('Scan completed');
    } catch (e) {
      debugPrint('Scan error: $e');
    } finally {
      _isScanning = false;
    }
  }

  /// Legacy method - starts a single scan (for backward compatibility)
  Future<void> startScanning() async {
    await startContinuousScanning();
  }

  /// Stop continuous scanning
  Future<void> stopScanning() async {
    _stopScanLoop();
  }

  void _stopScanLoop() {
    _continuousScanning = false;
    _scanTimer?.cancel();
    _scanTimer = null;

    try {
      FlutterBluePlus.stopScan();
    } catch (e) {
      debugPrint('Error stopping scan: $e');
    }

    _scanSubscription?.cancel();
    _scanSubscription = null;
    _isScanning = false;
  }

  bool _isKarassBeacon(ScanResult result) {
    // Check for our custom service UUID in advertised services
    for (final serviceUuid in result.advertisementData.serviceUuids) {
      if (serviceUuid.toString().toLowerCase() == BluetoothConfig.serviceUuid.toLowerCase()) {
        debugPrint('Found Karass beacon by UUID: ${result.device.platformName}');
        return true;
      }
    }

    // Alternative: Check device name for "Karass" prefix
    final name = result.device.platformName.toLowerCase();
    if (name.contains('karass')) {
      debugPrint('Found Karass beacon by name: $name');
      return true;
    }

    // Check local name in advertisement data
    final localName = result.advertisementData.advName.toLowerCase();
    if (localName.contains('karass')) {
      debugPrint('Found Karass beacon by local name: $localName');
      return true;
    }

    return false;
  }

  /// Start BLE advertising (beaconing)
  Future<void> startBeaconing() async {
    if (_isAdvertising) return;

    // Check and request permissions first
    if (!await hasPermissions()) {
      final granted = await requestPermissions();
      if (!granted) {
        debugPrint('Cannot start beaconing - permissions not granted');
        return;
      }
    }

    try {
      // Check if peripheral mode is supported
      final isSupported = await _blePeripheral.isSupported;
      if (!isSupported) {
        debugPrint('BLE Peripheral mode not supported on this device');
        return;
      }

      // Create advertisement data
      final advertiseData = AdvertiseData(
        serviceUuid: BluetoothConfig.serviceUuid,
        localName: 'Karass',
        includePowerLevel: true,
      );

      // Start advertising
      await _blePeripheral.start(
        advertiseData: advertiseData,
        advertiseSettings: AdvertiseSettings(
          advertiseMode: AdvertiseMode.advertiseModeLowLatency,
          txPowerLevel: AdvertiseTxPower.advertiseTxPowerHigh,
          connectable: false,
          timeout: 0, // Advertise indefinitely
        ),
      );

      _isAdvertising = true;
      debugPrint('BLE advertising started with UUID: ${BluetoothConfig.serviceUuid}');
    } catch (e) {
      debugPrint('Error starting BLE advertising: $e');
      _isAdvertising = false;
    }
  }

  /// Stop BLE advertising
  Future<void> stopBeaconing() async {
    if (!_isAdvertising) return;

    try {
      await _blePeripheral.stop();
      _isAdvertising = false;
      debugPrint('BLE advertising stopped');
    } catch (e) {
      debugPrint('Error stopping BLE advertising: $e');
    }
  }

  bool get isScanning => _isScanning || _continuousScanning;
  bool get isBeaconing => _isAdvertising;

  /// Pause scanning (for app lifecycle)
  Future<void> pause() async {
    await stopScanning();
    await stopBeaconing();
  }

  /// Resume scanning (for app lifecycle)
  Future<void> resume() async {
    // Let the caller decide whether to resume scanning/beaconing
  }

  Future<void> dispose() async {
    _stopScanLoop();
    await stopBeaconing();
    await _adapterSubscription?.cancel();
    _adapterSubscription = null;
    await _bluetoothStateController?.close();
    await _karrassDetectedController?.close();
    _bluetoothStateController = null;
    _karrassDetectedController = null;
  }
}
