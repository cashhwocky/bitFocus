import 'package:flutter/material.dart' hide Text;
import 'lowercase.dart';

class TabItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const TabItem(this.icon, this.selectedIcon, this.label);
}

/// Rounded tab dock. Horizontal (bottom) or vertical (left side rail).
/// Only the selected tab shows its name in the bottom bar, so six tabs fit cleanly.
class TabDock extends StatelessWidget {
  final List<TabItem> items;
  final int index;
  final ValueChanged<int> onSelect;
  final bool vertical;

  const TabDock({
    super.key,
    required this.items,
    required this.index,
    required this.onSelect,
    this.vertical = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(vertical ? 32 : 34),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: vertical ? _rail(scheme) : _bar(scheme),
    );
  }

  Widget _bar(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: LayoutBuilder(
        builder: (context, c) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: c.maxWidth),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [for (int i = 0; i < items.length; i++) _barItem(scheme, i)],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _barItem(ColorScheme scheme, int i) {
    final item = items[i];
    final sel = i == index;
    return Semantics(
      button: true,
      selected: sel,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelect(i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          height: 48,
          padding: EdgeInsets.symmetric(horizontal: sel ? 14 : 10),
          decoration: BoxDecoration(
            color: sel ? scheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                sel ? item.selectedIcon : item.icon,
                size: 23,
                color: sel ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                child: sel
                    ? Padding(
                        padding: const EdgeInsets.only(left: 7),
                        child: Text(
                          item.label,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rail(ColorScheme scheme) {
    return SizedBox(
      width: 72,
      child: LayoutBuilder(
        builder: (context, c) {
          return SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight - 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [for (int i = 0; i < items.length; i++) _railItem(scheme, i)],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _railItem(ColorScheme scheme, int i) {
    final item = items[i];
    final sel = i == index;
    return Semantics(
      button: true,
      selected: sel,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelect(i),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                width: 52,
                height: 32,
                decoration: BoxDecoration(
                  color: sel ? scheme.primaryContainer : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  sel ? item.selectedIcon : item.icon,
                  size: 23,
                  color: sel ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                item.label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                  color: sel ? scheme.onSurface : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
