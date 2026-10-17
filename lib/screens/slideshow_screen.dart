import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SlideshowScreen extends StatefulWidget {
  final String albumId;
  final String albumName;

  const SlideshowScreen({
    super.key,
    required this.albumId,
    required this.albumName,
  });

  @override
  State<SlideshowScreen> createState() => _SlideshowScreenState();
}

class _SlideshowScreenState extends State<SlideshowScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _photos = [];
  int _currentIndex = 0;
  bool _isPlaying = true;
  bool _isLoading = true;

  Timer? _timer;
  RealtimeChannel? _channel;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  static const _slideDuration = Duration(seconds: 4);
  static const _fadeDuration = Duration(milliseconds: 800);

  @override
  void initState() {
    super.initState();

    // Animation de fondu
    _fadeController = AnimationController(
      vsync: this,
      duration: _fadeDuration,
      value: 1.0,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );

    // Cacher la barre système pour un vrai plein écran
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _loadPhotos();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _channel?.unsubscribe();
    _fadeController.dispose();
    // Restaurer l'UI système
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _loadPhotos() async {
    try {
      final data = await _supabase
          .from('media')
          .select()
          .eq('album_id', widget.albumId)
          .order('created_at', ascending: false);

      final photosWithUrls = <Map<String, dynamic>>[];
      for (final photo in data) {
        final signedUrl = await _supabase.storage
            .from('family-media')
            .createSignedUrl(photo['storage_path'], 3600);
        photosWithUrls.add({...photo, 'url': signedUrl});
      }

      setState(() {
        _photos = photosWithUrls;
        _isLoading = false;
      });

      if (_photos.isNotEmpty) _startTimer();
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _subscribeRealtime() {
    _channel = _supabase
        .channel('slideshow-${widget.albumId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'media',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'album_id',
            value: widget.albumId,
          ),
          callback: (payload) async {
            final newMedia = payload.newRecord;
            final signedUrl = await _supabase.storage
                .from('family-media')
                .createSignedUrl(newMedia['storage_path'], 3600);

            if (mounted) {
              setState(() {
                _photos.add({...newMedia, 'url': signedUrl});
              });
            }
          },
        )
        .subscribe();
  }

  void _startTimer() {
    _timer?.cancel();
    if (!_isPlaying || _photos.length < 2) return;

    _timer = Timer.periodic(_slideDuration, (_) {
      _goToNext();
    });
  }

  void _goToNext() {
    if (_photos.isEmpty) return;

    _fadeController.reverse().then((_) {
      setState(() {
        _currentIndex = (_currentIndex + 1) % _photos.length;
      });
      _fadeController.forward();
    });
  }

  void _goToPrevious() {
    if (_photos.isEmpty) return;

    _fadeController.reverse().then((_) {
      setState(() {
        _currentIndex =
            (_currentIndex - 1 + _photos.length) % _photos.length;
      });
      _fadeController.forward();
    });
  }

  void _togglePlay() {
    setState(() => _isPlaying = !_isPlaying);
    if (_isPlaying) {
      _startTimer();
    } else {
      _timer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_photos.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.photo_library_outlined,
                  size: 64, color: Colors.white54),
              SizedBox(height: 16),
              Text(
                'Aucune photo à afficher',
                style: TextStyle(color: Colors.white70, fontSize: 18),
              ),
            ],
          ),
        ),
      );
    }

    final currentPhoto = _photos[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Photo avec fondu
          Positioned.fill(
            child: GestureDetector(
              onTap: _togglePlay,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: InteractiveViewer(
                  panEnabled: false,
                  scaleEnabled: false,
                  child: Image.network(
                    currentPhoto['url'],
                    fit: BoxFit.contain,
                    gaplessPlayback: true, // évite le flash noir
                  ),
                ),
              ),
            ),
          ),

          // Overlay boutons fermer
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black38,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ),

          // Navigation gauche / droite
          if (_photos.length > 1) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: const Icon(Icons.chevron_left,
                    color: Colors.white, size: 48),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black26,
                ),
                onPressed: _goToPrevious,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: const Icon(Icons.chevron_right,
                    color: Colors.white, size: 48),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black26,
                ),
                onPressed: _goToNext,
              ),
            ),
          ],

          // Indicateur bas : compteur + play/pause + points
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.6),
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Points indicateurs
                    if (_photos.length <= 20)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_photos.length, (i) {
                          return Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i == _currentIndex
                                  ? Colors.white
                                  : Colors.white38,
                            ),
                          );
                        }),
                      ),
                    const SizedBox(height: 8),
                    // Compteur + play/pause
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${_currentIndex + 1} / ${_photos.length}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(width: 16),
                        IconButton(
                          icon: Icon(
                            _isPlaying
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_filled,
                            color: Colors.white,
                            size: 36,
                          ),
                          onPressed: _togglePlay,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Badge pausé
          if (!_isPlaying)
            IgnorePointer(
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.pause, color: Colors.white),
                      SizedBox(width: 8),
                      Text('En pause',
                          style:
                              TextStyle(color: Colors.white, fontSize: 16)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
