import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// All Menu2 screens. Each push* builds a fresh menu so the lists are never stale.
module Menus {

    function pushMain() as Void {
        var m = new WatchUi.Menu2({:title => "Wand"});
        m.addItem(new WatchUi.MenuItem("Paint device", "teach a direction", :paint, null));
        m.addItem(new WatchUi.MenuItem("Spots", Store.spots.size().toString() + " · " + Store.spotName(Store.curSpot), :spots, null));
        m.addItem(new WatchUi.MenuItem("Sync devices", Store.devices.size().toString() + " from HA", :sync, null));
        m.addItem(new WatchUi.MenuItem("Test connection", null, :ping, null));
        m.addItem(new WatchUi.MenuItem("Settings", null, :settings, null));
        WatchUi.pushView(m, new MainDelegate(), WatchUi.SLIDE_UP);
    }

    function pushSpots() as Void {
        var m = new WatchUi.Menu2({:title => "Spots"});
        for (var i = 0; i < Store.spots.size(); i++) {
            var s = Store.spots[i] as Array;
            var id = s[0] as Number;
            var sub = (id == Store.curSpot) ? "current" : "";
            var pres = s[2] as String;
            if (!pres.equals("")) { sub = sub + (sub.equals("") ? "" : " · ") + "auto"; }
            sub = sub + (sub.equals("") ? "" : " · ") + Store.targetsForSpot(id).size().toString() + " painted";
            m.addItem(new WatchUi.MenuItem(s[1] as String, sub, id, null));
        }
        m.addItem(new WatchUi.MenuItem("+ Add spot", null, :add, null));
        WatchUi.pushView(m, new SpotsDelegate(), WatchUi.SLIDE_LEFT);
    }

    function pushSpotMenu(spotId as Number) as Void {
        var m = new WatchUi.Menu2({:title => Store.spotName(spotId)});
        m.addItem(new WatchUi.MenuItem("Use this spot", spotId == Store.curSpot ? "current" : null, :use, null));
        m.addItem(new WatchUi.MenuItem("Paint device here", null, :paint, null));
        var pres = Store.spotPresence(spotId);
        m.addItem(new WatchUi.MenuItem("Presence sensor", pres.equals("") ? "none" : Store.presenceName(pres), :presence, null));
        m.addItem(new WatchUi.MenuItem("Painted devices", Store.targetsForSpot(spotId).size().toString(), :painted, null));
        m.addItem(new WatchUi.MenuItem("Delete spot", null, :delete, null));
        WatchUi.pushView(m, new SpotMenuDelegate(spotId), WatchUi.SLIDE_LEFT);
    }

    function pushAddSpot() as Void {
        var m = new WatchUi.Menu2({:title => "Name the spot"});
        for (var i = 0; i < Store.PRESET_NAMES.size(); i++) {
            m.addItem(new WatchUi.MenuItem(Store.PRESET_NAMES[i], null, i, null));
        }
        m.addItem(new WatchUi.MenuItem("Spot " + Store.nextId.toString(), null, :generic, null));
        WatchUi.pushView(m, new AddSpotDelegate(), WatchUi.SLIDE_LEFT);
    }

    // Pick a device. cb.invoke(entityId). `skip` is left out of the list.
    function pushDevicePicker(title as String, cb as Method(entity as String) as Void, skip as String?) as Void {
        if (Store.devices.size() == 0) {
            WatchUi.pushView(new MsgView("Devices", "No devices yet.\nMenu > Sync devices", null), new MsgDelegate(), WatchUi.SLIDE_LEFT);
            return;
        }
        var m = new WatchUi.Menu2({:title => title});
        for (var i = 0; i < Store.devices.size(); i++) {
            var d = Store.devices[i] as Array;
            var ent = d[0] as String;
            if (skip != null && ent.equals(skip)) { continue; }
            m.addItem(new WatchUi.MenuItem(d[1] as String, ent, i, null));
        }
        WatchUi.pushView(m, new DevicePickDelegate(cb), WatchUi.SLIDE_LEFT);
    }

    function pushPresencePicker(spotId as Number) as Void {
        var m = new WatchUi.Menu2({:title => "Presence sensor"});
        m.addItem(new WatchUi.MenuItem("None", "pick spot by hand", -1, null));
        m.addItem(new WatchUi.MenuItem("Beacon · near", "RSSI over " + Store.bleNear.toString() + " dBm", :near, null));
        m.addItem(new WatchUi.MenuItem("Beacon · far", "RSSI under " + Store.bleFar.toString() + " dBm", :far, null));
        for (var i = 0; i < Store.presence.size(); i++) {
            var p = Store.presence[i] as Array;
            m.addItem(new WatchUi.MenuItem(p[1] as String, (p[0] as String) + " · " + (p[2] as String), i, null));
        }
        WatchUi.pushView(m, new PresencePickDelegate(spotId), WatchUi.SLIDE_LEFT);
    }

    function pushPainted(spotId as Number) as Void {
        var list = Store.targetsForSpot(spotId);
        var m = new WatchUi.Menu2({:title => "Painted · select = delete"});
        for (var i = 0; i < list.size(); i++) {
            var t = list[i] as Array;
            var sub = (t[2] as Float).format("%.0f") + "° ±" + (t[3] as Float).format("%.0f") + "°";
            m.addItem(new WatchUi.MenuItem(Store.deviceName(t[1] as String), sub, t[1] as String, null));
        }
        if (list.size() == 0) { m.addItem(new WatchUi.MenuItem("Nothing painted", null, :none, null)); }
        WatchUi.pushView(m, new PaintedDelegate(spotId), WatchUi.SLIDE_LEFT);
    }

    function pushSettings() as Void {
        var m = new WatchUi.Menu2({:title => "Settings"});
        m.addItem(new WatchUi.MenuItem("Trigger", Store.triggerMode == 1 ? "START + wrist flick" : "START button only", :trigger, null));
        var sensNames = ["Low", "Medium", "High"];
        m.addItem(new WatchUi.MenuItem("Flick sensitivity", sensNames[Store.sensitivity], :sens, null));
        m.addItem(new WatchUi.MenuItem("Range", "+" + Store.rangeDeg.toString() + "° past the edge", :range, null));
        m.addItem(new WatchUi.MenuItem("Separation", Store.sepDeg.toString() + "° between devices", :sep, null));
        m.addItem(new WatchUi.MenuItem("Beacon near", "over " + Store.bleNear.toString() + " dBm", :near, null));
        m.addItem(new WatchUi.MenuItem("Beacon far", "under " + Store.bleFar.toString() + " dBm", :far, null));
        m.addItem(new WatchUi.MenuItem("Beacon signal", "live RSSI, for tuning", :rssi, null));
        m.addItem(new WatchUi.MenuItem("HA URL", Ha.baseUrl(), :url, null));
        m.addItem(new WatchUi.MenuItem("Reset all data", "spots, paints, devices", :reset, null));
        WatchUi.pushView(m, new SettingsDelegate(), WatchUi.SLIDE_LEFT);
    }

    function pushChoice(title as String, labels as Array<String>, values as Array<Number>, current as Number, cb as Method(v as Number) as Void) as Void {
        var m = new WatchUi.Menu2({:title => title});
        for (var i = 0; i < labels.size(); i++) {
            m.addItem(new WatchUi.MenuItem(labels[i], values[i] == current ? "current" : null, values[i], null));
        }
        WatchUi.pushView(m, new ChoiceDelegate(cb), WatchUi.SLIDE_LEFT);
    }

    // Run `cb` after the system has finished popping a Confirmation dialog.
    var _laterTimer as Timer.Timer? = null;
    function later(cb as Method() as Void) as Void {
        _laterTimer = new Timer.Timer();
        (_laterTimer as Timer.Timer).start(cb, 150, false);
    }

    // fitTextToArea can return null when nothing fits; never hand null to drawText.
    function fit(text as String, font as Graphics.FontDefinition, w as Number, h as Number) as String {
        var f = Graphics.fitTextToArea(text, font, w, h, true);
        return (f == null) ? text : f;
    }

    function toast(msg as String) as Void {
        if (WatchUi has :showToast) {
            WatchUi.showToast(msg, null);
        }
    }
}

// ---------------------------------------------------------------------------

class MainDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() { Menu2InputDelegate.initialize(); }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :paint) {
            if (Store.spots.size() == 0) {
                Menus.toast("Add a spot first");
                Menus.pushAddSpot();
            } else {
                Menus.pushDevicePicker("Paint which?", method(:onPaintDevice), null);
            }
        } else if (id == :spots) {
            Menus.pushSpots();
        } else if (id == :sync) {
            var v = new MsgView("Sync", "Asking HA...", :sync);
            WatchUi.pushView(v, new MsgDelegate(), WatchUi.SLIDE_LEFT);
        } else if (id == :ping) {
            var v = new MsgView("Test", "Pinging HA...", :ping);
            WatchUi.pushView(v, new MsgDelegate(), WatchUi.SLIDE_LEFT);
        } else if (id == :settings) {
            Menus.pushSettings();
        }
    }

    function onPaintDevice(entity as String) as Void {
        // Paint on the current spot; pick one first if none is current.
        var spotId = Store.curSpot;
        if (Store.spotIndex(spotId) < 0) { spotId = (Store.spots[0] as Array)[0] as Number; Store.curSpot = spotId; }
        var v = new PaintView(spotId, entity);
        WatchUi.pushView(v, new PaintDelegate(v), WatchUi.SLIDE_LEFT);
    }
}

class SpotsDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() { Menu2InputDelegate.initialize(); }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :add) {
            Menus.pushAddSpot();
        } else if (id instanceof Number) {
            Menus.pushSpotMenu(id as Number);
        }
    }
}

class SpotMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _spotId as Number;

    function initialize(spotId as Number) {
        Menu2InputDelegate.initialize();
        _spotId = spotId;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :use) {
            Store.curSpot = _spotId;
            Store.save();
            Menus.toast("Spot: " + Store.spotName(_spotId));
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        } else if (id == :paint) {
            Store.curSpot = _spotId;
            Store.save();
            Menus.pushDevicePicker("Paint which?", method(:onPaintDevice), null);
        } else if (id == :presence) {
            Menus.pushPresencePicker(_spotId);
        } else if (id == :painted) {
            Menus.pushPainted(_spotId);
        } else if (id == :delete) {
            var dlg = new WatchUi.Confirmation("Delete " + Store.spotName(_spotId) + "?");
            WatchUi.pushView(dlg, new DeleteSpotConfirm(_spotId), WatchUi.SLIDE_UP);
        }
    }

    function onPaintDevice(entity as String) as Void {
        var v = new PaintView(_spotId, entity);
        WatchUi.pushView(v, new PaintDelegate(v), WatchUi.SLIDE_LEFT);
    }
}

class DeleteSpotConfirm extends WatchUi.ConfirmationDelegate {
    private var _spotId as Number;

    function initialize(spotId as Number) {
        ConfirmationDelegate.initialize();
        _spotId = spotId;
    }

    function onResponse(response as WatchUi.Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            Store.deleteSpot(_spotId);
            Menus.later(method(:leave));
        }
        return true;
    }

    // The dialog is gone now: drop the spot menu and rebuild the spots list.
    function leave() as Void {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        Menus.pushSpots();
    }
}

class AddSpotDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() { Menu2InputDelegate.initialize(); }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        var name = (id instanceof Number) ? Store.PRESET_NAMES[id as Number] : ("Spot " + Store.nextId.toString());
        // Avoid duplicate names: "Couch 2".
        var base = name;
        var n = 2;
        while (nameTaken(name)) { name = base + " " + n.toString(); n++; }
        var spotId = Store.addSpot(name);
        Store.curSpot = spotId;
        Store.save();
        Menus.toast("Added " + name);
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        Menus.pushSpotMenu(spotId);
    }

    private function nameTaken(name as String) as Boolean {
        for (var i = 0; i < Store.spots.size(); i++) {
            if (((Store.spots[i] as Array)[1] as String).equals(name)) { return true; }
        }
        return false;
    }
}

class DevicePickDelegate extends WatchUi.Menu2InputDelegate {
    private var _cb as Method(entity as String) as Void;

    function initialize(cb as Method(entity as String) as Void) {
        Menu2InputDelegate.initialize();
        _cb = cb;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var i = item.getId();
        if (i instanceof Number) {
            var ent = (Store.devices[i as Number] as Array)[0] as String;
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            _cb.invoke(ent);
        }
    }
}

class PresencePickDelegate extends WatchUi.Menu2InputDelegate {
    private var _spotId as Number;

    function initialize(spotId as Number) {
        Menu2InputDelegate.initialize();
        _spotId = spotId;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        var ent = "";
        if (id == :near) { ent = Beacon.NEAR; }
        else if (id == :far) { ent = Beacon.FAR; }
        else if (id instanceof Number && (id as Number) >= 0) { ent = (Store.presence[id as Number] as Array)[0] as String; }
        Store.setSpotPresence(_spotId, ent);
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        Menus.pushSpotMenu(_spotId);
    }
}

class PaintedDelegate extends WatchUi.Menu2InputDelegate {
    private var _spotId as Number;

    function initialize(spotId as Number) {
        Menu2InputDelegate.initialize();
        _spotId = spotId;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id instanceof String) {
            Store.deleteTarget(_spotId, id as String);
            Menus.toast("Removed");
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            Menus.pushPainted(_spotId);
        }
    }
}

class SettingsDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() { Menu2InputDelegate.initialize(); }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :trigger) {
            Menus.pushChoice("Trigger", ["START button only", "START + wrist flick"], [0, 1], Store.triggerMode, method(:setTrigger));
        } else if (id == :sens) {
            Menus.pushChoice("Flick sensitivity", ["Low", "Medium", "High"], [0, 1, 2], Store.sensitivity, method(:setSens));
        } else if (id == :range) {
            Menus.pushChoice("Range past edge", ["0°", "5°", "10°", "15°", "20°", "30°"], [0, 5, 10, 15, 20, 30], Store.rangeDeg, method(:setRange));
        } else if (id == :sep) {
            Menus.pushChoice("Separation", ["5°", "10°", "15°", "20°", "30°"], [5, 10, 15, 20, 30], Store.sepDeg, method(:setSep));
        } else if (id == :near) {
            Menus.pushChoice("Near: stronger than", ["-50 dBm", "-55 dBm", "-58 dBm", "-62 dBm", "-65 dBm", "-68 dBm"], [-50, -55, -58, -62, -65, -68], Store.bleNear, method(:setNear));
        } else if (id == :far) {
            Menus.pushChoice("Far: weaker than", ["-65 dBm", "-70 dBm", "-72 dBm", "-75 dBm", "-80 dBm", "-85 dBm"], [-65, -70, -72, -75, -80, -85], Store.bleFar, method(:setFar));
        } else if (id == :rssi) {
            var v = new BeaconView();
            WatchUi.pushView(v, new MsgDelegate(), WatchUi.SLIDE_LEFT);
        } else if (id == :url) {
            WatchUi.pushView(new MsgView("HA URL", Ha.baseUrl() + "\n\nChange it in the Connect IQ app settings, or rebuild.", null), new MsgDelegate(), WatchUi.SLIDE_LEFT);
        } else if (id == :reset) {
            var dlg = new WatchUi.Confirmation("Erase all Wand data?");
            WatchUi.pushView(dlg, new ResetConfirm(), WatchUi.SLIDE_UP);
        }
    }

    private function refresh() as Void {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        Menus.pushSettings();
    }
    function setTrigger(v as Number) as Void { Store.triggerMode = v; Store.save(); refresh(); }
    function setSens(v as Number) as Void { Store.sensitivity = v; Store.save(); refresh(); }
    function setRange(v as Number) as Void { Store.rangeDeg = v; Store.save(); refresh(); }
    function setSep(v as Number) as Void { Store.sepDeg = v; Store.save(); refresh(); }
    function setNear(v as Number) as Void { Store.bleNear = v; if (Store.bleFar >= v) { Store.bleFar = v - 5; } Store.save(); refresh(); }
    function setFar(v as Number) as Void { Store.bleFar = v; if (Store.bleNear <= v) { Store.bleNear = v + 5; } Store.save(); refresh(); }
}

class ResetConfirm extends WatchUi.ConfirmationDelegate {
    function initialize() { ConfirmationDelegate.initialize(); }

    function onResponse(response as WatchUi.Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            Store.spots = [];
            Store.targets = [];
            Store.devices = [];
            Store.presence = [];
            Store.curSpot = -1;
            Store.save();
            Menus.toast("Erased");
        }
        return true;
    }
}

class ChoiceDelegate extends WatchUi.Menu2InputDelegate {
    private var _cb as Method(v as Number) as Void;

    function initialize(cb as Method(v as Number) as Void) {
        Menu2InputDelegate.initialize();
        _cb = cb;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var v = item.getId() as Number;
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        _cb.invoke(v);
    }
}

// ---------------------------------------------------------------------------
// Simple text screen. With op = :sync or :ping it runs that HA call on show.

class MsgView extends WatchUi.View {
    private var _title as String;
    private var _text as String;
    private var _op as Symbol?;
    private var _ha as Ha?;
    private var _ok as Boolean? = null;

    function initialize(title as String, text as String, op as Symbol?) {
        View.initialize();
        _title = title;
        _text = text;
        _op = op;
    }

    function onShow() as Void {
        if (_op == null || _ha != null) { return; }
        _ha = new Ha(method(:onDone));
        if (_op == :sync) { (_ha as Ha).sync(); }
        else if (_op == :ping) { (_ha as Ha).ping(); }
    }

    function onDone(ok as Boolean, msg as String) as Void {
        _ok = ok;
        if (_op == :sync) {
            _text = ok ? ("Synced " + msg + "\n" + Store.presence.size().toString() + " presence sensors") : ("Failed:\n" + msg);
        } else {
            _text = ok ? "HA answered.\nCheck the HA notification." : ("Failed:\n" + msg);
        }
        AimView.buzz(ok ? [50, 120] : [30, 80, 0, 80, 30, 80]);
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 40, Graphics.FONT_SMALL, _title, Graphics.TEXT_JUSTIFY_CENTER);
        var color = (_ok == null) ? Graphics.COLOR_WHITE : ((_ok as Boolean) ? Graphics.COLOR_GREEN : Graphics.COLOR_RED);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var fitted = Menus.fit(_text, Graphics.FONT_SMALL, w - 60, h - 140);
        dc.drawText(w / 2, h / 2, Graphics.FONT_SMALL, fitted, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

class MsgDelegate extends WatchUi.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }

    function onSelect() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}

// ---------------------------------------------------------------------------
// Live beacon signal, for tuning the near / far thresholds: scans back to back and
// shows the average RSSI of each 3 s window and the zone it falls in.

class BeaconView extends WatchUi.View {
    private var _scanner as BeaconScanner? = null;
    private var _rssi as Number? = null;
    private var _scans as Number = 0;

    function initialize() {
        View.initialize();
    }

    function onShow() as Void {
        if (_scanner == null) { _scanner = new BeaconScanner(); }
        (_scanner as BeaconScanner).scan(method(:onScan));
    }

    function onHide() as Void {
        if (_scanner != null) { (_scanner as BeaconScanner).stop(); }
    }

    function onScan(rssi as Number?) as Void {
        _rssi = rssi;
        _scans++;
        WatchUi.requestUpdate();
        (_scanner as BeaconScanner).scan(method(:onScan));
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 40, Graphics.FONT_SMALL, "Beacon signal", Graphics.TEXT_JUSTIFY_CENTER);
        var big = (_scans == 0) ? "Listening..." : (_rssi == null ? "Not found" : (_rssi as Number).toString() + " dBm");
        var zone = "";
        var color = Graphics.COLOR_WHITE;
        if (_rssi != null) {
            zone = Beacon.zone(_rssi as Number);
            color = zone.equals("") ? Graphics.COLOR_ORANGE : Graphics.COLOR_GREEN;
            zone = zone.equals("") ? "between spots" : zone;
        } else if (_scans > 0) {
            color = Graphics.COLOR_RED;
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h / 2 - 14, Graphics.FONT_LARGE, big, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h / 2 + 26, Graphics.FONT_SMALL, zone, Graphics.TEXT_JUSTIFY_CENTER);
        var thr = "near > " + Store.bleNear.toString() + "  far < " + Store.bleFar.toString();
        dc.drawText(w / 2, h - 70, Graphics.FONT_XTINY, thr, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h - 50, Graphics.FONT_XTINY, "scan " + _scans.toString() + " · START = back", Graphics.TEXT_JUSTIFY_CENTER);
    }
}
