import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Main screen: shows the current spot, the compass ring with the painted arcs
// of that spot, and the device you are pointing at. START or a wrist flick fires.
class AimView extends WatchUi.View {
    public var aim as Aim;
    private var _ha as Ha?;
    private var _status as String = "";
    private var _busy as Boolean = false;
    private var _lastLocate as Number = -999999;
    private var _beacon as BeaconScanner? = null;
    private var _beaconTimer as Timer.Timer? = null;
    private const BEACON_EVERY_MS = 30000;

    function initialize() {
        View.initialize();
        aim = new Aim();
    }

    function onShow() as Void {
        aim.start(method(:onGesture));
        var now = System.getTimer();
        if (Store.hasPresenceSpots() && Ha.configured() && now - _lastLocate > 60000) {
            _lastLocate = now;
            _status = "Locating...";
            _ha = new Ha(method(:onPresenceSync));
            (_ha as Ha).sync();
        }
        if (Store.hasBeaconSpots()) {
            // A 3 s listen now, then again every 30 s while this screen is up, so a walk
            // from the bed to the desk changes the spot without a menu trip.
            _status = "Locating...";
            beaconScan();
            _beaconTimer = new Timer.Timer();
            (_beaconTimer as Timer.Timer).start(method(:beaconScan), BEACON_EVERY_MS, true);
        }
    }

    function onHide() as Void {
        aim.stop();
        if (_beaconTimer != null) { (_beaconTimer as Timer.Timer).stop(); _beaconTimer = null; }
        if (_beacon != null) { (_beacon as BeaconScanner).stop(); }
    }

    function beaconScan() as Void {
        if (_beacon == null) { _beacon = new BeaconScanner(); }
        (_beacon as BeaconScanner).scan(method(:onBeacon));
    }

    function onBeacon(rssi as Number?) as Void {
        _status = Store.autoSpotBeacon(rssi);
        WatchUi.requestUpdate();
    }

    function onPresenceSync(ok as Boolean, msg as String) as Void {
        if (ok) {
            _status = Store.autoSpot() ? "" : "No presence match";
        } else {
            _status = msg;
        }
        WatchUi.requestUpdate();
    }

    function onGesture(h as Float) as Void {
        fire(h);
    }

    // Trigger from the START button: use the current heading.
    function fireNow() as Void {
        var h = aim.heading;
        if (h == null) {
            refuse("No compass");
            return;
        }
        fire(h);
    }

    function fire(h as Float) as Void {
        if (_busy) { return; }
        if (!Ha.configured()) { refuse("Set URL"); return; }
        var m = Store.match(h, Store.curSpot);
        var ent = m.get(:entity);
        if (ent == null) {
            var r = m.get(:reason) as String;
            if (r.equals("Ambiguous")) {
                r = Store.deviceName(m.get(:first) as String) + " / " + Store.deviceName(m.get(:second) as String) + "?";
            }
            refuse(r);
            return;
        }
        _busy = true;
        buzz([50, 120]);
        var view = new ResultView(ent as String, h, Store.curSpot);
        WatchUi.pushView(view, new ResultDelegate(view), WatchUi.SLIDE_LEFT);
        _busy = false;
    }

    function refuse(reason as String) as Void {
        _status = reason;
        buzz([30, 80, 0, 80, 30, 80]);
        WatchUi.requestUpdate();
    }

    static function buzz(pattern as Array<Number>) as Void {
        if (!(Attention has :vibrate)) { return; }
        var profiles = [] as Array<Attention.VibeProfile>;
        for (var i = 0; i + 1 < pattern.size(); i += 2) {
            profiles = profiles.add(new Attention.VibeProfile(pattern[i], pattern[i + 1]));
        }
        Attention.vibrate(profiles);
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var hgt = dc.getHeight();
        var cx = w / 2;
        var cy = hgt / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var h = aim.heading;
        var spotOk = Store.spotIndex(Store.curSpot) >= 0;

        // Compass ring, heading-up. Painted arcs of the current spot.
        var r = cx - 6;
        dc.setPenWidth(4);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, r);
        var m = null;
        if (h != null && spotOk) {
            m = Store.match(h as Float, Store.curSpot);
            var list = Store.targetsForSpot(Store.curSpot);
            dc.setPenWidth(8);
            for (var i = 0; i < list.size(); i++) {
                var t = list[i] as Array;
                var rel = Store.signedDiff(t[2] as Float, h as Float);   // 0 = straight ahead
                var half = t[3] as Float;
                var chosen = (m.get(:entity) != null) && (t[1] as String).equals(m.get(:entity) as String);
                dc.setColor(chosen ? Graphics.COLOR_GREEN : Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
                // dc angles: 0 = 3 o'clock, counter-clockwise. Up is 90.
                var a1 = Store.norm(90.0 - (rel - half)).toNumber();
                var a2 = Store.norm(90.0 - (rel + half)).toNumber();
                dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, a1, a2);
            }
        }
        // Aim marker at the top.
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[cx, 14] as [Numeric, Numeric], [cx - 8, 30] as [Numeric, Numeric], [cx + 8, 30] as [Numeric, Numeric]]);

        // Spot name.
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        var spotLabel = spotOk ? Store.spotName(Store.curSpot) : "No spot (menu)";
        dc.drawText(cx, 48, Graphics.FONT_SMALL, spotLabel, Graphics.TEXT_JUSTIFY_CENTER);

        // Heading.
        var hs = (h == null) ? "---" : (((h as Float) + 0.5).toNumber() % 360).toString() + "°";
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, hgt - 78, Graphics.FONT_TINY, hs, Graphics.TEXT_JUSTIFY_CENTER);

        // Big label: what we would fire at.
        var big = "Aim";
        var color = Graphics.COLOR_LT_GRAY;
        if (m != null) {
            var ent = m.get(:entity);
            if (ent != null) {
                big = Store.deviceName(ent as String);
                color = Graphics.COLOR_GREEN;
            } else {
                var reason = m.get(:reason) as String;
                if (reason.equals("Ambiguous")) {
                    big = Store.deviceName(m.get(:first) as String) + " / " + Store.deviceName(m.get(:second) as String);
                    color = Graphics.COLOR_ORANGE;
                } else {
                    big = reason;
                }
            }
        } else if (h == null) {
            big = "No compass";
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var fitted = Menus.fit(big, Graphics.FONT_MEDIUM, w - 70, 80);
        dc.drawText(cx, cy, Graphics.FONT_MEDIUM, fitted, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Status / hint line.
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        var hint = _status.equals("") ? (Store.triggerMode == 1 ? "START or flick" : "START") : _status;
        if (_status.equals("") && aim.source.equals("mag")) { hint = hint + " · raw compass"; }
        if (Store.hasBeaconSpots() && Beacon.lastRssi != null) { hint = hint + " · " + (Beacon.lastRssi as Number).toString() + " dBm"; }
        dc.drawText(cx, hgt - 52, Graphics.FONT_XTINY, hint, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function setStatus(s as String) as Void {
        _status = s;
        WatchUi.requestUpdate();
    }
}

class AimDelegate extends WatchUi.BehaviorDelegate {
    private var _view as AimView;

    function initialize(view as AimView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onSelect() as Boolean {
        _view.fireNow();
        return true;
    }

    function onMenu() as Boolean {
        Menus.pushMain();
        return true;
    }

    function onNextPage() as Boolean {
        Store.nextSpot(1);
        _view.setStatus("");
        return true;
    }

    function onPreviousPage() as Boolean {
        Store.nextSpot(-1);
        _view.setStatus("");
        return true;
    }

    function onTap(evt as ClickEvent) as Boolean {
        // A tap on the touchscreen opens the menu; the trigger stays on START/flick
        // so a brush of the screen cannot fire a device.
        Menus.pushMain();
        return true;
    }
}
