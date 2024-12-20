//
//  MQTTDemoApp.swift
//  MQTTDemo
//
//  Created by supertext on 2024/12/11.
//

import SwiftUI

@main
struct MQTTDemoApp: App {
    @UIApplicationDelegateAdaptor var delegate:AppDelegate
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
class AppDelegate:NSObject,UIApplicationDelegate{
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {

        return true
    }
}
