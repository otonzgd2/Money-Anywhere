import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import 'opportunity_catalog.dart';

typedef OpportunityPin = ({
  String id,
  String? districtCode,
  String title,
  LatLng point,
  OpportunityCategory? category,
});

class OppMap extends StatelessWidget {
  const OppMap({super.key, required this.pins, required this.onOpen});
  final List<OpportunityPin> pins;
  final void Function(OpportunityPin) onOpen;

  @override
  Widget build(BuildContext context) => FlutterMap(
    options: MapOptions(
      initialCenter: pins.first.point,
      initialZoom: 13,
      initialCameraFit: pins.length < 2
          ? null
          : CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(
                pins.map((p) => p.point).toList(),
              ),
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
                  foregroundColor: pin.category?.color,
                ),
                icon: const Icon(Icons.place),
              ),
            ),
        ],
      ),
      const RichAttributionWidget(
        attributions: [TextSourceAttribution('OpenStreetMap contributors')],
      ),
    ],
  );
}
