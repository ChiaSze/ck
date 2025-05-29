import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'battery_provider.dart';
import 'battery_status_page.dart';
import 'characteristics_page.dart';
import 'history_page.dart';
import 'home_page.dart';
import 'warning_page.dart';
import 'bluetooth_provider.dart';

// Global navigator key for app-wide navigation
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Global navigation state key
final GlobalKey<MainNavigationPageState> mainNavigationKey = GlobalKey<MainNavigationPageState>();

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    print('Flutter binding initialized');
    
    bool firebaseInitialized = false;
    // Initialize Firebase with more detailed logging
    try {
      print('Attempting to initialize Firebase...');
      await Firebase.initializeApp();
      print('Firebase initialized successfully');
      print('Firebase apps: ${Firebase.apps.length}');
      print('Default app name: ${Firebase.app().name}');
      print('Firebase options: ${Firebase.app().options.projectId}');
      firebaseInitialized = true;
    } catch (e, stackTrace) {
      print('Firebase initialization error: $e');
      print('Stack trace: $stackTrace');
      print('App will run without Firebase functionality');
    }

    final batteryProvider = BatteryProvider(firebaseEnabled: firebaseInitialized);
    try {
      await batteryProvider.initialize();
      print('Battery provider initialized successfully');
      print('Firebase enabled in provider: ${batteryProvider.isFirebaseEnabled}');
      
      // Start periodic sync only if Firebase is initialized
      if (firebaseInitialized) {
        print('Starting periodic Firebase sync');
        batteryProvider.startPeriodicSync();
      }
    } catch (e) {
      print('Error initializing battery provider: $e');
    }

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => BluetoothProvider()),
          ChangeNotifierProvider.value(value: batteryProvider),
        ],
        child: const MyApp(),
      ),
    );
  } catch (e, stackTrace) {
    print('Error in main: $e');
    print('Stack trace: $stackTrace');
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'App initialization failed',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Error: $e',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => main(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BluetoothProvider()),
        ChangeNotifierProvider(create: (_) => BatteryProvider()),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
          navigationBarTheme: const NavigationBarThemeData(
            backgroundColor: Colors.white,
            labelTextStyle: WidgetStatePropertyAll(
              TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ),
        home: const MainNavigationPage(),
        builder: (context, child) {
          // Set up warning notification callback
          final batteryProvider = Provider.of<BatteryProvider>(context, listen: false);
          batteryProvider.setWarningNotificationCallback((type, details) {
            _showWarningNotification(context, type);
          });
          
          return child!;
        },
      ),
    );
  }

  void _showWarningNotification(BuildContext context, String warningType) {
    // Show a snackbar notification
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'BMS Warning: $warningType',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Text(
                    'Tap to view details',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        action: SnackBarAction(
          label: 'VIEW',
          textColor: Colors.white,
          onPressed: () {
            // Navigate to warning page
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const WarningPage(),
              ),
            );
          },
        ),
      ),
    );
  }
}

// Navigation helper function accessible globally
void navigateToBatteryPage(BuildContext context) {
  mainNavigationKey.currentState?.navigateTo(1);
}

class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => MainNavigationPageState();
}

class MainNavigationPageState extends State<MainNavigationPage> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    print('MainNavigationPage initialized');
    // Initialize Bluetooth connection
    Future.delayed(Duration.zero, () {
      if (mounted) {
        try {
          final bluetoothProvider = Provider.of<BluetoothProvider>(context, listen: false);
          bluetoothProvider.checkDeviceConnection();
          print('Bluetooth connection check initiated');
        } catch (e) {
          print('Error checking Bluetooth connection: $e');
        }
      }
    });
  }

  // Public method to change pages
  void navigateTo(int index) {
    print('Navigating to index: $index');
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    print('Building MainNavigationPage');
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          const HomePage(),
          // Battery Status Page with connection check
          Consumer2<BluetoothProvider, BatteryProvider>(
            builder: (context, bluetoothProvider, batteryProvider, _) {
              print('Building Battery Status Page');
              final isConnected = bluetoothProvider.connectedDevice != null;
              final hasNotifyChar = batteryProvider.notifyCharacteristic != null;
              final hasWriteChar = batteryProvider.writeCharacteristic != null;
              final hasRequiredCharacteristics = hasNotifyChar && hasWriteChar;
              
              if (!isConnected || !hasRequiredCharacteristics) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isConnected ? Icons.bluetooth_searching : Icons.bluetooth_disabled,
                        size: 48,
                        color: isConnected ? Colors.orange : Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        isConnected 
                          ? 'Waiting for BLE characteristics...'
                          : 'No device connected',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: isConnected ? Colors.orange : Colors.grey,
                        ),
                      ),
                      if (isConnected) ...[
                        const SizedBox(height: 8),
                        Text(
                          'FFF1: ${hasNotifyChar ? "✓" : "✗"} FFF2: ${hasWriteChar ? "✓" : "✗"}',
                          style: TextStyle(
                            fontSize: 12,
                            color: hasRequiredCharacteristics ? Colors.green : Colors.orange,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }
              
              return const BatteryStatusPage();
            },
          ),
          const WarningPage(),
          const HistoryPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: navigateTo,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.inventory_2),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.battery_full),
            label: 'Battery',
          ),
          NavigationDestination(
            icon: Icon(Icons.warning),
            label: 'Warning',
          ),
          NavigationDestination(
            icon: Icon(Icons.history),
            label: 'History',
          ),
        ],
      ),
    );
  }
}