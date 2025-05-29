import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'battery_provider.dart';
import 'characteristics_page.dart';
import 'bluetooth_provider.dart';
import 'warning_page.dart';

class BatteryStatusPage extends StatefulWidget {
  const BatteryStatusPage({Key? key}) : super(key: key);

  @override
  State<BatteryStatusPage> createState() => _BatteryStatusPageState();
}

class _BatteryStatusPageState extends State<BatteryStatusPage> {
  final ScrollController _scrollController = ScrollController();
  bool _isRefreshing = false;
  Timer? _autoRefreshTimer;
  bool _showDebugLogs = false;
  bool _hasInitialDataLogged = false;

  @override
  void initState() {
    super.initState();
    _startAutoRefresh();
    // Add initial data to history when page is first loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _logCurrentDataToHistory();
    });
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  void _logCurrentDataToHistory() {
    final provider = context.read<BatteryProvider>();
    if (provider.readings.isNotEmpty && !_hasInitialDataLogged) {
      provider.refreshHistory();
      _hasInitialDataLogged = true;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshData() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    
    try {
      final provider = context.read<BatteryProvider>();
      
      // Request new data from the device
      await provider.requestNewData();
      
      // Wait for data to be received
      await Future.delayed(const Duration(seconds: 2));
      
      // Add to history if we have new data
      if (provider.readings.isNotEmpty) {
        await provider.refreshHistory();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error refreshing data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  Widget _buildDebugLogs() {
    return Consumer<BatteryProvider>(
      builder: (context, provider, _) {
        final logs = provider.debugLogs;
        if (logs.isEmpty) return const SizedBox.shrink();

        return Card(
          margin: const EdgeInsets.all(8),
          color: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                title: Text(
                  'DEBUG LOGS',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                trailing: IconButton(
                  icon: Icon(_showDebugLogs ? Icons.expand_less : Icons.expand_more),
                  onPressed: () => setState(() => _showDebugLogs = !_showDebugLogs),
                ),
              ),
              if (_showDebugLogs)
                Container(
                  height: 180,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(8),
                      bottomRight: Radius.circular(8),
                    ),
                  ),
                  child: ListView.builder(
                    reverse: true,
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final log = logs[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Text(
                          log,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCellCard(BatteryCell cell) {
    final theme = Theme.of(context);
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'CELL ${cell.cellNumber}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600, 
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _buildCellMetric(
              icon: Icons.electric_bolt,
              label: 'Voltage',
              value: '${cell.voltage.toStringAsFixed(3)}V',
              color: _getVoltageColor(cell.voltage),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCellMetric({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                icon,
                size: 16,
                color: color,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionStatus(BatteryProvider provider) {
    final isConnected = provider.isConnected;
    final isWaiting = provider.isWaitingForData;
    final hasData = provider.hasData;
    final theme = Theme.of(context);
    final hasNotifyChar = provider.notifyCharacteristic != null;
    final hasWriteChar = provider.writeCharacteristic != null;
    final hasWarnings = provider.bmsErrors.isNotEmpty;

    return Card(
      margin: const EdgeInsets.all(8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isConnected 
                      ? (hasWarnings ? Colors.orange.withOpacity(0.1) : Colors.green.withOpacity(0.1))
                      : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    hasWarnings ? Icons.warning_amber_rounded :
                      (isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled),
                    color: hasWarnings ? Colors.orange :
                      (isConnected ? Colors.green : Colors.red),
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          isConnected 
                            ? (hasWarnings ? 'WARNING' : 'CONNECTED')
                            : 'DISCONNECTED',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: hasWarnings ? Colors.orange :
                              (isConnected ? Colors.green : Colors.red),
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        if (hasWarnings) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const WarningPage(),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${provider.bmsErrors.length} WARNING${provider.bmsErrors.length > 1 ? 'S' : ''}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (isConnected) ...[
                      Text(
                        'FFF1: ${hasNotifyChar ? "✓" : "✗"} FFF2: ${hasWriteChar ? "✓" : "✗"}',
                        style: TextStyle(
                          fontSize: 10,
                          color: hasNotifyChar && hasWriteChar ? Colors.green : Colors.orange,
                        ),
                      ),
                    ],
                  ],
                ),
                if (isConnected && hasData && provider.readings.isNotEmpty) ...[
                  const Spacer(),
                  Text(
                    'UPDATED: ${provider.readings.last.timestamp.toString().split('.').first}',
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
            if (isConnected && isWaiting) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.hourglass_empty,
                      size: 14,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'WAITING FOR DATA...',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.orange,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatCurrent(double currentInA) {
    final currentInmA = (currentInA * 1000).toStringAsFixed(1);
    return '$currentInmA mA';
  }

  Widget _buildBatteryOverview(BatteryReading latestReading, int cellCount) {
    final theme = Theme.of(context);
    
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      elevation: 1,
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'BATTERY OVERVIEW',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: theme.colorScheme.primary,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$cellCount CELLS',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildOverviewItem(
              label: 'Total Voltage',
              value: '${latestReading.totalVoltage.toStringAsFixed(3)}V',
              icon: Icons.electric_bolt,
              color: _getVoltageColor(latestReading.totalVoltage),
            ),
            const SizedBox(height: 12),
            _buildOverviewItem(
              label: 'Current Draw',
              value: _formatCurrent(latestReading.current),
              icon: Icons.power,
              color: theme.colorScheme.secondary,
            ),
            const SizedBox(height: 12),
            _buildOverviewItem(
              label: 'State of Charge',
              value: '${latestReading.soc.toStringAsFixed(1)}%',
              icon: Icons.battery_full,
              color: _getSocColor(latestReading.soc),
            ),
            const SizedBox(height: 12),
            _buildOverviewItem(
              label: 'Temperature',
              value: '${latestReading.temperature.toStringAsFixed(1)}°C',
              icon: Icons.thermostat,
              color: _getTemperatureColor(latestReading.temperature),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewItem({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 18,
            color: color,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final batteryProvider = Provider.of<BatteryProvider>(context);
    final bluetoothProvider = Provider.of<BluetoothProvider>(context, listen: false);
    final device = bluetoothProvider.connectedDevice;
    final theme = Theme.of(context);
    final hasWarnings = batteryProvider.bmsErrors.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Battery Status',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        elevation: 0,
        actions: [
          if (hasWarnings)
            IconButton(
              icon: Badge(
                label: Text('${batteryProvider.bmsErrors.length}'),
                child: const Icon(Icons.warning_amber_rounded, size: 20),
              ),
              tooltip: 'View Warnings',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const WarningPage(),
                  ),
                );
              },
            ),
          if (device != null)
            IconButton(
              icon: const Icon(Icons.developer_board, size: 20),
              tooltip: 'Show Bluetooth Characteristics',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CharacteristicsPage(device: device),
                  ),
                );
              },
            ),
          IconButton(
            icon: Icon(_showDebugLogs ? Icons.bug_report : Icons.bug_report_outlined, size: 20),
            onPressed: () => setState(() => _showDebugLogs = !_showDebugLogs),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _refreshData,
          ),
        ],
      ),
      body: Consumer<BatteryProvider>(
        builder: (context, provider, child) {
          if (provider.readings.isEmpty) {
            return Column(
              children: [
                _buildConnectionStatus(provider),
                if (_showDebugLogs) _buildDebugLogs(),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (provider.isWaitingForData) ...[
                          CircularProgressIndicator(
                            color: theme.colorScheme.primary,
                            strokeWidth: 3,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Waiting for data...',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                          ),
                        ] else ...[
                          Icon(
                            Icons.battery_alert,
                            size: 48,
                            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No data available',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Pull down to refresh',
                            style: TextStyle(
                              fontSize: 14,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          final latestReading = provider.readings.last;

          return RefreshIndicator(
            onRefresh: _refreshData,
            color: theme.colorScheme.primary,
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              children: [
                _buildConnectionStatus(provider),
                if (_showDebugLogs) _buildDebugLogs(),
                const SizedBox(height: 12),
                
                // Battery Overview
                _buildBatteryOverview(latestReading, provider.cellCount),
                const SizedBox(height: 20),

                // Individual Cells Header
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.battery_5_bar,
                        color: theme.colorScheme.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'BATTERY CELLS',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Individual Cells Grid
                _buildCellsGrid(provider.cells),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCellsGrid(List<BatteryCell> cells) {
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    int crossAxisCount = isPortrait ? 2 : 4;
    
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 1.5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: cells.length,
      itemBuilder: (context, index) => _buildCellCard(cells[index]),
    );
  }

  Color _getTemperatureColor(double temperature) {
    if (temperature < 20) return Colors.blue;
    if (temperature < 30) return Colors.green;
    if (temperature < 40) return Colors.orange;
    return Colors.red;
  }

  Color _getVoltageColor(double voltage) {
    if (voltage < 3.0) return Colors.red;
    if (voltage < 3.5) return Colors.orange;
    if (voltage < 4.2) return Colors.green;
    return Colors.red;
  }
  
  Color _getSocColor(double soc) {
    if (soc < 20) return Colors.red;
    if (soc < 40) return Colors.orange;
    if (soc < 80) return Colors.amber;
    return Colors.green;
  }
}