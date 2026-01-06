import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../widgets/control_button.dart';
import '../config/constants.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _ipController = TextEditingController();
  String _status = "Disconnected";
  bool _isConnected = false;
  bool _isBackgroundRunning = false;
  WebSocketChannel? _channel;
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _loadIp();
    _requestPermissions();
    _checkServiceStatus();
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    const initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
    await _notificationsPlugin.initialize(initializationSettings);
  }

  Future<void> _showNotification(String title, String body) async {
    await _notificationsPlugin.show(
      0,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          notificationChannelId,
          'Bike Light Alerts',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
    );
  }

  Future<void> _requestPermissions() async {
    await Permission.notification.request();
  }

  Future<void> _loadIp() async {
    final prefs = await SharedPreferences.getInstance();
    _ipController.text = prefs.getString('saved_ip') ?? '192.168.4.1';
  }

  Future<void> _saveIp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_ip', _ipController.text);
  }

  Future<void> _checkServiceStatus() async {
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    setState(() {
      _isBackgroundRunning = isRunning;
      if (isRunning) {
        _status = "Background Service Running";
      }
    });
  }

  /// Connect button - direct WebSocket connection with status display
  void _connect() {
    _saveIp();
    setState(() {
      _status = "Connecting...";
    });
    try {
      _channel = IOWebSocketChannel.connect('ws://${_ipController.text}:81');
      setState(() {
        _isConnected = true;
        _status = "Connected (Foreground)";
      });

      _channel!.stream.listen(
        (message) {
          // Parse JSON and check for NOTIFICATION status
          try {
            final data = jsonDecode(message);
            if (data['status'] == 'NOTIFICATION') {
              _showNotification('Bike Alert', 'Notification received!');
            }
            setState(() {
              _status = "Status: ${data['status']}";
            });
          } catch (e) {
            setState(() {
              _status = "Connected: $message";
            });
          }
          print("Received message: $message");
        },
        onError: (e) {
          setState(() {
            _status = "Error: $e";
            _isConnected = false;
          });
        },
        onDone: () {
          setState(() {
            _status = "Connection closed";
            _isConnected = false;
          });
        },
      );
    } catch (e) {
      setState(() {
        _status = "Exception: $e";
        _isConnected = false;
      });
    }
  }

  /// Background button - starts background service for persistent connection
  Future<void> _startBackground() async {
    await _saveIp();

    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();

    if (!isRunning) {
      await service.startService();
    }

    setState(() {
      _isBackgroundRunning = true;
      _isConnected = true;
      _status = "Background Service Started";
    });
  }

  /// Disconnect button - stops both foreground and background connections
  Future<void> _disconnect() async {
    // Stop background service
    final service = FlutterBackgroundService();
    service.invoke("stopService");

    // Close foreground connection
    _channel?.sink.close();
    _channel = null;

    setState(() {
      _isConnected = false;
      _isBackgroundRunning = false;
      _status = "Disconnected";
    });
  }

  /// Send command via foreground channel
  void _sendCommand(String cmd) {
    if (_channel != null) {
      _channel!.sink.add(cmd);
    }
    // Also send via background service if running
    if (_isBackgroundRunning) {
      final service = FlutterBackgroundService();
      service.invoke("sendCommand", {"command": cmd});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bike Light Remote')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // IP Address Input
            TextField(
              controller: _ipController,
              decoration: const InputDecoration(labelText: 'ESP IP Address', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),

            // Row 1: Connect and Disconnect buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isConnected ? null : _connect,
                    icon: const Icon(Icons.power),
                    label: const Text('Connect'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      disabledBackgroundColor: Colors.green.withValues(alpha: 0.3),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isConnected ? _disconnect : null,
                    icon: const Icon(Icons.power_off),
                    label: const Text('Disconnect'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      disabledBackgroundColor: Colors.red.withValues(alpha: 0.3),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Row 2: Background Service button
            ElevatedButton.icon(
              onPressed: _isBackgroundRunning ? null : _startBackground,
              icon: Icon(_isBackgroundRunning ? Icons.cloud_done : Icons.cloud_upload),
              label: Text(_isBackgroundRunning ? 'Background Running' : 'Start Background'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                disabledBackgroundColor: Colors.teal.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 20),

            // Status Display
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isConnected ? Colors.green.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _isConnected ? Icons.check_circle : Icons.cancel,
                        color: _isConnected ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Status: $_status',
                          style: TextStyle(
                            color: _isConnected ? Colors.green : Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_isBackgroundRunning) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.cloud_done, color: Colors.teal, size: 18),
                        const SizedBox(width: 8),
                        Text('Background Service Active', style: TextStyle(color: Colors.teal.shade300, fontSize: 12)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 30),

            // Controls Section
            const Text("Controls", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),

            // Turn signals
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ControlButton(label: 'LEFT', command: 'L', color: Colors.orange, onPressed: () => _sendCommand('L')),
                ControlButton(label: 'RIGHT', command: 'R', color: Colors.orange, onPressed: () => _sendCommand('R')),
              ],
            ),
            const SizedBox(height: 10),

            // Brake
            Row(
              children: [
                ControlButton(
                  label: 'BRAKE',
                  command: 'B',
                  color: Colors.red,
                  height: 60,
                  onPressed: () => _sendCommand('B'),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Idle and Warning
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ControlButton(label: 'IDLE', command: 'I', color: Colors.blueGrey, onPressed: () => _sendCommand('I')),
                ControlButton(label: 'WARN', command: 'W', color: Colors.purple, onPressed: () => _sendCommand('W')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ipController.dispose();
    _channel?.sink.close();
    super.dispose();
  }
}
