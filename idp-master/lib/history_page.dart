import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'battery_provider.dart';
import 'bluetooth_provider.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  bool _isExporting = false;
  String? _lastExportPath;
  final Map<int, bool> _expandedItems = {};
  final Map<int, bool> _exportingItems = {};

  // Convert A to mA
  String _formatCurrent(double currentInA) {
    final currentInmA = (currentInA * 1000).toStringAsFixed(1);
    return '$currentInmA mA';
  }

  Future<String> _generateCSV(List<BatteryReading> readings) async {
    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().toString().replaceAll(':', '-').replaceAll('.', '-');
    final file = File('${directory.path}/battery_history_$timestamp.csv');
    
    // Create CSV header
    final header = [
      'Timestamp',
      'Total Voltage (V)',
      'Current (mA)',
      'Temperature (°C)',
      'State of Charge (%)',
      ...List.generate(readings.first.cells.length, (i) => 'Cell ${i + 1} Voltage (V)'),
    ].join(',');

    // Create CSV rows
    final rows = readings.map((reading) {
      final cellVoltages = reading.cells.map((cell) => cell.voltage.toStringAsFixed(3));
      return [
        reading.timestamp.toString(),
        reading.totalVoltage.toStringAsFixed(3),
        (reading.current * 1000).toStringAsFixed(1), // Convert to mA
        reading.temperature.toStringAsFixed(1),
        reading.soc.toStringAsFixed(1),
        ...cellVoltages,
      ].join(',');
    }).toList();

    // Write to file
    await file.writeAsString([header, ...rows].join('\n'));
    return file.path;
  }

  Future<void> _exportSingleReading(BatteryReading reading, int index) async {
    if (_exportingItems[index] ?? false) return;

    setState(() => _exportingItems[index] = true);

    try {
      final filePath = await _generateCSV([reading]);
      _lastExportPath = filePath;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('CSV file exported successfully'),
            action: SnackBarAction(
              label: 'Share',
              onPressed: () => Share.shareXFiles([XFile(filePath)]),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exporting CSV: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _exportingItems[index] = false);
      }
    }
  }

  Future<void> _refreshHistory() async {
    final provider = context.read<BatteryProvider>();
    await provider.refreshHistory();
  }

  Future<bool> _showDeleteConfirmation(BuildContext context, int index) async {
    final reading = context.read<BatteryProvider>().historyReadings[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete History Entry'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Are you sure you want to delete this entry?'),
              const SizedBox(height: 8),
              Text(
                'Device: ${reading.deviceName}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Text(
                'Time: ${reading.timestamp.toString().split('.')[0]}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('DELETE'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      final provider = context.read<BatteryProvider>();
      await provider.deleteHistoryReading(index);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('History entry deleted'),
          duration: Duration(seconds: 2),
        ),
      );
    }
    
    return confirmed ?? false;
  }

  Future<void> _exportToCSV() async {
    final provider = context.read<BatteryProvider>();
    if (provider.historyReadings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No history data to export')),
      );
      return;
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final file = File('${directory.path}/battery_history_$timestamp.csv');

      // Create CSV content
      final csvContent = StringBuffer();
      // Add header
      csvContent.writeln('Timestamp,Device Name,Total Voltage (V),Current (mA),Temperature (°C),SOC (%),Cell Voltages (V)');
      
      // Add data rows
      for (var reading in provider.historyReadings) {
        final cellVoltages = reading.cells.map((cell) => cell.voltage.toStringAsFixed(3)).join(',');
        csvContent.writeln(
          '${reading.timestamp.toIso8601String()},'
          '${reading.deviceName},'
          '${reading.totalVoltage.toStringAsFixed(3)},'
          '${(reading.current * 1000).toStringAsFixed(2)},'
          '${reading.temperature.toStringAsFixed(1)},'
          '${reading.soc.toStringAsFixed(1)},'
          '$cellVoltages'
        );
      }

      await file.writeAsString(csvContent.toString());
      
      // Share the file
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Battery History Data',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exporting data: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Battery History'),
        actions: [
          // Sync status indicator
          if (context.read<BatteryProvider>().isSyncing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),
          // Export button
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _exportToCSV,
            tooltip: 'Export to CSV',
          ),
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshHistory,
            tooltip: 'Add current reading to history',
          ),
        ],
      ),
      body: Consumer2<BatteryProvider, BluetoothProvider>(
        builder: (context, batteryProvider, bluetoothProvider, _) {
          if (batteryProvider.historyReadings.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history,
                    size: 48,
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No history data available',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap refresh to add current reading to history',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }

          final deviceName = bluetoothProvider.connectedDevice?.platformName ?? 'Unknown Device';

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: batteryProvider.historyReadings.length,
            itemBuilder: (context, index) {
              final reading = batteryProvider.historyReadings[index];
              final isExpanded = _expandedItems[index] ?? false;
              final isExporting = _exportingItems[index] ?? false;

              return Dismissible(
                key: Key(reading.timestamp.toString()),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.delete,
                    color: Colors.white,
                  ),
                ),
                confirmDismiss: (direction) async {
                  final result = await _showDeleteConfirmation(context, index);
                  return result ?? false;
                },
                child: Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    children: [
                      InkWell(
                        onTap: () {
                          setState(() {
                            _expandedItems[index] = !isExpanded;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      reading.deviceName,
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      reading.timestamp.toString().split('.')[0],
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      isExporting ? Icons.hourglass_empty : Icons.file_download,
                                      size: 20,
                                    ),
                                    onPressed: isExporting ? null : () => _exportSingleReading(reading, index),
                                    tooltip: 'Download CSV',
                                  ),
                                  Icon(
                                    Icons.battery_full,
                                    color: Theme.of(context).colorScheme.primary,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${reading.soc.toStringAsFixed(1)}%',
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    isExpanded ? Icons.expand_less : Icons.expand_more,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (isExpanded) ...[
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  _buildDataItem(
                                    context,
                                    'Voltage',
                                    '${reading.totalVoltage.toStringAsFixed(2)}V',
                                    Icons.electric_bolt,
                                  ),
                                  _buildDataItem(
                                    context,
                                    'Current',
                                    _formatCurrent(reading.current),
                                    Icons.power,
                                  ),
                                  _buildDataItem(
                                    context,
                                    'Temp',
                                    '${reading.temperature.toStringAsFixed(1)}°C',
                                    Icons.thermostat,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: reading.cells.map((cell) {
                                  return Chip(
                                    label: Text(
                                      'Cell ${cell.cellNumber}: ${cell.voltage.toStringAsFixed(2)}V',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildDataItem(BuildContext context, String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
} 