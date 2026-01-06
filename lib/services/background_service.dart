import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/constants.dart';

/// Initialize the background service
Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    notificationChannelId,
    'Bike Light Service',
    description: 'Running in background to listen for bike signals',
    importance: Importance.low,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false, // User starts manually via Connect button
      isForegroundMode: true,
      notificationChannelId: notificationChannelId,
      initialNotificationTitle: 'Bike Light Service',
      initialNotificationContent: 'Listening for signals...',
      foregroundServiceNotificationId: notificationId,
    ),
    iosConfiguration: IosConfiguration(),
  );
}

/// Background service entry point
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Ensure Flutter bindings are initialized in background isolate
  DartPluginRegistrant.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  String ip = prefs.getString('saved_ip') ?? '192.168.4.1';
  String url = 'ws://$ip:81';

  WebSocketChannel? channel;

  // Initialize notifications plugin in background
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  // Initialize the plugin for Android
  const initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  Future<void> showNotification(String title, String body) async {
    await flutterLocalNotificationsPlugin.show(
      0,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          notificationChannelId,
          'Bike Light Alerts',
          importance: Importance.max,
          priority: Priority.high,
          ticker: 'ticker',
        ),
      ),
    );
  }

  void connect() {
    try {
      channel = IOWebSocketChannel.connect(url);

      channel!.stream.listen(
        (message) {
          if (service is AndroidServiceInstance) {
            try {
              final data = jsonDecode(message);
              if (data['status'] != null) {
                String status = data['status'];
                service.setForegroundNotificationInfo(title: 'Bike Light: $status', content: 'Connected to $ip');

                if (status == 'BRAKE' || status == 'TURN_LEFT' || status == 'TURN_RIGHT') {
                  showNotification('Bike Alert', 'Signal: $status');
                }
              }
            } catch (e) {
              // Not JSON
            }
          }
        },
        onError: (e) {
          // Retry logic could go here
        },
        onDone: () {
          // Reconnect logic
        },
      );
    } catch (e) {
      // Handle connection error
    }
  }

  connect();

  service.on('stopService').listen((event) {
    channel?.sink.close();
    service.stopSelf();
  });

  service.on('sendCommand').listen((event) {
    if (channel != null && event != null) {
      channel!.sink.add(jsonEncode(event));
    }
  });
}
