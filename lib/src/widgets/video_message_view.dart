// offline-chatview/lib/src/widgets/video_message_view.dart
import 'package:flutter/material.dart';
import 'dart:io'; // Needed for File class
import 'package:chatview_utils/chatview_utils.dart'; // For Message model
import 'package:open_filex/open_filex.dart'; // Import open_filex
import 'package:url_launcher/url_launcher.dart'; // Import url_launcher
import 'package:flutter/foundation.dart' show kIsWeb; // Import kIsWeb

class VideoMessageView extends StatelessWidget {
  const VideoMessageView({
    Key? key,
    required this.message,
    required this.isMessageBySender,
    // You can add a VideoMessageConfiguration here if needed for customization
    // this.videoMessageConfig,
  }) : super(key: key);

  final Message message;
  final bool isMessageBySender;
  // final VideoMessageConfiguration? videoMessageConfig; // Uncomment if added

  // Function to check if a string is a valid HTTP/HTTPS URL
  bool _isWebUrl(String urlString) {
    try {
      final uri = Uri.parse(urlString);
      return uri.scheme == 'http' || uri.scheme == 'https';
    } catch (e) {
      return false;
    }
  }

  void _onVideoTap(BuildContext context, String pathOrUrl) async {
    print('--- Video Tap Debug Start ---');
    print('1. Input path/URL: $pathOrUrl');

    if (kIsWeb) {
      // On web, always try to open as a URL
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
      return; // Exit as web handling is done
    }

    // For non-web platforms (mobile, desktop)
    if (_isWebUrl(pathOrUrl)) {
      print('2. Detected as Web URL. Attempting to open with url_launcher.');
      try {
        final uri = Uri.parse(pathOrUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication); // Open in external browser
          print('Opened web URL: $pathOrUrl');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Opened web video: ${uri.host}')),
          );
        } else {
          print('Could not launch web URL: $pathOrUrl');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open web video: $pathOrUrl')),
          );
        }
      } catch (e) {
        print('Error parsing or launching URL: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid URL or error opening: $pathOrUrl')),
        );
      }
    } else {
      // Assume it's a local file path
      String actualFilePath;
      if (pathOrUrl.startsWith('file:///')) {
        actualFilePath = Uri.decodeComponent(pathOrUrl.substring('file:///'.length));
      } else {
        actualFilePath = Uri.decodeComponent(pathOrUrl);
      }
      print('2. Detected as Local File Path: $actualFilePath. Attempting to open with OpenFilex.');

      final File file = File(actualFilePath);

      if (await file.exists()) {
        print('3. Local file exists at path: $actualFilePath');
        try {
          final OpenResult result = await OpenFilex.open(actualFilePath);
          print('4. OpenFilex result type: ${result.type}');
          print('5. OpenFilex result message: ${result.message}');

          if (result.type == ResultType.done) {
            print('Video opened successfully!');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Opened video: ${file.path.split('/').last}')),
            );
          } else {
            print('Failed to open local video with OpenFilex. Error: ${result.message}');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not open video: ${file.path.split('/').last}. Error: ${result.message}')),
            );
          }
        } catch (e) {
          print('6. Exception caught when trying to open local video with OpenFilex: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('An unexpected error occurred: ${e.toString()}')),
          );
        }
      } else {
        print('3. Local file DOES NOT exist at path: $actualFilePath');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Video file not found on device: ${file.path.split('/').last}')),
        );
      }
    }
    print('--- Video Tap Debug End ---');
  }

  @override
  Widget build(BuildContext context) {
    final String pathOrUrl = message.message;

    String displayFileName;
    IconData displayIcon;
    Color iconColor = isMessageBySender ? Colors.blue[700]! : Colors.grey[700]!;
    Color textColor = isMessageBySender ? Colors.blue[900]! : Colors.black87;

    if (_isWebUrl(pathOrUrl)) {
      displayFileName = Uri.parse(pathOrUrl).host; // Show domain for URL
      displayIcon = Icons.ondemand_video; // Video icon for URLs
    } else {
      // Treat as a local file path
      String actualFilePath;
      if (pathOrUrl.startsWith('file:///')) {
        actualFilePath = Uri.decodeComponent(pathOrUrl.substring('file:///'.length));
      } else {
        actualFilePath = Uri.decodeComponent(pathOrUrl);
      }
      displayFileName = actualFilePath.split('/').last; // Show file name for local files
      displayIcon = Icons.video_file; // Generic video file icon
    }

    return GestureDetector( // Wrap the Container with GestureDetector
      onTap: () => _onVideoTap(context, pathOrUrl), // Call the _onVideoTap method
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        margin: EdgeInsets.only(
          top: 6,
          right: isMessageBySender ? 6 : 0,
          left: isMessageBySender ? 0 : 6,
          bottom: message.reaction.reactions.isNotEmpty ? 15 : 0,
        ),
        decoration: BoxDecoration(
          color: isMessageBySender ? Colors.blue[100] : Colors.grey[300],
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              displayIcon,
              color: iconColor,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayFileName,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Conditional display for file size/status or URL status
                  _isWebUrl(pathOrUrl)
                      ? Text(
                          'Web Video',
                          style: const TextStyle(fontSize: 12, color: Colors.black54),
                        )
                      : FutureBuilder<bool>(
                          future: File(pathOrUrl.startsWith('file:///') ? Uri.decodeComponent(pathOrUrl.substring('file:///'.length)) : Uri.decodeComponent(pathOrUrl)).exists(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.done) {
                              if (snapshot.hasData && snapshot.data == true) {
                                final file = File(pathOrUrl.startsWith('file:///') ? Uri.decodeComponent(pathOrUrl.substring('file:///'.length)) : Uri.decodeComponent(pathOrUrl));
                                return Text(
                                  'Video exists (${(file.lengthSync() / 1024).toStringAsFixed(2)} KB)',
                                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                                );
                              } else {
                                return const Text(
                                  'Video not found',
                                  style: TextStyle(fontSize: 12, color: Colors.red),
                                );
                              }
                            }
                            return const Text('Checking video...', style: TextStyle(fontSize: 12, color: Colors.black54));
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