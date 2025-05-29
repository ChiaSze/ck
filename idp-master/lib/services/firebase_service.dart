import 'package:cloud_firestore/cloud_firestore.dart';
import '../battery_provider.dart';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collectionName = 'battery_history';

  // Convert BatteryReading to Map for Firestore
  Map<String, dynamic> _readingToMap(BatteryReading reading) {
    return {
      'timestamp': reading.timestamp.toIso8601String(),
      'deviceName': reading.deviceName,
      'totalVoltage': reading.totalVoltage,
      'current': reading.current,
      'temperature': reading.temperature,
      'soc': reading.soc,
      'cells': reading.cells.map((cell) => {
        'cellNumber': cell.cellNumber,
        'voltage': cell.voltage,
      }).toList(),
    };
  }

  // Convert Firestore document to BatteryReading
  BatteryReading _mapToReading(Map<String, dynamic> data) {
    final cells = (data['cells'] as List).map((cell) => BatteryCell(
      cellNumber: cell['cellNumber'],
      voltage: cell['voltage'].toDouble(),
    )).toList();

    return BatteryReading(
      cells: cells,
      totalVoltage: data['totalVoltage'].toDouble(),
      current: data['current'].toDouble(),
      temperature: data['temperature'].toDouble(),
      soc: data['soc'].toDouble(),
      timestamp: DateTime.parse(data['timestamp']),
      deviceName: data['deviceName'] as String,
    );
  }

  // Upload a single reading to Firestore and return the document ID
  Future<String?> uploadReading(BatteryReading reading) async {
    try {
      print('Attempting to upload reading to Firebase...');
      print('Reading details:');
      print('- Device: ${reading.deviceName}');
      print('- Timestamp: ${reading.timestamp}');
      print('- Total Voltage: ${reading.totalVoltage}V');
      print('- Current: ${reading.current}A');
      print('- Temperature: ${reading.temperature}°C');
      print('- SOC: ${reading.soc}%');
      print('- Cell count: ${reading.cells.length}');

      // Convert reading to a map
      final readingData = {
        'timestamp': reading.timestamp.toIso8601String(),
        'deviceName': reading.deviceName,
        'totalVoltage': reading.totalVoltage,
        'current': reading.current,
        'temperature': reading.temperature,
        'soc': reading.soc,
        'cells': reading.cells.map((cell) => {
          'cellNumber': cell.cellNumber,
          'voltage': cell.voltage,
        }).toList(),
      };

      print('Uploading to collection: $_collectionName');
      // Add to Firestore and get the document reference
      final docRef = await _firestore.collection(_collectionName).add(readingData);
      print('Successfully uploaded reading to Firebase with ID: ${docRef.id}');
      return docRef.id;
    } catch (e, stackTrace) {
      print('Error uploading reading to Firebase: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }

  // Upload multiple readings to Firebase
  Future<void> uploadReadings(List<BatteryReading> readings) async {
    try {
      final batch = _firestore.batch();
      
      for (var reading in readings) {
        final docRef = _firestore.collection(_collectionName).doc();
        batch.set(docRef, _readingToMap(reading));
      }
      
      await batch.commit();
      print('Successfully uploaded ${readings.length} readings to Firebase');
    } catch (e) {
      print('Error uploading readings to Firebase: $e');
      rethrow;
    }
  }

  // Delete a reading from Firestore
  Future<bool> deleteReading(String documentId) async {
    try {
      await _firestore.collection(_collectionName).doc(documentId).delete();
      print('Successfully deleted reading from Firebase');
      return true;
    } catch (e) {
      print('Error deleting reading from Firebase: $e');
      return false;
    }
  }

  // Get all readings for a device
  Stream<List<BatteryReading>> getDeviceReadings(String deviceName) {
    return _firestore
        .collection(_collectionName)
        .where('deviceName', isEqualTo: deviceName)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            final cells = (data['cells'] as List).map((cell) => BatteryCell(
              cellNumber: cell['cellNumber'],
              voltage: cell['voltage'].toDouble(),
            )).toList();

            return BatteryReading(
              cells: cells,
              totalVoltage: data['totalVoltage'].toDouble(),
              current: data['current'].toDouble(),
              temperature: data['temperature'].toDouble(),
              soc: data['soc'].toDouble(),
              timestamp: DateTime.parse(data['timestamp']),
              deviceName: data['deviceName'],
              documentId: doc.id,
            );
          }).toList();
        });
  }

  // Get the latest reading for a device
  Future<BatteryReading?> getLatestReading(String deviceName) async {
    try {
      final snapshot = await _firestore
          .collection(_collectionName)
          .where('deviceName', isEqualTo: deviceName)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;

      final doc = snapshot.docs.first;
      final data = doc.data();
      final cells = (data['cells'] as List).map((cell) => BatteryCell(
        cellNumber: cell['cellNumber'],
        voltage: cell['voltage'].toDouble(),
      )).toList();

      return BatteryReading(
        cells: cells,
        totalVoltage: data['totalVoltage'].toDouble(),
        current: data['current'].toDouble(),
        temperature: data['temperature'].toDouble(),
        soc: data['soc'].toDouble(),
        timestamp: DateTime.parse(data['timestamp']),
        deviceName: data['deviceName'],
        documentId: doc.id,
      );
    } catch (e) {
      print('Error getting latest reading from Firebase: $e');
      return null;
    }
  }

  // Sync local readings with Firebase
  Future<void> syncReadings(List<BatteryReading> localReadings) async {
    try {
      // Get all readings from Firebase
      final snapshot = await _firestore
          .collection(_collectionName)
          .orderBy('timestamp', descending: true)
          .get();

      // Create a map of existing Firebase readings by timestamp
      final Map<String, DocumentSnapshot> existingReadings = {};
      for (var doc in snapshot.docs) {
        final timestamp = doc.data()['timestamp'] as String;
        existingReadings[timestamp] = doc;
      }

      // Upload new readings that don't exist in Firebase
      final batch = _firestore.batch();
      var newReadingsCount = 0;

      for (var reading in localReadings) {
        final timestamp = reading.timestamp.toIso8601String();
        if (!existingReadings.containsKey(timestamp)) {
          final docRef = _firestore.collection(_collectionName).doc();
          batch.set(docRef, _readingToMap(reading));
          newReadingsCount++;
        }
      }

      if (newReadingsCount > 0) {
        await batch.commit();
        print('Successfully synced $newReadingsCount new readings to Firebase');
      } else {
        print('No new readings to sync with Firebase');
      }
    } catch (e) {
      print('Error syncing readings with Firebase: $e');
      rethrow;
    }
  }
} 