import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Timer;

// Talks to Home Assistant through the phone (Garmin Connect).
// Every call ends in cb.invoke(ok as Boolean, message as String).
class Ha {
    private var _cb as Method(ok as Boolean, msg as String) as Void;
    private var _timer as Timer.Timer?;

    function initialize(cb as Method(ok as Boolean, msg as String) as Void) {
        _cb = cb;
    }

    static function baseUrl() as String {
        var u = Properties.getValue("haUrl");
        var s = (u instanceof String) ? (u as String) : "";
        while (s.length() > 0) {
            var last = s.substring(s.length() - 1, s.length());
            if (last == null || !last.equals("/")) { break; }
            var head = s.substring(0, s.length() - 1);
            s = (head == null) ? "" : head;
        }
        return s;
    }

    static function webhookId() as String {
        var id = Properties.getValue("webhookId");
        return (id instanceof String) ? (id as String) : "";
    }

    static function webhookUrl() as String {
        return baseUrl() + "/api/webhook/" + webhookId();
    }

    static function configured() as Boolean {
        return baseUrl().length() > 8 && webhookUrl().length() > baseUrl().length() + 14;
    }

    // action: "toggle" | "on" | "off" | "ping" | "sync"
    function send(action as String, entity as String?, spot as String?) as Void {
        if (!configured()) {
            _cb.invoke(false, "Set URL in settings");
            return;
        }
        var params = {"action" => action} as Dictionary<Object, Object>;
        if (entity != null) { params.put("entity_id", entity); }
        if (spot != null) { params.put("spot", spot); }
        // No :responseType here: HA's webhook trigger always answers with an empty body and
        // no Content-Type header, and onPost() only ever looks at the status code, never the
        // body. Asking the SDK to parse that empty, untyped body as text made some firmware
        // report a parse failure (-400 / -1002, "Bad response") instead of the real 200.
        var opts = {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => {"Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON}
        };
        Communications.makeWebRequest(webhookUrl(), params, opts, method(:onPost));
    }

    function control(entity as String, spotName as String) as Void {
        send("toggle", entity, spotName);
    }

    function ping() as Void {
        send("ping", null, null);
    }

    // Two steps: ask HA to publish the state file, wait for it, download it.
    // The file name carries the webhook id so the unauthenticated /local/ path is not guessable.
    private var _syncing as Boolean = false;

    function sync() as Void {
        _syncing = true;
        send("sync", null, null);
    }

    function onPost(code as Number, data as Dictionary or String or Null) as Void {
        if (code != 200) {
            _syncing = false;
            _cb.invoke(false, describe(code));
            return;
        }
        if (_syncing) {
            _timer = new Timer.Timer();
            (_timer as Timer.Timer).start(method(:fetchState), 2500, false);
            return;
        }
        _cb.invoke(true, "OK");
    }

    function fetchState() as Void {
        var url = baseUrl() + "/local/wand/state-" + webhookId() + ".json?t=" + Time.now().value().toString();
        var opts = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        Communications.makeWebRequest(url, null, opts, method(:onState));
    }

    function onState(code as Number, data as Dictionary or String or Null) as Void {
        _syncing = false;
        if (code != 200 || !(data instanceof Dictionary)) {
            _cb.invoke(false, code == 404 ? "State file missing" : describe(code));
            return;
        }
        var d = data as Dictionary;
        var dev = d.get("devices");
        var pres = d.get("presence");
        var ts = d.get("ts");
        if (!(dev instanceof Array)) {
            _cb.invoke(false, "Bad state file");
            return;
        }
        Store.setSynced(dev, (pres instanceof Array) ? pres : [], (ts instanceof Number) ? ts : 0);
        _cb.invoke(true, dev.size().toString() + " devices");
    }

    static function describe(code as Number) as String {
        if (code == -104) { return "Phone not connected"; }
        if (code == -300) { return "HA timeout"; }
        if (code == -1001) { return "HTTPS required"; }
        if (code == -400 || code == -1002) { return "Bad response"; }
        if (code == -402 || code == -403) { return "Response too big"; }
        if (code == 404) { return "Webhook not found"; }
        if (code == 401 || code == 403) { return "Not local / denied"; }
        if (code == 405) { return "Wrong method"; }
        if (code < 0) { return "Comm error " + code.toString(); }
        return "HTTP " + code.toString();
    }
}
