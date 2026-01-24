/**
 * Firebase Cloud Messaging service
 */

const fs = require('fs');
const path = require('path');
const https = require('https');
const { google } = require('googleapis');

const FCM_PROJECT_ID = 'karass-b41bc';
const SERVICE_ACCOUNT_PATH = path.join(__dirname, '..', 'service-account.json');

/**
 * Get OAuth2 access token for FCM
 */
async function getAccessToken() {
  if (!fs.existsSync(SERVICE_ACCOUNT_PATH)) {
    console.log('Warning: service-account.json not found. Push notifications disabled.');
    return null;
  }

  const serviceAccount = JSON.parse(fs.readFileSync(SERVICE_ACCOUNT_PATH, 'utf8'));
  const jwtClient = new google.auth.JWT(
    serviceAccount.client_email,
    null,
    serviceAccount.private_key,
    ['https://www.googleapis.com/auth/firebase.messaging']
  );

  const tokens = await jwtClient.authorize();
  return tokens.access_token;
}

/**
 * Send FCM push notification to a topic
 */
async function sendPushToTopic(topic, title, body, data = {}) {
  const accessToken = await getAccessToken();
  if (!accessToken) return false;

  const message = {
    message: {
      topic: topic,
      notification: {
        title: title,
        body: body
      },
      data: {
        ...data,
        type: 'announcement'
      },
      android: {
        priority: 'high',
        notification: {
          channel_id: 'announcement_channel'
        }
      },
      apns: {
        payload: {
          aps: {
            alert: {
              title: title,
              body: body
            },
            sound: 'default'
          }
        }
      }
    }
  };

  return new Promise((resolve) => {
    const postData = JSON.stringify(message);

    const options = {
      hostname: 'fcm.googleapis.com',
      port: 443,
      path: `/v1/projects/${FCM_PROJECT_ID}/messages:send`,
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(postData)
      }
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => {
        if (res.statusCode === 200) {
          console.log('Push notification sent successfully');
          resolve(true);
        } else {
          console.log('FCM response:', res.statusCode, data);
          resolve(false);
        }
      });
    });

    req.on('error', (e) => {
      console.error('FCM error:', e.message);
      resolve(false);
    });

    req.write(postData);
    req.end();
  });
}

module.exports = {
  getAccessToken,
  sendPushToTopic
};
