import 'dart:convert';

import 'package:flutter/foundation.dart';

/// What happens when the queue reaches its end, or a track finishes.
enum RepeatSetting {
  /// Stop after the last track in the queue.
  off('Repeat off'),

  /// Wrap around to the first track.
  all('Repeat all'),

  /// Keep replaying the current track.
  one('Repeat one');

  const RepeatSetting(this.label);

  final String label;

  /// The next mode in the order the repeat button cycles through:
  /// off → all → one → off.
  RepeatSetting get next =>
      RepeatSetting.values[(index + 1) % RepeatSetting.values.length];

  /// Reads a stored [name]. Takes an [Object?] rather than a [String] so a
  /// value of the wrong type in the saved JSON falls back instead of throwing.
  static RepeatSetting fromName(Object? name) => RepeatSetting.values
      .firstWhere((mode) => mode.name == name, orElse: () => RepeatSetting.off);
}

/// The two "how does the queue advance" settings, kept together because they
/// are shown, persisted and applied to the player as a pair.
@immutable
class PlaybackMode {
  const PlaybackMode({this.shuffle = false, this.repeat = RepeatSetting.off});

  /// Whether the queue plays in a random order rather than its listed one.
  final bool shuffle;

  final RepeatSetting repeat;

  PlaybackMode copyWith({bool? shuffle, RepeatSetting? repeat}) => PlaybackMode(
    shuffle: shuffle ?? this.shuffle,
    repeat: repeat ?? this.repeat,
  );

  /// Label for the shuffle toggle, phrased as the state it is in.
  String get shuffleLabel => shuffle ? 'Shuffle on' : 'Shuffle off';

  Map<String, Object?> toJson() => {'shuffle': shuffle, 'repeat': repeat.name};

  factory PlaybackMode.fromJson(Map<String, Object?> json) => PlaybackMode(
    shuffle: json['shuffle'] == true,
    repeat: RepeatSetting.fromName(json['repeat']),
  );

  String encode() => jsonEncode(toJson());

  /// Reads back [encode]. Returns `null` for anything unreadable, so a value
  /// written by an older build — or a corrupt one — just leaves the defaults
  /// in place instead of throwing on launch.
  static PlaybackMode? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      return json is Map<String, Object?> ? PlaybackMode.fromJson(json) : null;
    } on FormatException {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaybackMode &&
          other.shuffle == shuffle &&
          other.repeat == repeat);

  @override
  int get hashCode => Object.hash(shuffle, repeat);

  @override
  String toString() =>
      'PlaybackMode(shuffle: $shuffle, repeat: ${repeat.name})';
}
