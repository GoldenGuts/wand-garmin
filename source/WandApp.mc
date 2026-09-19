import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class WandApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        Store.load();
    }

    function onStop(state as Dictionary?) as Void {
        Store.save();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new AimView();
        return [view, new AimDelegate(view)];
    }
}
