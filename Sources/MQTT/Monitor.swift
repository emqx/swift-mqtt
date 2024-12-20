//
//  Monitor.swift
//  swift-mqtt
//
//  Created by supertext on 2024/12/11.
//

import Network

extension MQTT{
    final class Monitor{
        private let impl:NWPathMonitor
        private var onChange:((NWPath.Status)->Void)?
        init(_ onChange:((NWPath.Status)->Void)?){
            self.impl = NWPathMonitor()
            self.onChange = onChange
            self.impl.pathUpdateHandler = {[weak self] newPath in
                guard let self else { return }
                self.status = newPath.status
            }
        }
        var status:NWPath.Status = .unsatisfied{
            didSet{
                if status == oldValue{ return }
                self.onChange?(status)
            }
        }
        func start(queue:DispatchQueue){
            if impl.queue == nil{
                impl.start(queue: queue)
            }
        }
        func stop(){
            impl.cancel()
        }
    }
}

