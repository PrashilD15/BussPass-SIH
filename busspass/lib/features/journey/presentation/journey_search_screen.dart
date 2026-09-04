import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:busspass/data/providers/app_providers.dart';
import 'package:busspass/data/models/network_models.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:busspass/features/journey/presentation/journey_details_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/app_theme.dart';

class JourneySearchScreen extends ConsumerStatefulWidget {
  const JourneySearchScreen({super.key});

  @override
  ConsumerState<JourneySearchScreen> createState() =>
      _JourneySearchScreenState();
}

class _JourneySearchScreenState extends ConsumerState<JourneySearchScreen> {
  final TextEditingController _toController = TextEditingController();
  final TextEditingController _fromController = TextEditingController();
  final FocusNode _toFocusNode = FocusNode();
  final FocusNode _fromFocusNode = FocusNode();

  List<NetworkStop> _filteredStops = [];
  bool _isTyping = false;
  bool _isLocating = false;
  NetworkStop? _selectedOrigin;
  NetworkStop? _selectedDestination;
  String _activeField = 'to';

  @override
  void initState() {
    super.initState();
    _fromFocusNode.addListener(() {
      if (_fromFocusNode.hasFocus) {
        setState(() {
          _activeField = 'from';
          _onSearchChanged(
              _fromController.text, ref.read(allStopsProvider).value ?? []);
        });
      }
    });
    _toFocusNode.addListener(() {
      if (_toFocusNode.hasFocus) {
        setState(() {
          _activeField = 'to';
          _onSearchChanged(
              _toController.text, ref.read(allStopsProvider).value ?? []);
        });
      }
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _toFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _toController.dispose();
    _fromController.dispose();
    _toFocusNode.dispose();
    _fromFocusNode.dispose();
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
          .take(10)
          .toList();
    });
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
        final origin = nearest;
        setState(() {
          _selectedOrigin = origin;
          _fromController.text = origin.name;
          _activeField = 'to';
        });
        _checkAndNavigate();
        if (_selectedDestination == null) {
          _toFocusNode.requestFocus();
        }
      }
    } catch (e) {
      debugPrint('Locate error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                const Text('Could not get GPS location. Please type manually.'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _checkAndNavigate() async {
    if (_selectedOrigin == null || _selectedDestination == null) return;
    final origin = _selectedOrigin!;
    final dest = _selectedDestination!;

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => JourneyDetailsScreen(
            originId: origin.id,
            destinationId: dest.id,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final stopsAsync = ref.watch(allStopsProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Plan Journey'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // ── Search Header ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl, 4, AppSpacing.xl, AppSpacing.xl),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(
                bottom: BorderSide(color: AppColors.hairline),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Timeline Graphics
                Column(
                  children: [
                    const SizedBox(height: 14),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: AppColors.brand,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Container(
                      height: 36,
                      width: 1,
                      color: AppColors.hairline,
                    ),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: stopsAsync.when(
                    data: (allStops) => Column(
                      children: [
                        _SearchInput(
                          controller: _fromController,
                          focusNode: _fromFocusNode,
                          hint: 'From where?',
                          onChanged: (val) => _onSearchChanged(val, allStops),
                          suffixIcon: _isLocating
                              ? const Padding(
                                  padding: EdgeInsets.all(12.0),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.brand,
                                    ),
                                  ),
                                )
                              : IconButton(
                                  icon: const Icon(
                                    Icons.gps_fixed_rounded,
                                    color: AppColors.brand,
                                    size: 20,
                                  ),
                                  onPressed: _locateMe,
                                ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _SearchInput(
                          controller: _toController,
                          focusNode: _toFocusNode,
                          hint: 'Where to?',
                          onChanged: (val) => _onSearchChanged(val, allStops),
                        ),
                      ],
                    ),
                    loading: () => Column(
                      children: [
                        _SearchInput(
                            controller: _fromController,
                            hint: 'Loading stops...',
                            readOnly: true),
                        const SizedBox(height: AppSpacing.md),
                        _SearchInput(
                            controller: _toController,
                            hint: 'Loading stops...',
                            readOnly: true),
                      ],
                    ),
                    error: (_, _) => Column(
                      children: [
                        _SearchInput(
                            controller: _fromController,
                            hint: 'Error loading stops',
                            readOnly: true),
                        const SizedBox(height: AppSpacing.md),
                        _SearchInput(
                            controller: _toController,
                            hint: 'Error loading stops',
                            readOnly: true),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Results Area ──────────────────────────────────────────
          Expanded(
            child: _isTyping ? _buildSearchResults() : _buildRecentSearches(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_filteredStops.isEmpty) {
      return Center(
        child: Text(
          'No stops found',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: _filteredStops.length,
      separatorBuilder: (context, index) =>
          const Divider(height: 1, indent: 64),
      itemBuilder: (context, index) {
        final stop = _filteredStops[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl, vertical: AppSpacing.xs),
          leading: Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.canvas,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.hairline),
            ),
            child: const Icon(
              Icons.directions_bus_rounded,
              color: AppColors.inkMuted,
              size: 18,
            ),
          ),
          title: Text(
            stop.name,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontSize: 15),
          ),
          subtitle: Text(
            stop.city,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontSize: 12),
          ),
          onTap: () {
            if (_activeField == 'from') {
              setState(() {
                _selectedOrigin = stop;
                _fromController.text = stop.name;
                _isTyping = false;
              });
              if (_selectedDestination == null) {
                _toFocusNode.requestFocus();
              } else {
                _checkAndNavigate();
              }
            } else {
              setState(() {
                _selectedDestination = stop;
                _toController.text = stop.name;
                _isTyping = false;
              });
              if (_selectedOrigin == null) {
                _fromFocusNode.requestFocus();
              } else {
                _checkAndNavigate();
              }
            }
          },
        ).animate().fadeIn(duration: 200.ms, delay: (index * 20).ms);
      },
    );
  }

  Widget _buildRecentSearches() {
    final recent = ref.watch(recentSearchesProvider);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl, vertical: AppSpacing.sm),
          child: Text(
            'Recent Searches',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        if (recent.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Text(
              'No recent searches yet. Search to plan a journey.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 13,
                    color: AppColors.inkMuted,
                  ),
            ),
          )
        else
          ...recent.map((r) => _RecentItem(
                originId: r.originStopId,
                destinationId: r.destinationStopId,
                title: r.originName,
                subtitle: '→ ${r.destinationName}',
              )),
      ],
    ).animate().fadeIn();
  }
}

class _SearchInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool readOnly;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final Widget? suffixIcon;

  const _SearchInput({
    required this.controller,
    required this.hint,
    this.readOnly = false,
    this.focusNode,
    this.onChanged,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.hairline),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        readOnly: readOnly,
        onChanged: onChanged,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontSize: 14, color: AppColors.inkMuted),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: suffixIcon != null ? 10 : 14),
          isDense: true,
          suffixIcon: suffixIcon,
        ),
      ),
    );
  }
}

class _RecentItem extends ConsumerWidget {
  final String originId;
  final String destinationId;
  final String title;
  final String subtitle;

  const _RecentItem({
    required this.originId,
    required this.destinationId,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl, vertical: AppSpacing.xs),
      leading: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.canvas,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.hairline),
        ),
        child: const Icon(Icons.history_rounded,
            color: AppColors.inkMuted, size: 18),
      ),
      title: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(fontSize: 14),
      ),
      subtitle: Text(
        subtitle,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(fontSize: 12),
      ),
      onTap: () {
        if (context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => JourneyDetailsScreen(
                originId: originId,
                destinationId: destinationId,
              ),
            ),
          );
        }
      },
    );
  }
}
