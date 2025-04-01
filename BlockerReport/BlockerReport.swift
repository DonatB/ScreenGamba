//
//  BlockerReport.swift
//  BlockerReport
//
//  Created by Donat on 30.3.25.
//

import DeviceActivity
import SwiftUI

@main
struct BlockerReport: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        // Create a report for each DeviceActivityReport.Context that your app supports.
        TotalActivityReport { totalActivity in
            TotalActivityView(totalActivity: totalActivity)
        }
    }
}
