import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'battery_provider.dart';

class WarningPage extends StatelessWidget {
  const WarningPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'BMS Warnings',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_outlined, size: 20),
            tooltip: 'Add Test Warnings',
            onPressed: () => _showTestWarningDialog(context),
          ),
          Consumer<BatteryProvider>(
            builder: (context, provider, _) {
              if (provider.bmsErrors.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: 'Clear All Warnings',
                onPressed: () => _showClearConfirmation(context, provider),
              );
            },
          ),
        ],
      ),
      body: Consumer<BatteryProvider>(
        builder: (context, provider, _) {
          if (provider.bmsErrors.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 64,
                    color: theme.colorScheme.primary.withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No Active Warnings',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'All systems are operating normally',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: provider.bmsErrors.length,
            itemBuilder: (context, index) {
              final error = provider.bmsErrors[index];
              return _buildErrorCard(context, error);
            },
          );
        },
      ),
    );
  }

  Widget _buildErrorCard(BuildContext context, BmsError error) {
    final theme = Theme.of(context);
    final color = _getErrorColor(error.type);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    _getErrorIcon(error.type),
                    color: color,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        error.type.toUpperCase(),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatTimestamp(error.timestamp),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatExactTime(error.timestamp),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (error.details != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  error.details!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: theme.colorScheme.primaryContainer,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.dashboard,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Visit the dashboard for further details.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
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

  String _formatExactTime(DateTime timestamp) {
    // Format: "MMM dd, yyyy at HH:mm:ss"
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final month = months[timestamp.month - 1];
    final day = timestamp.day.toString().padLeft(2, '0');
    final year = timestamp.year;
    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final second = timestamp.second.toString().padLeft(2, '0');
    
    return '$month $day, $year at $hour:$minute:$second';
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 0) {
      return '${difference.inDays} ${difference.inDays == 1 ? 'day' : 'days'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} ${difference.inHours == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} ${difference.inMinutes == 1 ? 'minute' : 'minutes'} ago';
    } else if (difference.inSeconds > 30) {
      return '${difference.inSeconds} seconds ago';
    } else {
      return 'Just now';
    }
  }

  Color _getErrorColor(String errorType) {
    switch (errorType.toLowerCase()) {
      case 'overvoltage':
      case 'overcurrent':
      case 'overtemperature':
        return Colors.red;
      case 'undervoltage':
      case 'undertemperature':
        return Colors.orange;
      case 'cell imbalance':
        return Colors.amber;
      case 'charging error':
      case 'discharging error':
        return Colors.purple;
      case 'communication error':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  IconData _getErrorIcon(String errorType) {
    switch (errorType.toLowerCase()) {
      case 'overvoltage':
      case 'undervoltage':
        return Icons.electric_bolt;
      case 'overcurrent':
        return Icons.power;
      case 'overtemperature':
      case 'undertemperature':
        return Icons.thermostat;
      case 'cell imbalance':
        return Icons.battery_alert;
      case 'charging error':
        return Icons.charging_station;
      case 'discharging error':
        return Icons.power_off;
      case 'communication error':
        return Icons.bluetooth_disabled;
      default:
        return Icons.warning;
    }
  }

  Future<void> _showClearConfirmation(BuildContext context, BatteryProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Warnings'),
        content: const Text('Are you sure you want to clear all warning history?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('CLEAR'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await provider.clearErrors();
    }
  }

  Future<void> _showTestWarningDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Test Warnings'),
        content: const Text(
          'This will add a series of test warnings to verify the warning system. '
          'Existing warnings will be cleared first.\n\n'
          'Do you want to proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ADD TEST DATA'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final provider = Provider.of<BatteryProvider>(context, listen: false);
      provider.addTestWarnings();
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Test warnings added'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
} 