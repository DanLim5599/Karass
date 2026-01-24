import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../config/constants.dart';

class BluetoothService {
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;

  final StreamController<bool> _bluetoothStateController = StreamController<bool>.broadcast();
  final StreamController<bool> _karrassDetectedController = StreamController<bool>.broadcast();

  Stream<bool> get bluetoothStateStream => _bluetoothStateController.stream;
  Stream<bool> get karassDetectedStream => _karrassDetectedController.stream;

  bool _isScanning = false;
  bool _isAdvertising = false;

  Future<void> init() async {
    // Listen to Bluetooth adapter state
    _adapterSubscription = FlutterBluePlus.adapterState.listen(
      (state) {
        _bluetoothStateController.add(state == BluetoothAdapterState.on);
      },
      onError: (e) {
        // Emit false on error - Bluetooth unavailable
        _bluetoothStateController.add(false);
      },
    );
  }

  Future<bool> isBluetoothOn() async {
    try {
      final state = await FlutterBluePlus.adapterState.first.timeout(
        const Duration(seconds: 5),
        onTimeout: () => BluetoothAdapterState.unknown,
      );
      return state == BluetoothAdapterState.on;
    } catch (e) {
      // Return false if we can't determine Bluetooth state
      return false;
    }
  }

  Future<bool> isSupported() async {
    return await FlutterBluePlus.isSupported;
  }

  Future<void> requestBluetoothOn() async {
    await FlutterBluePlus.turnOn();
  }

  Future<void> startScanning() async {
    if (_isScanning) return;
    _isScanning = true;

    try {
      // Start scanning for devices
      await FlutterBluePlus.startScan(
        timeout: BluetoothConfig.scanDuration,
        androidUsesFineLocation: true,
      );

      // Listen to scan results
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (final result in results) {
          // Check if this is a Karass beacon
          if (_isKarassBeacon(result)) {
            _karrassDetectedController.add(true);
            break;
          }
        }
      });
    } catch (e) {
      _isScanning = false;
      rethrow;
    }
  }

  Future<void> stopScanning() async {
    await FlutterBluePlus.stopScan();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    _isScanning = false;
  }

  bool _isKarassBeacon(ScanResult result) {
    // Check for our custom service UUID in advertised services
    for (final serviceUuid in result.advertisementData.serviceUuids) {
      if (serviceUuid.toString().toLowerCase() == BluetoothConfig.serviceUuid.toLowerCase()) {
        return true;
      }
    }

    // Alternative: Check device name for "Karass" prefix
    final name = result.device.platformName.toLowerCase();
    if (name.contains('karass')) {
      return true;
    }

    // For MVP/testing: Consider any device with strong signal as potential Karass user
    // This can be removed in production
    // if (result.rssi > -50) {
    //   return true;
    // }

    return false;
  }

  // Advertising (beaconing) - Note: This requires platform-specific implementation
  // For iOS/Android BLE advertising, additional setup is needed
  Future<void> startBeaconing() async {
    if (_isAdvertising) return;
    _isAdvertising = true;

    // Note: flutter_blue_plus primarily supports central (scanning) mode
    // For full peripheral (advertising) support, consider using:
    // - flutter_ble_peripheral package
    // - Platform channels for native implementation

    // For MVP, we'll simulate beaconing status
    // In production, implement actual BLE advertising
  }

  Future<void> stopBeaconing() async {
    _isAdvertising = false;
  }

  bool get isScanning => _isScanning;
  bool get isBeaconing => _isAdvertising;

  Future<void> dispose() async {
    await stopScanning();
    await stopBeaconing();
    await _adapterSubscription?.cancel();
    await _bluetoothStateController.close();
    await _karrassDetectedController.close();
  }
}
