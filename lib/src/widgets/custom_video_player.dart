/*
           File: custom_video_player.dart
           Author:
                Alias: Aeris Sinclaire
                Company: Cityzen
           Date: July 9, 2025
           Version: 1.0.0
           License: GNU Lesser General Public License v3.0
     
           This program is free software: you can redistribute it and/or modify
           it under the terms of the GNU Lesser General Public License as published by
           the Free Software Foundation, either version 3 of the License, or
           (at your option) any later version.
     
           This program is distributed in the hope that it will be useful,
           but WITHOUT ANY WARRANTY; without even the implied warranty of
           MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
           GNU Lesser General Public License for more details.
     
           You should have received a copy of the GNU Lesser General Public License
           along with this program. If not, see <https://www.gnu.org/licenses/>.
     
Description:
    This Flutter widget provides a custom video player built with `media_kit`, designed for the
    `offline-chatview` package. It offers a minimalist UI with interactive controls that appear
    on demand, supporting local video file playback for an immersive viewing experience.

Features:
    - Video Playback: Plays local video files, integrated as a `MessageType.video` within `offline-chatview`.
    - Hidden Controls: Play/pause button, volume mute/unmute, and timestamp slider are hidden by default,
      appearing on user interaction (tap, drag, long press).
    - Tap to Play/Pause: A central play/pause icon appears when controls are visible. Tapping the video
      toggles play/pause and control visibility.
    - Volume Control:
      - Tap Top-Right Icon to Mute/Unmute: Toggles mute, preserving last volume.
      - Slide Up/Down to Adjust Volume: Vertical drag on the left video side activates a slider for precise
        volume adjustment.
    - Playback Speed Control:
      - Long Press Right to Speed Up: Accelerates playback (e.g., 2.0x).
      - Long Press Left to Slow Down: Slows down playback (e.g., 0.5x).
      - Speed Indicator: A temporary overlay shows current playback speed.
    - Drag Slider to Seek: A progress bar at the bottom allows seeking to any point in the video.
      (BUG: TIMESTAMP RESETS TO ZERO THEN GOES BACK TO CURRENT POSITION WHEN SPEED UP)
    - Error Handling: Displays an error message and retry option if video loading fails.

Dependencies:
    - flutter:
        sdk: flutter
    - media_kit: ^1.1.10 (or compatible version)
    - media_kit_video: ^1.2.4 (or compatible version)
    - chatview (forked offline-chatview package): Required for `MessageType.video` integration.

Usage:
    This widget is primarily intended to be used within the `offline-chatview` package.
    When sending or displaying a video message, provide the local video file URL to the `videoUrl` property.

    Example (within offline-chatview's MessageView/Bubble):
    ```dart
    import 'package:flutter/material.dart';
    import 'package:chatview/chatview.dart'; // From your offline-chatview package
    import 'package:your_package_name/src/widgets/custom_video_player.dart'; // Path to this widget

    // Example of how a video message might be rendered in a custom bubble builder
    // assuming 'message' is a Message object from chatview
    Widget _buildVideoMessage(Message message) {
      if (message.messageType == MessageType.video && message.mediaUrl != null) {
        return SizedBox(
          width: 250,
          height: 150,
          child: CustomVideoPlayer(
            videoUrl: message.mediaUrl!,
          ),
        );
      }
      return const Text('Unsupported message type');
    }

    // In your ChatView widget, you would typically use a custom message builder:
    // ChatView(
    //   messageBuilder: (message, int, is).isVideo
    //       ? _buildVideoMessage(message)
    //       : null,
    // );
    ```
*/

//  (BUG: TIMESTAMP RESETS TO ZERO THEN GOES BACK TO CURRENT POSITION WHEN SPEED UP) 
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class CustomVideoPlayer extends StatefulWidget {
  final String videoUrl;

  const CustomVideoPlayer({Key? key, required this.videoUrl}) : super(key: key);

  @override
  State<CustomVideoPlayer> createState() => _CustomVideoPlayerState();
}

class _CustomVideoPlayerState extends State<CustomVideoPlayer> {
  late final Player _player;
  late final VideoController _controller;

  bool _isLoading = true;
  String? _errorMessage;

  // State variables for custom controls
  bool _isMuted = false;
  double _lastVolume = 100.0; // Stores last volume before muting
  double _currentRate = 1.0; // Current playback rate
  bool _showControls = false; // Controls visibility of the entire control overlay
  bool _isPlaying = false; // Tracks player's actual playing state

  // State variables for speed indicator overlay
  bool _showSpeedIndicator = false;
  String _speedIndicatorText = '';
  IconData? _speedIndicatorIcon;

  // State variables for vertical volume slider
  bool _showVolumeSlider = false;
  double _currentVolumeValue = 100.0; // Reflects current player volume (0-100)
  double _dragStartY = 0.0; // Start Y position for vertical drag gesture
  double _dragStartVolume = 0.0; // Volume at the start of a vertical drag

  // Timer for auto-hiding controls after inactivity
  Timer? _controlsTimer;
  bool _showVolumeIcon = false; // Controls visibility of the top-right volume icon

  // Cached total duration of the video
  Duration? _cachedTotalDuration;

  // StreamController for providing filtered position updates to the UI
  final StreamController<Duration> _positionController = StreamController<Duration>.broadcast();
  Duration _displayPosition = Duration.zero; // The position actually displayed on the slider

  @override
  void initState() {
    super.initState();
    _initializeVideoPlayer();
  }

  Future<void> _initializeVideoPlayer() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      _player = Player();
      _controller = VideoController(_player);

      String mediaPath = widget.videoUrl;
      // Decode the file path if it starts with 'file:///'
      if (mediaPath.startsWith('file:///')) {
        mediaPath = Uri.decodeComponent(mediaPath.substring('file:///'.length));
      }

      await _player.open(Media(mediaPath), play: true);
      _player.setPlaylistMode(PlaylistMode.single);

      // Listen to changes in the player's playing state
      _player.stream.playing.listen((playing) {
        if (mounted) {
          setState(() {
            _isPlaying = playing;
          });
        }
      });
      // Listen to changes in the player's volume
      _player.stream.volume.listen((volume) {
        if (mounted) {
          setState(() {
            _isMuted = (volume == 0.0);
            _currentVolumeValue = volume; // Keep _currentVolumeValue updated
            if (volume > 0) {
              _lastVolume = volume; // Keep track of last non-zero volume
            }
          });
        }
      });

      // Listen to the video's total duration and cache it once available
      _player.stream.duration.listen((duration) {
        if (mounted && _cachedTotalDuration == null && duration > Duration.zero) {
          setState(() {
            _cachedTotalDuration = duration;
            print('offline-chatview: Cached total duration: $_cachedTotalDuration');
          });
        }
      });

      // Listen to player position updates and filter out momentary zero positions
      _player.stream.position.listen((newPosition) {
        if (mounted) {
          // Ignore momentary zero positions that can cause the slider knob to jump
          if (newPosition == Duration.zero &&
              _displayPosition > Duration.zero &&
              _cachedTotalDuration != Duration.zero) {
            return;
          }
          setState(() {
            _displayPosition = newPosition; // Update the position displayed on the slider
          });
          _positionController.add(newPosition); // Add the new position to our controlled stream
        }
      });

      setState(() {
        _isLoading = false;
        _showControls = false; // Initially hide controls after successful loading
        _showVolumeIcon = false; // Initially hide volume icon
      });
      print('offline-chatview: MediaKit player initialized and playing for: ${widget.videoUrl}');
    } catch (e, st) {
      print("offline-chatview: Error initializing MediaKit player: $e");
      print("offline-chatview: Stack trace: $st");
      setState(() {
        _errorMessage = "Failed to load video: ${e.toString()}";
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _player.dispose();
    _controlsTimer?.cancel(); // Cancel any active auto-hide timer
    _positionController.close(); // Close the position stream controller
    super.dispose();
  }

  // Resets the timer to auto-hide controls after a period of inactivity
  void _resetControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() {
          _showControls = false;
          _showVolumeIcon = false;
          _showSpeedIndicator = false;
          _showVolumeSlider = false; // Hide volume slider too
        });
      }
    });
  }

  // Toggles the player's mute state
  void _toggleMute() async {
    // Show controls when mute/unmute is pressed
    setState(() {
      _showControls = true;
      _showVolumeIcon = true;
      _showVolumeSlider = false; // Ensure vertical slider is not visible
    });
    _resetControlsTimer(); // Reset timer on interaction

    if (_isMuted) {
      await _player.setVolume(_lastVolume); // Restore last non-zero volume
    } else {
      _lastVolume = _player.state.volume; // Save current volume before muting
      await _player.setVolume(0.0); // Mute the player
    }
  }

  // Initiates speed control based on the long press position
  void _startSpeedControl(LongPressStartDetails details) {
    setState(() {
      _showSpeedIndicator = true; // Show speed indicator overlay
      _showControls = true; // Show main controls
      _showVolumeIcon = true; // Show volume icon
      _showVolumeSlider = false; // Hide volume slider
      final double halfWidth = context.size!.width / 2;
      if (details.localPosition.dx < halfWidth) {
        // Long press on left side: slow down playback
        _currentRate = 0.5;
        _speedIndicatorText = '0.5x';
        _speedIndicatorIcon = Icons.fast_rewind;
      } else {
        // Long press on right side: speed up playback
        _currentRate = 2.0;
        _speedIndicatorText = '2.0x';
        _speedIndicatorIcon = Icons.fast_forward;
      }
      _player.setRate(_currentRate);
      print('offline-chatview: Player rate set to $_currentRate');
    });
    _resetControlsTimer(); // Reset timer on interaction
  }

  // Resets playback speed to normal when long press ends
  void _endSpeedControl() {
    setState(() {
      _showSpeedIndicator = false; // Hide speed indicator
      _currentRate = 1.0; // Reset to normal speed
      _player.setRate(_currentRate);
      print('offline-chatview: Player rate reset to $_currentRate');
    });
    _resetControlsTimer(); // Reset timer on interaction
  }

  // Toggles play/pause state and control visibility
  void _togglePlayPauseAndControls() {
    _player.playOrPause(); // Toggle player's play/pause state
    setState(() {
      _showControls = !_showControls; // Toggle visibility of bottom controls and play button
      _showVolumeIcon = _showControls; // Volume icon visibility follows main controls
      _showVolumeSlider = false; // Ensure vertical slider is not active
    });
    _resetControlsTimer(); // Reset timer on interaction
  }

  // Initiates vertical volume control gesture
  void _startDragVolumeControl(DragStartDetails details) {
    _dragStartY = details.localPosition.dy;
    _dragStartVolume = _currentVolumeValue; // Store volume at the start of the drag
    setState(() {
      _showVolumeSlider = true; // Show the vertical volume slider
      _showControls = true; // Show main controls
      _showVolumeIcon = false; // Explicitly hide top-right icon when vertical slider is active
    });
    _resetControlsTimer(); // Reset timer on interaction
  }

  // Updates volume based on vertical drag gesture
  void _updateDragVolumeControl(DragUpdateDetails details) {
    final double dragDeltaY = details.localPosition.dy - _dragStartY;

    // Adjust sensitivity for volume change
    final double sensitivity = 150.0;
    double volumeChange = (dragDeltaY / sensitivity) * 100.0;

    // Dragging down decreases volume, dragging up increases volume
    double newVolume = (_dragStartVolume - volumeChange).clamp(0.0, 100.0);
    _player.setVolume(newVolume);

    _resetControlsTimer(); // Keep resetting timer during drag
  }

  // Ends vertical volume control gesture
  void _endDragVolumeControl(DragEndDetails details) {
    _resetControlsTimer(); // Reset timer when drag ends
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    } else if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _initializeVideoPlayer,
              child: const Text('Try Again'),
            ),
          ],
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.all(15.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12.0),
          child: Stack( // Layers all video player elements
            children: [
              // GestureDetector covering the video area for interactions
              GestureDetector(
                onTap: _togglePlayPauseAndControls,
                onLongPressStart: _startSpeedControl,
                onLongPressEnd: (details) => _endSpeedControl(),
                onVerticalDragStart: _startDragVolumeControl,
                onVerticalDragUpdate: _updateDragVolumeControl,
                onVerticalDragEnd: _endDragVolumeControl,
                child: Positioned.fill(
                  child: Video(
                    controller: _controller,
                    fit: BoxFit.contain,
                    fill: Colors.black,
                    controls: (state) => const SizedBox.shrink(), // Hide default media_kit controls
                  ),
                ),
              ),

              // Centered play/pause button, visible when paused and controls are shown
              if (!_isPlaying && _showControls)
                Center(
                  child: StreamBuilder<bool>(
                    stream: _player.stream.playing,
                    builder: (context, playingSnapshot) {
                      return IconButton(
                        icon: const Icon(Icons.play_circle_fill, size: 80, color: Colors.white),
                        onPressed: _togglePlayPauseAndControls,
                      );
                    },
                  ),
                ),

              // Volume/Mute Icon at the top-right
              Align(
                alignment: Alignment.topRight,
                child: AnimatedOpacity(
                  opacity: (_showVolumeIcon && !_showVolumeSlider) ? 1.0 : 0.0, // Hidden if vertical slider is active
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: !(_showVolumeIcon && !_showVolumeSlider), // Ignore events when hidden
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: IconButton(
                        icon: Icon(
                          _isMuted ? Icons.volume_off : Icons.volume_up,
                          color: Colors.white,
                          size: 28.0,
                        ),
                        onPressed: _toggleMute,
                      ),
                    ),
                  ),
                ),
              ),

              // Speed Indicator overlay at the bottom center
              if (_showSpeedIndicator)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: AnimatedOpacity(
                    opacity: _showSpeedIndicator ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 50.0),
                      child: _buildSpeedIndicator(),
                    ),
                  ),
                ),

              // Vertical Volume Slider on the left side
              if (_showVolumeSlider)
                Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedOpacity(
                    opacity: _showVolumeSlider ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !_showVolumeSlider,
                      child: _buildVerticalVolumeSlider(),
                    ),
                  ),
                ),

              // Custom controls at the bottom, visible when _showControls is true
              Align(
                alignment: Alignment.bottomCenter,
                child: AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer( // Ignore pointer events when controls are hidden
                    ignoring: !_showControls,
                    child: _buildCustomControls(),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  // Builds the speed indicator overlay
  Widget _buildSpeedIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(10.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_speedIndicatorIcon != null)
            Icon(
              _speedIndicatorIcon,
              color: Colors.white,
              size: 20.0,
            ),
          const SizedBox(width: 8.0),
          Text(
            _speedIndicatorText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17.0,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // Builds the vertical volume slider
  Widget _buildVerticalVolumeSlider() {
    return Container(
      width: 60,
      height: MediaQuery.of(context).size.height * 0.25,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(20.0),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded( // Slider takes available vertical space
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 0.0),
              child: RotatedBox(
                quarterTurns: 3, // Rotate 270 degrees to make it vertical
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.grey,
                    thumbColor: Colors.white,
                    overlayColor: Colors.white.withOpacity(0.3),
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.0),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 16.0),
                    trackHeight: 3.0,
                  ),
                  child: Slider(
                    value: _currentVolumeValue, // Uses the state variable mirroring player volume
                    min: 0.0,
                    max: 100.0,
                    onChanged: (val) {
                      _player.setVolume(val);
                      _resetControlsTimer(); // Reset timer on interaction
                    },
                  ),
                ),
              ),
            ),
          ),
          // Volume Icon at the bottom of the slider
          Icon(
            _currentVolumeValue == 0 ? Icons.volume_off : Icons.volume_up,
            color: Colors.white,
            size: 24.0,
          ),
          const SizedBox(height: 8.0), // Padding below the icon
        ],
      ),
    );
  }

  // Builds the custom video playback controls (timestamp slider and time display)
  Widget _buildCustomControls() {
    return Container(
      color: Colors.black54,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: StreamBuilder<Duration>( // Stream for current playback position
        stream: _positionController.stream, // Uses the filtered position stream
        builder: (context, positionSnapshot) {
          final currentPosition = positionSnapshot.data ?? Duration.zero;
          return StreamBuilder<Duration>( // Stream for total video duration
            stream: _player.stream.duration,
            builder: (context, durationSnapshot) {
              // Use cached total duration if available, otherwise fallback to stream value
              final totalDurationFromStream = durationSnapshot.data ?? Duration.zero;
              final totalDuration = _cachedTotalDuration ?? totalDurationFromStream;

              // Debugging prints for timestamp slider values
              print('--- Timestamp Slider Debug ---');
              print('Current Position: $currentPosition');
              print('Total Duration (from stream): $totalDurationFromStream');
              print('Cached Total Duration: $_cachedTotalDuration');
              print('Effective Total Duration: $totalDuration');
              print('------------------------------');

              // Check if a valid total duration is available
              bool hasValidDuration = totalDuration > Duration.zero;

              return Column(
                mainAxisSize: MainAxisSize.min, // Keep column compact
                children: [
                  // Video playback slider
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.grey,
                      thumbColor: Colors.white,
                      overlayColor: Colors.white.withOpacity(0.3),
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.0),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 16.0),
                      trackHeight: 3.0,
                    ),
                    child: Slider(
                      key: ValueKey(hasValidDuration ? 'timestampSliderEnabled' : 'timestampSliderDisabled'),
                      value: hasValidDuration
                          ? currentPosition.inMilliseconds.toDouble().clamp(0.0, totalDuration.inMilliseconds.toDouble())
                          : 0.0, // Value is 0 if no valid duration
                      min: 0.0,
                      max: hasValidDuration ? totalDuration.inMilliseconds.toDouble() : 1.0, // Set max to 1.0 if duration is invalid
                      onChanged: hasValidDuration
                          ? (value) {
                              _player.seek(Duration(milliseconds: value.toInt()));
                              _resetControlsTimer(); // Reset timer on slider interaction
                            }
                          : null, // Disable slider if duration is unknown
                      onChangeStart: hasValidDuration ? (value) {
                        // Optionally pause player when dragging starts
                        if (_player.state.playing) {
                            _player.pause();
                        }
                      } : null,
                      onChangeEnd: hasValidDuration ? (value) {
                        // Optionally resume player when dragging ends
                        _player.play();
                        _resetControlsTimer();
                      } : null,
                    ),
                  ),
                  
                  // Indeterminate progress indicator if duration is not yet known
                  if (!hasValidDuration)
                    LinearProgressIndicator(
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withOpacity(0.5)),
                      value: null, // Indeterminate progress
                    ),

                  const SizedBox(height: 8),

                  // Display current time and total time
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(currentPosition),
                        style: const TextStyle(color: Colors.white),
                      ),
                      Text(
                        hasValidDuration ? _formatDuration(totalDuration) : '--:--', // Show --:-- if duration unknown
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // Helper function to format Duration objects into a readable string (e.g., "00:00")
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}

// The current speed control (long-press fast-forward/rewind) works by skipping frames.
// This is acceptable when paused, but when playing and speeding up,
// the video should play at the faster rate with audio, not skip frames.
// if long-pressed left, it rewinds, instead of slows down

// import 'dart:async';

// import 'package:flutter/material.dart';
// import 'package:media_kit/media_kit.dart';
// import 'package:media_kit_video/media_kit_video.dart';

// class CustomVideoPlayer extends StatefulWidget {
//   final String videoUrl;

//   const CustomVideoPlayer({Key? key, required this.videoUrl}) : super(key: key);

//   @override
//   State<CustomVideoPlayer> createState() => _CustomVideoPlayerState();
// }

// class _CustomVideoPlayerState extends State<CustomVideoPlayer> {
//   late final Player _player;
//   late final VideoController _controller;

//   bool _isLoading = true;
//   String? _errorMessage;

//   // New state variables for custom controls
//   bool _isMuted = false;
//   double _lastVolume = 100.0; // Store last volume before muting
//   double _currentRate = 1.0; // Current playback rate
//   bool _showControls = false; // Controls visibility of the entire control overlay (bottom bar, center play button)
//   bool _isPlaying = false; // To track player's actual playing state

//   // New state variables for speed indicator
//   bool _showSpeedIndicator = false;
//   String _speedIndicatorText = '';
//   IconData? _speedIndicatorIcon;

//   // New state variables for vertical volume slider
//   bool _showVolumeSlider = false;
//   double _currentVolumeValue = 100.0; // Reflects current player volume (0-100)
//   double _dragStartY = 0.0; // Start Y position for vertical drag
//   double _dragStartVolume = 0.0; // Volume at the start of a vertical drag

//   // Timer for auto-hiding controls
//   Timer? _controlsTimer;
//   bool _showVolumeIcon = false; // Separate control for volume icon visibility

//   // --- Cached Duration State Variable ---
//   Duration? _cachedTotalDuration;

//   // --- NEW: StreamController for filtered position updates ---
//   final StreamController<Duration> _positionController = StreamController<Duration>.broadcast();
//   Duration _displayPosition = Duration.zero; // The position actually displayed on the slider

//   // --- NEW: Timer for long-press seeking ---
//   Timer? _seekTimer;
//   static const Duration _seekIncrement = Duration(seconds: 5); // Amount to seek per tick

//   @override
//   void initState() {
//     super.initState();
//     _initializeVideoPlayer();
//   }

//   Future<void> _initializeVideoPlayer() async {
//     setState(() {
//       _isLoading = true;
//       _errorMessage = null;
//     });

//     try {
//       _player = Player();
//       _controller = VideoController(_player);

//       String mediaPath = widget.videoUrl;
//       if (mediaPath.startsWith('file:///')) {
//         mediaPath = Uri.decodeComponent(mediaPath.substring('file:///'.length));
//       }

//       await _player.open(Media(mediaPath), play: true);
//       _player.setPlaylistMode(PlaylistMode.single);

//       // Listen to player state changes
//       _player.stream.playing.listen((playing) {
//         if (mounted) {
//           setState(() {
//             _isPlaying = playing;
//           });
//         }
//       });
//       _player.stream.volume.listen((volume) {
//         if (mounted) {
//           setState(() {
//             _isMuted = (volume == 0.0);
//             _currentVolumeValue = volume; // Keep _currentVolumeValue updated
//             if (volume > 0) {
//               _lastVolume = volume; // Keep track of last non-zero volume
//             }
//           });
//         }
//       });

//       // --- Listen to duration stream and cache it ---
//       // IMPORTANT: Only cache if duration is valid and not already cached.
//       // The `duration > Duration.zero` check is crucial.
//       _player.stream.duration.listen((duration) {
//         if (mounted && duration > Duration.zero && (_cachedTotalDuration == null || _cachedTotalDuration == Duration.zero)) {
//           setState(() {
//             _cachedTotalDuration = duration;
//             print('offline-chatview: Cached total duration: $_cachedTotalDuration');
//           });
//         }
//       });

//       // --- MODIFIED: Filtered position updates ---
//       _player.stream.position.listen((newPosition) {
//         if (mounted) {
//           // If the new position is zero, but we know the current position isn't
//           // the start of the video, and the total duration isn't also zero
//           // (to avoid blocking actual resets/new loads), we ignore this zero.
//           // This prevents the slider knob from jumping to 0:00 momentarily.
//           if (newPosition == Duration.zero &&
//               _displayPosition > Duration.zero &&
//               (_cachedTotalDuration != null && _cachedTotalDuration! > Duration.zero)) {
//             // print('DEBUG: Ignored momentary 0:00 position.');
//             return; // Ignore this update
//           }
//           setState(() {
//             _displayPosition = newPosition; // Update our internal display position
//           });
//           _positionController.add(newPosition); // Add to our controlled stream
//         }
//       });

//       setState(() {
//         _isLoading = false;
//         _showControls = false; // Initially hide controls after loading
//         _showVolumeIcon = false; // Initially hide volume icon
//       });
//       print('offline-chatview: MediaKit player initialized and playing for: ${widget.videoUrl}');
//     } catch (e, st) {
//       print("offline-chatview: Error initializing MediaKit player: $e");
//       print("offline-chatview: Stack trace: $st");
//       setState(() {
//         _errorMessage = "Failed to load video: ${e.toString()}";
//         _isLoading = false;
//       });
//     }
//   }

//   @override
//   void dispose() {
//     _player.dispose();
//     _controlsTimer?.cancel(); // Cancel timer on dispose
//     _seekTimer?.cancel(); // Cancel seek timer on dispose
//     _positionController.close(); // --- NEW: Close the position controller ---
//     super.dispose();
//   }

//   // --- Auto-hide controls timer ---
//   void _resetControlsTimer() {
//     _controlsTimer?.cancel();
//     _controlsTimer = Timer(const Duration(milliseconds: 1200), () { // Increased duration for better feedback
//       if (mounted) {
//         setState(() {
//           _showControls = false;
//           _showVolumeIcon = false;
//           _showSpeedIndicator = false;
//           _showVolumeSlider = false; // Hide volume slider too
//         });
//       }
//     });
//   }

//   // --- Volume Control (Mute/Unmute) ---
//   void _toggleMute() async {
//     // When mute/unmute is pressed, explicitly show controls, then reset timer
//     setState(() {
//       _showControls = true;
//       _showVolumeIcon = true;
//       _showVolumeSlider = false; // Ensure vertical slider is not visible
//     });
//     _resetControlsTimer();

//     if (_isMuted) {
//       await _player.setVolume(_lastVolume); // Restore last volume
//     } else {
//       _lastVolume = _player.state.volume; // Save current volume
//       await _player.setVolume(0.0); // Mute
//     }
//     // _isMuted and _currentVolumeValue are updated by stream listener,
//     // so no need for explicit setState here for those.
//   }

//   // --- Rate/Speed Control (Long Press) ---
//   void _startSpeedControl(LongPressStartDetails details) {
//     setState(() {
//       _showSpeedIndicator = true; // Show indicator when long press starts
//       _showControls = true; // Show main controls
//       _showVolumeIcon = true; // Show volume icon
//       _showVolumeSlider = false; // Hide volume slider
//     });
//     _resetControlsTimer(); // Reset timer on interaction

//     final double halfWidth = context.size!.width / 2;
//     if (details.localPosition.dx < halfWidth) {
//       // Long press on left side: slow down (rewind visual)
//       _currentRate = 0.5; // Example: half speed
//       _speedIndicatorText = '0.5x';
//       _speedIndicatorIcon = Icons.fast_rewind;
//     } else {
//       // Long press on right side: speed up (forward visual)
//       _currentRate = 2.0; // Example: double speed
//       _speedIndicatorText = '2.0x';
//       _speedIndicatorIcon = Icons.fast_forward;
//     }
//     _player.setRate(_currentRate);
//     print('offline-chatview: Player rate set to $_currentRate');

//     // --- NEW: Start continuous seeking with a timer ---
//    _seekTimer?.cancel(); // Cancel any existing seek timer
// _seekTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
//   if (!mounted) {
//     timer.cancel();
//     return;
//   }

//   Duration newPosition;
//   if (details.localPosition.dx < halfWidth) {
//     // Rewind
//     newPosition = _player.state.position - _seekIncrement;
//   } else {
//     // Fast Forward
//     newPosition = _player.state.position + _seekIncrement;
//   }

//   // Clamp the new position to valid range (0 to total duration)
//   // MANUAL CLAMPING IMPLEMENTATION FOR DURATION
//   if (newPosition < Duration.zero) {
//     newPosition = Duration.zero;
//   }
//   if (_cachedTotalDuration != null && _cachedTotalDuration! > Duration.zero) {
//     if (newPosition > _cachedTotalDuration!) {
//       newPosition = _cachedTotalDuration!;
//     }
//   } else {
//     // If total duration is not known, we can't clamp to the end,
//     // but still prevent going negative.
//     // Forwards seeking past current position is fine if total is unknown.
//   }

//   _player.seek(newPosition);
//   // Update _displayPosition directly to show immediate feedback on slider
//   setState(() {
//     _displayPosition = newPosition;
//   });
// });
//   }

//   void _endSpeedControl() {
//     _seekTimer?.cancel(); // --- NEW: Stop continuous seeking when long press ends ---
//     setState(() {
//       _showSpeedIndicator = false; // Hide indicator when long press ends
//       _currentRate = 1.0; // Reset to normal speed
//       _player.setRate(_currentRate);
//       print('offline-chatview: Player rate reset to $_currentRate');
//     });
//     _resetControlsTimer(); // Reset timer on interaction
//   }

//   // --- Play/Pause on Tap & Control Visibility ---
//   void _togglePlayPauseAndControls() {
//     // Toggle play/pause
//     _player.playOrPause();
//     // Show all controls
//     setState(() {
//       _showControls = !_showControls; // Toggle visibility of bottom controls and play button
//       _showVolumeIcon = _showControls; // Volume icon visibility follows main controls
//       _showVolumeSlider = false; // Ensure vertical slider is not active
//     });
//     _resetControlsTimer(); // Reset timer on interaction
//   }

//   // --- Vertical Volume Slider Gestures ---
//   void _startDragVolumeControl(DragStartDetails details) {
//     _dragStartY = details.localPosition.dy;
//     _dragStartVolume = _currentVolumeValue; // Store volume at start of drag
//     setState(() {
//       _showVolumeSlider = true;
//       _showControls = true; // Show main controls too
//       _showVolumeIcon = false; // Explicitly hide top-right icon when vertical slider is active
//     });
//     _resetControlsTimer(); // Reset timer on interaction
//   }

//   void _updateDragVolumeControl(DragUpdateDetails details) {
//     final double dragDeltaY = details.localPosition.dy - _dragStartY;

//     // Adjust sensitivity. Smaller value = more sensitive. (e.g., 100.0 or 150.0)
//     final double sensitivity = 150.0;
//     double volumeChange = (dragDeltaY / sensitivity) * 100.0;

//     // Dragging down (positive deltaY) should decrease volume.
//     // Dragging up (negative deltaY) should increase volume.
//     double newVolume = (_dragStartVolume - volumeChange).clamp(0.0, 100.0);
//     _player.setVolume(newVolume);

//     // No need for setState here for _currentVolumeValue as it's updated by the stream listener.
//     _resetControlsTimer(); // Keep resetting timer during drag
//   }

//   void _endDragVolumeControl(DragEndDetails details) {
//     _resetControlsTimer(); // Reset timer when drag ends
//   }


//   @override
//   Widget build(BuildContext context) {
//     if (_isLoading) {
//       return const Center(child: CircularProgressIndicator());
//     } else if (_errorMessage != null) {
//       return Center(
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             const Icon(Icons.error_outline, color: Colors.red, size: 48),
//             const SizedBox(height: 8),
//             Text(
//               _errorMessage!,
//               textAlign: TextAlign.center,
//               style: const TextStyle(color: Colors.red),
//             ),
//             const SizedBox(height: 8),
//             ElevatedButton(
//               onPressed: _initializeVideoPlayer,
//               child: const Text('Try Again'),
//             ),
//           ],
//         ),
//       );
//     } else {
//       return Padding(
//         padding: const EdgeInsets.all(15.0),
//         child: ClipRRect(
//           borderRadius: BorderRadius.circular(12.0),
//           child: Stack(
//             // Main Stack to layer all elements
//             children: [
//               // This GestureDetector now covers ONLY the video content area
//               // to capture main taps and drags without interfering with slider.
//               GestureDetector(
//                 onTap: _togglePlayPauseAndControls,
//                 onLongPressStart: _startSpeedControl,
//                 onLongPressEnd: (details) => _endSpeedControl(),
//                 onVerticalDragStart: _startDragVolumeControl,
//                 onVerticalDragUpdate: _updateDragVolumeControl,
//                 onVerticalDragEnd: _endDragVolumeControl,
//                 child: Positioned.fill(
//                   child: Video(
//                     controller: _controller,
//                     fit: BoxFit.contain,
//                     fill: Colors.black,
//                     controls: (state) => const SizedBox.shrink(), // Hide default media_kit controls
//                   ),
//                 ),
//               ),

//               // Conditional Play Button (Center)
//               if (!_isPlaying && _showControls) // Show play button only when paused AND controls are visible
//                 Center(
//                   child: StreamBuilder<bool>(
//                     stream: _player.stream.playing,
//                     builder: (context, playingSnapshot) {
//                       return IconButton(
//                         icon: const Icon(Icons.play_circle_fill, size: 80, color: Colors.white),
//                         onPressed: _togglePlayPauseAndControls, // Tap to play/pause and hide controls
//                       );
//                     },
//                   ),
//                 ),

//               // Volume/Mute Icon (Top Right) - now conditionally visible and clickable
//               Align(
//                 alignment: Alignment.topRight,
//                 child: AnimatedOpacity(
//                   opacity: (_showVolumeIcon && !_showVolumeSlider) ? 1.0 : 0.0, // Hide if vertical slider is active
//                   duration: const Duration(milliseconds: 200),
//                   child: IgnorePointer(
//                     ignoring: !(_showVolumeIcon && !_showVolumeSlider), // Ignore pointer events when hidden
//                     child: Padding(
//                       padding: const EdgeInsets.all(8.0),
//                       child: IconButton(
//                         icon: Icon(
//                           _isMuted ? Icons.volume_off : Icons.volume_up,
//                           color: Colors.white,
//                           size: 28.0,
//                         ),
//                         onPressed: _toggleMute, // This now correctly handles mute and resets timer
//                       ),
//                     ),
//                   ),
//                 ),
//               ),

//               // Speed Indicator (Bottom Center)
//               if (_showSpeedIndicator)
//                 Align(
//                   alignment: Alignment.bottomCenter,
//                   child: AnimatedOpacity(
//                     opacity: _showSpeedIndicator ? 1.0 : 0.0,
//                     duration: const Duration(milliseconds: 200),
//                     child: Padding(
//                       padding: const EdgeInsets.only(bottom: 50.0), // Position above bottom controls if they are also visible
//                       child: _buildSpeedIndicator(),
//                     ),
//                   ),
//                 ),

//               // Vertical Volume Slider (Left Side)
//               if (_showVolumeSlider)
//                 Align(
//                   alignment: Alignment.centerLeft, // Position on the left side
//                   child: AnimatedOpacity(
//                     opacity: _showVolumeSlider ? 1.0 : 0.0,
//                     duration: const Duration(milliseconds: 200),
//                     child: IgnorePointer(
//                       ignoring: !_showVolumeSlider,
//                       child: _buildVerticalVolumeSlider(), // Use the new dedicated widget
//                     ),
//                   ),
//                 ),

//               // Custom Controls (Bottom) - Only visible when _showControls is true
//               Align(
//                 alignment: Alignment.bottomCenter,
//                 child: AnimatedOpacity(
//                   // Add a subtle fade for controls
//                   opacity: _showControls ? 1.0 : 0.0,
//                   duration: const Duration(milliseconds: 200),
//                   child: IgnorePointer(
//                     // Ignore pointer events when hidden
//                     ignoring: !_showControls,
//                     child: _buildCustomControls(), // This will now conditionally show Slider or ProgressIndicator
//                   ),
//                 ),
//               ),
//             ],
//           ),
//         ),
//       );
//     }
//   }

//   // New private widget for the speed indicator
//   Widget _buildSpeedIndicator() {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
//       decoration: BoxDecoration(
//         color: Colors.black.withOpacity(0.7),
//         borderRadius: BorderRadius.circular(10.0),
//       ),
//       child: Row(
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           if (_speedIndicatorIcon != null)
//             Icon(
//               _speedIndicatorIcon,
//               color: Colors.white,
//               size: 20.0, // Adjusted size to ~85% (from 24.0)
//             ),
//           const SizedBox(width: 8.0),
//           Text(
//             _speedIndicatorText,
//             style: const TextStyle(
//               color: Colors.white,
//               fontSize: 17.0, // Adjusted size to ~85% (from 20.0)
//               fontWeight: FontWeight.bold,
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   // NEW private widget for the vertical volume slider
//   Widget _buildVerticalVolumeSlider() {
//     return Container(
//       width: 60, // Wider container
//       height: MediaQuery.of(context).size.height * 0.25, // Shorter
//       decoration: BoxDecoration(
//         color: Colors.black.withOpacity(0.6),
//         borderRadius: BorderRadius.circular(20.0), // Rounder corners
//       ),
//       child: Column(
//         mainAxisAlignment: MainAxisAlignment.end, // Align contents to bottom
//         children: [
//           Expanded(
//             // Slider takes available space
//             child: Padding(
//               // Add horizontal padding for wider "margins"
//               padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 0.0), // Wider horizontal padding
//               child: RotatedBox(
//                 quarterTurns: 3, // Rotate 270 degrees to make it vertical
//                 child: SliderTheme(
//                   data: SliderTheme.of(context).copyWith(
//                     activeTrackColor: Colors.white,
//                     inactiveTrackColor: Colors.grey,
//                     thumbColor: Colors.white,
//                     overlayColor: Colors.white.withOpacity(0.3),
//                     thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.0),
//                     overlayShape: const RoundSliderOverlayShape(overlayRadius: 16.0),
//                     trackHeight: 3.0,
//                   ),
//                   child: Slider(
//                     value: _currentVolumeValue, // Use the state variable that mirrors player volume
//                     min: 0.0,
//                     max: 100.0,
//                     onChanged: (val) {
//                       _player.setVolume(val);
//                       _resetControlsTimer(); // Reset timer on interaction
//                     },
//                   ),
//                 ),
//               ),
//             ),
//           ),
//           // Volume Icon at the bottom of the slider
//           Icon(
//             _currentVolumeValue == 0 ? Icons.volume_off : Icons.volume_up,
//             color: Colors.white,
//             size: 24.0, // Can be adjusted
//           ),
//           const SizedBox(height: 8.0), // Padding below the icon
//         ],
//       ),
//     );
//   }


//   // This method builds the custom controls for the video player (now hidden by default)
//   Widget _buildCustomControls() {
//     // --- MODIFIED: Use _positionController.stream for position ---
//     return Container(
//       color: Colors.black54,
//       padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
//       child: StreamBuilder<Duration>(
//         // Outer stream for position
//         stream: _positionController.stream, // Use our filtered stream here
//         builder: (context, positionSnapshot) {
//           final currentPosition = positionSnapshot.data ?? Duration.zero;
//           // IMPORTANT: Do NOT rely on _player.stream.duration here directly for total duration
//           // because it might fluctuate or emit 0:00. Use _cachedTotalDuration instead.

//           // --- Use _cachedTotalDuration as the primary source for total duration ---
//           final totalDuration = _cachedTotalDuration ?? Duration.zero;

//           // --- Debugging Prints for Timestamp Slider ---
//           print('--- Timestamp Slider Debug ---');
//           print('Current Position: $currentPosition');
//           // Still print this to monitor if the underlying stream is misbehaving
//           print('Total Duration (from stream): ${_player.state.duration}');
//           print('Cached Total Duration: $_cachedTotalDuration');
//           print('Effective Total Duration: $totalDuration'); // This should now always be the cached value if available
//           print('------------------------------');
//           // --- End Debugging Prints ---

//           // Check if we have a valid total duration (either cached or from stream)
//           // `totalDuration` will be the cached one, so we just check if it's > zero
//           bool hasValidDuration = totalDuration > Duration.zero;

//           return Column(
//             mainAxisSize: MainAxisSize.min, // Keep column compact
//             children: [
//               // Always render a Slider, but adjust its behavior and appearance
//               SliderTheme(
//                 data: SliderTheme.of(context).copyWith(
//                   activeTrackColor: Colors.white,
//                   inactiveTrackColor: Colors.grey,
//                   thumbColor: Colors.white,
//                   overlayColor: Colors.white.withOpacity(0.3),
//                   thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.0),
//                   overlayShape: const RoundSliderOverlayShape(overlayRadius: 16.0),
//                   trackHeight: 3.0,
//                 ),
//                 child: Slider(
//                   // Using a key can sometimes help Flutter retain state more predictably,
//                   // but the primary fix is the consistent widget type.
//                   key: ValueKey(hasValidDuration ? 'timestampSliderEnabled' : 'timestampSliderDisabled'),
//                   value: hasValidDuration
//                       ? currentPosition.inMilliseconds.toDouble().clamp(0.0, totalDuration.inMilliseconds.toDouble())
//                       : 0.0, // If no valid duration, value is 0
//                   min: 0.0,
//                   // If duration is invalid, set max to 1.0 or any small non-zero value
//                   // to prevent issues with a zero max value, but ensure it's not interactive.
//                   max: hasValidDuration ? totalDuration.inMilliseconds.toDouble() : 1.0,
//                   onChanged: hasValidDuration
//                       ? (value) {
//                           _player.seek(Duration(milliseconds: value.toInt()));
//                           _resetControlsTimer(); // Reset timer on slider interaction
//                         }
//                       : null, // Set to null to disable the slider if duration is unknown
//                   // Add onChangeStart and onChangeEnd for better UX during seeking
//                   onChangeStart: hasValidDuration
//                       ? (value) {
//                           // Optionally pause player here to prevent jitter while dragging
//                           // if (_player.state.playing) {
//                           //    _player.pause(); // Decided against pausing here as it interrupts flow
//                           // }
//                           _seekTimer?.cancel(); // Cancel any active seek timer during manual slider drag
//                         }
//                       : null,
//                   onChangeEnd: hasValidDuration
//                       ? (value) {
//                           // _player.play(); // No need to explicitly play, player should resume on its own
//                           _resetControlsTimer();
//                         }
//                       : null,
//                 ),
//               ),
//               // If totalDuration is 0 and you still want an active loading animation,
//               // you can overlay a LinearProgressIndicator. However, for consistency
//               // and to truly fix the ParentDataWidget error, we should avoid
//               // changing widget types. Instead, you can make the Slider's
//               // appearance subtly indicate loading, or explicitly add a small
//               // loading indicator *outside* the slider.
//               // For simplicity and to avoid the ParentDataWidget error,
//               // we're not adding a conditional LinearProgressIndicator here.
//               // The slider will simply be at 0 and non-interactive when duration is not known.

//               const SizedBox(height: 8),

//               // Display current time / total time
//               Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   Text(
//                     _formatDuration(currentPosition),
//                     style: const TextStyle(color: Colors.white),
//                   ),
//                   Text(
//                     hasValidDuration ? _formatDuration(totalDuration) : '--:--', // Show --:-- if duration unknown
//                     style: const TextStyle(color: Colors.white),
//                   ),
//                 ],
//               ),
//             ],
//           );
//         },
//       ),
//     );
//   }

//   // Helper to format duration for display
//   String _formatDuration(Duration duration) {
//     String twoDigits(int n) => n.toString().padLeft(2, '0');
//     final hours = twoDigits(duration.inHours);
//     final minutes = twoDigits(duration.inMinutes.remainder(60));
//     final seconds = twoDigits(duration.inSeconds.remainder(60));
//     if (duration.inHours > 0) {
//       return '$hours:$minutes:$seconds';
//     }
//     return '$minutes:$seconds';
//   }
// }

// CURRENT

