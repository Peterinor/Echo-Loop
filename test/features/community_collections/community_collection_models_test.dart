import 'package:flutter_test/flutter_test.dart';

import 'package:echo_loop/features/community_collections/models/community_collection_models.dart';
import 'package:echo_loop/models/collection.dart';

void main() {
  test(
    'legacy collection source is read as community and stored canonically',
    () {
      expect(
        CollectionSource.fromString('official'),
        CollectionSource.community,
      );
      expect(CollectionSource.community.storageValue, 'community');
    },
  );

  test('subtitle DTO converts seconds to millisecond precision', () {
    final subtitle = CommunitySubtitle.fromJson({
      'fileId': 'file-1',
      'sentences': [
        {'text': 'A sentence', 'startTime': 1.125, 'endTime': 2.5},
      ],
      'words': [
        {'word': 'A', 'startTime': 1.125, 'endTime': 1.4},
      ],
    });

    expect(subtitle.sentences.single.startTime.inMilliseconds, 1125);
    expect(subtitle.sentences.single.endTime.inMilliseconds, 2500);
    expect(subtitle.words.single.endTime.inMilliseconds, 1400);
  });
}
