import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;

// Persistent state + the aiming maths.
//
// spots:    [id, name, presenceEntity]            one per place you stand; presenceEntity is an
//                                                  HA sensor id, Beacon.NEAR / Beacon.FAR, or ""
// targets:  [spotId, entityId, centerDeg, halfDeg] one painted direction per (spot, device)
// devices:  [entityId, name, state]                synced from HA (state.json)
// presence: [entityId, name, state]                sensors a spot can be linked to
module Store {
    var spots as Array = [];
    var targets as Array = [];
    var devices as Array = [];
    var presence as Array = [];
    var curSpot as Number = -1;
    var nextId as Number = 1;
    var triggerMode as Number = 1;   // 0 = START button only, 1 = button + wrist flick
    var sensitivity as Number = 1;   // 0 low, 1 medium, 2 high
    var rangeDeg as Number = 10;     // extra degrees allowed beyond the painted edge
    var sepDeg as Number = 15;       // best and second best must differ by this much
    var bleNear as Number = -62;     // beacon RSSI stronger than this = the near spot (dBm)
    var bleFar as Number = -72;      // beacon RSSI weaker than this = the far spot (dBm)
    var lastSync as Number = 0;
    var demoHeading as Float? = null; // fixed heading for simulator screenshots (Demo.mc), not saved

    const PRESET_NAMES = ["Couch", "Bed", "Desk", "Kitchen", "Dining", "Door", "Bathroom", "Balcony", "Hall", "TV"];

    function load() as Void {
        var v;
        v = Storage.getValue("spots");    if (v instanceof Array) { spots = v; }
        v = Storage.getValue("targets");  if (v instanceof Array) { targets = v; }
        v = Storage.getValue("devices");  if (v instanceof Array) { devices = v; }
        v = Storage.getValue("presence"); if (v instanceof Array) { presence = v; }
        v = Storage.getValue("curSpot");  if (v instanceof Number) { curSpot = v; }
        v = Storage.getValue("nextId");   if (v instanceof Number) { nextId = v; }
        v = Storage.getValue("trig");     if (v instanceof Number) { triggerMode = v; }
        v = Storage.getValue("sens");     if (v instanceof Number) { sensitivity = v; }
        v = Storage.getValue("range");    if (v instanceof Number) { rangeDeg = v; }
        v = Storage.getValue("sep");      if (v instanceof Number) { sepDeg = v; }
        v = Storage.getValue("bleNear");  if (v instanceof Number) { bleNear = v; }
        v = Storage.getValue("bleFar");   if (v instanceof Number) { bleFar = v; }
        v = Storage.getValue("lastSync"); if (v instanceof Number) { lastSync = v; }
        if (curSpot < 0 && spots.size() > 0) { curSpot = (spots[0] as Array)[0] as Number; }
    }

    function save() as Void {
        Storage.setValue("spots", spots as Array<PropertyValueType>);
        Storage.setValue("targets", targets as Array<PropertyValueType>);
        Storage.setValue("devices", devices as Array<PropertyValueType>);
        Storage.setValue("presence", presence as Array<PropertyValueType>);
        Storage.setValue("curSpot", curSpot);
        Storage.setValue("nextId", nextId);
        Storage.setValue("trig", triggerMode);
        Storage.setValue("sens", sensitivity);
        Storage.setValue("range", rangeDeg);
        Storage.setValue("sep", sepDeg);
        Storage.setValue("bleNear", bleNear);
        Storage.setValue("bleFar", bleFar);
        Storage.setValue("lastSync", lastSync);
    }

    // ---- spots -------------------------------------------------------------

    function spotIndex(id as Number) as Number {
        for (var i = 0; i < spots.size(); i++) {
            if ((spots[i] as Array)[0] == id) { return i; }
        }
        return -1;
    }

    function spotName(id as Number) as String {
        var i = spotIndex(id);
        return i < 0 ? "No spot" : (spots[i] as Array)[1] as String;
    }

    function spotPresence(id as Number) as String {
        var i = spotIndex(id);
        return i < 0 ? "" : (spots[i] as Array)[2] as String;
    }

    function addSpot(name as String) as Number {
        var id = nextId;
        nextId++;
        spots = spots.add([id, name, ""]);
        if (curSpot < 0) { curSpot = id; }
        save();
        return id;
    }

    function setSpotPresence(id as Number, entity as String) as Void {
        var i = spotIndex(id);
        if (i >= 0) { spots[i] = [id, spotName(id), entity]; save(); }
    }

    function deleteSpot(id as Number) as Void {
        var i = spotIndex(id);
        if (i < 0) { return; }
        spots = removeAt(spots, i);
        var keep = [] as Array;
        for (var k = 0; k < targets.size(); k++) {
            if ((targets[k] as Array)[0] != id) { keep = keep.add(targets[k]); }
        }
        targets = keep;
        if (curSpot == id) { curSpot = spots.size() > 0 ? (spots[0] as Array)[0] as Number : -1; }
        save();
    }

    function nextSpot(step as Number) as Void {
        if (spots.size() == 0) { return; }
        var i = spotIndex(curSpot);
        i = (i + step + spots.size()) % spots.size();
        curSpot = (spots[i] as Array)[0] as Number;
        save();
    }

    // Any spot linked to an HA presence sensor (needs a sync to locate).
    function hasPresenceSpots() as Boolean {
        for (var i = 0; i < spots.size(); i++) {
            var ent = (spots[i] as Array)[2] as String;
            if (!ent.equals("") && !Beacon.isBeacon(ent)) { return true; }
        }
        return false;
    }

    // Any spot linked to the BLE beacon (needs a scan to locate).
    function hasBeaconSpots() as Boolean {
        for (var i = 0; i < spots.size(); i++) {
            if (Beacon.isBeacon((spots[i] as Array)[2] as String)) { return true; }
        }
        return false;
    }

    // Pick the spot linked to the beacon zone of `rssi`. Returns "" on success, else why not.
    // In the gap between the thresholds the current spot stays (hysteresis).
    function autoSpotBeacon(rssi as Number?) as String {
        if (rssi == null) { return "Beacon not found"; }
        var z = Beacon.zone(rssi as Number);
        if (z.equals("")) { return "Between spots"; }
        var want = z.equals("near") ? Beacon.NEAR : Beacon.FAR;
        for (var i = 0; i < spots.size(); i++) {
            if (((spots[i] as Array)[2] as String).equals(want)) {
                curSpot = (spots[i] as Array)[0] as Number;
                save();
                return "";
            }
        }
        return "No " + z + " spot";
    }

    // Pick the first spot whose linked presence sensor says we are there.
    function autoSpot() as Boolean {
        for (var i = 0; i < spots.size(); i++) {
            var ent = (spots[i] as Array)[2] as String;
            if (ent.equals("") || Beacon.isBeacon(ent)) { continue; }
            var st = presenceState(ent);
            if (st.equals("on") || st.equals("home")) {
                curSpot = (spots[i] as Array)[0] as Number;
                save();
                return true;
            }
        }
        return false;
    }

    function presenceName(entity as String) as String {
        if (Beacon.isBeacon(entity)) { return Beacon.label(entity); }
        for (var i = 0; i < presence.size(); i++) {
            var p = presence[i] as Array;
            if ((p[0] as String).equals(entity)) { return p[1] as String; }
        }
        return entity;
    }

    function presenceState(entity as String) as String {
        for (var i = 0; i < presence.size(); i++) {
            var p = presence[i] as Array;
            if ((p[0] as String).equals(entity)) { return p[2] as String; }
        }
        return "";
    }

    // ---- devices -----------------------------------------------------------

    function deviceName(entity as String) as String {
        for (var i = 0; i < devices.size(); i++) {
            var d = devices[i] as Array;
            if ((d[0] as String).equals(entity)) { return d[1] as String; }
        }
        return entity;
    }

    function deviceState(entity as String) as String {
        for (var i = 0; i < devices.size(); i++) {
            var d = devices[i] as Array;
            if ((d[0] as String).equals(entity)) { return d[2] as String; }
        }
        return "";
    }

    function setSynced(dev as Array, pres as Array, ts as Number) as Void {
        devices = dev;
        presence = pres;
        lastSync = ts;
        save();
    }

    // ---- targets -----------------------------------------------------------

    function targetsForSpot(spotId as Number) as Array {
        var out = [] as Array;
        for (var i = 0; i < targets.size(); i++) {
            if ((targets[i] as Array)[0] == spotId) { out = out.add(targets[i]); }
        }
        return out;
    }

    function findTarget(spotId as Number, entity as String) as Number {
        for (var i = 0; i < targets.size(); i++) {
            var t = targets[i] as Array;
            if (t[0] == spotId && (t[1] as String).equals(entity)) { return i; }
        }
        return -1;
    }

    // Replace the painted direction of (spot, entity), or add it.
    function setTarget(spotId as Number, entity as String, center as Float, half as Float) as Void {
        var i = findTarget(spotId, entity);
        var row = [spotId, entity, center, half];
        if (i >= 0) { targets[i] = row; } else { targets = targets.add(row); }
        save();
    }

    function deleteTarget(spotId as Number, entity as String) as Void {
        var i = findTarget(spotId, entity);
        if (i >= 0) { targets = removeAt(targets, i); save(); }
    }

    // "It learns from it": widen the painted arc of `entity` so it covers `heading`.
    function learn(spotId as Number, entity as String, heading as Float) as Void {
        var i = findTarget(spotId, entity);
        if (i < 0) {
            setTarget(spotId, entity, heading, 8.0);
            return;
        }
        var t = targets[i] as Array;
        var c = t[2] as Float;
        var w = t[3] as Float;
        var d = signedDiff(heading, c);
        if (d.abs() <= w) { return; }
        // New arc from the far edge of the old arc to the new heading.
        var edge = d > 0 ? c - w : c + w;
        var span = signedDiff(heading, edge).abs();
        var newHalf = span / 2.0;
        if (newHalf > 80.0) { newHalf = 80.0; }
        var newCenter = norm(edge + (d > 0 ? newHalf : -newHalf));
        targets[i] = [spotId, entity, newCenter, newHalf];
        save();
    }

    // ---- matching ----------------------------------------------------------

    // Returns {:entity => String or null, :reason => String, :second => String or null, :dist => Float}
    // reason is empty when a device is chosen; otherwise it explains the refusal.
    function match(heading as Float, spotId as Number) as Dictionary {
        if (spotIndex(spotId) < 0) {
            return {:entity => null, :reason => "No spot", :second => null};
        }
        var list = targetsForSpot(spotId);
        if (list.size() == 0) {
            return {:entity => null, :reason => "Nothing painted", :second => null};
        }
        var bestEnt = null;
        var bestScore = 9999.0;
        var bestDist = 0.0;
        var secondEnt = null;
        var secondScore = 9999.0;
        for (var i = 0; i < list.size(); i++) {
            var t = list[i] as Array;
            var ent = t[1] as String;
            var d = angDist(heading, t[2] as Float);
            var score = d - (t[3] as Float);   // <= 0 inside the painted arc
            if (score > rangeDeg) { continue; }
            if (score < bestScore) {
                if (bestEnt != null && !(bestEnt as String).equals(ent)) {
                    secondEnt = bestEnt;
                    secondScore = bestScore;
                }
                bestEnt = ent;
                bestScore = score;
                bestDist = d;
            } else if (!ent.equals(bestEnt as String) && score < secondScore) {
                secondEnt = ent;
                secondScore = score;
            }
        }
        if (bestEnt == null) {
            return {:entity => null, :reason => "Nothing in range", :second => null};
        }
        if (secondEnt != null && (secondScore - bestScore) < sepDeg) {
            return {:entity => null, :reason => "Ambiguous", :second => secondEnt, :first => bestEnt};
        }
        return {:entity => bestEnt, :reason => "", :second => null, :dist => bestDist};
    }

    // ---- angle helpers -----------------------------------------------------

    function norm(a as Float) as Float {
        var x = a;
        while (x < 0.0) { x += 360.0; }
        while (x >= 360.0) { x -= 360.0; }
        return x;
    }

    // b - a in (-180, 180]
    function signedDiff(b as Float, a as Float) as Float {
        var d = norm(b - a);
        if (d > 180.0) { d -= 360.0; }
        return d;
    }

    function angDist(a as Float, b as Float) as Float {
        return signedDiff(a, b).abs();
    }

    // Circular mean of a list of headings (degrees), and the arc half-width that covers
    // 90 % of them. A percentile rather than the maximum, so one compass glitch during
    // the 5 s sweep cannot blow the arc up until it overlaps the next device.
    function arcOf(samples as Array<Float>) as Array<Float> {
        var n = samples.size();
        var sx = 0.0;
        var sy = 0.0;
        for (var i = 0; i < n; i++) {
            var r = Math.toRadians(samples[i]);
            sx += Math.cos(r);
            sy += Math.sin(r);
        }
        var center = norm(Math.toDegrees(Math.atan2(sy, sx)).toFloat());
        var dev = new Array<Float>[n];
        for (var i = 0; i < n; i++) { dev[i] = angDist(samples[i], center); }
        for (var i = 1; i < n; i++) {           // insertion sort, n <= 50
            var v = dev[i];
            var k = i - 1;
            while (k >= 0 && dev[k] > v) { dev[k + 1] = dev[k]; k--; }
            dev[k + 1] = v;
        }
        var half = dev[((n - 1) * 9) / 10] + 3.0;
        if (half < 5.0) { half = 5.0; }
        if (half > 60.0) { half = 60.0; }
        return [center, half];
    }

    // Circular mean of the non-null entries (degrees), or null when there are none.
    function meanOf(samples as Array<Float?>) as Float? {
        var sx = 0.0;
        var sy = 0.0;
        var n = 0;
        for (var i = 0; i < samples.size(); i++) {
            var s = samples[i];
            if (s == null) { continue; }
            var r = Math.toRadians(s as Float);
            sx += Math.cos(r);
            sy += Math.sin(r);
            n++;
        }
        if (n == 0) { return null; }
        return norm(Math.toDegrees(Math.atan2(sy, sx)).toFloat());
    }

    function removeAt(arr as Array, i as Number) as Array {
        var out = [] as Array;
        for (var k = 0; k < arr.size(); k++) {
            if (k != i) { out = out.add(arr[k]); }
        }
        return out;
    }
}
