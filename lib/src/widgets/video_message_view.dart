// offline-chatview/lib/src/widgets/video_message_view.dart
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:chatview_utils/chatview_utils.dart';
// import 'package:open_filex/open_filex.dart'; // Still useful for non-video files or fallback
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:video_thumbnail/video_thumbnail.dart'; // Import for video thumbnail
import 'package:path_provider/path_provider.dart'; // For temporary directory
import 'package:chatview/src/widgets/custom_video_player.dart'; // Import your custom video player
import 'package:chatview/src/values/typedefs.dart';
import 'package:chatview/src/models/config_models/message_configuration.dart';
import 'dart:ui' as ui; // Import for image processing
import 'dart:async'; 

class VideoMessageView extends StatefulWidget {
  const VideoMessageView({
    Key? key,
    required this.message,
    required this.isMessageBySender,
    this.videoMessageConfig,
    this.customVideoPlayerBuilder, // Add this for custom player
  }) : super(key: key);

  final Message message;
  final bool isMessageBySender;
  final VideoMessageConfiguration? videoMessageConfig;
  final CustomVideoPlayerBuilder? customVideoPlayerBuilder;

  @override
  State<VideoMessageView> createState() => _VideoMessageViewState();
}

class _VideoMessageViewState extends State<VideoMessageView> {
  String? _thumbnailPath;
  bool _isLoadingThumbnail = true;
  String _fallbackThumbnailAsset = 'assets/default_video_thumbnail.png';

  // We'll store the actual aspect ratio here
  double _videoAspectRatio = 16 / 9; // Default, will be updated by generated thumbnail

  @override
  void initState() {
    super.initState();
    _generateThumbnail();
  }

  bool _isWebUrl(String urlString) {
    try {
      final uri = Uri.parse(urlString);
      return uri.scheme == 'http' || uri.scheme == 'https';
    } catch (e) {
      return false;
    }
  }

  Future<void> _generateThumbnail() async {
    if (!mounted) return; // Ensure widget is still mounted

    setState(() {
      _isLoadingThumbnail = true;
    });

    final String pathOrUrl = widget.message.message;
    print('Attempting to generate thumbnail for: $pathOrUrl');

    if (_isWebUrl(pathOrUrl)) {
      print('Path is a web URL, skipping thumbnail generation.');
      // For web URLs, we can't generate a thumbnail directly client-side.
      // We'll just use the default aspect ratio.
      if (mounted) {
        setState(() {
          _isLoadingThumbnail = false;
          _thumbnailPath = null;
          _videoAspectRatio = 16 / 9; // Fallback for web URLs
        });
      }
    } else {
      String actualFilePath;
      if (pathOrUrl.startsWith('file:///')) {
        actualFilePath = Uri.decodeComponent(pathOrUrl.substring('file:///'.length));
      } else {
        actualFilePath = Uri.decodeComponent(pathOrUrl);
      }

      final File file = File(actualFilePath);
      if (await file.exists()) {
        print('File exists at: $actualFilePath');
        try {
          final tempDir = await getTemporaryDirectory();
          final String? thumbnail = await VideoThumbnail.thumbnailFile(
            video: actualFilePath,
            thumbnailPath: tempDir.path,
            imageFormat: ImageFormat.JPEG,
            maxHeight: 400, // Make these large enough to capture good quality
            maxWidth: 400, // but the AspectRatio will control display size
            quality: 75,
          );

          double? actualWidth;
          double? actualHeight;

          if (thumbnail != null) {
            print("SUCCESS: Thumbnail generated at: $thumbnail");
            // Load the generated thumbnail to get its actual dimensions
            final Image image = Image.file(File(thumbnail));
            final Completer<ui.Image> completer = Completer<ui.Image>();
            image.image.resolve(const ImageConfiguration()).addListener(
              ImageStreamListener((ImageInfo info, bool _) {
                completer.complete(info.image);
              }),
            );
            final ui.Image uiImage = await completer.future;
            actualWidth = uiImage.width.toDouble();
            actualHeight = uiImage.height.toDouble();
            uiImage.dispose(); // Release image resources

            if (actualWidth != null && actualHeight != null && actualHeight > 0) {
              _videoAspectRatio = actualWidth / actualHeight;
              print('Calculated thumbnail aspect ratio: $_videoAspectRatio');
            } else {
              print('Could not get actual thumbnail dimensions, using default aspect ratio.');
              _videoAspectRatio = 16 / 9; // Fallback
            }
          } else {
            print("ERROR: VideoThumbnail.thumbnailFile returned NULL for path: $actualFilePath");
            _videoAspectRatio = 16 / 9; // Fallback if thumbnail generation fails
          }

          if (mounted) {
            setState(() {
              _thumbnailPath = thumbnail;
              _isLoadingThumbnail = false;
            });
          }
        } catch (e, st) {
          print("CRITICAL ERROR generating thumbnail or getting dimensions: $e");
          print("Stack trace: $st");
          if (mounted) {
            setState(() {
              _isLoadingThumbnail = false;
              _thumbnailPath = null;
              _videoAspectRatio = 16 / 9; // Fallback on error
            });
          }
        }
      } else {
        print('ERROR: File does NOT exist at: $actualFilePath');
        if (mounted) {
          setState(() {
            _isLoadingThumbnail = false;
            _thumbnailPath = null;
            _videoAspectRatio = 16 / 9; // Fallback if file not found
          });
        }
      }
    }
  }

  void _onVideoTap(BuildContext context, String pathOrUrl) async {
    print('--- Video Tap Debug Start ---');
    print('1. Input path/URL: $pathOrUrl');

    if (kIsWeb) {
      try {
        final uri = Uri.parse(pathOrUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.platformDefault);
          print('Opened URL on Web: $pathOrUrl');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Opened web video: ${uri.host}')),
          );
        } else {
          print('Could not launch URL on Web: $pathOrUrl');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open web video.')),
          );
        }
      } catch (e) {
        print('Error parsing or launching URL on Web: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid URL or error opening: $pathOrUrl')),
        );
      }
      print('--- Video Tap Debug End (Web) ---');
      return;
    }

    if (widget.customVideoPlayerBuilder != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => widget.customVideoPlayerBuilder!(pathOrUrl),
        ),
      );
      print('Opened video with custom builder.');
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(title: Text('Video Player')),
            body: Center(
              child: CustomVideoPlayer(videoUrl: pathOrUrl),
            ),
          ),
        ),
      );
      print('Opened video with default in-app player.');
    }
    print('--- Video Tap Debug End ---');
  }

  @override
  Widget build(BuildContext context) {
    final String pathOrUrl = widget.message.message;

    String displayFileName;
    IconData displayIcon;
    Color iconColor = widget.isMessageBySender ? Colors.blue[700]! : Colors.grey[700]!;
    Color textColor = widget.isMessageBySender ? Colors.blue[900]! : Colors.black87;

    if (_isWebUrl(pathOrUrl)) {
      displayFileName = Uri.parse(pathOrUrl).host;
      displayIcon = Icons.ondemand_video;
    } else {
      String actualFilePath;
      if (pathOrUrl.startsWith('file:///')) {
        actualFilePath = Uri.decodeComponent(pathOrUrl.substring('file:///'.length));
      } else {
        actualFilePath = Uri.decodeComponent(pathOrUrl);
      }
      displayFileName = actualFilePath.split('/').last;
      displayIcon = Icons.video_file;
    }

    // Determine max width for the content based on bubble constraints
    final double maxWidthForContent = MediaQuery.of(context).size.width * 0.7 - (8 * 2); // Container padding 8 horizontal

    return GestureDetector(
      onTap: () => _onVideoTap(context, pathOrUrl),
      child: Container(
        padding: const EdgeInsets.all(8), // Reduced padding slightly
        margin: EdgeInsets.only(
          top: 6,
          right: widget.isMessageBySender ? 6 : 0,
          left: widget.isMessageBySender ? 0 : 6,
          bottom: widget.message.reaction.reactions.isNotEmpty ? 15 : 0,
        ),
        decoration: BoxDecoration(
          color: widget.isMessageBySender ? Colors.blue[100] : Colors.grey[300],
          borderRadius: BorderRadius.circular(14),
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
          // Removed maxHeight: 200, to allow the bubble to adapt vertically
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min, // Keep this
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail/Loading/Fallback Area wrapped in AspectRatio
            // This AspectRatio will now use the dynamically calculated _videoAspectRatio
            // to ensure the visual preview matches the video's original shape.
            AspectRatio(
              aspectRatio: _videoAspectRatio,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _isLoadingThumbnail
                    ? Container(
                        color: Colors.grey[200],
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(displayIcon, color: iconColor, size: 40),
                              const SizedBox(height: 5),
                              const Text('Loading video...', style: TextStyle(fontSize: 12, color: Colors.black54)),
                            ],
                          ),
                        ),
                      )
                    : _thumbnailPath != null
                        ? Stack(
                            alignment: Alignment.center,
                            children: [
                              Image.file(
                                File(_thumbnailPath!),
                                width: double.infinity,
                                height: double.infinity,
                                fit: BoxFit.contain, // <<< CRITICAL CHANGE: Use BoxFit.contain
                                errorBuilder: (context, error, stackTrace) => Container(
                                  color: Colors.grey[200],
                                  child: Center(
                                    child: Icon(displayIcon, color: iconColor, size: 40),
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.play_circle_fill,
                                color: Colors.white.withOpacity(0.8),
                                size: 50,
                              ),
                            ],
                          )
                        : Stack(
                            alignment: Alignment.center,
                            children: [
                              Image.asset(
                                _fallbackThumbnailAsset,
                                width: double.infinity,
                                height: double.infinity,
                                fit: BoxFit.contain, // <<< CRITICAL CHANGE: Use BoxFit.contain
                                errorBuilder: (context, error, stackTrace) => Container(
                                  color: Colors.grey[200],
                                  child: Center(
                                    child: Icon(displayIcon, color: iconColor, size: 40),
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.play_circle_fill,
                                color: Colors.white.withOpacity(0.8),
                                size: 50,
                              ),
                              Positioned(
                                bottom: 8,
                                child: Text(
                                  'Video Preview',
                                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 2, color: Colors.black)]),
                                ),
                              )
                            ],
                          ),
              ),
            ),
            const SizedBox(height: 4), // Small spacing between thumbnail and text info

            // Text information section - made more compact
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayFileName,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12, // Still relatively small for compact display
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  // No SizedBox here to save vertical space.

                  _isWebUrl(pathOrUrl)
                      ? Text(
                          'Web Video',
                          style: const TextStyle(fontSize: 10, color: Colors.black54),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : FutureBuilder<bool>(
                          future: File(pathOrUrl.startsWith('file:///')
                                  ? Uri.decodeComponent(pathOrUrl.substring('file:///'.length))
                                  : Uri.decodeComponent(pathOrUrl))
                              .exists(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.done) {
                              if (snapshot.hasData && snapshot.data == true) {
                                final file = File(pathOrUrl.startsWith('file:///')
                                    ? Uri.decodeComponent(pathOrUrl.substring('file:///'.length))
                                    : Uri.decodeComponent(pathOrUrl));
                                return Text(
                                  'Video exists (${(file.lengthSync() / 1024).toStringAsFixed(2)} KB)',
                                  style: const TextStyle(fontSize: 10, color: Colors.black54),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                );
                              } else {
                                return const Text(
                                  'Video not found',
                                  style: TextStyle(fontSize: 10, color: Colors.red),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                );
                              }
                            }
                            return const Text('Checking video...', style: TextStyle(fontSize: 10, color: Colors.black54));
                          },
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