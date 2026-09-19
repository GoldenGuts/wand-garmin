import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.Timer;

// BLE beacon ranging. The watch sends no BLE adverts while the phone is connected, so a
// room scanner (ESPHome) cannot see it. Instead the scanner advertises a fixed service UUID
// and the watch listens for a few seconds and averages the RSSI. Strong = the spot next to
// the beacon, weak = the far spot. The watch never connects to the beacon.
module Beacon {
    const SERVICE = "7a4d0001-9b2e-4c8f-8f1a-5e6b7c8d9e0f";
    const CHARACTERISTIC = "7a4d0002-9b2e-4c8f-8f1a-5e6b7c8d9e0f";
    const NEAR = "ble:near";                    // spot presence values, see Store.spots
    const FAR = "ble:far";
    const SCAN_MS = 3000;

    var lastRssi as Number? = null;             // last completed scan, null = beacon not seen
    var registered as Boolean = false;

    function isBeacon(entity as String) as Boolean {
        return entity.equals(NEAR) || entity.equals(FAR);
    }

    function label(entity as String) as String {
        if (entity.equals(NEAR)) { return "Beacon · near"; }
        if (entity.equals(FAR)) { return "Beacon · far"; }
        return entity;
    }

    // "near", "far", or "" when the RSSI sits in the gap between the two thresholds.
    function zone(rssi as Number) as String {
        if (rssi > Store.bleNear) { return "near"; }
        if (rssi < Store.bleFar) { return "far"; }
        return "";
    }
}

// One scan at a time: start(), collect adverts that carry the beacon service UUID,
// stop after SCAN_MS and hand the average RSSI (or null) to the callback.
class BeaconScanner extends BluetoothLowEnergy.BleDelegate {
    private var _svc as BluetoothLowEnergy.Uuid;
    private var _timer as Timer.Timer? = null;
    private var _cb as Method(rssi as Number?) as Void? = null;
    private var _sum as Number = 0;
    private var _n as Number = 0;

    function initialize() {
        BleDelegate.initialize();
        _svc = BluetoothLowEnergy.stringToUuid(Beacon.SERVICE);
        BluetoothLowEnergy.setDelegate(self);
        // Real watches only report scan results for services of a registered profile.
        if (!Beacon.registered) {
            try {
                BluetoothLowEnergy.registerProfile({
                    :uuid => _svc,
                    :characteristics => [{:uuid => BluetoothLowEnergy.stringToUuid(Beacon.CHARACTERISTIC)}]
                });
                Beacon.registered = true;
            } catch (e) { }
        }
    }

    function scanning() as Boolean {
        return _timer != null;
    }

    function scan(cb as Method(rssi as Number?) as Void) as Void {
        if (_timer != null) { return; }
        _cb = cb;
        _sum = 0;
        _n = 0;
        BluetoothLowEnergy.setDelegate(self);
        try {
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
        } catch (e) {
            Beacon.lastRssi = null;
            cb.invoke(null);
            return;
        }
        _timer = new Timer.Timer();
        (_timer as Timer.Timer).start(method(:finish), Beacon.SCAN_MS, false);
    }

    function finish() as Void {
        _timer = null;
        try { BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF); } catch (e) { }
        var r = (_n > 0) ? (_sum / _n) : null;
        Beacon.lastRssi = r;
        if (_cb != null) { (_cb as Method(rssi as Number?) as Void).invoke(r); }
    }

    function stop() as Void {
        if (_timer != null) { (_timer as Timer.Timer).stop(); _timer = null; }
        try { BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF); } catch (e) { }
    }

    function onScanResults(scanResults as BluetoothLowEnergy.Iterator) as Void {
        var r = scanResults.next();
        while (r != null) {
            var sr = r as BluetoothLowEnergy.ScanResult;
            if (isBeacon(sr)) {
                _sum += sr.getRssi();
                _n++;
            }
            r = scanResults.next();
        }
    }

    private function isBeacon(sr as BluetoothLowEnergy.ScanResult) as Boolean {
        var it = sr.getServiceUuids();
        var u = it.next();
        while (u != null) {
            if ((u as BluetoothLowEnergy.Uuid).equals(_svc)) { return true; }
            u = it.next();
        }
        return false;
    }
}
