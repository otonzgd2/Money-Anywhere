import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

/// Map view of the opportunity list (ui-states.md S6, map mode). Only items with an exact location get a pin;
/// city-level items (most real job posts) are counted in the bottom pill and stay in the list.
/// Tiles: OpenStreetMap (free, attribution required and shown).
class OppMap extends StatelessWidget {
  const OppMap({super.key, required this.items, required this.onOpen, required this.onShowList});
  final List<Map<String, dynamic>> items;
  final void Function(Map<String, dynamic>) onOpen;
  final VoidCallback onShowList;

  static const bangkok = LatLng(13.7466, 100.5393);
  static const groupIcon = {'job': '💼', 'skill': '🛠️', 'sell': '🛒', 'money': '💰'};

  static LatLng? pointOf(Map<String, dynamic> o) {
    final l = o['location'] as Map?;
    if (l == null || l['precision'] != 'exact' || l['lat'] is! num || l['lng'] is! num) return null;
    return LatLng((l['lat'] as num).toDouble(), (l['lng'] as num).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final pinned = [for (final o in items) if (pointOf(o) != null) o];
    final unpinned = items.length - pinned.length;
    final pts = pinned.map((o) => pointOf(o)!).toList();
    final center = pts.isEmpty
        ? bangkok
        : LatLng(pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length, pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length);
    return Stack(children: [
      FlutterMap(
        options: MapOptions(initialCenter: center, initialZoom: 13),
        children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.moneyanywhere.money_anywhere'),
          MarkerLayer(markers: [
            for (final o in pinned)
              Marker(
                point: pointOf(o)!,
                width: 46,
                height: 46,
                child: GestureDetector(
                  onTap: () => onOpen(o),
                  child: Container(
                    decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: const Color(0xFF0E9F6E), width: 2)),
                    alignment: Alignment.center,
                    child: Text(groupIcon[o['mapGroup']] ?? '📍', style: const TextStyle(fontSize: 22)),
                  ),
                ),
              ),
          ]),
          const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
        ],
      ),
      Positioned(
        top: 8,
        left: 8,
        right: 8,
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          if (unpinned > 0) ActionChip(avatar: const Text('📋'), label: Text('ไม่มีที่ตั้ง $unpinned รายการ ดูในรายการ'), onPressed: onShowList),
          if (pinned.isEmpty) const Chip(label: Text('ไม่มีรายการที่ปักหมุดได้ในหมวดนี้')),
          const Chip(label: Text('หมุดตัวอย่างเป็นที่อยู่สมมติ (DEMO)')),
        ]),
      ),
    ]);
  }
}
