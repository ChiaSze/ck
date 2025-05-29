import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import 'battery_provider.dart';

class BluetoothProvider extends ChangeNotifier {
  BluetoothDevice? _connectedDevice;
  bool _isScanning = false;
  List<ScanResult> _scanResults = [];
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;
  StreamSubscription<bool>? _isScanningSubscription;
  Timer? _scanTimer;
  BuildContext? _context;

  BluetoothDevice? get connectedDevice => _connectedDevice;
  bool get isScanning => _isScanning;
  List<ScanResult> get scanResults => _scanResults;

  void setContext(BuildContext context) {
    _context = context;
  }

  BluetoothProvider() {
    _init();
  }

  void _init() {
    _isScanningSubscription = FlutterBluePlus.isScanning.listen((state) {
      _isScanning = state;
      notifyListeners();
    });
  }

  Future<void> startScan() async {
    try {
      _scanResults.clear();
      notifyListeners();

      // Start scanning
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 4),
        androidUsesFineLocation: false,
      );

      // Listen to scan results
      _scanResultsSubscription?.cancel();
      _scanResultsSubscription = FlutterBluePlus.scanResults.listen((results) {
        _scanResults = results;
        notifyListeners();
      });

      // Stop scanning after timeout
      _scanTimer?.cancel();
      _scanTimer = Timer(const Duration(seconds: 4), () {
        stopScan();
      });
    } catch (e) {
      debugPrint('Error starting scan: $e');
    }
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
      _scanResultsSubscription?.cancel();
      _scanTimer?.cancel();
    } catch (e) {
      debugPrint('Error stopping scan: $e');
    }
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      // Disconnect from current device if any
      if (_connectedDevice != null) {
        await disconnectFromDevice();
      }

      // Connect to new device
      await device.connect();
      _connectedDevice = device;

      // Discover services
      List<BluetoothService> services = await device.discoverServices();

      // Find the UART service and characteristic
      BluetoothCharacteristic? notifyCharacteristic;
      BluetoothCharacteristic? writeCharacteristic;
      for (var service in services) {
        if (service.uuid.toString().toUpperCase() == 'FFF0') {
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid.toString().toUpperCase() == 'FFF1') {
              notifyCharacteristic = characteristic;
            } else if (characteristic.uuid.toString().toUpperCase() == 'FFF2') {
              writeCharacteristic = characteristic;
            }
          }
        }
      }

      if (notifyCharacteristic != null && writeCharacteristic != null && _context != null) {
        // Set up the battery provider with both characteristics
        final batteryProvider = Provider.of<BatteryProvider>(
          _context!,
          listen: false,
        );
        batteryProvider.setCharacteristics(notifyCharacteristic, writeCharacteristic);
      } else {
        debugPrint('Required characteristics not found or context not set');
        await disconnectFromDevice();
        throw Exception('Failed to find required characteristics or context not set');
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error connecting to device: $e');
      await disconnectFromDevice();
      rethrow;
    }
  }

  Future<void> disconnectFromDevice() async {
    try {
      if (_connectedDevice != null) {
        // Stop any ongoing scans
        await stopScan();
        
        // Disconnect from the device
        await _connectedDevice!.disconnect();
        
        // Clear the connected device
        _connectedDevice = null;

        // Clear the battery provider's characteristics
        if (_context != null) {
          final batteryProvider = Provider.of<BatteryProvider>(
            _context!,
            listen: false,
          );
          batteryProvider.setCharacteristics(null, null);
        }

        // Clear scan results to force a fresh scan
        _scanResults.clear();
        
        // Notify listeners of the state change
        notifyListeners();
        
        // Start a new scan after a short delay
        Future.delayed(const Duration(milliseconds: 500), () {
          startScan();
        });
      }
    } catch (e) {
      debugPrint('Error disconnecting from device: $e');
      // Even if there's an error, try to clean up the state
      _connectedDevice = null;
      _scanResults.clear();
      notifyListeners();
    }
  }

  Future<void> checkDeviceConnection() async {
    try {
      if (_connectedDevice != null) {
        bool isConnected = _connectedDevice!.isConnected;
        if (!isConnected) {
          await disconnectFromDevice();
        }
      }
    } catch (e) {
      debugPrint('Error checking device connection: $e');
      await disconnectFromDevice();
    }
  }

  @override
  void dispose() {
    stopScan();
    disconnectFromDevice();
    _scanResultsSubscription?.cancel();
    _isScanningSubscription?.cancel();
    _scanTimer?.cancel();
    super.dispose();
  }
}

