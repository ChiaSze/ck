//bluetooth_searching_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BluetoothScannerPage extends StatefulWidget {
  const BluetoothScannerPage({super.key});

  @override
  State<BluetoothScannerPage> createState() => _BluetoothScannerPageState();
}

class _BluetoothScannerPageState extends State<BluetoothScannerPage> {
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  bool _isInitialized = false;
  BluetoothDevice? _selectedDevice;
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;

  @override
  void initState() {
    super.initState();
    _initializeBluetooth();
  }

  Future<void> _initializeBluetooth() async {
    // Check if Bluetooth is supported
    if (await FlutterBluePlus.isSupported == false) {
      _showError("Bluetooth is not supported on this device");
      return;
    }

    // Request permissions
    if (Platform.isAndroid) {
      await _requestPermissions();
    }

    // Initialize Bluetooth
    try {
      // Listen for adapter state changes
      FlutterBluePlus.adapterState.listen((state) {
        setState(() {
          _adapterState = state;
          if (state == BluetoothAdapterState.on) {
            _isInitialized = true;
          } else {
            _isInitialized = false;
          }
        });
      });

      // Turn on Bluetooth if it's off (Android only)
      if (Platform.isAndroid) {
        await FlutterBluePlus.turnOn();
      }

      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      print('Bluetooth initialization error: $e');
      _showError('Failed to initialize Bluetooth: $e');
    }
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      // Request location permission (required for BLE scanning on Android)
      var locationStatus = await Permission.locationWhenInUse.request();
      var bluetoothStatus = await Permission.bluetooth.request();
      var bluetoothScanStatus = await Permission.bluetoothScan.request();
      var bluetoothConnectStatus = await Permission.bluetoothConnect.request();

      if (locationStatus.isDenied || bluetoothStatus.isDenied ||
          bluetoothScanStatus.isDenied || bluetoothConnectStatus.isDenied) {
        _showError('Required permissions were denied');
        return;
      }
    }
  }

  void _startScan() async {
    if (_isScanning) return;
    if (!_isInitialized) {
      _showError('Bluetooth is not initialized');
      return;
    }

    if (_adapterState != BluetoothAdapterState.on) {
      _showError('Bluetooth is not turned on');
      return;
    }

    setState(() {
      _scanResults.clear();
      _isScanning = true;
    });

    try {
      await FlutterBluePlus.stopScan();

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: true,
      );

      FlutterBluePlus.scanResults.listen(
            (results) {
          setState(() {
            _scanResults = results;
          });
          print("Scan Results: $_scanResults"); // Log scan results
        },
        onError: (e) {
          _showError('Scan error: $e');
          setState(() {
            _isScanning = false;
          });
        },
        onDone: () {
          setState(() {
            _isScanning = false;
          });
        },
      );

      Future.delayed(const Duration(seconds: 15), () {
        if (mounted && _isScanning) {
          _stopScan();
        }
      });

    } catch (e) {
      print('Scan error: $e');
      setState(() {
        _isScanning = false;
      });
      _showError('Failed to start scan: $e');
    }
  }

  void _stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      print('Stop scan error: $e');
    }
    if (mounted) {
      setState(() {
        _isScanning = false;
      });
    }
  }

  void _handleDeviceSelection(BluetoothDevice device) async {
    if (_selectedDevice == device) {
      // Disconnect
      try {
        await device.disconnect();
        setState(() {
          _selectedDevice = null;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Disconnected from ${device.platformName}')),
          );
        }
      } catch (e) {
        _showError('Failed to disconnect: $e');
      }
    } else {
      // Connect
      try {
        await device.connect(autoConnect: false);
        setState(() {
          _selectedDevice = device;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Connected to ${device.platformName}')),
          );
          // Return the selected device instead of navigating
          Navigator.pop(context, device);
        }

        // Setup disconnect listener
        device.connectionState.listen((BluetoothConnectionState state) {
          if (state == BluetoothConnectionState.disconnected) {
            setState(() {
              if (_selectedDevice == device) {
                _selectedDevice = null;
              }
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${device.platformName} disconnected')),
              );
            }
          }
        });
      } catch (e) {
        _showError('Failed to connect: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bluetooth Scanner'),
        actions: [
          IconButton(
            icon: Icon(_isScanning ? Icons.stop : Icons.refresh),
            onPressed: _isScanning ? _stopScan : _startScan,
          ),
        ],
      ),
      body: Column(
        children: [
          // Status Bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.withOpacity(0.1),
            child: Row(
              children: [
                Icon(
                  _isScanning ? Icons.bluetooth_searching : Icons.bluetooth,
                  color: _adapterState == BluetoothAdapterState.on
                      ? Colors.blue
                      : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  _getStatusText(),
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
          // Device List
          Expanded(
            child: _scanResults.isEmpty
                ? Center(
              child: Text(
                _getEmptyStateText(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 16,
                ),
              ),
            )
                : ListView.separated(
              itemCount: _scanResults.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, index) {
                final result = _scanResults[index];
                final device = result.device;
                final isSelected = _selectedDevice == device;

                String deviceName = device.platformName.isNotEmpty
                    ? device.platformName
                    : device.advName.isNotEmpty
                    ? device.advName
                    : 'Unknown Device';

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isSelected ? Colors.blue : Colors.grey[200],
                    child: Icon(
                      Icons.bluetooth,
                      color: isSelected ? Colors.white : Colors.grey[600],
                    ),
                  ),
                  title: Text(
                    deviceName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ID: ${device.remoteId}'),
                      Text('Signal: ${result.rssi} dBm'),
                    ],
                  ),
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                      isSelected ? Colors.red : Colors.blue,
                    ),
                    onPressed: () => _handleDeviceSelection(device),
                    child: Text(
                      isSelected ? 'Disconnect' : 'Connect',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  onTap: () => _handleDeviceSelection(device),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isInitialized && !_isScanning ? _startScan : _stopScan,
        icon: Icon(_isScanning ? Icons.stop : Icons.search),
        label: Text(_isScanning ? 'Stop' : 'Scan'),
        backgroundColor: _isScanning ? Colors.red : Colors.blue,
      ),
    );
  }

  String _getStatusText() {
    if (!_isInitialized) return 'Initializing Bluetooth...';
    if (_adapterState != BluetoothAdapterState.on) return 'Bluetooth is off';
    if (_isScanning) return 'Scanning...';
    return 'Ready to scan';
  }

  String _getEmptyStateText() {
    if (!_isInitialized) return 'Initializing Bluetooth...\nPlease wait';
    if (_adapterState != BluetoothAdapterState.on) return 'Please turn on Bluetooth';
    if (_isScanning) return 'Searching for devices...';
    return 'No devices found\nTap scan to start';
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  void dispose() {
    _stopScan();
    super.dispose();
  }
}
