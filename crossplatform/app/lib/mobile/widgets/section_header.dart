import 'package:waytty_l10n/waytty_l10n.dart';
import 'package:flutter/material.dart';

import '../theme/mobile_tokens.dart';

/// Uppercase, letter-spaced section label for grouped lists/settings.
class SectionHeader extends StatelessWidget {
  final String title;
  final bool translate;
  const SectionHeader(this.title, {super.key, this.translate = true});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: MobileTokens.space1,
        bottom: MobileTokens.space2,
        top: MobileTokens.space2,
      ),
      child: Text(
        (translate ? tr(context, title) : title).toUpperCase(),
        style: MobileTokens.sectionLabel(),
      ),
    );
  }
}
