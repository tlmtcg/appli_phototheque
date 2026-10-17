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

class _SlideshowScreenState extends State<SlideshowScreen> {
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _photos = [];
  int _currentIndex = 0;
  bool _isPlaying = true;
  bool _isLoading = true;
  bool _isTransitioning = false;

  Timer? _timer;
  RealtimeChannel? _channel;

  static const _slideDuration = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _loadPhotos();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _channel?.unsubscribe();
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

      // Précharger les 2 premières images pour un fondu fluide
      if (_photos.isNotEmpty) {
        _precache(_photos[0]['url']);
        if (_photos.length > 1) _precache(_photos[1]['url']);
        _startTimer();
      }
    } catch (e) {
      debugPrint('Erreur loadPhotos: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _precache(String url) async {
    try {
      await precacheImage(NetworkImage(url), context);
    } catch (_) {}
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
              _precache(signedUrl);
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

  Future<void> _goToNext() async {
    if (_photos.isEmpty || _isTransitioning) return;

    final nextIndex = (_currentIndex + 1) % _photos.length;

    // Précharger l'image suivante AVANT de lancer la transition
    await _precache(_photos[nextIndex]['url']);
    if (!mounted) return;

    setState(() {
      _isTransitioning = true;
      _currentIndex = nextIndex;
    });

    // Précharger la suivante pour le prochain tour
    final following = (_currentIndex + 1) % _photos.length;
    _precache(_photos[following]['url']);

    // Libérer le flag après l'animation
    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) setState(() => _isTransitioning = false);
  }

  Future<void> _goToPrevious() async {
    if (_photos.isEmpty || _isTransitioning) return;

    final prevIndex = (_currentIndex - 1 + _photos.length) % _photos.length;

    await _precache(_photos[prevIndex]['url']);
    if (!mounted) return;

    setState(() {
      _isTransitioning = true;
      _currentIndex = prevIndex;
    });

    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) setState(() => _isTransitioning = false);
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
              Icon(
                Icons.photo_library_outlined,
                size: 64,
                color: Colors.white54,
              ),
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
          // Photo avec fondu fluide
          Positioned.fill(
            child: GestureDetector(
              onTap: _togglePlay,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 800),
                switchInCurve: Curves.easeInOut,
                switchOutCurve: Curves.easeInOut,
                // Empêche AnimatedSwitcher d'animer la taille (images)
                layoutBuilder: (currentChild, previousChildren) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      ...previousChildren,
                      if (currentChild != null) currentChild,
                    ],
                  );
                },
                transitionBuilder: (child, animation) {
                  return FadeTransition(opacity: animation, child: child);
                },
                child: Image.network(
                  currentPhoto['url'],
                  key: ValueKey(currentPhoto['id']), // ← clé unique obligatoire
                  fit: BoxFit.contain,
                  // PAS de gaplessPlayback
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
                  style: IconButton.styleFrom(backgroundColor: Colors.black38),
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
                icon: const Icon(
                  Icons.chevron_left,
                  color: Colors.white,
                  size: 48,
                ),
                style: IconButton.styleFrom(backgroundColor: Colors.black26),
                onPressed: _goToPrevious,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: const Icon(
                  Icons.chevron_right,
                  color: Colors.white,
                  size: 48,
                ),
                style: IconButton.styleFrom(backgroundColor: Colors.black26),
                onPressed: _goToNext,
              ),
            ),
          ],

          // Indicateur bas
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${_currentIndex + 1} / ${_photos.length}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.pause, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'En pause',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
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
