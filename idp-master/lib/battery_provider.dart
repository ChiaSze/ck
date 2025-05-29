import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/firebase_service.dart';

class BatteryCell {
  final int cellNumber;
  final double voltage;

  BatteryCell({
    required this.cellNumber,
    required this.voltage,
  });
}

class BatteryReading {
  final List<BatteryCell> cells;
  final double totalVoltage;
  final double current;
  final double temperature;
  final double soc;
  final DateTime timestamp;
  final String deviceName;
  final String? documentId;

  BatteryReading({
    required this.cells,
    required this.totalVoltage,
    required this.current,
    required this.temperature,
    required this.soc,
    required this.timestamp,
    required this.deviceName,
    this.documentId,
  });
}

class BmsError {
  final String type;
  final DateTime timestamp;
  final String? details;

  BmsError({
    required this.type,
    required this.timestamp,
    this.details,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'timestamp': timestamp.toIso8601String(),
    'details': details,
  };

  factory BmsError.fromJson(Map<String, dynamic> json) => BmsError(
    type: json['type'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    details: json['details'] as String?,
  );
}

// Add a notification callback type
typedef WarningNotificationCallback = void Function(String type, String? details);

class BatteryProvider extends ChangeNotifier {
  BluetoothCharacteristic? _notifyCharacteristic;
  BluetoothCharacteristic? _writeCharacteristic;
  List<BatteryReading> readings = [];
  List<BatteryReading> historyReadings = [];
  List<int> _buffer = [];
  String _lineBuffer = '';
  Timer? _readTimer;
  Timer? _timeoutTimer;
  bool _isProcessing = false;
  DateTime? _lastUpdateTime;
  double _temperature = 0.0;
  bool _hasData = false;
  bool _isConnected = false;
  bool _isWaitingForData = false;
  String _lastRawData = '';
  List<BatteryCell> _cells = [];
  int _cellCount = 0;

  // Add new properties for enhanced connection handling
  Timer? _reconnectTimer;
  Timer? _connectionCheckTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 3;
  static const Duration _reconnectDelay = Duration(seconds: 2);
  static const Duration _connectionCheckInterval = Duration(seconds: 5);
  List<String> _debugLogs = [];
  static const int _maxLogs = 100;
  bool _hasInitialHistoryLogged = false;
  Timer? _initialHistoryTimer;
  static const Duration _initialHistoryDelay = Duration(seconds: 8);
  static const Duration _refreshHistoryDelay = Duration(seconds: 5);
  static const String _historyStorageKey = 'battery_history_data';
  static const int _maxStoredHistory = 100;
  String? _lastConnectedDeviceName;

  // Add Firebase service and enabled flag
  final FirebaseService? _firebaseService;
  bool _isSyncing = false;
  Timer? _syncTimer;
  final bool _firebaseEnabled;

  List<BmsError> _bmsErrors = [];
  static const String _errorStorageKey = 'bms_errors';

  // Add notification callback
  WarningNotificationCallback? _onWarningReceived;

  BatteryProvider({bool firebaseEnabled = false}) 
      : _firebaseEnabled = firebaseEnabled,
        _firebaseService = firebaseEnabled ? FirebaseService() : null;

  double get temperature => _temperature;
  bool get hasData => _hasData;
  bool get isConnected => _isConnected;
  bool get isWaitingForData => _isWaitingForData;
  String get lastRawData => _lastRawData;
  List<BatteryCell> get cells => _cells;
  int get cellCount => _cellCount;

  // Add getter for debug logs
  List<String> get debugLogs => List.unmodifiable(_debugLogs);

  // Add getter for last connected device name
  String? get lastConnectedDeviceName => _lastConnectedDeviceName;

  // Get sync status
  bool get isSyncing => _isSyncing;

  // Add getter for Firebase enabled status
  bool get isFirebaseEnabled => _firebaseEnabled;

  // Getters
  BluetoothCharacteristic? get notifyCharacteristic => _notifyCharacteristic;
  BluetoothCharacteristic? get writeCharacteristic => _writeCharacteristic;

  // Add getter for BMS errors
  List<BmsError> get bmsErrors => List.unmodifiable(_bmsErrors);

  void _addDebugLog(String message) {
    _debugLogs.insert(0, '${DateTime.now().toString().split('.').first}: $message');
    if (_debugLogs.length > _maxLogs) {
      _debugLogs.removeLast();
    }
    notifyListeners();
  }

  void setCharacteristics(BluetoothCharacteristic? newNotifyCharacteristic, BluetoothCharacteristic? newWriteCharacteristic) async {
    if (_notifyCharacteristic != null || _writeCharacteristic != null) {
      _addDebugLog('Stopping monitoring of previous characteristics');
      await _stopMonitoring();
    }
    
    _notifyCharacteristic = newNotifyCharacteristic;
    _writeCharacteristic = newWriteCharacteristic;
    
    if (_notifyCharacteristic != null && _writeCharacteristic != null) {
      // Store the device name when connecting
      _lastConnectedDeviceName = _notifyCharacteristic!.device.platformName;
      _addDebugLog('Stored device name: $_lastConnectedDeviceName');
      
      _addDebugLog('=== New Characteristics Details ===');
      _addDebugLog('Notify Characteristic UUID: ${_notifyCharacteristic!.uuid}');
      _addDebugLog('Write Characteristic UUID: ${_writeCharacteristic!.uuid}');
      _addDebugLog('Notify Properties: ${_notifyCharacteristic!.properties}');
      _addDebugLog('Write Properties: ${_writeCharacteristic!.properties}');
      _addDebugLog('Is notifying: ${_notifyCharacteristic!.isNotifying}');
      
      // Verify we're using the correct characteristics
      if (_notifyCharacteristic!.uuid.toString().toUpperCase() != 'FFF1' ||
          _writeCharacteristic!.uuid.toString().toUpperCase() != 'FFF2') {
        _addDebugLog('WARNING: Using incorrect characteristics!');
        _addDebugLog('Expected: FFF1 (notify) and FFF2 (write)');
        _addDebugLog('Got: ${_notifyCharacteristic!.uuid} and ${_writeCharacteristic!.uuid}');
      } else {
        _addDebugLog('Confirmed: Using correct characteristics');
      }
      
      _isConnected = true;
      _reconnectAttempts = 0;
      await _startMonitoring();
      _startConnectionCheck();
    } else {
      _isConnected = false;
      _notifyCharacteristic = null;
      _writeCharacteristic = null;
      _stopConnectionCheck();
    }
    
    notifyListeners();
  }

  Future<void> _startMonitoring() async {
    if (_notifyCharacteristic == null) return;

    try {
      if (!_notifyCharacteristic!.isNotifying) {
        await _notifyCharacteristic!.setNotifyValue(true);
        _addDebugLog('Notifications enabled for FFF1');
      }

      _notifyCharacteristic!.lastValueStream.listen(
        (value) {
          _addDebugLog('Received notification: ${value.map((e) => '0x${e.toRadixString(16).padLeft(2, '0')}').join(' ')}');
          _processReceivedData(value);
        },
        onError: (error) {
          _addDebugLog('Error in notification stream: $error');
          _handleConnectionError();
        },
        cancelOnError: false,
      );
    } catch (e) {
      _addDebugLog('Error setting up notifications: $e');
      _handleConnectionError();
    }
  }

  void _processReceivedData(List<int> data) {
    if (data.isEmpty) {
      _addDebugLog('Received empty data');
      return;
    }
    
    // Basic data logging first
    _addDebugLog('=== Basic Data Received ===');
    _addDebugLog('Length: ${data.length} bytes');
    _addDebugLog('First byte: 0x${data[0].toRadixString(16).padLeft(2, '0')}');
    _addDebugLog('Last byte: 0x${data.last.toRadixString(16).padLeft(2, '0')}');
    
    // Check if data starts with AA (0x41 0x41 in ASCII)
    if (data[0] != 0x41 || data[1] != 0x41) {
      _addDebugLog('WARNING: Data does not start with AA');
      _addDebugLog('First bytes: ${data.take(2).map((e) => '0x${e.toRadixString(16).padLeft(2, '0')}').join(' ')}');
      return;
    }

    // Log all bytes in hex
    _addDebugLog('All bytes (hex): ${data.map((e) => '0x${e.toRadixString(16).padLeft(2, '0')}').join(' ')}');
    _addDebugLog('========================');
    
    _lastRawData = data.map((e) => '0x${e.toRadixString(16).padLeft(2, '0')}').join(' ');
    
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 5), () {
      if (_isWaitingForData) {
        _handleTimeout();
      }
    });

    // Process the data directly since it's in a fixed format
    _processData(data);
  }

  void _processData(List<int> data) {
    try {
      String asciiData = String.fromCharCodes(data);
      _addDebugLog('\n=== Processing Data ===');
      _addDebugLog('Raw ASCII data: "$asciiData"');
      
      List<String> parts = asciiData.trim().split(RegExp(r'[\s\r\n]+'));
      if (parts.length < 3) {
        _addDebugLog('Invalid data format: not enough parts');
        return;
      }

      if (parts[0] != 'AA') {
        _addDebugLog('Invalid data format: missing AA prefix');
        return;
      }

      // Check for error message (AA 99 indicates error)
      if (parts[1] == '99') {
        int errorCode = int.tryParse(parts[2]) ?? 0;
        String errorType = _getErrorType(errorCode);
        _addDebugLog('BMS Error detected: $errorType (Code: $errorCode)');
        addBmsError(errorType, details: 'Error code: $errorCode');
        return;
      }

      int cellNumber = int.tryParse(parts[1]) ?? 0;
      if (cellNumber < 1 || cellNumber > 13) {
        _addDebugLog('Invalid cell number: $cellNumber');
        return;
      }

      int value = int.tryParse(parts[2]) ?? 0;
      _addDebugLog('Processing AA $cellNumber: raw value = $value');

      if (cellNumber <= 9) {
        double voltage = value / 1000.0;
        _addDebugLog('Cell $cellNumber voltage: $voltage V (raw: $value)');
        _updateCellVoltage(cellNumber, voltage);
      } else if (cellNumber == 10) {
        double totalVoltage = value / 1000.0;
        _addDebugLog('Total voltage: $totalVoltage V (raw: $value)');
        _updateTotalVoltage(totalVoltage);
      } else if (cellNumber == 11) {
        _addDebugLog('SOC: $value %');
        _updateSOC(value.toDouble());
      } else if (cellNumber == 12) {
        _addDebugLog('Temperature: $value °C');
        _updateTemperature(value.toDouble());
      } else if (cellNumber == 13) {
        double current = value / 1000.0;
        _addDebugLog('=== Processing Current (AA 13) ===');
        _addDebugLog('Raw value: $value');
        _addDebugLog('Converted current: $current A');
        _addDebugLog('Current readings count: ${readings.length}');
        if (readings.isNotEmpty) {
          _addDebugLog('Previous current value: ${readings.last.current} A');
        }
        _updateCurrent(current);
        _addDebugLog('=== Current Processing Complete ===');
      }

      _hasData = true;
      _isWaitingForData = false;
      notifyListeners();
    } catch (e) {
      _addDebugLog('Error processing data: $e');
    }
  }

  void _updateTotalVoltage(double totalVoltage) {
    if (readings.isNotEmpty) {
      var lastReading = readings.last;
      readings[readings.length - 1] = BatteryReading(
        cells: lastReading.cells,
        totalVoltage: totalVoltage,
        current: lastReading.current,
        temperature: lastReading.temperature,
        soc: lastReading.soc,
        timestamp: DateTime.now(),
        deviceName: lastReading.deviceName,
        documentId: lastReading.documentId,
      );
    }
  }

  void _updateCellVoltage(int cellNumber, double voltage) {
    _addDebugLog('\n=== Updating Cell $cellNumber ===');
    _addDebugLog('Current cells: ${_cells.map((c) => 'Cell ${c.cellNumber}: ${c.voltage}V').join(', ')}');
    
    int index = _cells.indexWhere((cell) => cell.cellNumber == cellNumber);
    if (index == -1) {
      _addDebugLog('Adding new cell $cellNumber with voltage $voltage V');
      _cells.add(BatteryCell(
        cellNumber: cellNumber,
        voltage: voltage,
      ));
    } else {
      _addDebugLog('Updating cell $cellNumber from ${_cells[index].voltage}V to $voltage V');
      _cells[index] = BatteryCell(
        cellNumber: cellNumber,
        voltage: voltage,
      );
    }
    
    _cells.sort((a, b) => a.cellNumber.compareTo(b.cellNumber));
    _cellCount = _cells.length;
    _addDebugLog('Cells after update: ${_cells.map((c) => 'Cell ${c.cellNumber}: ${c.voltage}V').join(', ')}');
    _addDebugLog('Total cell count: $_cellCount');
    
    if (readings.isEmpty) {
      _addDebugLog('Creating first reading with ${_cells.length} cells');
      var reading = BatteryReading(
        cells: List.from(_cells),
        totalVoltage: 0.0,
        current: 0.0,
        temperature: _temperature,
        soc: 0.0,
        timestamp: DateTime.now(),
        deviceName: _lastConnectedDeviceName ?? 'Unknown Device',
        documentId: null,
      );
      readings.add(reading);
    }
    if (readings.length > 100) readings.removeAt(0);
  }

  void _updateSOC(double soc) {
    if (readings.isNotEmpty) {
      var lastReading = readings.last;
      readings[readings.length - 1] = BatteryReading(
        cells: lastReading.cells,
        totalVoltage: lastReading.totalVoltage,
        current: lastReading.current,
        temperature: lastReading.temperature,
        soc: soc,
        timestamp: DateTime.now(),
        deviceName: lastReading.deviceName,
        documentId: lastReading.documentId,
      );
    }
  }

  void _updateTemperature(double temperature) {
    _temperature = temperature;
    
    if (readings.isNotEmpty) {
      var lastReading = readings.last;
      readings[readings.length - 1] = BatteryReading(
        cells: _cells,
        totalVoltage: lastReading.totalVoltage,
        current: lastReading.current,
        temperature: temperature,
        soc: lastReading.soc,
        timestamp: DateTime.now(),
        deviceName: lastReading.deviceName,
        documentId: lastReading.documentId,
      );
    }
  }

  void _updateCurrent(double current) {
    _addDebugLog('\n=== Updating Current ===');
    _addDebugLog('New current value: $current A');
    _addDebugLog('Readings available: ${readings.length}');
    
    if (readings.isNotEmpty) {
      var lastReading = readings.last;
      _addDebugLog('Previous reading - Current: ${lastReading.current}A, Total Voltage: ${lastReading.totalVoltage}V');
      
      readings[readings.length - 1] = BatteryReading(
        cells: lastReading.cells,
        totalVoltage: lastReading.totalVoltage,
        current: current,
        temperature: lastReading.temperature,
        soc: lastReading.soc,
        timestamp: DateTime.now(),
        deviceName: lastReading.deviceName,
        documentId: lastReading.documentId,
      );
      
      _addDebugLog('Updated reading - Current: ${readings.last.current}A, Total Voltage: ${readings.last.totalVoltage}V');
    } else {
      _addDebugLog('No readings available to update current');
    }
    _addDebugLog('=== Current Update Complete ===\n');
  }

  Future<void> writeData(List<int> data) async {
    if (_writeCharacteristic == null) {
      _addDebugLog('Cannot write: Write characteristic not available');
      return;
    }

    try {
      await _writeCharacteristic!.write(data);
      _addDebugLog('Data written successfully: ${data.map((e) => '0x${e.toRadixString(16).padLeft(2, '0')}').join(' ')}');
    } catch (e) {
      _addDebugLog('Error writing data: $e');
      _handleConnectionError();
    }
  }

  Future<void> _stopMonitoring() async {
    if (_notifyCharacteristic != null && _notifyCharacteristic!.isNotifying) {
      try {
        await _notifyCharacteristic!.setNotifyValue(false);
        _addDebugLog('Notifications disabled for FFF1');
      } catch (e) {
        _addDebugLog('Error disabling notifications: $e');
      }
    }
  }

  void _startConnectionCheck() {
    _stopConnectionCheck();
    _connectionCheckTimer = Timer.periodic(_connectionCheckInterval, (timer) async {
      if (_notifyCharacteristic == null || _writeCharacteristic == null) {
        _handleConnectionError();
        return;
      }

      try {
        bool isConnected = _notifyCharacteristic!.device.isConnected;
        if (!isConnected) {
          _addDebugLog('Device disconnected during check');
          _handleConnectionError();
        }
      } catch (e) {
        _addDebugLog('Error checking connection: $e');
        _handleConnectionError();
      }
    });
  }

  void _stopConnectionCheck() {
    _connectionCheckTimer?.cancel();
    _connectionCheckTimer = null;
  }

  void _handleConnectionError() {
    _isConnected = false;
    _reconnectAttempts++;
    _addDebugLog('Connection error (attempt $_reconnectAttempts of $_maxReconnectAttempts)');
    
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _addDebugLog('Max reconnection attempts reached');
      _stopConnectionCheck();
      setCharacteristics(null, null);
    } else {
      Future.delayed(_reconnectDelay, () {
        if (_notifyCharacteristic != null && _writeCharacteristic != null) {
          _startMonitoring();
        }
      });
    }
    
    notifyListeners();
  }

  @override
  void dispose() {
    _initialHistoryTimer?.cancel();
    _stopMonitoring();
    _syncTimer?.cancel();
    _stopConnectionCheck();
    super.dispose();
  }

  // Add method to save history to local storage
  Future<void> _saveHistoryToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = historyReadings.map((reading) {
        return {
          'timestamp': reading.timestamp.toIso8601String(),
          'totalVoltage': reading.totalVoltage,
          'current': reading.current,
          'temperature': reading.temperature,
          'soc': reading.soc,
          'deviceName': reading.deviceName,
          'cells': reading.cells.map((cell) => {
            'cellNumber': cell.cellNumber,
            'voltage': cell.voltage,
          }).toList(),
        };
      }).toList();
      
      // Also save the last connected device name separately
      if (_lastConnectedDeviceName != null) {
        await prefs.setString('last_device_name', _lastConnectedDeviceName!);
      }
      
      await prefs.setString(_historyStorageKey, jsonEncode(historyJson));
      _addDebugLog('History saved to local storage: ${historyReadings.length} entries');
    } catch (e) {
      _addDebugLog('Error saving history to storage: $e');
    }
  }

  // Add method to load history from local storage
  Future<void> loadHistoryFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load the last connected device name
      _lastConnectedDeviceName = prefs.getString('last_device_name');
      _addDebugLog('Loaded last device name: $_lastConnectedDeviceName');
      
      final historyJson = prefs.getString(_historyStorageKey);
      
      if (historyJson != null) {
        final List<dynamic> decoded = jsonDecode(historyJson);
        historyReadings.clear();
        
        for (var item in decoded) {
          final cells = (item['cells'] as List).map((cell) => BatteryCell(
            cellNumber: cell['cellNumber'],
            voltage: cell['voltage'].toDouble(),
          )).toList();
          
          historyReadings.add(BatteryReading(
            cells: cells,
            totalVoltage: item['totalVoltage'].toDouble(),
            current: item['current'].toDouble(),
            temperature: item['temperature'].toDouble(),
            soc: item['soc'].toDouble(),
            timestamp: DateTime.parse(item['timestamp']),
            deviceName: item['deviceName'] as String? ?? 'Unknown Device',
            documentId: item['documentId'] as String?,
          ));
        }
        
        _addDebugLog('History loaded from storage: ${historyReadings.length} entries');
        notifyListeners();
      }
    } catch (e) {
      _addDebugLog('Error loading history from storage: $e');
    }
  }

  // Add method to initialize provider
  @override
  Future<void> initialize() async {
    await loadHistoryFromStorage();
    await loadErrorsFromStorage();
  }

  // Modify startPeriodicSync to check Firebase state
  void startPeriodicSync() {
    if (!_firebaseEnabled) {
      _addDebugLog('Firebase sync disabled');
      return;
    }
    
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (timer) async {
      if (readings.isNotEmpty) {
        await refreshHistory();
      }
    });
  }

  // Add method to stop periodic sync
  void stopPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  // Modify refreshHistory to handle Firebase state
  Future<void> refreshHistory() async {
    if (readings.isEmpty) return;

    final latestReading = readings.last;
    if (historyReadings.isEmpty || 
        historyReadings.first.timestamp != latestReading.timestamp) {
      // Add to local history first
      historyReadings.insert(0, latestReading);
      if (historyReadings.length > 100) {
        historyReadings.removeLast();
      }
      
      // Save to local storage
      await _saveHistoryToPrefs();
      
      // Upload to Firebase if enabled
      if (_firebaseEnabled && _firebaseService != null) {
        try {
          _isSyncing = true;
          notifyListeners();
          
          final documentId = await _firebaseService!.uploadReading(latestReading);
          if (documentId != null) {
            // Update the reading with the document ID
            final updatedReading = BatteryReading(
              cells: latestReading.cells,
              totalVoltage: latestReading.totalVoltage,
              current: latestReading.current,
              temperature: latestReading.temperature,
              soc: latestReading.soc,
              timestamp: latestReading.timestamp,
              deviceName: latestReading.deviceName,
              documentId: documentId,
            );
            
            // Update the reading in the history
            if (historyReadings.isNotEmpty) {
              historyReadings[0] = updatedReading;
              // Save the updated history with document ID
              await _saveHistoryToPrefs();
            }
          } else {
            _addDebugLog('Failed to get document ID from Firebase upload');
          }
        } catch (e) {
          _addDebugLog('Error syncing with Firebase: $e');
        } finally {
          _isSyncing = false;
          notifyListeners();
        }
      }
    }
  }

  // Modify deleteHistoryReading to handle Firebase state
  Future<void> deleteHistoryReading(int index) async {
    if (index >= 0 && index < historyReadings.length) {
      final reading = historyReadings[index];
      
      // Delete from Firebase if enabled and reading has document ID
      if (_firebaseEnabled && _firebaseService != null && reading.documentId != null) {
        try {
          final success = await _firebaseService!.deleteReading(reading.documentId!);
          if (!success) {
            _addDebugLog('Failed to delete reading from Firebase');
          }
        } catch (e) {
          _addDebugLog('Error deleting from Firebase: $e');
        }
      }
      
      // Remove from local history regardless of Firebase success
      historyReadings.removeAt(index);
      await _saveHistoryToPrefs();
      notifyListeners();
    }
  }

  void _handleTimeout() {
    _addDebugLog('Data reception timeout');
    _isWaitingForData = false;
    notifyListeners();
  }

  Future<void> requestNewData() async {
    if (_writeCharacteristic == null) {
      _addDebugLog('Cannot request new data: Write characteristic not available');
      return;
    }

    try {
      // Send a request for new data (0xAA 0x00 0x00)
      await writeData([0x41, 0x41, 0x30, 0x30, 0x30, 0x30]); // "AA0000" in ASCII
      _addDebugLog('Requested new data from device');
      _isWaitingForData = true;
      notifyListeners();
    } catch (e) {
      _addDebugLog('Error requesting new data: $e');
      _handleConnectionError();
    }
  }

  // Modify addBmsError to trigger notification
  void addBmsError(String type, {String? details}) {
    final error = BmsError(
      type: type,
      timestamp: DateTime.now(),
      details: details,
    );
    _bmsErrors.insert(0, error); // Add to start of list
    if (_bmsErrors.length > 100) {
      _bmsErrors.removeLast(); // Keep only last 100 errors
    }
    _saveErrorsToPrefs();
    notifyListeners();

    // Trigger notification callback if set
    if (_onWarningReceived != null) {
      _onWarningReceived!(type, details);
    }
  }

  // Add method to clear errors
  Future<void> clearErrors() async {
    _bmsErrors.clear();
    await _saveErrorsToPrefs();
    notifyListeners();
  }

  // Add method to save errors to preferences
  Future<void> _saveErrorsToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final errorsJson = _bmsErrors.map((error) => error.toJson()).toList();
      await prefs.setString(_errorStorageKey, jsonEncode(errorsJson));
      _addDebugLog('Saved ${_bmsErrors.length} BMS errors to storage');
    } catch (e) {
      _addDebugLog('Error saving BMS errors to storage: $e');
    }
  }

  // Add method to load errors from preferences
  Future<void> loadErrorsFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final errorsJson = prefs.getString(_errorStorageKey);
      if (errorsJson != null) {
        final List<dynamic> decoded = jsonDecode(errorsJson);
        _bmsErrors = decoded.map((item) => BmsError.fromJson(item)).toList();
        _addDebugLog('Loaded ${_bmsErrors.length} BMS errors from storage');
        notifyListeners();
      }
    } catch (e) {
      _addDebugLog('Error loading BMS errors from storage: $e');
    }
  }

  String _getErrorType(int errorCode) {
    switch (errorCode) {
      case 1:
        return 'Overvoltage';
      case 2:
        return 'Undervoltage';
      case 3:
        return 'Overcurrent';
      case 4:
        return 'Overtemperature';
      case 5:
        return 'Undertemperature';
      case 6:
        return 'Cell Imbalance';
      case 7:
        return 'Charging Error';
      case 8:
        return 'Discharging Error';
      case 9:
        return 'Communication Error';
      default:
        return 'Unknown Error';
    }
  }

  // Add method to set notification callback
  void setWarningNotificationCallback(WarningNotificationCallback callback) {
    _onWarningReceived = callback;
  }

  // Add method to generate test warnings
  void addTestWarnings() {
    _addDebugLog('Adding test warnings...');
    
    // Clear existing warnings first
    _bmsErrors.clear();
    
    // Add a series of test warnings with different timestamps
    final now = DateTime.now();
    
    // Add warnings with different timestamps
    addBmsError(
      'Overvoltage',
      details: 'Cell 3 voltage exceeded 4.25V',
    );
    
    Future.delayed(const Duration(seconds: 1), () {
      addBmsError(
        'Overtemperature',
        details: 'Battery temperature reached 45°C',
      );
    });
    
    Future.delayed(const Duration(seconds: 2), () {
      addBmsError(
        'Cell Imbalance',
        details: 'Cell voltage difference > 0.2V',
      );
    });
    
    Future.delayed(const Duration(seconds: 3), () {
      addBmsError(
        'Overcurrent',
        details: 'Discharge current exceeded 50A',
      );
    });
    
    Future.delayed(const Duration(seconds: 4), () {
      addBmsError(
        'Communication Error',
        details: 'Lost connection to BMS controller',
      );
    });

    _addDebugLog('Test warnings added');
  }

  // Add method to clear test warnings
  void clearTestWarnings() {
    _addDebugLog('Clearing test warnings...');
    _bmsErrors.clear();
    _saveErrorsToPrefs();
    notifyListeners();
    _addDebugLog('Test warnings cleared');
  }
}