import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:busspass/core/ui/responsive_wrapper.dart';
import 'package:busspass/data/providers/app_providers.dart';
import 'package:busspass/data/providers/state_provider.dart';
import 'package:busspass/data/models/network_models.dart';
import 'package:busspass/data/models/ticket.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:busspass/features/journey/presentation/journey_details_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/app_theme.dart';
import 'package:intl/intl.dart';
import 'dart:ui';

class JourneySearchScreen extends ConsumerStatefulWidget {
  /// Pre-fill the origin — e.g. the stop selected on the map tab. The map's
  /// "Find Routes from here" used to open a blank search and discard it.
  final NetworkStop? initialOrigin;

  const JourneySearchScreen({super.key, this.initialOrigin});

  @override
  ConsumerState<JourneySearchScreen> createState() =>
      _JourneySearchScreenState();
}

class _JourneySearchScreenState extends ConsumerState<JourneySearchScreen> {
  NetworkStop? _selectedOrigin;
  NetworkStop? _selectedDestination;
  DateTime _departDate = DateTime.now();
  TimeOfDay _departTime = TimeOfDay.now();
  int _adultCount = 1;
  int _ladyCount = 0;
  int _childCount = 0;

  @override
  void initState() {
    super.initState();
    _selectedOrigin = widget.initialOrigin;
  }

  bool _isLocating = false;

  Future<void> _openLocationPicker(String title, bool isOrigin) async {
    final stop = await showModalBottomSheet<NetworkStop>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _LocationPickerModal(
        title: title,
        onLocateMe: isOrigin ? _locateMe : null,
        isLocating: _isLocating,
        isOrigin: isOrigin,
      ),
    );

    if (stop != null) {
      setState(() {
        if (isOrigin) {
          _selectedOrigin = stop;
        } else {
          _selectedDestination = stop;
        }
      });
    }
  }

  Future<void> _locateMe() async {
    setState(() => _isLocating = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Location permissions denied.')),
            );
          }
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Location permissions permanently denied.')),
          );
        }
        return;
      }
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 5),
        ),
      ).catchError((_) {
        throw Exception('Location request timed out. Please enter manually.');
      });
      
      final allStops = ref.read(allStopsProvider).value ?? [];
      if (allStops.isEmpty) return;

      NetworkStop? nearest;
      double minDistance = double.infinity;
      for (var stop in allStops) {
        double distance = Geolocator.distanceBetween(
            position.latitude, position.longitude, stop.lat, stop.lng);
        if (distance < minDistance) {
          minDistance = distance;
          nearest = stop;
        }
      }
      if (nearest != null) {
        if (mounted) {
          Navigator.pop(context, nearest); // Close modal and return stop
        }
      }
    } catch (e) {
      debugPrint('Locate error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                const Text('Could not get GPS location. Please type manually.'),
            backgroundColor: context.palette.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _departDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: context.palette.brand,
              onPrimary: Colors.white,
              onSurface: context.palette.ink,
            ),
          ),
          child: child!,
        );
      },
    );
    if (date != null) {
      setState(() => _departDate = date);
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _departTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: context.palette.brand,
              onPrimary: Colors.white,
              onSurface: context.palette.ink,
            ),
          ),
          child: child!,
        );
      },
    );
    if (time != null) {
      setState(() => _departTime = time);
    }
  }

  void _swapLocations() {
    setState(() {
      final temp = _selectedOrigin;
      _selectedOrigin = _selectedDestination;
      _selectedDestination = temp;
    });
  }

  String _getFullSTCName(String code, String fallbackState) {
    return '$code ($fallbackState)';
  }

  void _searchBuses() {
    if (_selectedOrigin == null || _selectedDestination == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select origin and destination'),
          backgroundColor: context.palette.danger,
        ),
      );
      return;
    }

    if (_adultCount + _ladyCount + _childCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select at least one passenger'),
          backgroundColor: context.palette.danger,
        ),
      );
      return;
    }

    final combinedDate = DateTime(
      _departDate.year,
      _departDate.month,
      _departDate.day,
      _departTime.hour,
      _departTime.minute,
    );

    // Persist the search so home shortcuts, frequent-route chips, and travel
    // pattern reminders all learn from it. Fire and forget.
    ref.read(recentSearchesProvider.notifier).record(
          origin: _selectedOrigin!,
          destination: _selectedDestination!,
        );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JourneyDetailsScreen(
          originId: _selectedOrigin!.id,
          destinationId: _selectedDestination!.id,
          departAfter: combinedDate,
          adultCount: _adultCount,
          ladyCount: _ladyCount,
          childCount: _childCount,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final screenWidth = MediaQuery.sizeOf(context).width;
    
    return ResponsiveWrapper(
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: palette.ink),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Stack(
          children: [
            // Background UI
            Positioned(
              top: -screenWidth * 0.2,
              right: -screenWidth * 0.2,
              child: Container(
                width: screenWidth * 0.7,
                height: screenWidth * 0.7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.brand.withValues(alpha: 0.15),
              ),
            ).animate(onPlay: (controller) => controller.repeat()).effect(
              duration: 10.seconds,
              curve: Curves.easeInOutSine,
            ),
          ),
          Positioned(
            top: screenWidth * 0.4,
            left: -screenWidth * 0.25,
            child: Container(
              width: screenWidth * 0.6,
              height: screenWidth * 0.6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.accent.withValues(alpha: 0.15),
              ),
            ).animate(onPlay: (controller) => controller.repeat()).effect(
              duration: 8.seconds,
              curve: Curves.easeInOutSine,
            ),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            child: Container(color: Colors.transparent),
          ),

          // Main Content
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Where to next?',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: palette.ink,
                          letterSpacing: -0.5,
                        ),
                  ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.2),
                  const SizedBox(height: AppSpacing.lg),

                  // The Glassmorphic Search Card
                  Container(
                    decoration: BoxDecoration(
                      color: palette.surface.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                      boxShadow: [
                        BoxShadow(
                          color: palette.ink.withValues(alpha: 0.05),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Location Section
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Column(
                                children: [
                                  _LocationSelector(
                                    label: 'Leaving from',
                                    icon: Icons.my_location_rounded,
                                    iconColor: palette.brand,
                                    value: _selectedOrigin?.name,
                                    onTap: () => _openLocationPicker('Leaving from', true),
                                  ),
                                  
                                  // Prominent Animated Travel Indicator
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Padding(
                                        padding: const EdgeInsets.only(left: 30.0),
                                        child: Row(
                                          children: [
                                            Column(
                                              children: [
                                                Container(width: 2, height: 4, color: palette.inkSoft.withValues(alpha: 0.3)),
                                                const SizedBox(height: 2),
                                                Container(width: 2, height: 4, color: palette.inkSoft.withValues(alpha: 0.3)),
                                                const SizedBox(height: 2),
                                                Container(width: 2, height: 4, color: palette.inkSoft.withValues(alpha: 0.3)),
                                              ],
                                            ),
                                            const SizedBox(width: 12),
                                            Icon(Icons.directions_bus_rounded, color: palette.brand, size: 18)
                                                .animate(onPlay: (controller) => controller.repeat())
                                                .moveY(begin: -6, end: 6, duration: 1.5.seconds, curve: Curves.easeInOut)
                                                .fadeIn(duration: 500.ms),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  
                                  _LocationSelector(
                                    label: 'Going to',
                                    icon: Icons.location_on_rounded,
                                    iconColor: palette.accent,
                                    value: _selectedDestination?.name,
                                    onTap: () => _openLocationPicker('Going to', false),
                                  ),
                                ],
                              ),
                              Positioned(
                                right: AppSpacing.md,
                                child: GestureDetector(
                                  onTap: _swapLocations,
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: palette.canvas,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: palette.ink.withValues(alpha: 0.1),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                      border: Border.all(color: palette.hairline),
                                    ),
                                    child: Icon(Icons.swap_vert_rounded,
                                        color: palette.inkSoft, size: 22),
                                  ),
                                ).animate(target: _selectedOrigin != null && _selectedDestination != null ? 1 : 0)
                                 .scale(duration: 200.ms, curve: Curves.easeOutBack),
                              ),
                            ],
                          ),
                        ),
                        
                        const Divider(height: 1),
                        
                        // Date & Time Section
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Row(
                            children: [
                              Expanded(
                                child: _InfoSelector(
                                  icon: Icons.calendar_today_rounded,
                                  label: 'Date',
                                  value: DateFormat('E, d MMM').format(_departDate),
                                  onTap: _pickDate,
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 40,
                                color: palette.hairline,
                                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                              ),
                              Expanded(
                                child: _InfoSelector(
                                  icon: Icons.access_time_rounded,
                                  label: 'Time',
                                  value: _departTime.format(context),
                                  onTap: _pickTime,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const Divider(height: 1),

                        // Passengers Section
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Passengers',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: palette.inkMuted,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              Column(
                                children: [
                                  _PassengerCounter(
                                    title: 'Adults',
                                    subtitle: 'Full fare',
                                    count: _adultCount,
                                    onChanged: (val) => setState(() => _adultCount = val),
                                    min: 1,
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  _PassengerCounter(
                                    title: 'Ladies',
                                    subtitle: '50% Off (Mahila Samman)',
                                    count: _ladyCount,
                                    onChanged: (val) => setState(() => _ladyCount = val),
                                    min: 0,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(duration: 500.ms, delay: 100.ms).slideY(begin: 0.1),

                  const SizedBox(height: AppSpacing.lg),

                  // Search Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _searchBuses,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: palette.brand,
                        foregroundColor: Colors.white,
                        elevation: 4,
                        shadowColor: palette.brand.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                        ),
                      ),
                      child: const Text(
                        'Search Buses',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ).animate().fadeIn(duration: 500.ms, delay: 200.ms).scale(curve: Curves.easeOutBack),
                  
                  const SizedBox(height: AppSpacing.lg),
                  
                  // Powered By STC
                  Consumer(
                    builder: (context, ref, child) {
                      final stc = ref.watch(effectiveSTCProvider);
                      
                      final color = Color(stc.badgeColor);
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Powered by',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: palette.inkMuted,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.5,
                                ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 20,
                            height: 20,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                'assets/ST-logos/${stc.stcCode.toLowerCase()}.png',
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) =>
                                    Icon(Icons.directions_bus_rounded, color: color, size: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _getFullSTCName(stc.stcCode, stc.stateName),
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: palette.ink,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                          ),
                        ],
                      ).animate().fadeIn(delay: 300.ms);
                    },
                  ),
                  
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    ));
  }
}

class _LocationSelector extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color iconColor;
  final String? value;
  final VoidCallback onTap;

  const _LocationSelector({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: palette.canvas,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: palette.inkSoft.withValues(alpha: 0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: palette.ink.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: palette.inkMuted,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value ?? 'Select Location',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: value != null ? palette.ink : palette.inkMuted,
                          fontWeight: value != null ? FontWeight.w700 : FontWeight.w500,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoSelector extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _InfoSelector({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Icon(icon, color: palette.inkSoft, size: 20),
          const SizedBox(width: AppSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.inkMuted,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: palette.ink,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PassengerCounter extends StatelessWidget {
  final String title;
  final String subtitle;
  final int count;
  final int min;
  final ValueChanged<int> onChanged;

  const _PassengerCounter({
    required this.title,
    required this.subtitle,
    required this.count,
    required this.min,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.ink,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: palette.inkMuted,
                  ),
            ),
          ],
        ),
        Row(
          children: [
            _CounterButton(
              icon: Icons.remove_rounded,
              onTap: count > min ? () => onChanged(count - 1) : null,
            ),
            SizedBox(
              width: 36,
              child: Text(
                count.toString(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: palette.ink,
                    ),
              ),
            ),
            _CounterButton(
              icon: Icons.add_rounded,
              onTap: count < 9 ? () => onChanged(count + 1) : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _CounterButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _CounterButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: enabled ? palette.brand.withValues(alpha: 0.1) : palette.canvas,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: enabled ? palette.brand.withValues(alpha: 0.2) : palette.hairline,
          ),
        ),
        child: Icon(
          icon,
          size: 18,
          color: enabled ? palette.brand : palette.inkMuted.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

// ── Location Picker Bottom Sheet ─────────────────────────────────────────────

class _LocationPickerModal extends ConsumerStatefulWidget {
  final String title;
  final VoidCallback? onLocateMe;
  final bool isLocating;

  /// Which end of the journey is being picked — recent routes offer the
  /// matching endpoint first.
  final bool isOrigin;

  const _LocationPickerModal({
    required this.title,
    this.onLocateMe,
    this.isLocating = false,
    this.isOrigin = true,
  });

  @override
  ConsumerState<_LocationPickerModal> createState() => _LocationPickerModalState();
}

class _LocationPickerModalState extends ConsumerState<_LocationPickerModal> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<NetworkStop> _filteredStops = [];
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query, List<NetworkStop> allStops) {
    if (query.isEmpty) {
      setState(() {
        _filteredStops = [];
        _isTyping = false;
      });
      return;
    }
    final q = query.toLowerCase();
    setState(() {
      _isTyping = true;
      _filteredStops = allStops
          .where((stop) =>
              stop.name.toLowerCase().contains(q) ||
              stop.city.toLowerCase().contains(q) ||
              stop.depot.toLowerCase().contains(q) ||
              stop.district.toLowerCase().contains(q))
          .take(15)
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final stopsAsync = ref.watch(allStopsProvider);

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 20),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: palette.hairline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Row(
              children: [
                Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: palette.ink,
                      ),
                ),
                const Spacer(),
                if (widget.onLocateMe != null)
                  TextButton.icon(
                    onPressed: widget.isLocating ? null : widget.onLocateMe,
                    icon: widget.isLocating
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: palette.brand),
                          )
                        : Icon(Icons.my_location_rounded, size: 18, color: palette.brand),
                    label: Text(
                      'Current Location',
                      style: TextStyle(color: palette.brand, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Search Field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Container(
              decoration: BoxDecoration(
                color: palette.canvas,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                border: Border.all(color: palette.hairline),
              ),
              child: TextField(
                controller: _searchController,
                focusNode: _focusNode,
                style: Theme.of(context).textTheme.bodyLarge,
                decoration: InputDecoration(
                  hintText: 'Search city, station, or district...',
                  hintStyle: TextStyle(color: palette.inkMuted),
                  border: InputBorder.none,
                  prefixIcon: Icon(Icons.search_rounded, color: palette.inkSoft),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close_rounded, color: palette.inkSoft, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('', ref.read(allStopsProvider).value ?? []);
                          },
                        )
                      : null,
                ),
                onChanged: (val) {
                  stopsAsync.whenData((stops) => _onSearchChanged(val, stops));
                },
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1),

          // Results
          Expanded(
            child: stopsAsync.when(
              loading: () => Center(child: CircularProgressIndicator(color: palette.brand)),
              error: (err, _) => Center(child: Text('Error loading stops: $err')),
              data: (stops) {
                if (!_isTyping) {
                  return _buildRecentSearches(context);
                }
                if (_filteredStops.isEmpty) {
                  return Center(
                    child: Text(
                      'No stops found',
                      style: TextStyle(color: palette.inkMuted),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  itemCount: _filteredStops.length,
                  separatorBuilder: (context, index) => const Divider(height: 1, indent: 64),
                  itemBuilder: (context, index) {
                    final stop = _filteredStops[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xl, vertical: AppSpacing.xs),
                      leading: Container(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: palette.canvas,
                          shape: BoxShape.circle,
                          border: Border.all(color: palette.hairline),
                        ),
                        child: Icon(Icons.directions_bus_rounded, color: palette.inkSoft, size: 18),
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              stop.name,
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 15),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _StcBadge(stcCode: ref.watch(activeSTCProvider)),
                        ],
                      ),
                      subtitle: Text(
                        stop.subtitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12),
                      ),
                      onTap: () => Navigator.pop(context, stop),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentSearches(BuildContext context) {
    final palette = context.palette;
    final network = ref.watch(networkProvider).value;
    final saved = ref.watch(savedPlacesProvider);
    final recents = ref.watch(recentSearchesProvider);

    // Resolve the saved stops referenced by recents on the active network.
    // Search rows whose endpoint ids don't exist here (e.g. after a state
    // switch) are dropped rather than shown broken.
    NetworkStop? stopById(String id) => network?.stopById(id);

    final suggestions = <({NetworkStop stop, IconData icon, String label})>[];
    for (final place in saved) {
      final stop = stopById(place.stopId);
      if (stop == null) continue;
      suggestions.add((
        stop: stop,
        icon: place.kind == SavedPlaceKind.home
            ? Icons.home_rounded
            : place.kind == SavedPlaceKind.work
                ? Icons.work_rounded
                : Icons.star_rounded,
        label: place.label,
      ));
    }
    for (final r in recents.take(8)) {
      final stop = widget.isOrigin
          ? stopById(r.originStopId)
          : stopById(r.destinationStopId);
      if (stop == null) continue;
      if (suggestions.any((s) => s.stop.id == stop.id)) continue;
      suggestions.add((
        stop: stop,
        icon: Icons.history_rounded,
        label: widget.isOrigin
            ? 'From ${r.originName}'
            : 'To ${r.destinationName}',
      ));
      if (suggestions.length >= 10) break;
    }

    if (suggestions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded,
                size: 48, color: palette.hairlineStrong),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Start typing to search',
              style: TextStyle(color: palette.inkMuted),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Your saved places and recent stops will appear here',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl, vertical: AppSpacing.md),
          child: Text(
            'SUGGESTED',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 0.8,
                ),
          ),
        ),
        ...suggestions.map((s) => ListTile(
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl, vertical: 0),
              leading: Icon(s.icon, color: palette.inkSoft, size: 20),
              title: Text(
                s.stop.name.isEmpty ? s.stop.city : s.stop.name,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500),
              ),
              subtitle: Text(s.label),
              onTap: () => Navigator.pop(context, s.stop),
            )),
      ],
    );
  }
}

class _StcBadge extends StatelessWidget {
  final String stcCode;
  const _StcBadge({required this.stcCode});

  @override
  Widget build(BuildContext context) {
    final meta = stcMetaFor(stcCode);
    final color = Color(meta.badgeColor);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/ST-logos/${meta.stcCode.toLowerCase()}.png',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    Icon(Icons.directions_bus, size: 10, color: color),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            meta.stcCode,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
