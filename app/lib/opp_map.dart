import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import 'opportunity_catalog.dart';
import 'thang_rot_theme.dart';

typedef OpportunityPin = ({
  String id,
  String? districtCode,
  String title,
  LatLng point,
  OpportunityCategory? category,
});
typedef DistrictPin = ({String district, LatLng point, int count});

class OppMap extends StatelessWidget {
  const OppMap({
    super.key,
    required this.pins,
    required this.districtPins,
    required this.onOpen,
    required this.onOpenDistrict,
  });
  final List<OpportunityPin> pins;
  final List<DistrictPin> districtPins;
  final void Function(OpportunityPin) onOpen;
  final ValueChanged<String> onOpenDistrict;

  @override
  Widget build(BuildContext context) {
    final points = [
      for (final pin in pins) pin.point,
      for (final pin in districtPins) pin.point,
    ];
    return Column(
      children: [
        Expanded(
          child: FlutterMap(
            options: MapOptions(
              initialCenter: points.first,
              initialZoom: 13,
              initialCameraFit: points.length < 2
                  ? null
                  : CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(points),
                      padding: const EdgeInsets.all(48),
                      maxZoom: 15,
                    ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.moneyanywhere.money_anywhere',
              ),
              MarkerLayer(
                markers: [
                  for (final pin in pins)
                    Marker(
                      key: ValueKey((pin.id, pin.districtCode)),
                      point: pin.point,
                      width: 48,
                      height: 48,
                      child: IconButton(
                        tooltip: pin.title,
                        onPressed: () => onOpen(pin),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: pin.category?.color ?? brandDark,
                          side: const BorderSide(color: brandDark),
                        ),
                        icon: Icon(pin.category?.icon ?? Icons.place_outlined),
                      ),
                    ),
                  for (final pin in districtPins)
                    Marker(
                      key: ValueKey(pin.district),
                      point: pin.point,
                      width: 44,
                      height: 44,
                      child: IconButton(
                        tooltip: 'เขต${pin.district} ${pin.count} รายการจำลอง',
                        onPressed: () => onOpenDistrict(pin.district),
                        style: IconButton.styleFrom(
                          backgroundColor: brandDark,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.zero,
                          side: const BorderSide(color: Colors.white, width: 2),
                        ),
                        icon: Text(
                          '${pin.count}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
        ),
        if (pins.isNotEmpty || districtPins.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Row(
              children: [
                for (final pin in pins)
                  _MapCard(
                    label: pin.title,
                    icon: pin.category?.icon ?? Icons.place_outlined,
                    action: 'ดูรายละเอียด',
                    onTap: () => onOpen(pin),
                  ),
                for (final pin in districtPins)
                  _MapCard(
                    label: 'เขต${pin.district}',
                    icon: Icons.place_outlined,
                    action: 'ดู ${pin.count} รายการ · DEMO',
                    onTap: () => onOpenDistrict(pin.district),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MapCard extends StatelessWidget {
  const _MapCard({
    required this.label,
    required this.icon,
    required this.action,
    required this.onTap,
  });
  final String label, action;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 238,
    child: Card(
      margin: const EdgeInsets.only(right: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        leading: Icon(icon, color: brandDark),
        title: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(action, style: const TextStyle(color: brandDark)),
        onTap: onTap,
      ),
    ),
  );
}
