import 'package:flutter/foundation.dart';

import 'track.dart';

enum SortField {
  title('Title'),
  artist('Artist'),
  dateAdded('Date added'),
  duration('Duration');

  const SortField(this.label);
  final String label;

  static SortField fromName(String? name) => SortField.values.firstWhere(
    (field) => field.name == name,
    orElse: () => SortField.title,
  );
}

@immutable
class SortOption {
  const SortOption({this.field = SortField.title, this.ascending = true});

  final SortField field;
  final bool ascending;

  SortOption copyWith({SortField? field, bool? ascending}) => SortOption(
    field: field ?? this.field,
    ascending: ascending ?? this.ascending,
  );

  Map<String, Object?> toJson() => {
    'field': field.name,
    'ascending': ascending,
  };

  factory SortOption.fromJson(Map<String, Object?> json) => SortOption(
    field: SortField.fromName(json['field'] as String?),
    ascending: json['ascending'] as bool? ?? true,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SortOption &&
          other.field == field &&
          other.ascending == ascending);

  @override
  int get hashCode => Object.hash(field, ascending);
}

/// Case-insensitive match across title, artist and album.
///
/// An empty or whitespace-only [query] matches everything.
List<Track> searchTracks(List<Track> tracks, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return tracks;
  return tracks
      .where(
        (track) =>
            track.title.toLowerCase().contains(needle) ||
            track.artist.toLowerCase().contains(needle) ||
            track.album.toLowerCase().contains(needle),
      )
      .toList();
}

/// Returns a new sorted list; [tracks] is left untouched.
///
/// Ties always fall back to an A-to-Z title comparison, applied *after* the
/// direction flag, so entries within a group keep a readable order even when
/// the primary sort is descending.
List<Track> sortTracks(List<Track> tracks, SortOption option) {
  int byTitle(Track a, Track b) =>
      a.title.toLowerCase().compareTo(b.title.toLowerCase());

  final sorted = [...tracks];
  sorted.sort((a, b) {
    final primary = switch (option.field) {
      SortField.title => byTitle(a, b),
      SortField.artist => a.artist.toLowerCase().compareTo(
        b.artist.toLowerCase(),
      ),
      SortField.dateAdded => a.dateAdded.compareTo(b.dateAdded),
      SortField.duration => a.duration.compareTo(b.duration),
    };
    final directed = option.ascending ? primary : -primary;
    if (directed != 0) return directed;
    return byTitle(a, b);
  });
  return sorted;
}

/// Search first, then sort — the order the library screen applies them.
List<Track> queryTracks(List<Track> tracks, String query, SortOption option) =>
    sortTracks(searchTracks(tracks, query), option);
