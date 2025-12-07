import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'widgets/chat_widget.dart';

void main() {
  runApp(const WheelchairDashboardApp());
}

class WheelchairDashboardApp extends StatelessWidget {
  const WheelchairDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wheelchair Dashboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0E27),
        fontFamily: 'monospace',
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Sensor values (in cm)
  double frontSensor = 0;
  double backSensor = 0;
  double leftSensor = 0;
  double rightSensor = 0;

  // Direction: 0=Stop, 1=Forward, 2=Backward, 3=Left, 4=Right
  int direction = 0;

  Timer? _timer;
  final Random _random = Random();

  // Serial port variables
  SerialPort? _port;
  StreamSubscription<Uint8List>? _serialSubscription;
  final List<Map<String, String>> _availablePorts = [];
  String _currentPort = '';
  bool _isConnected = false;
  String _serialBuffer = '';

  // Unit selection
  bool _useCentimeters = true; // true = cm, false = inches
  bool _showChat = false;

  @override
  void initState() {
    super.initState();
    _refreshAvailablePorts(autoConnect: true);
    _startSimulation();
  }

  void _refreshAvailablePorts({bool autoConnect = false}) {
    final ports = <Map<String, String>>[];
    for (final portName in SerialPort.availablePorts) {
      final port = SerialPort(portName);
      final description = port.description ?? '';
      final manufacturer = port.manufacturer ?? '';
      ports.add({
        'name': portName,
        'description': description.isNotEmpty
            ? description
            : (manufacturer.isNotEmpty ? manufacturer : 'Serial Device'),
      });
      port.dispose();
    }

    String nextPort = _currentPort;
    if (ports.isEmpty) {
      nextPort = '';
    } else if (!ports.any((port) => port['name'] == nextPort) ||
        nextPort.isEmpty) {
      nextPort = ports.first['name']!;
    }

    setState(() {
      _availablePorts
        ..clear()
        ..addAll(ports);
      _currentPort = nextPort;
    });

    if (autoConnect && nextPort.isNotEmpty) {
      unawaited(_connectToSerial(nextPort));
    } else if (ports.isEmpty && _isConnected) {
      unawaited(_disconnectSerial());
    }
  }

  void _startSimulation() {
    // Simulate sensor data updates for other sensors
    _timer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      setState(() {
        // Only simulate other sensors, front sensor comes from ESP32
        backSensor = 50 + _random.nextDouble() * 150;
        leftSensor = 50 + _random.nextDouble() * 150;
        rightSensor = 50 + _random.nextDouble() * 150;
        // Direction is now controlled by keyboard
      });
    });
  }

  Future<void> _connectToSerial([String? portName]) async {
    final targetPort = (portName ?? _currentPort).trim();
    if (targetPort.isEmpty) {
      if (mounted) {
        setState(() {
          _isConnected = false;
        });
      } else {
        _isConnected = false;
      }
      print('No serial port selected.');
      return;
    }

    await _disconnectSerial();

    SerialPort? openedPort;
    try {
      final port = SerialPort(targetPort);

      if (!port.openReadWrite()) {
        print('Failed to open port: ${SerialPort.lastError}');
        port.dispose();
        if (mounted) {
          setState(() {
            _isConnected = false;
          });
        } else {
          _isConnected = false;
        }
        return;
      }

      final config = SerialPortConfig()
        ..baudRate = 115200
        ..bits = 8
        ..stopBits = 1
        ..parity = SerialPortParity.none;
      port.config = config;

      final reader = SerialPortReader(port);
      _serialSubscription = reader.stream.listen(
        _handleSerialData,
        onError: (error) {
          print('Serial error: $error');
          if (mounted) {
            setState(() {
              _isConnected = false;
            });
          } else {
            _isConnected = false;
          }
          unawaited(_disconnectSerial());
        },
      );

      openedPort = port;
      _port = port;
      _serialBuffer = '';

      if (mounted) {
        setState(() {
          _currentPort = targetPort;
          _isConnected = true;
        });
      } else {
        await _disconnectSerial();
        return;
      }

      print('Connected to $targetPort');
    } catch (e) {
      openedPort?.close();
      openedPort?.dispose();
      print('Error connecting to serial: $e');
      if (mounted) {
        setState(() {
          _isConnected = false;
        });
      } else {
        _isConnected = false;
      }
    }
  }

  Future<void> _disconnectSerial() async {
    final hadPort = _port != null;
    final hadSubscription = _serialSubscription != null;

    if (_serialSubscription != null) {
      await _serialSubscription!.cancel();
      _serialSubscription = null;
    }

    if (_port != null) {
      try {
        _port!.close();
      } catch (_) {}
      try {
        _port!.dispose();
      } catch (_) {}
      _port = null;
    }

    if (hadPort || hadSubscription || _isConnected) {
      if (mounted) {
        setState(() {
          _isConnected = false;
        });
      } else {
        _isConnected = false;
      }
      print('Disconnected from serial');
    }
  }

  void _handleSerialData(Uint8List data) {
    String received = String.fromCharCodes(data);
    _serialBuffer += received;

    // Process complete lines
    while (_serialBuffer.contains('\n')) {
      int newlineIndex = _serialBuffer.indexOf('\n');
      String line = _serialBuffer.substring(0, newlineIndex).trim();
      _serialBuffer = _serialBuffer.substring(newlineIndex + 1);

      // Parse the sensor data
      _parseSensorData(line);
    }
  }

  void _parseSensorData(String line) {
    // The ESP32 sends distance in format like "Distance: 123.45 cm" or just numbers
    // Adjust parsing based on your HCSR04 library's ToString() format
    try {
      // Try to extract numbers from the line
      RegExp regex = RegExp(r'(\d+\.?\d*)');
      Iterable<Match> matches = regex.allMatches(line);

      if (matches.isNotEmpty) {
        double distance = double.parse(matches.first.group(0)!);
        setState(() {
          frontSensor = distance;
        });
        print('Front sensor: $distance cm');
      }
    } catch (e) {
      // If parsing fails, just print the line for debugging
      print('Received: $line');
    }
  }

  double _convertToDisplayUnit(double cm) {
    if (_useCentimeters) {
      return cm;
    } else {
      return cm / 2.54; // Convert cm to inches
    }
  }

  String _getUnitLabel() {
    return _useCentimeters ? 'CM' : 'IN';
  }

  void _toggleUnit() {
    setState(() {
      _useCentimeters = !_useCentimeters;
    });
  }

  Future<void> _changePort(String newPort) async {
    final sanitized = newPort.trim();
    if (sanitized.isEmpty) {
      return;
    }

    if (mounted) {
      setState(() {
        _currentPort = sanitized;
      });
    } else {
      _currentPort = sanitized;
    }

    await _connectToSerial(sanitized);
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      setState(() {
        // Arrow keys and WASD
        if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
            event.logicalKey == LogicalKeyboardKey.keyW) {
          direction = 1; // Forward
        } else if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
            event.logicalKey == LogicalKeyboardKey.keyS) {
          direction = 2; // Backward
        } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
            event.logicalKey == LogicalKeyboardKey.keyA) {
          direction = 3; // Left
        } else if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
            event.logicalKey == LogicalKeyboardKey.keyD) {
          direction = 4; // Right
        } else if (event.logicalKey == LogicalKeyboardKey.space) {
          direction = 0; // Stop
        }
      });
    } else if (event is KeyUpEvent) {
      // When key is released, stop
      setState(() {
        direction = 0;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_disconnectSerial());
    super.dispose();
  }

  void _showPortDialog() {
    _refreshAvailablePorts();
    final TextEditingController portController = TextEditingController(
      text: _currentPort,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F1329),
        title: const Text(
          'Change Serial Port',
          style: TextStyle(color: Color(0xFF00FFFF)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: portController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Port Name',
                labelStyle: const TextStyle(color: Color(0xFF00FFFF)),
                hintText: 'e.g., COM7',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                enabledBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Color(0xFF00FFFF)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(
                    color: Color(0xFF00FF88),
                    width: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Available ports:',
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 150),
              child: _availablePorts.isEmpty
                  ? Center(
                      child: Text(
                        'No serial devices detected',
                        style: TextStyle(color: Colors.white.withOpacity(0.5)),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _availablePorts.map((port) {
                          final name = port['name'] ?? '';
                          final description =
                              port['description'] ?? 'Serial Device';
                          return InkWell(
                            onTap: () {
                              portController.text = name;
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      color: Color(0xFF00FF88),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    description,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.6),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              unawaited(_changePort(portController.text));
            },
            child: const Text(
              'Connect',
              style: TextStyle(color: Color(0xFF00FFFF)),
            ),
          ),
        ],
      ),
    );
  }

  Color _getSensorColor(double value) {
    if (value < 50) return const Color(0xFFFF0040); // Red - danger
    if (value < 100) return const Color(0xFFFFAA00); // Orange - warning
    return const Color(0xFF00FF88); // Cyan - safe
  }

  String _getDirectionText() {
    switch (direction) {
      case 1:
        return 'FORWARD';
      case 2:
        return 'BACKWARD';
      case 3:
        return 'LEFT';
      case 4:
        return 'RIGHT';
      default:
        return 'STOP';
    }
  }

  IconData _getDirectionIcon() {
    switch (direction) {
      case 1:
        return Icons.arrow_upward;
      case 2:
        return Icons.arrow_downward;
      case 3:
        return Icons.arrow_back;
      case 4:
        return Icons.arrow_forward;
      default:
        return Icons.stop;
    }
  }

  Color _getDirectionColor() {
    return direction == 0 ? const Color(0xFF666666) : const Color(0xFF00FFFF);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: !_showChat,
      onKeyEvent: (node, event) {
        if (_showChat) {
          return KeyEventResult.ignored;
        }
        _handleKeyEvent(event);
        return KeyEventResult.handled;
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.5,
              colors: [Color(0xFF1A1F3A), Color(0xFF0A0E27)],
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                // Background grid
                CustomPaint(size: Size.infinite, painter: GridPainter()),

                Row(
                  children: [
                    // Main Dashboard Content
                    Expanded(
                      child: Column(
                        children: [
                          // Header
                          _buildHeader(),

                          const SizedBox(height: 20),

                          // Main Dashboard
                          Expanded(
                            child: Stack(
                              children: [
                                // Center direction indicator
                                Center(child: _buildDirectionIndicator()),

                                // Sensors positioned around
                                Positioned(
                                  top: 20,
                                  left: 0,
                                  right: 0,
                                  child: Center(
                                    child: _buildSensorDisplay(
                                      'FRONT',
                                      frontSensor,
                                      Icons.sensors,
                                    ),
                                  ),
                                ),

                                Positioned(
                                  bottom: 20,
                                  left: 0,
                                  right: 0,
                                  child: Center(
                                    child: _buildSensorDisplay(
                                      'BACK',
                                      backSensor,
                                      Icons.sensors,
                                    ),
                                  ),
                                ),

                                Positioned(
                                  left: 20,
                                  top: 0,
                                  bottom: 0,
                                  child: Center(
                                    child: _buildSensorDisplay(
                                      'LEFT',
                                      leftSensor,
                                      Icons.sensors,
                                    ),
                                  ),
                                ),

                                Positioned(
                                  right: 20,
                                  top: 0,
                                  bottom: 0,
                                  child: Center(
                                    child: _buildSensorDisplay(
                                      'RIGHT',
                                      rightSensor,
                                      Icons.sensors,
                                    ),
                                  ),
                                ),

                                // Keyboard controls hint
                                Positioned(
                                  bottom: 10,
                                  left: 0,
                                  right: 0,
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFF0F1329,
                                        ).withOpacity(0.8),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: const Color(
                                            0xFF00FFFF,
                                          ).withOpacity(0.3),
                                          width: 1,
                                        ),
                                      ),
                                      child: const Text(
                                        'Use Arrow Keys or WASD to control • Space to Stop',
                                        style: TextStyle(
                                          color: Color(0xFF00FFFF),
                                          fontSize: 12,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),
                        ],
                      ),
                    ),

                    // Chat Sidebar
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: _showChat ? 400 : 0,
                      child: _showChat
                          ? const ChatWidget()
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF00FFFF), width: 2),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00FFFF).withOpacity(0.5),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Icon(
              Icons.accessible,
              color: Color(0xFF00FFFF),
              size: 32,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WHEELCHAIR',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00FFFF),
                    letterSpacing: 4,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'NEURAL CONTROL SYSTEM',
                  style: TextStyle(
                    fontSize: 10,
                    color: Color(0xFF00FF88),
                    letterSpacing: 2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _buildChatToggle(),
          const SizedBox(width: 12),
          _buildUnitToggle(),
          const SizedBox(width: 12),
          Flexible(child: _buildPortControls()),
          const SizedBox(width: 10),
          _buildStatusDot(),
        ],
      ),
    );
  }

  Widget _buildChatToggle() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _showChat
              ? const Color(0xFF00FF88)
              : const Color(0xFF00FFFF).withOpacity(0.3),
          width: 1,
        ),
        color: _showChat
            ? const Color(0xFF00FF88).withOpacity(0.1)
            : const Color(0xFF0F1329).withOpacity(0.6),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              _showChat = !_showChat;
            });
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 14,
                  color: _showChat
                      ? const Color(0xFF00FF88)
                      : const Color(0xFF00FFFF).withOpacity(0.8),
                ),
                const SizedBox(width: 6),
                Text(
                  'AI CHAT',
                  style: TextStyle(
                    color: _showChat
                        ? const Color(0xFF00FF88)
                        : const Color(0xFF00FFFF).withOpacity(0.9),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnitToggle() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF00FFFF).withOpacity(0.3),
          width: 1,
        ),
        color: const Color(0xFF0F1329).withOpacity(0.6),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _toggleUnit,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.straighten,
                  size: 14,
                  color: const Color(0xFF00FFFF).withOpacity(0.8),
                ),
                const SizedBox(width: 6),
                Text(
                  _useCentimeters ? 'CM' : 'IN',
                  style: TextStyle(
                    color: const Color(0xFF00FFFF).withOpacity(0.9),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPortControls() {
    final accentColor = _isConnected
        ? const Color(0xFF00FF88)
        : const Color(0xFF00FFFF);
    final hasSelection =
        _availablePorts.any((port) => port['name'] == _currentPort) &&
        _currentPort.isNotEmpty;
    final dropdownValue = hasSelection ? _currentPort : null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: accentColor.withOpacity(0.3), width: 1),
            borderRadius: BorderRadius.circular(8),
            color: const Color(0xFF0F1329).withOpacity(0.6),
            boxShadow: [
              BoxShadow(
                color: accentColor.withOpacity(0.1),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          constraints: const BoxConstraints(minWidth: 120, maxWidth: 300),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: dropdownValue,
              hint: Text(
                _availablePorts.isEmpty ? 'NO PORTS' : 'SELECT PORT',
                style: TextStyle(
                  color: accentColor.withOpacity(0.7),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              dropdownColor: const Color(0xFF0F1329),
              iconEnabledColor: accentColor,
              iconDisabledColor: accentColor.withOpacity(0.3),
              isExpanded: true,
              style: TextStyle(
                color: accentColor,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
              items: _availablePorts
                  .map(
                    (port) => DropdownMenuItem<String>(
                      value: port['name'],
                      child: Text(
                        '${port['name']} - ${port['description']}',
                        style: TextStyle(
                          color: const Color(0xFF00FFFF).withOpacity(0.9),
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _availablePorts.isEmpty
                  ? null
                  : (value) {
                      if (value != null) {
                        unawaited(_changePort(value));
                      }
                    },
            ),
          ),
        ),
        const SizedBox(width: 6),
        _buildHeaderIconButton(
          icon: Icons.refresh,
          tooltip: 'Refresh ports',
          onPressed: () => _refreshAvailablePorts(),
        ),
        const SizedBox(width: 6),
        _buildHeaderIconButton(
          icon: Icons.settings,
          tooltip: 'Port settings',
          onPressed: _showPortDialog,
        ),
        const SizedBox(width: 8),
        _buildConnectButton(),
      ],
    );
  }

  Widget _buildConnectButton() {
    final buttonColor = _isConnected
        ? const Color(0xFFFF0040)
        : const Color(0xFF00FF88);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: buttonColor.withOpacity(0.3),
            blurRadius: 8,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isConnected
              ? () => unawaited(_disconnectSerial())
              : (_currentPort.isNotEmpty
                    ? () => unawaited(_connectToSerial(_currentPort))
                    : null),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: buttonColor, width: 2),
              borderRadius: BorderRadius.circular(8),
              color: buttonColor.withOpacity(0.15),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isConnected ? Icons.link_off : Icons.link,
                  size: 16,
                  color: buttonColor,
                ),
                const SizedBox(width: 6),
                Text(
                  _isConnected ? 'DISCONNECT' : 'CONNECT',
                  style: TextStyle(
                    color: buttonColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              border: Border.all(
                color: const Color(0xFF00FFFF).withOpacity(0.3),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(6),
              color: const Color(0xFF0F1329).withOpacity(0.6),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 16,
              color: const Color(0xFF00FFFF).withOpacity(0.9),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusDot() {
    final statusColor = _isConnected
        ? const Color(0xFF00FF88)
        : const Color(0xFFFF0040);
    final statusLabel = _isConnected ? 'CONNECTED' : 'IDLE';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: statusColor, width: 1),
        borderRadius: BorderRadius.circular(20),
        color: statusColor.withOpacity(0.1),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: statusColor.withOpacity(0.8),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            statusLabel,
            style: TextStyle(
              color: statusColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectionIndicator() {
    return Container(
      width: 280,
      height: 280,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _getDirectionColor(), width: 3),
        boxShadow: [
          BoxShadow(
            color: _getDirectionColor().withOpacity(0.3),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Stack(
        children: [
          // Animated rotating border
          if (direction != 0) RotatingBorder(color: _getDirectionColor()),

          // Center content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _getDirectionColor().withOpacity(0.1),
                    border: Border.all(color: _getDirectionColor(), width: 2),
                  ),
                  child: Icon(
                    _getDirectionIcon(),
                    size: 80,
                    color: _getDirectionColor(),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _getDirectionText(),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: _getDirectionColor(),
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0xFF00FFFF).withOpacity(0.5),
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'EEG SIGNAL',
                    style: TextStyle(
                      fontSize: 10,
                      color: Color(0xFF00FFFF),
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSensorDisplay(String label, double value, IconData icon) {
    final color = _getSensorColor(value);
    final displayValue = _convertToDisplayUnit(value);
    final unitLabel = _getUnitLabel();

    return Container(
      width: 140,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1329).withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5), width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.2),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            displayValue.toStringAsFixed(_useCentimeters ? 0 : 1),
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: color,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            unitLabel,
            style: TextStyle(
              fontSize: 10,
              color: color.withOpacity(0.7),
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          // Distance bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (value / 200).clamp(0.0, 1.0),
              backgroundColor: Colors.white.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}

// Grid background painter
class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00FFFF).withOpacity(0.05)
      ..strokeWidth = 1;

    const spacing = 40.0;

    // Draw vertical lines
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Draw horizontal lines
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Rotating border animation
class RotatingBorder extends StatefulWidget {
  final Color color;

  const RotatingBorder({super.key, required this.color});

  @override
  State<RotatingBorder> createState() => _RotatingBorderState();
}

class _RotatingBorderState extends State<RotatingBorder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: const Size(280, 280),
          painter: RotatingBorderPainter(
            progress: _controller.value,
            color: widget.color,
          ),
        );
      },
    );
  }
}

class RotatingBorderPainter extends CustomPainter {
  final double progress;
  final Color color;

  RotatingBorderPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.6)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    const sweepAngle = pi / 3; // 60 degrees
    final startAngle = progress * 2 * pi;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(RotatingBorderPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
