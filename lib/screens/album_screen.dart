import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phototheque/screens/slideshow_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';

class AlbumScreen extends StatefulWidget {
  final String albumId;
  final String albumName;

  const AlbumScreen({
    super.key,
    required this.albumId,
    required this.albumName,
  });

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  final _supabase = Supabase.instance.client;
  final _picker = ImagePicker();

  List<Map<String, dynamic>> _photos = [];
  final Map<String, int> _likeCounts = {};
  final Set<String> _myLikes = {};

  bool _isLoading = true;
  bool _isUploading = false;
  int _uploadProgress = 0;
  int _uploadTotal = 0;

  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadPhotos() async {
    setState(() => _isLoading = true);
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

      await _loadLikes();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur : $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadLikes() async {
    if (_photos.isEmpty) return;

    try {
      final ids = _photos.map((p) => p['id'] as String).toList();
      final likes = await _supabase
          .from('likes')
          .select()
          .inFilter('media_id', ids);

      final counts = <String, int>{};
      final mine = <String>{};
      final myUserId = _supabase.auth.currentUser!.id;

      for (final like in likes) {
        final mediaId = like['media_id'] as String;
        counts[mediaId] = (counts[mediaId] ?? 0) + 1;
        if (like['user_id'] == myUserId) mine.add(mediaId);
      }

      setState(() {
        _likeCounts
          ..clear()
          ..addAll(counts);
        _myLikes
          ..clear()
          ..addAll(mine);
      });
    } catch (_) {}
  }

  void _subscribeRealtime() {
    _channel = _supabase
        .channel('album-${widget.albumId}')
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
                _photos.insert(0, {...newMedia, 'url': signedUrl});
              });
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'likes',
          callback: (_) => _loadLikes(),
        )
        .subscribe();
  }

  Future<void> _toggleLike(String mediaId) async {
    final userId = _supabase.auth.currentUser!.id;
    final isLiked = _myLikes.contains(mediaId);

    try {
      if (isLiked) {
        await _supabase
            .from('likes')
            .delete()
            .eq('media_id', mediaId)
            .eq('user_id', userId);
        setState(() {
          _myLikes.remove(mediaId);
          _likeCounts[mediaId] = (_likeCounts[mediaId] ?? 1) - 1;
        });
      } else {
        await _supabase.from('likes').insert({
          'media_id': mediaId,
          'user_id': userId,
        });
        setState(() {
          _myLikes.add(mediaId);
          _likeCounts[mediaId] = (_likeCounts[mediaId] ?? 0) + 1;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur like : $e')));
      }
    }
  }

  Future<void> _pickAndUpload() async {
    final files = await _picker.pickMultiImage(imageQuality: 100);
    if (files.isEmpty) return;

    setState(() {
      _isUploading = true;
      _uploadTotal = files.length;
      _uploadProgress = 0;
    });

    int successCount = 0;

    for (final file in files) {
      try {
        final compressed = await FlutterImageCompress.compressWithFile(
          file.path,
          minWidth: 1920,
          minHeight: 1920,
          quality: 80,
          format: CompressFormat.jpeg,
        );
        if (compressed == null) continue;

        final fileName =
            '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
        final path = '${widget.albumId}/$fileName';

        await _supabase.storage
            .from('family-media')
            .uploadBinary(
              path,
              compressed,
              fileOptions: const FileOptions(contentType: 'image/jpeg'),
            );

        await _supabase.from('media').insert({
          'album_id': widget.albumId,
          'uploaded_by': _supabase.auth.currentUser!.id,
          'storage_path': path,
        });

        successCount++;
        setState(() => _uploadProgress = successCount);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur sur ${file.name} : $e')),
          );
        }
      }
    }

    setState(() {
      _isUploading = false;
      _uploadProgress = 0;
      _uploadTotal = 0;
    });

    if (successCount > 0) await _loadPhotos();
  }

  Future<void> _deletePhoto(Map<String, dynamic> photo) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette photo ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _supabase.storage.from('family-media').remove([
        photo['storage_path'],
      ]);
      await _supabase.from('media').delete().eq('id', photo['id']);
      setState(() => _photos.removeWhere((p) => p['id'] == photo['id']));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }
  }

  void _openPhoto(Map<String, dynamic> photo) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PhotoViewerScreen(
          photo: photo,
          likeCount: _likeCounts[photo['id']] ?? 0,
          isLiked: _myLikes.contains(photo['id']),
          onToggleLike: () => _toggleLike(photo['id']),
          onDelete: () => _deletePhoto(photo),
        ),
      ),
    ).then((_) => _loadLikes());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.albumName),
        actions: [
          IconButton(
            icon: const Icon(Icons.slideshow),
            tooltip: 'Diaporama',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SlideshowScreen(
                    albumId: widget.albumId,
                    albumName: widget.albumName,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _photos.isEmpty
              ? const _EmptyState()
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _photos.length,
                  itemBuilder: (context, index) {
                    final photo = _photos[index];
                    return GestureDetector(
                      onTap: () => _openPhoto(photo),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(photo['url'], fit: BoxFit.cover),
                            // Badge likes
                            if ((_likeCounts[photo['id']] ?? 0) > 0)
                              Positioned(
                                bottom: 4,
                                right: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.favorite,
                                        size: 12,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        '${_likeCounts[photo['id']]}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          if (_isUploading)
            Container(
              color: Colors.black.withValues(alpha: 0.5),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text('Upload $_uploadProgress / $_uploadTotal'),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isUploading ? null : _pickAndUpload,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('Ajouter'),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.photo_library_outlined,
            size: 64,
            color: AppColors.textLight,
          ),
          const SizedBox(height: 16),
          Text('Aucune photo', style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 8),
          Text(
            'Appuie sur "Ajouter" pour commencer',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ÉCRAN PLEIN ÉCRAN : photo + likes + commentaires
// ============================================================

class _PhotoViewerScreen extends StatefulWidget {
  final Map<String, dynamic> photo;
  final int likeCount;
  final bool isLiked;
  final VoidCallback onToggleLike;
  final VoidCallback onDelete;

  const _PhotoViewerScreen({
    required this.photo,
    required this.likeCount,
    required this.isLiked,
    required this.onToggleLike,
    required this.onDelete,
  });

  @override
  State<_PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<_PhotoViewerScreen> {
  final _supabase = Supabase.instance.client;
  final _commentController = TextEditingController();

  List<Map<String, dynamic>> _comments = [];
  bool _loadingComments = true;
  late bool _isLiked;
  late int _likeCount;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.isLiked;
    _likeCount = widget.likeCount;
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    try {
      final data = await _supabase
          .from('comments')
          .select()
          .eq('media_id', widget.photo['id'])
          .order('created_at', ascending: true);

      debugPrint('COMMENTS LOADED: ${data.length}');

      setState(() {
        _comments = List<Map<String, dynamic>>.from(data);
        _loadingComments = false;
      });
    } catch (e) {
      debugPrint('ERREUR LOAD COMMENTS: $e');
      setState(() => _loadingComments = false);
    }
  }

  Future<void> _addComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    _commentController.clear();

    try {
      await _supabase.from('comments').insert({
        'media_id': widget.photo['id'],
        'user_id': _supabase.auth.currentUser!.id,
        'content': text,
        'author_name':
            _supabase.auth.currentUser!.email?.split('@').first ?? 'Anonyme',
      });
      await _loadComments();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              Navigator.pop(context);
              widget.onDelete();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Photo
          Expanded(
            flex: 3,
            child: Center(
              child: InteractiveViewer(
                child: Image.network(widget.photo['url']),
              ),
            ),
          ),

          // Barre likes
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    _isLiked ? Icons.favorite : Icons.favorite_border,
                    color: _isLiked ? Colors.red : Colors.white,
                  ),
                  onPressed: () {
                    setState(() {
                      _isLiked = !_isLiked;
                      _likeCount += _isLiked ? 1 : -1;
                    });
                    widget.onToggleLike();
                  },
                ),
                Text(
                  '$_likeCount',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),

          // Commentaires
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.white,
              child: Column(
                children: [
                  Expanded(
                    child: _loadingComments
                        ? const Center(child: CircularProgressIndicator())
                        : _comments.isEmpty
                        ? const Center(
                            child: Text(
                              'Aucun commentaire',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _comments.length,
                            itemBuilder: (context, i) {
                              final c = _comments[i];
                              
                              final name =
                                  c['author_name'] as String? ?? 'Anonyme';

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: RichText(
                                  text: TextSpan(
                                    style: const TextStyle(
                                      color: AppColors.textDark,
                                      fontSize: 14,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: '$name : ',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      TextSpan(text: c['content']),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  // Champ de saisie
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _commentController,
                              decoration: const InputDecoration(
                                hintText: 'Ajouter un commentaire…',
                                isDense: true,
                              ),
                              onSubmitted: (_) => _addComment(),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.send,
                              color: AppColors.primary,
                            ),
                            onPressed: _addComment,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
