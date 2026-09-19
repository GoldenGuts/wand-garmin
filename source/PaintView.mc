import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// Teach a direction: stand on the spot, aim at the device, press START, and
// lazily zigzag across the device for 5 seconds, a little past each edge.
// The watch stores the centre and the width of that sweep.
class PaintView extends WatchUi.View {
    private var _spotId as Number;
    private var _entity as String;
    private var _aim as Aim;
    private var _timer as Timer.Timer?;
    private var _painting as Boolean = false;
    private var _left as Number = 0;
    private var _saved as Array<Float>? = null;
    private var _msg as String = "";

    function initialize(spotId as Number, entity as String) {
        View.initialize();
        _spotId = spotId;
        _entity = entity;
        _aim = new Aim();
        var i = Store.findTarget(spotId, entity);
        if (i >= 0) {
            var t = Store.targets[i] as Array;
            _saved = [t[2] as Float, t[3] as Float];
        }
    }

    function onShow() as Void { _aim.start(null); }

    function onHide() as Void {
        _aim.stop();
        if (_timer != null) { (_timer as Timer.Timer).stop(); _timer = null; }
    }

    function isPainting() as Boolean { return _painting; }

    function begin() as Void {
        if (_painting) { return; }
        if (_aim.heading == null) {
            _msg = "No compass yet";
            WatchUi.requestUpdate();
            return;
        }
        _painting = true;
        _left = 50;   // 5 s at 10 Hz
        _msg = "";
        _aim.beginPaint();
        AimView.buzz([40, 100]);
        _timer = new Timer.Timer();
        (_timer as Timer.Timer).start(method(:tick), 100, true);
    }

    function tick() as Void {
        _left--;
        if (_left <= 0) { finish(); }
        WatchUi.requestUpdate();
    }

    function finish() as Void {
        if (_timer != null) { (_timer as Timer.Timer).stop(); _timer = null; }
        _painting = false;
        var arc = _aim.endPaint();
        if (arc == null) {
            _msg = "Too few samples";
            AimView.buzz([30, 80, 0, 80, 30, 80]);
        } else {
            Store.setTarget(_spotId, _entity, arc[0], arc[1]);
            _saved = arc;
            _msg = "Saved";
            AimView.buzz([50, 120, 0, 80, 50, 120]);
        }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var r = cx - 6;
        dc.setPenWidth(4);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, r);
        var hd = _aim.heading;
        var arc = _painting ? _aim.paintPreview() : _saved;
        if (hd != null && arc != null) {
            var rel = Store.signedDiff(arc[0], hd as Float);
            dc.setPenWidth(8);
            dc.setColor(_painting ? Graphics.COLOR_BLUE : Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE,
                Store.norm(90.0 - (rel - arc[1])).toNumber(), Store.norm(90.0 - (rel + arc[1])).toNumber());
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[cx, 14] as [Numeric, Numeric], [cx - 8, 30] as [Numeric, Numeric], [cx + 8, 30] as [Numeric, Numeric]]);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 48, Graphics.FONT_XTINY, "Paint @ " + Store.spotName(_spotId), Graphics.TEXT_JUSTIFY_CENTER);
        var name = Menus.fit(Store.deviceName(_entity), Graphics.FONT_SMALL, w - 70, 60);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 34, Graphics.FONT_SMALL, name, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var mid;
        var color = Graphics.COLOR_LT_GRAY;
        if (_painting) {
            mid = "Sweep... " + ((_left + 9) / 10).toString();
            color = Graphics.COLOR_BLUE;
        } else if (_saved != null) {
            var s = _saved as Array<Float>;
            mid = s[0].format("%.0f") + "° ±" + s[1].format("%.0f") + "°";
            color = Graphics.COLOR_GREEN;
        } else {
            mid = "Not painted";
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 12, Graphics.FONT_MEDIUM, mid, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var hs = (hd == null) ? "---" : (((hd as Float) + 0.5).toNumber() % 360).toString() + "°";
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 44, Graphics.FONT_TINY, hs, Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        var hint = _painting ? "zigzag over it" : (_msg.equals("") ? "START = paint 5 s" : _msg);
        dc.drawText(cx, h - 56, Graphics.FONT_XTINY, hint, Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class PaintDelegate extends WatchUi.BehaviorDelegate {
    private var _view as PaintView;

    function initialize(view as PaintView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onSelect() as Boolean {
        _view.begin();
        return true;
    }

    function onBack() as Boolean {
        if (_view.isPainting()) { return true; }   // ignore BACK mid-sweep
        return false;
    }
}
