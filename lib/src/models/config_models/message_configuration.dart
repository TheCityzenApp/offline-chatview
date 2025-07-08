/*
 * Copyright (c) 2022 Simform Solutions
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

import '../../values/typedefs.dart';
import '../models.dart'; // Ensure models.dart is correctly imported for other configs

class MessageConfiguration {
  const MessageConfiguration({
    this.imageMessageConfig,
    this.messageReactionConfig,
    this.emojiMessageConfig,
    this.customMessageBuilder,
    this.voiceMessageConfig,
    this.customMessageReplyViewBuilder,
    this.videoMessageConfig, // ADD THIS LINE
    this.customVideoPlayerBuilder, // ADD THIS LINE
  });

  /// Provides configuration of image message appearance.
  final ImageMessageConfiguration? imageMessageConfig;

  /// Provides configuration of image message appearance.
  final MessageReactionConfiguration? messageReactionConfig;

  /// Provides configuration of emoji messages appearance.
  final EmojiMessageConfiguration? emojiMessageConfig;

  /// Provides builder to create view for custom messages.
  final CustomMessageBuilder? customMessageBuilder;

  /// Configurations for voice message bubble
  final VoiceMessageConfiguration? voiceMessageConfig;

  /// To customize reply view for custom message type
  final CustomMessageReplyViewBuilder? customMessageReplyViewBuilder;

  /// Provides configuration of video messages appearance.
  final VideoMessageConfiguration? videoMessageConfig; // ADD THIS LINE

  /// Provides a custom video player builder.
  final CustomVideoPlayerBuilder? customVideoPlayerBuilder; // ADD THIS LINE

  // Add the copyWith method to allow easy modification of properties
  MessageConfiguration copyWith({
    ImageMessageConfiguration? imageMessageConfig,
    MessageReactionConfiguration? messageReactionConfig,
    EmojiMessageConfiguration? emojiMessageConfig,
    CustomMessageBuilder? customMessageBuilder,
    VoiceMessageConfiguration? voiceMessageConfig,
    CustomMessageReplyViewBuilder? customMessageReplyViewBuilder,
    VideoMessageConfiguration? videoMessageConfig,
    CustomVideoPlayerBuilder? customVideoPlayerBuilder,
  }) {
    return MessageConfiguration(
      imageMessageConfig: imageMessageConfig ?? this.imageMessageConfig,
      messageReactionConfig: messageReactionConfig ?? this.messageReactionConfig,
      emojiMessageConfig: emojiMessageConfig ?? this.emojiMessageConfig,
      customMessageBuilder: customMessageBuilder ?? this.customMessageBuilder,
      voiceMessageConfig: voiceMessageConfig ?? this.voiceMessageConfig,
      customMessageReplyViewBuilder: customMessageReplyViewBuilder ?? this.customMessageReplyViewBuilder,
      videoMessageConfig: videoMessageConfig ?? this.videoMessageConfig, // ADD THIS LINE
      customVideoPlayerBuilder: customVideoPlayerBuilder ?? this.customVideoPlayerBuilder, // ADD THIS LINE
    );
  }
}

// You will also need to define VideoMessageConfiguration somewhere,
// for example, in models.dart or a new config file if it doesn't exist.
// For now, let's assume it's an empty class if you don't have specific configs for video messages yet.
// Example of a basic VideoMessageConfiguration:
class VideoMessageConfiguration {
  const VideoMessageConfiguration(); // You can add properties here if you need them later
}