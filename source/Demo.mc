import Toybox.Application;
import Toybox.Lang;

// Sample data for simulator screenshots. Only in `./build.sh demo` builds; every other build
// strips this file via excludeAnnotations in monkey.jungle.
(:demo)
module Demo {
    function seed() as Void {
        Store.spots = [[1, "Bed", Beacon.NEAR], [2, "Desk", Beacon.FAR]];
        Store.curSpot = 1;
        Store.nextId = 3;
        Store.devices = [
            ["light.bed_lamp", "Bed lamp", "on"],
            ["fan.ceiling_fan", "Ceiling fan", "off"],
            ["media_player.tv", "TV", "off"],
            ["light.desk_lamp", "Desk lamp", "on"],
            ["switch.monitor", "Monitor", "on"]
        ];
        Store.presence = [["person.me", "Me", "home"]];
        Store.targets = [
            [1, "light.bed_lamp", 40.0, 12.0],
            [1, "fan.ceiling_fan", 95.0, 15.0],
            [1, "media_player.tv", 170.0, 14.0],
            [2, "light.desk_lamp", 300.0, 10.0],
            [2, "switch.monitor", 350.0, 10.0],
            [2, "fan.ceiling_fan", 60.0, 12.0]
        ];
        Store.lastSync = 1;
        Store.demoHeading = 42.0;          // the simulator has no compass
        Beacon.lastRssi = -57;
        Application.Properties.setValue("haUrl", "https://ha.example.com");
        Application.Properties.setValue("webhookId", "demo");
    }
}
