import SwiftUI
import WidgetKit

@main
struct MacWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClockWidget()
        BatteryWidget()
        CalendarWidget()
        SystemWidget()
        GitHubWidget()
        MusicWidget()
        PhotoWidget1()
        PhotoWidget2()
        PhotoWidget3()
    }
}
