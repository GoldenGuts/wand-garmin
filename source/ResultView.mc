import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// Shown right after a trigger. Sends the toggle, reports the answer, and lets you
// correct a wrong guess (DOWN): the wrong device is toggled back, the right one is
// toggled, and the right one learns this heading.
class ResultView extends WatchUi.View {
    public var entity as String;
    public var heading as Float;
    public var spotId as Number;
    private var _line as String = "Sending...";
    private var _ok as Boolean? = null;
    private var _ha as Ha?;
    private var _timer as Timer.Timer?;
    private var _corrected as Boolean = false;
    private var _sent as Boolean = false;

    function initialize(entity as String, heading as Float, spotId as Number) {
        View.initialize();
        self.entity = entity;
        self.heading = heading;
        self.spotId = spotId;
    }

    function onShow() as Void {
        if (!_sent) {
            _sent = true;
            _ha = new Ha(method(:onDone));
            (_ha as Ha).control(entity, Store.spotName(spotId));
        }
    }

    function onDone(ok as Boolean, msg as String) as Void {
        _ok = ok;
        _line = ok ? "Toggled" : msg;
        if (!ok) { AimView.buzz([30, 80, 0, 80, 30, 80]); }
        WatchUi.requestUpdate();
        if (ok && !_corrected) {
            // Auto-close so the next point-and-flick is one motion away.
            _timer = new Timer.Timer();
            (_timer as Timer.Timer).start(method(:autoClose), 2500, false);
        }
    }

    function autoClose() as Void {
        if (!_corrected) { WatchUi.popView(WatchUi.SLIDE_RIGHT); }
    }

    function onHide() as Void {
        if (_timer != null) { (_timer as Timer.Timer).stop(); _timer = null; }
    }

    // Called by the picker when the user chose the device they meant.
    function correctTo(right as String) as Void {
        _corrected = true;
        if (_timer != null) { (_timer as Timer.Timer).stop(); _timer = null; }
        Store.learn(spotId, right, heading);
        var wrong = entity;
        entity = right;
        _line = "Fixing...";
        WatchUi.requestUpdate();
        // Undo the wrong one, then fire the right one.
        var undo = new Ha(method(:onUndone));
        undo.control(wrong, Store.spotName(spotId));
    }

    function onUndone(ok as Boolean, msg as String) as Void {
        _ha = new Ha(method(:onDone));
        (_ha as Ha).control(entity, Store.spotName(spotId));
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var color = (_ok == null) ? Graphics.COLOR_LT_GRAY : ((_ok as Boolean) ? Graphics.COLOR_GREEN : Graphics.COLOR_RED);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h / 2 - 70, Graphics.FONT_SMALL, _line, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var name = Menus.fit(Store.deviceName(entity), Graphics.FONT_MEDIUM, w - 60, 90);
        dc.drawText(cx, h / 2, Graphics.FONT_MEDIUM, name, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h / 2 + 50, Graphics.FONT_XTINY, heading.format("%.0f") + "°  ·  " + Store.spotName(spotId), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h - 58, Graphics.FONT_XTINY, _corrected ? "" : "Wrong? DOWN to fix", Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class ResultDelegate extends WatchUi.BehaviorDelegate {
    private var _view as ResultView;

    function initialize(view as ResultView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onNextPage() as Boolean {
        Menus.pushDevicePicker("Meant which?", method(:onPicked), _view.entity);
        return true;
    }

    function onPicked(entity as String) as Void {
        _view.correctTo(entity);
    }

    function onSelect() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
