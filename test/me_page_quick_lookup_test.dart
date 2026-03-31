import 'package:flutter_test/flutter_test.dart';
import 'package:vrc_monitor/widgets/me_page.dart';

void main() {
  group('parseQuickLookup', () {
    test('prefers instance over user regardless of position', () {
      const input =
          'user usr_de21ec4a-523b-4b6d-a453-b5514bef20e1 and '
          'wrld_61e374f5-a05f-44a9-80ff-6b845923dcd3:01520~hidden'
          '(usr_de21ec4a-523b-4b6d-a453-b5514bef20e1)~region(jp)';

      final match = parseQuickLookup(input);

      expect(match, isNotNull);
      expect(match!.type, QuickLookupType.instance);
      expect(match.worldId, 'wrld_61e374f5-a05f-44a9-80ff-6b845923dcd3');
      expect(
        match.instanceId,
        '01520~hidden(usr_de21ec4a-523b-4b6d-a453-b5514bef20e1)~region(jp)',
      );
    });

    test('matches world when only world id exists', () {
      final match = parseQuickLookup(
        'look at wrld_b3c848cd-af56-44fd-86b2-0a1cd0fec3a9 please',
      );

      expect(match, isNotNull);
      expect(match!.type, QuickLookupType.world);
      expect(match.value, 'wrld_b3c848cd-af56-44fd-86b2-0a1cd0fec3a9');
    });

    test('matches user when no instance or world exists', () {
      final match = parseQuickLookup(
        'profile usr_de21ec4a-523b-4b6d-a453-b5514bef20e1',
      );

      expect(match, isNotNull);
      expect(match!.type, QuickLookupType.user);
      expect(match.value, 'usr_de21ec4a-523b-4b6d-a453-b5514bef20e1');
    });

    test('matches avatar when only avatar exists', () {
      final match = parseQuickLookup(
        'avatar avtr_143ae13c-4a04-4588-99a1-a7d528aa2025',
      );

      expect(match, isNotNull);
      expect(match!.type, QuickLookupType.avatar);
      expect(match.value, 'avtr_143ae13c-4a04-4588-99a1-a7d528aa2025');
    });

    test('returns null when no supported id exists', () {
      expect(parseQuickLookup('nothing useful here'), isNull);
      expect(parseQuickLookup('   '), isNull);
    });
  });
}
