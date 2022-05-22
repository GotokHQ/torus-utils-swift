//
//  File.swift
//  
//
//  Created by Shubham on 1/8/21.
//

import Foundation
import PromiseKit
import FetchNodeDetails

public protocol AbstractTorusUtils {
    
    func setTorusNodePubKeys(nodePubKeys: Array<TorusNodePubModel>)
    
    func retrieveShares(endpoints : Array<String>, verifierIdentifier: String, verifierId:String, idToken: String, extraParams: Data) -> Promise<[String:String]>
    
    func getPublicAddress(endpoints : Array<String>, torusNodePubs : Array<TorusNodePubModel>, verifier : String, verifierId : String, isExtended: Bool) -> Promise<[String:String]>
}
