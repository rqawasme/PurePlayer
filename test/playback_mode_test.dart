import 'package:flutter_test/flutter_test.dart';
import 'package:pureplayer/models/playback_mode.dart';

void main() {
  group('RepeatSetting', () {
    test('cycles off → all → one → off', () {
      expect(RepeatSetting.off.next, RepeatSetting.all);
      expect(RepeatSetting.all.next, RepeatSetting.one);
      expect(RepeatSetting.one.next, RepeatSetting.off);
    });

    test('fromName falls back to off for unknown or missing names', () {
      expect(RepeatSetting.fromName('one'), RepeatSetting.one);
      expect(RepeatSetting.fromName('nonsense'), RepeatSetting.off);
      expect(RepeatSetting.fromName(null), RepeatSetting.off);
    });
  });

  group('PlaybackMode', () {
    test('defaults to playing in order, once', () {
      const mode = PlaybackMode();
      expect(mode.shuffle, isFalse);
      expect(mode.repeat, RepeatSetting.off);
    });

    test('copyWith changes one setting and keeps the other', () {
      const mode = PlaybackMode(shuffle: true, repeat: RepeatSetting.all);
      expect(
        mode.copyWith(shuffle: false),
        const PlaybackMode(repeat: RepeatSetting.all),
      );
      expect(
        mode.copyWith(repeat: RepeatSetting.one),
        const PlaybackMode(shuffle: true, repeat: RepeatSetting.one),
      );
      expect(mode.copyWith(), mode);
    });

    test('survives an encode/decode round trip', () {
      for (final repeat in RepeatSetting.values) {
        for (final shuffle in [true, false]) {
          final mode = PlaybackMode(shuffle: shuffle, repeat: repeat);
          expect(PlaybackMode.decode(mode.encode()), mode);
        }
      }
    });

    test('decode returns null for anything unreadable', () {
      expect(PlaybackMode.decode(null), isNull);
      expect(PlaybackMode.decode(''), isNull);
      expect(PlaybackMode.decode('not json'), isNull);
      // Valid JSON, wrong shape — an older build's value, say.
      expect(PlaybackMode.decode('42'), isNull);
      expect(PlaybackMode.decode('["shuffle"]'), isNull);
    });

    test('decode fills in defaults for missing or wrong-typed fields', () {
      expect(PlaybackMode.decode('{}'), const PlaybackMode());
      expect(
        PlaybackMode.decode('{"shuffle": true}'),
        const PlaybackMode(shuffle: true),
      );
      expect(
        PlaybackMode.decode('{"repeat": "all"}'),
        const PlaybackMode(repeat: RepeatSetting.all),
      );
      expect(PlaybackMode.decode('{"shuffle": "yes"}'), const PlaybackMode());
    });

    test('equality covers both settings', () {
      const mode = PlaybackMode(shuffle: true, repeat: RepeatSetting.one);
      const same = PlaybackMode(shuffle: true, repeat: RepeatSetting.one);
      expect(mode, same);
      expect(mode.hashCode, same.hashCode);
      expect(mode, isNot(const PlaybackMode(repeat: RepeatSetting.one)));
      expect(mode, isNot(const PlaybackMode(shuffle: true)));
    });
  });
}
