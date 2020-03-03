//
//  PingClient.swift
//  ShadowsocksX-R
//
//  Created by 称一称 on 16/9/5.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//


import Foundation

fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l < r
  case (nil, _?):
    return true
  default:
    return false
  }
}


public typealias SimplePingClientCallback = (String?)->()




class PingServers:NSObject{
    static let instance = PingServers()
    
    let SerMgr = ServerProfileManager.instance
    var fastest:String?
    var fastest_id : Int=0
    
    //    func ping(_ i:Int=0){
    //        if i == 0{
    //            fastest_id = 0
    //            fastest = nil
    //        }
    //
    //        if i >= SerMgr.profiles.count{
    //            DispatchQueue.main.async {
    //                // do the UI update HERE
    //                let notice = NSUserNotification()
    //                notice.title = "Ping测试完成！"
    //                notice.subtitle = "最快的是\(self.SerMgr.profiles[self.fastest_id].remark) \(self.SerMgr.profiles[self.fastest_id].serverHost) \(self.SerMgr.profiles[self.fastest_id].latency!)ms"
    //                NSUserNotificationCenter.default.deliver(notice)
    //            }
    //            return
    //        }
    //        let host = self.SerMgr.profiles[i].serverHost
    //        SimplePingClient.pingHostname(host) { latency in
    //            DispatchQueue.global().async {
    //            print("[Ping Result]-\(host) latency is \(latency ?? "fail")")
    //            self.SerMgr.profiles[i].latency = latency ?? "fail"
    //
    //            if latency != nil {
    //                if self.fastest == nil{
    //                    self.fastest = latency
    //                    self.fastest_id = i
    //                }else{
    //                    if Int(latency!) < Int(self.fastest!) {
    //                        self.fastest = latency
    //                        self.fastest_id = i
    //                    }
    //                }
    //                DispatchQueue.main.async {
    //                    // do the UI update HERE
    //                    (NSApplication.shared().delegate as! AppDelegate).updateServersMenu()
    //                    (NSApplication.shared().delegate as! AppDelegate).updateRunningModeMenu()
    //                }
    //            }
    //            }
    //            self.ping(i+1)
    //        }
    //    }
    
    func runCommand(cmd : String, args : String...) -> (output: [String], error: [String], exitCode: Int32) {
        
        var output : [String] = []
        var error : [String] = []
        
        let task = Process()
        task.launchPath = cmd
        task.arguments = args
        
        let outpipe = Pipe()
        task.standardOutput = outpipe
        let errpipe = Pipe()
        task.standardError = errpipe
        
        task.launch()
        
        let outdata = outpipe.fileHandleForReading.readDataToEndOfFile()
        if var string = String(data: outdata, encoding: .utf8) {
            string = string.trimmingCharacters(in: .newlines)
            output = string.components(separatedBy: "\n")
        }
        
        let errdata = errpipe.fileHandleForReading.readDataToEndOfFile()
        if var string = String(data: errdata, encoding: .utf8) {
            string = string.trimmingCharacters(in: .newlines)
            error = string.components(separatedBy: "\n")
        }
        
        task.waitUntilExit()
        let status = task.terminationStatus
        
        return (output, error, status)
    }
    
    func getlatencyFromString(result:String) -> Double?{
        var res = result
        if !result.contains("round-trip min/avg/max/stddev =") {
            return nil
        }
        res.removeSubrange(res.range(of: "round-trip min/avg/max/stddev = ")!)
        res = String(res.dropLast(3))
        res = res.components(separatedBy: "/")[1]
        let latency = Double(res)
        return latency
    }
    
    func pingSingleHost(host:String,completionHandler:@escaping (Double?) -> Void){
        DispatchQueue.global(qos: .userInteractive).async {
            if let outputString = self.runCommand(cmd: "/sbin/ping", args: "-c","5","-t","2",host).output.last{
                completionHandler(self.getlatencyFromString(result: outputString))
            }
        }
    }
    
    

    func ping(_ i:Int=0){
        
        neverSpeedTestBefore = false
        
        var result:[(Int,Double)] = []
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name("PingTestFinish"), object: nil, queue: OperationQueue.main) { (noti) in
            DispatchQueue.main.async {
                
                for k in 0..<self.SerMgr.profiles.count {
                    if let late = self.SerMgr.profiles[k].latency{
                        if let latency = Double(late){
                            result.append((k,latency))
                        }
                    }
                }

                // do the UI update HERE
                if let min = result.min(by: {$0.1 < $1.1}){
                    self.fastest = String(describing: min.1)
                    self.fastest_id  = min.0
                    let notice = NSUserNotification()
                    notice.title = "Ping测试完成！最快\(self.SerMgr.profiles[self.fastest_id].latency!)ms"
                    notice.subtitle = "最快的是\(self.SerMgr.profiles[self.fastest_id].serverHost) \(self.SerMgr.profiles[self.fastest_id].remark)"
                    
                    NSUserNotificationCenter.default.deliver(notice)
                    
                    UserDefaults.standard.setValue("\(self.SerMgr.profiles[self.fastest_id].latency!)", forKey: "FastestNode")
                    UserDefaults.standard.synchronize()
                    
                    DispatchQueue.main.async {
                        (NSApplication.shared.delegate as! AppDelegate).updateServersMenu()
                        (NSApplication.shared.delegate as! AppDelegate).updateRunningModeMenu()
                    }
                }
                
            }
        }
        
        var testResult = 0
        var haspostNotification = false
        for k in 0..<SerMgr.profiles.count {
            let host = self.SerMgr.profiles[k].serverHost
            pingSingleHost(host: host, completionHandler: { [weak self] in
                guard let w = self else {return}
                if let latency = $0{
                    testResult += 1
                    w.SerMgr.profiles[k].latency = String(latency)
                    if testResult == w.SerMgr.profiles.count-1 {
                        haspostNotification = true
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: NSNotification.Name("PingTestFinish"), object: nil)
                        }
                    }
                }
            })
        }
        
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now()+3) {
            if !haspostNotification {
                NotificationCenter.default.post(name: NSNotification.Name("PingTestFinish"), object: nil)
            }
        }
    }
}


typealias Task = (_ cancel : Bool) -> Void

@discardableResult func delay(_ time: TimeInterval, task: @escaping ()->()) ->  Task? {
    
    func dispatch_later(block: @escaping ()->()) {
        let t = DispatchTime.now() + time
        DispatchQueue.main.asyncAfter(deadline: t, execute: block)
    }
    
    
    
    var closure: (()->Void)? = task
    var result: Task?
    
    let delayedClosure: Task = {
        cancel in
        if let internalClosure = closure {
            if (cancel == false) {
                DispatchQueue.main.async(execute: internalClosure)
            }
        }
        closure = nil
        result = nil
    }
    
    result = delayedClosure
    
    dispatch_later {
        if let delayedClosure = result {
            delayedClosure(false)
        }
    }
    
    return result;
    
}


func cancel(_ task: Task?) {
    task?(true)
}

var neverSpeedTestBefore:Bool = true
