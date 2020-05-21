/**
 torus utils class
 Author: Shubham Rathi
 */

import Foundation
import FetchNodeDetails
import web3swift
import PromiseKit
import secp256k1
import PMKFoundation
import CryptoSwift
import BigInt


@available(iOS 9.0, *)
public class TorusUtils{
    static let context = secp256k1_context_create(UInt32(SECP256K1_CONTEXT_SIGN|SECP256K1_CONTEXT_VERIFY))
    var privateKey = ""
    let nodePubKeys : Array<TorusNodePub> = [TorusNodePub(_X: "4086d123bd8b370db29e84604cd54fa9f1aeb544dba1cc9ff7c856f41b5bf269", _Y: "fde2ac475d8d2796aab2dea7426bc57571c26acad4f141463c036c9df3a8b8e8"),TorusNodePub(_X: "1d6ae1e674fdc1849e8d6dacf193daa97c5d484251aa9f82ff740f8277ee8b7d", _Y: "43095ae6101b2e04fa187e3a3eb7fbe1de706062157f9561b1ff07fe924a9528"),TorusNodePub(_X: "fd2af691fe4289ffbcb30885737a34d8f3f1113cbf71d48968da84cab7d0c262", _Y: "c37097edc6d6323142e0f310f0c2fb33766dbe10d07693d73d5d490c1891b8dc"),TorusNodePub(_X: "e078195f5fd6f58977531135317a0f8d3af6d3b893be9762f433686f782bec58", _Y: "843f87df076c26bf5d4d66120770a0aecf0f5667d38aa1ec518383d50fa0fb88"),TorusNodePub(_X: "a127de58df2e7a612fd256c42b57bb311ce41fd5d0ab58e6426fbf82c72e742f", _Y: "388842e57a4df814daef7dceb2065543dd5727f0ee7b40d527f36f905013fa96")]
    
    public init(){
        
    }
    
    func getMetadata() -> Promise<BigInt>{
        return Promise<BigInt>.value(BigInt(0))
    }
    
    public func getPublicAddress(endpoints : Array<String>, torusNodePubs : Array<TorusNodePub>, verifier : String, verifierId : String, isExtended: Bool) -> Promise<[String:String]>{
        
        let (tempPromise, seal) = Promise<[String:String]>.pending()
        let keyLookup = self.keyLookup(endpoints: endpoints, verifier: verifier, verifierId: verifierId)
        
        keyLookup.then{ lookupData -> Promise<[String: String]> in
            let error = lookupData["err"]
            
            if(error != nil){
                // Assign key to the user and return (wraped in a promise)
                return self.keyAssign(endpoints: endpoints, torusNodePubs: torusNodePubs, verifier: verifier, verifierId: verifierId).then{ data -> Promise<[String:String]> in
                    // Do keylookup again
                    return self.keyLookup(endpoints: endpoints, verifier: verifier, verifierId: verifierId)
                }.then{ data -> Promise<[String: String]> in
                    
                    return Promise<[String: String]>.value(data)
                }
            }else{
                return Promise<[String: String]>.value(lookupData)
            }
        }.done{ data in
            
            if(!isExtended){
                seal.fulfill(["address": data["address"]!])
            }else{
                seal.fulfill(data)
            }
        }.catch{err in
            print("err", err)
            seal.reject(TorusError.decodingError)
        }
        
        return tempPromise
        
    }
    
    public func retrieveShares(endpoints : Array<String>, verifierIdentifier: String, verifierId:String, idToken: String, extraParams: Data) -> Promise<String>{
        
        // Generate privatekey
        let privateKey = SECP256K1.generatePrivateKey()
        let publicKey = SECP256K1.privateToPublic(privateKey: privateKey!, compressed: false)?.suffix(64) // take last 64
        
        // Split key in 2 parts, X and Y
        let publicKeyHex = publicKey?.toHexString()
        let pubKeyX = publicKey?.prefix(publicKey!.count/2).toHexString().addLeading0sForLength64()
        let pubKeyY = publicKey?.suffix(publicKey!.count/2).toHexString().addLeading0sForLength64()
        
        // Hash the token from OAuth login
        // let tempIDToken = verifierParams.map{$0["idtoken"]!}.joined(separator: "\u{001d}")

        let hashedOnce = idToken.sha3(.keccak256)
        // let tokenCommitment = hashedOnce.sha3(.keccak256)
        
        let timestamp = String(Int(Date().timeIntervalSince1970))
        
        var nodeReturnedPubKeyX:String = ""
        var nodeReturnedPubKeyY:String = ""
        
        print(privateKey?.toHexString() as Any, publicKeyHex as Any, pubKeyX as Any, pubKeyY as Any, hashedOnce)
        
        return Promise<String>{ seal in
            
            getPublicAddress(endpoints: endpoints, torusNodePubs: nodePubKeys, verifier: verifierIdentifier, verifierId: verifierId, isExtended: true).then{ data in
                return self.commitmentRequest(endpoints: endpoints, verifier: verifierIdentifier, pubKeyX: pubKeyX!, pubKeyY: pubKeyY!, timestamp: timestamp, tokenCommitment: hashedOnce)
            }.then{ data -> Promise<[Int:[String:String]]> in
                   // print("data after commitment requrest", data)
                    return self.retrieveIndividualNodeShare(endpoints: endpoints, extraParams: extraParams, verifier: verifierIdentifier, tokenCommitment: idToken, nodeSignatures: data, verifierId: verifierId)
            }.then{ data -> Promise<[Int:String]> in
                print("data after retrieve shares", data)
                if let temp  = data.first{
                    nodeReturnedPubKeyX = temp.value["pubKeyX"]!.addLeading0sForLength64()
                    nodeReturnedPubKeyY = temp.value["pubKeyY"]!.addLeading0sForLength64()
                }
                return self.decryptIndividualShares(shares: data, privateKey: privateKey!.toHexString())
            }.then{ data -> Promise<String> in
                print("individual shares array", data)
                return self.lagrangeInterpolation(shares: data)
            }.done{ data in
                let publicKey = SECP256K1.privateToPublic(privateKey: Data.init(hex: data) , compressed: false)?.suffix(64) // take last 64
                
                // Split key in 2 parts, X and Y
                // let publicKeyHex = publicKey?.toHexString()
                let pubKeyX = publicKey?.prefix(publicKey!.count/2).toHexString()
                let pubKeyY = publicKey?.suffix(publicKey!.count/2).toHexString()
                
                print("private key rebuild", data, pubKeyX, pubKeyY)

                // Verify
                if( pubKeyX == nodeReturnedPubKeyX && pubKeyY == nodeReturnedPubKeyY) {
                    self.privateKey = data
                    seal.fulfill(data)

                }else{
                    throw "could not derive private key"
                }
            }.catch{ err in
                // print(err)
                seal.reject(err)
            }
            
        }
        
    }
    
}
