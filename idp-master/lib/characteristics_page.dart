import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import 'battery_provider.dart';
import 'main.dart';

class CharacteristicsPage extends StatefulWidget {
  final BluetoothDevice device;

  const CharacteristicsPage({super.key, required this.device});

  @override
  State<CharacteristicsPage> createState() => _CharacteristicsPageState();
}

class _CharacteristicsPageState extends State<CharacteristicsPage> {
  List<BluetoothService> _services = [];
  bool _isLoading = true;
  Map<String, List<List<int>>> _characteristicHistory = {};
  Map<String, StreamSubscription> _notifySubscriptions = {};
  BluetoothCharacteristic? _batteryCharacteristic;
  Map<String, TextEditingController> _writeControllers = {};

  @override
  void initState() {
    super.initState();
    _discoverServices();
  }

  Future<void> _discoverServices() async {
    try {
      // Request larger MTU first
      print("Requesting larger MTU...");
      try {
        final mtu = await widget.device.requestMtu(512);
        print("MTU negotiation successful: $mtu bytes");
      } catch (e) {
        print("MTU negotiation failed: $e");
      }

      _services = await widget.device.discoverServices();
      print("Discovered ${_services.length} services");

      // List all services and characteristics
      print("\n=== All Discovered Services ===");
      for (var service in _services) {
        print("\nService: ${service.uuid}");
        print("Service Name: ${_getServiceName(service.uuid.toString())}");
        for (var characteristic in service.characteristics) {
          print("  Characteristic: ${characteristic.uuid}");
          print("  Properties: ${_getPropertiesString(characteristic.properties)}");
          print("  Is Notifying: ${characteristic.isNotifying}");
          print("  Value: ${characteristic.lastValue.map((e) => '0x${e.toRadixString(16).padLeft(2, '0')}').join(' ')}");
          print("  ---");
        }
      }
      print("===============================\n");

      // Set up all characteristics
      for (var service in _services) {
        for (var characteristic in service.characteristics) {
          print("\nSetting up characteristic: ${characteristic.uuid}");
          print("Service: ${_getServiceName(service.uuid.toString())}");
          print("Properties: ${_getPropertiesString(characteristic.properties)}");

          // Initialize history for this characteristic
          _characteristicHistory[characteristic.uuid.toString()] = [];

          // Set up write controller if characteristic is writable
          if (characteristic.properties.write || characteristic.properties.writeWithoutResponse) {
            print("Setting up write controller for ${characteristic.uuid}");
            _writeControllers[characteristic.uuid.toString()] = TextEditingController();
          }

          // Set up notifications if supported
          if (characteristic.properties.notify || characteristic.properties.indicate) {
            print("Setting up notifications for ${characteristic.uuid}");
            try {
              await characteristic.setNotifyValue(true);
              print("Notifications enabled for ${characteristic.uuid}");
              
              _notifySubscriptions[characteristic.uuid.toString()] =
                characteristic.lastValueStream.listen(
                  (value) {
                    print("\n=== Notification from ${characteristic.uuid} ===");
                    print("Length: ${value.length} bytes");
                    print("Raw data: ${value.map((e) => '0x${e.toRadixString(16).padLeft(2, '0')}').join(' ')}");
                    try {
                      String asciiString = String.fromCharCodes(value);
                      print("ASCII: $asciiString");
                    } catch (e) {
                      print("Error converting to ASCII: $e");
                    }
                    _processReceivedData(characteristic.uuid.toString(), value);
                  },
                  onError: (error) {
                    print("Error in notification stream for ${characteristic.uuid}: $error");
                    print("Error details: ${error.toString()}");
                  },
                  cancelOnError: false
                );
              print("Notification listener set up for ${characteristic.uuid}");
            } catch (e) {
              print("Error setting up notifications for ${characteristic.uuid}: $e");
              print("Error details: ${e.toString()}");
            }
          }

          // If this is FFF1, set it up for notifications
          if (characteristic.uuid.toString().toUpperCase() == 'FFF1') {
            print("Found FFF1 characteristic - setting up for notifications");
            setState(() {
              _batteryCharacteristic = characteristic;
            });
            
            // Set up the battery provider
            if (mounted) {
              Provider.of<BatteryProvider>(context, listen: false)
                .setCharacteristics(characteristic, null);
            }
          }
          // If this is FFF2, set it up for writing
          else if (characteristic.uuid.toString().toUpperCase() == 'FFF2') {
            print("Found FFF2 characteristic - setting up for writing");
            if (mounted) {
              final batteryProvider = Provider.of<BatteryProvider>(context, listen: false);
              if (batteryProvider.notifyCharacteristic != null) {
                batteryProvider.setCharacteristics(
                  batteryProvider.notifyCharacteristic,
                  characteristic
                );
              }
            }
          }
        }
      }
    } catch (e) {
      print('Error discovering services: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _processReceivedData(String uuid, List<int> value) {
    if (value.isEmpty) return;

    // Process data from FFF1 characteristic
    if (uuid.toUpperCase() != 'FFF1') {
      print("Ignoring data from non-FFF1 characteristic: $uuid");
      return;
    }

    // Convert to hex for debugging
    String hexString = value.map((e) => '0x${e.toRadixString(16).padLeft(2, '0')}').join(' ');
    print("\nReceived data from FFF1:");
    print("Hex: $hexString");

    // Try to interpret as ASCII
    try {
      String asciiString = String.fromCharCodes(value);
      print("ASCII: $asciiString");
    } catch (e) {
      print("Error interpreting data as ASCII: $e");
    }

    setState(() {
      _characteristicHistory[uuid]?.add(value);
      // Keep history manageable
      if ((_characteristicHistory[uuid]?.length ?? 0) > 20) {
        _characteristicHistory[uuid]?.removeAt(0);
      }
    });
  }

  Future<void> _readCharacteristic(BluetoothCharacteristic characteristic) async {
    try {
      final value = await characteristic.read();
      _processReceivedData(characteristic.uuid.toString(), value);

      String hexData = value.map((e) => '0x${e.toRadixString(16).padLeft(2, '0')}').join(' ');
      
      _showMessage('''
Read ${value.length} bytes: $hexData
''');
    } catch (e) {
      _showError('Error reading characteristic: $e');
    }
  }

  Widget _buildDataDisplay(String uuid, List<List<int>> history, BluetoothCharacteristic characteristic) {
    if (history.isEmpty) return const SizedBox.shrink();

    bool isBatteryData = history.any((data) => 
      data.isNotEmpty && data[0] == 0xAA && 
      (data.length > 1 && [0x02, 0x03, 0x04].contains(data[1]))
    );

    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isBatteryData ? 'Battery Data History' : 'Data History',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '${history.length} readings',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (isBatteryData)
                      ElevatedButton.icon(
                        icon: const Icon(Icons.battery_full),
                        label: const Text('Battery Status'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () {
                          navigateToBatteryPage(context);
                        },
                      ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.clear_all),
                      onPressed: () {
                        setState(() {
                          _characteristicHistory[uuid]?.clear();
                        });
                      },
                      tooltip: 'Clear History',
                    ),
                  ],
                ),
              ],
            ),
            if (history.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Latest Data:',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      history.last.map((e) => '0x${e.toRadixString(16).padLeft(2, '0')}').join(' '),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCharacteristicTile(BluetoothCharacteristic characteristic) {
    String uuid = characteristic.uuid.toString();
    bool isNotifyChar = uuid.toUpperCase() == 'FFF1';
    bool isWriteChar = uuid.toUpperCase() == 'FFF2';

    return ListTile(
      title: Text('Characteristic ${_formatUUID(uuid)}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('UUID: $uuid'),
          Text('Properties: ${_getPropertiesString(characteristic.properties)}'),
          if (characteristic.isNotifying)
            const Text('Notifications: Enabled', style: TextStyle(color: Colors.green)),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (characteristic.properties.notify || characteristic.properties.indicate)
            IconButton(
              icon: Icon(
                characteristic.isNotifying ? Icons.notifications_active : Icons.notifications_none,
                color: characteristic.isNotifying ? Colors.green : Colors.grey,
              ),
              onPressed: () async {
                try {
                  await characteristic.setNotifyValue(!characteristic.isNotifying);
                  setState(() {}); // Refresh the UI
                } catch (e) {
                  _showError('Error toggling notifications: $e');
                }
              },
              tooltip: characteristic.isNotifying ? 'Disable Notifications' : 'Enable Notifications',
            ),
          if (characteristic.properties.read)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _readCharacteristic(characteristic),
              tooltip: 'Read Value',
            ),
          if (characteristic.properties.write || characteristic.properties.writeWithoutResponse)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _showWriteDialog(characteristic),
              tooltip: 'Write Value',
            ),
        ],
      ),
    );
  }

  void _showWriteDialog(BluetoothCharacteristic characteristic) {
    String uuid = characteristic.uuid.toString();
    bool isWriteChar = uuid.toUpperCase() == 'FFF2';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Write to ${_formatUUID(uuid)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isWriteChar)
              const Text(
                'This is the write characteristic (FFF2).\nData written here will be sent to the module.',
                style: TextStyle(color: Colors.blue),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _writeControllers[characteristic.uuid.toString()],
              decoration: const InputDecoration(
                labelText: 'Enter data (hex format, e.g., "AA BB CC")',
                hintText: 'Enter hex values separated by spaces',
              ),
              keyboardType: TextInputType.text,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              try {
                String input = _writeControllers[characteristic.uuid.toString()]?.text ?? '';
                List<int> data = input
                    .split(' ')
                    .where((s) => s.isNotEmpty)
                    .map((s) => int.parse(s, radix: 16))
                    .toList();
                
                await characteristic.write(data);
                if (mounted) {
                  Navigator.pop(context);
                  _showMessage('Data written successfully');
                }
              } catch (e) {
                if (mounted) {
                  Navigator.pop(context);
                  _showError('Error writing data: $e');
                }
              }
            },
            child: const Text('Write'),
          ),
        ],
      ),
    );
  }

  String _formatUUID(String uuid) {
    uuid = uuid.replaceAll('-', '').replaceAll(' ', '');
    if (uuid.length <= 4) return uuid.toUpperCase();
    if (uuid.length >= 4) {
      return uuid.substring(0, 4).toUpperCase();
    }
    return uuid.toUpperCase();
  }

  String _getPropertiesString(CharacteristicProperties properties) {
    List<String> props = [];
    if (properties.broadcast) props.add('Broadcast');
    if (properties.read) props.add('Read');
    if (properties.writeWithoutResponse) props.add('Write Without Response');
    if (properties.write) props.add('Write');
    if (properties.notify) props.add('Notify');
    if (properties.indicate) props.add('Indicate');
    return props.join(', ');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.device.platformName.isNotEmpty
                ? widget.device.platformName
                : 'Unknown Device'),
            Text(
              widget.device.remoteId.toString(),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _services.isEmpty
                    ? const Center(child: Text('No services found'))
                    : ListView.builder(
                        itemCount: _services.length,
                        itemBuilder: (context, serviceIndex) {
                          BluetoothService service = _services[serviceIndex];
                          return Card(
                            margin: const EdgeInsets.all(8.0),
                            child: ExpansionTile(
                              title: Text('Service ${_formatUUID(service.uuid.toString())}'),
                              subtitle: Text(
                                'UUID: ${service.uuid}',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                              children: service.characteristics
                                  .map(_buildCharacteristicTile)
                                  .toList(),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    for (var subscription in _notifySubscriptions.values) {
      subscription.cancel();
    }
    for (var controller in _writeControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _getServiceName(String uuid) {
    // Common Bluetooth service UUIDs
    final Map<String, String> serviceNames = {
      '00001800-0000-1000-8000-00805f9b34fb': 'Generic Access',
      '00001801-0000-1000-8000-00805f9b34fb': 'Generic Attribute',
      '0000180a-0000-1000-8000-00805f9b34fb': 'Device Information',
      '0000180f-0000-1000-8000-00805f9b34fb': 'Battery Service',
      '0000180d-0000-1000-8000-00805f9b34fb': 'Heart Rate',
      '0000fff0-0000-1000-8000-00805f9b34fb': 'Custom Service (FFF0)',
      '0000fff1-0000-1000-8000-00805f9b34fb': 'Notify Characteristic (FFF1)',
      '0000fff2-0000-1000-8000-00805f9b34fb': 'Write Characteristic (FFF2)',
    };
    return serviceNames[uuid.toLowerCase()] ?? 'Unknown Service';
  }
}