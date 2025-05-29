//home_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import 'bluetooth_provider.dart';

// Import the navigation helper from main.dart
import 'main.dart' show navigateToBatteryPage;

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isScanning = false;
  List<ScanResult> _scanResults = [];

  @override
  void initState() {
    super.initState();
    // Set the context for the BluetoothProvider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<BluetoothProvider>().setContext(context);
      }
    });
    
    // Check for already discovered devices
    FlutterBluePlus.scanResults.listen((results) {
      if (mounted) {
        setState(() {
          _scanResults = results;
        });
      }
    });
    
    // Listen for scan status changes
    FlutterBluePlus.isScanning.listen((isScanning) {
      if (mounted && _isScanning != isScanning) {
        setState(() {
          _isScanning = isScanning;
        });
      }
    });
  }

  void _startScan() async {
    // Clear previous results
    setState(() {
      _scanResults = [];
    });

    try {
      // Start scanning
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error scanning: $e')),
      );
    }
  }

  void _stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      debugPrint('Error stopping scan: $e');
    }
  }

  void _connectToDevice(BluetoothDevice device) async {
    // Stop scanning first
    if (_isScanning) {
      await FlutterBluePlus.stopScan();
    }

    final bluetoothProvider = Provider.of<BluetoothProvider>(context, listen: false);

    try {
      // Show connecting dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Connecting to ${device.platformName}'),
            content: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Please wait...'),
              ],
            ),
          );
        },
      );

      // Connect to device and set up battery monitoring
      await bluetoothProvider.connectToDevice(device);
      
      // Wait for services to be discovered and notifications to be enabled
      await Future.delayed(const Duration(seconds: 2));
      
      // Close dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully connected to ${device.platformName}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      
      // Navigate to battery page using the global navigation function
      if (mounted) {
        // Use Future.delayed to allow the snackbar to be visible before navigation
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            navigateToBatteryPage(context);
          }
        });
      }
    } catch (e) {
      // Close dialog
      if (mounted) {
        Navigator.of(context).pop();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to connect: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BMS Battery Monitor'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (!_isScanning) {
            _startScan();
          }
        },
        child: Column(
          children: [
            // Connected device status
            Consumer<BluetoothProvider>(
              builder: (context, provider, _) {
                final device = provider.connectedDevice;
                if (device != null) {
                  return Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.bluetooth_connected, color: Colors.blue, size: 28),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                device.platformName.isEmpty ? 'Unknown Device' : device.platformName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              Text(
                                device.remoteId.toString(),
                                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            ElevatedButton(
                              onPressed: () async {
                                try {
                                  final bluetoothProvider = Provider.of<BluetoothProvider>(context, listen: false);
                                  await bluetoothProvider.disconnectFromDevice();
                                  if (mounted) {
                                    // Start a new scan to refresh the device list
                                    _startScan();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Device disconnected')),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Error disconnecting: $e')),
                                    );
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade100,
                                foregroundColor: Colors.red,
                              ),
                              child: const Text('Disconnect'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),

            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Available Devices',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  _isScanning
                      ? IconButton(
                          icon: const Icon(Icons.stop),
                          onPressed: _stopScan,
                        )
                      : IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: _startScan,
                        ),
                ],
              ),
            ),
            Expanded(
              child: _isScanning && _scanResults.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Scanning for devices...'),
                        ],
                      ),
                    )
                  : _scanResults.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.bluetooth_searching,
                                size: 64,
                                color: Colors.grey,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'No devices found',
                                style: TextStyle(fontSize: 18),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.search),
                                label: const Text('Scan for Devices'),
                                onPressed: _startScan,
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _scanResults.length,
                          itemBuilder: (context, index) {
                            final result = _scanResults[index];
                            final device = result.device;
                            final name = device.platformName.isNotEmpty
                                ? device.platformName
                                : 'Unknown Device';
                                
                            // Check if device is already connected
                            final bluetoothProvider = Provider.of<BluetoothProvider>(context, listen: false);
                            final isConnected = bluetoothProvider.connectedDevice?.remoteId == device.remoteId;

                            return ListTile(
                              title: Text(name),
                              subtitle: Text(device.remoteId.toString()),
                              leading: const Icon(Icons.bluetooth),
                              trailing: isConnected
                                  ? const Icon(Icons.check_circle, color: Colors.green)
                                  : ElevatedButton(
                                      onPressed: () => _connectToDevice(device),
                                      child: const Text('Connect'),
                                    ),
                              onTap: isConnected 
                                  ? () {
                                      // Navigate directly to battery page using global function
                                      navigateToBatteryPage(context);
                                    }
                                  : () => _connectToDevice(device),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: _isScanning
          ? FloatingActionButton(
              onPressed: _stopScan,
              backgroundColor: Colors.red,
              child: const Icon(Icons.stop),
            )
          : FloatingActionButton(
              onPressed: _startScan,
              child: const Icon(Icons.search),
            ),
    );
  }

  @override
  void dispose() {
    // Stop scanning when the page is disposed
    if (_isScanning) {
      FlutterBluePlus.stopScan();
    }
    super.dispose();
  }
}