import Toybox.Lang;
import Toybox.Math;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Reads the compass at 10 Hz and watches the accelerometer / gyroscope for a
// wrist flick. The Forerunner 965 has no microphone, so the finger snap of the
// original app (Snap Control, Wear OS) becomes a flick (or the START button).
class Aim {
    public var heading as Float? = null;        // degrees, 0 = north, where 12 o'clock points
    public var gyroOk as Boolean = false;
    public var source as String = "";           // "fused" (Sensor.Info) or "mag" (raw fallback)
    private var _lastFused as Number = 0;       // ms of the last non-null Sensor.Info heading
    private var _magHeading as Float? = null;
    public var lastJerk as Float = 0.0;         // for the sensitivity screen

    private const HIST = 30;                    // 3 s of headings at 10 Hz
    private var _hist as Array<Float?>;
    private var _histIdx as Number = 0;
    private var _timer as Timer.Timer?;
    private var _onGesture as Method(h as Float) as Void?;
    private var _lastTrigger as Number = 0;
    private var _prevMag as Float = 1000.0;
    private var _running as Boolean = false;
    private var _samples as Array<Float>? = null; // painting buffer

    function initialize() {
        _hist = new Array<Float?>[HIST];
    }

    function start(onGesture as Method(h as Float) as Void?) as Void {
        _onGesture = onGesture;
        if (_running) { return; }
        _running = true;
        _timer = new Timer.Timer();
        (_timer as Timer.Timer).start(method(:poll), 100, true);
        // Always listen: the accelerometer + magnetometer give a fallback heading when
        // Sensor.Info.heading is null, and the flick detector needs the motion data.
        registerMotion();
    }

    function stop() as Void {
        if (!_running) { return; }
        _running = false;
        if (_timer != null) { (_timer as Timer.Timer).stop(); _timer = null; }
        try { Sensor.unregisterSensorDataListener(); } catch (e) { }
    }

    private function registerMotion() as Void {
        var withGyro = {
            :period => 1,
            :accelerometer => {:enabled => true, :sampleRate => 25},
            :magnetometer => {:enabled => true, :sampleRate => 25},
            :gyroscope => {:enabled => true, :sampleRate => 25}
        };
        try {
            Sensor.registerSensorDataListener(method(:onMotion), withGyro);
            gyroOk = true;
        } catch (e) {
            gyroOk = false;
            try {
                Sensor.registerSensorDataListener(method(:onMotion), {
                    :period => 1,
                    :accelerometer => {:enabled => true, :sampleRate => 25},
                    :magnetometer => {:enabled => true, :sampleRate => 25}
                });
            } catch (e2) {
                try {
                    Sensor.registerSensorDataListener(method(:onMotion),
                        {:period => 1, :accelerometer => {:enabled => true, :sampleRate => 25}});
                } catch (e3) { }
            }
        }
    }

    private const SMOOTH = 4;                   // 0.4 s circular average for aim + display

    function poll() as Void {
        var info = Sensor.getInfo();
        var h = info.heading;
        var now = System.getTimer();
        var raw = null;
        if (Store.demoHeading != null) {
            raw = Store.demoHeading;
            source = "fused";
        } else if (h != null) {
            raw = Store.norm(Math.toDegrees(h).toFloat());
            source = "fused";
            _lastFused = now;
        } else if (now - _lastFused > 3000 && _magHeading != null) {
            raw = _magHeading;
            source = "mag";
        } else {
            raw = _hist[(_histIdx - 1 + HIST) % HIST];   // hold the last value briefly
        }
        _hist[_histIdx] = raw;
        _histIdx = (_histIdx + 1) % HIST;
        if (_samples != null && raw != null) {
            _samples = (_samples as Array<Float>).add(raw as Float);
        }
        var recent = new Array<Float?>[SMOOTH];
        for (var i = 0; i < SMOOTH; i++) {
            recent[i] = _hist[(_histIdx - 1 - i + HIST) % HIST];
        }
        heading = Store.meanOf(recent);
        WatchUi.requestUpdate();
    }

    // ---- painting ----------------------------------------------------------

    function beginPaint() as Void { _samples = [] as Array<Float>; }

    function paintCount() as Number { return _samples == null ? 0 : (_samples as Array<Float>).size(); }

    // Returns [center, half] or null when too few samples.
    function endPaint() as Array<Float>? {
        var s = _samples;
        _samples = null;
        if (s == null || s.size() < 5) { return null; }
        return Store.arcOf(s);
    }

    function paintPreview() as Array<Float>? {
        if (_samples == null || (_samples as Array<Float>).size() < 3) { return null; }
        return Store.arcOf(_samples as Array<Float>);
    }

    // ---- gesture -----------------------------------------------------------

    private function accelThreshold() as Float {
        // jerk between two 40 ms samples, in milli-g
        if (Store.sensitivity == 0) { return 1600.0; }
        if (Store.sensitivity == 2) { return 700.0; }
        return 1100.0;
    }

    private function gyroThreshold() as Float {
        // deg/s about any axis
        if (Store.sensitivity == 0) { return 500.0; }
        if (Store.sensitivity == 2) { return 220.0; }
        return 340.0;
    }

    // Tilt-compensated heading from raw accelerometer + magnetometer. Uncalibrated,
    // so it is only stable, not true north; the app only compares headings with
    // headings painted the same way, so that is enough.
    private function magHeading(acc as Sensor.AccelerometerData, mag as Sensor.MagnetometerData) as Float? {
        var n = acc.x.size();
        if (n == 0 || mag.x.size() < n) { return null; }
        var ax = 0.0; var ay = 0.0; var az = 0.0;
        var mx = 0.0; var my = 0.0; var mz = 0.0;
        for (var i = 0; i < n; i++) {
            ax += acc.x[i]; ay += acc.y[i]; az += acc.z[i];
            mx += mag.x[i]; my += mag.y[i]; mz += mag.z[i];
        }
        var norm = Math.sqrt(ax * ax + ay * ay + az * az);
        if (norm < 1.0) { return null; }
        ax /= norm; ay /= norm; az /= norm;
        var roll = Math.atan2(ay, az);
        var pitch = Math.atan2(-ax, Math.sqrt(ay * ay + az * az));
        var sr = Math.sin(roll); var cr = Math.cos(roll);
        var sp = Math.sin(pitch); var cp = Math.cos(pitch);
        var xh = mx * cp + mz * sp;
        var yh = mx * sr * sp + my * cr - mz * sr * cp;
        if (xh.abs() < 0.001 && yh.abs() < 0.001) { return null; }
        return Store.norm(Math.toDegrees(Math.atan2(yh, xh)).toFloat());
    }

    function onMotion(data as Sensor.SensorData) as Void {
        var acc = data.accelerometerData;
        var gyr = data.gyroscopeData;
        var mag = data.magnetometerData;
        if (acc != null && mag != null) {
            _magHeading = magHeading(acc, mag);
        }
        if (_onGesture == null || Store.triggerMode != 1) { return; }
        var n = 0;
        var hit = -1;
        if (acc != null) {
            var xs = acc.x;
            var ys = acc.y;
            var zs = acc.z;
            n = xs.size();
            var thr = accelThreshold();
            for (var i = 0; i < n; i++) {
                var x = xs[i].toFloat();
                var y = ys[i].toFloat();
                var z = zs[i].toFloat();
                var magn = Math.sqrt(x * x + y * y + z * z).toFloat();
                var jerk = (magn - _prevMag).abs();
                _prevMag = magn;
                if (jerk > lastJerk) { lastJerk = jerk; }
                if (jerk > thr && hit < 0) { hit = i; }
            }
        }
        if (hit < 0 && gyr != null) {
            var gx = gyr.x;
            var gy = gyr.y;
            var gz = gyr.z;
            n = gx.size();
            var gthr = gyroThreshold();
            for (var i = 0; i < n; i++) {
                if (gx[i].abs() > gthr || gy[i].abs() > gthr || gz[i].abs() > gthr) { hit = i; break; }
            }
        }
        if (hit >= 0) { gestureAt(hit, n); }
        lastJerk = lastJerk * 0.7;
    }

    private function gestureAt(i as Number, n as Number) as Void {
        var now = System.getTimer();
        if (now - _lastTrigger < 1500) { return; }
        _lastTrigger = now;
        // The batch covers the last second; sample i happened (n - i)/n s ago.
        // Use the heading from ~300 ms before the flick, before the wrist moved.
        var agoMs = ((n - i) * 1000) / (n > 0 ? n : 25) + 300;
        var back = agoMs / 100;
        if (back >= HIST) { back = HIST - 1; }
        var idx = (_histIdx - 1 - back + HIST * 2) % HIST;
        var h = _hist[idx];
        if (h == null) { h = heading; }
        if (h == null) { return; }
        if (_onGesture != null) { (_onGesture as Method(h as Float) as Void).invoke(h as Float); }
    }
}
