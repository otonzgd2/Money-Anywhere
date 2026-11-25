// Geocoder port. District table adapter: text -> approximate district centre (search point only, never a pin).
function createGeocoder(districts) {
  return {
    geocode(text) {
      if (!text) return null;
      const t = String(text).replace(/^เขต\s*/, '').trim();
      const d = districts.find(x => x.name === t || x.id === t);
      return d ? { lat: d.lat, lng: d.lng, precision: 'city' } : null;
    }
  };
}
module.exports = { createGeocoder };
