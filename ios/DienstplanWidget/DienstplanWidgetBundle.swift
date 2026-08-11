import WidgetKit
import SwiftUI

@main
struct DienstplanWidgetBundle: WidgetBundle {
    var body: some Widget {
        DienstplanWidget()
        CalendarNextDaysWidget()   // NEU — Medium: heute + nächste 2 Tage mit Terminen
        CalendarChronoWidget()     // NEU — Large: chronologische Liste
    }
}