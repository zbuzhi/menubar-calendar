import Foundation
import CryptoKit

// Verification needs only a public key, never another Keychain authorization.
enum VerificationFailure: Error { case invalidInput, invalidSignature }
do {
    let args = CommandLine.arguments
    guard args.count == 3 || args.count == 4,
          let keyData = Data(base64Encoded:args[1]) else { throw VerificationFailure.invalidInput }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation:keyData)
    let data = try Data(contentsOf:URL(fileURLWithPath:args[2]))
    let signedData: Data
    let signature: Data
    if args.count == 4 {
        signedData = data
        guard let value = Data(base64Encoded:args[3]) else { throw VerificationFailure.invalidInput }
        signature = value
    } else {
        let marker = Data("<!-- sparkle-signatures:\n".utf8)
        guard let range = data.range(of:marker,options:.backwards),
              let suffix = String(data:data[range.lowerBound...],encoding:.utf8) else { throw VerificationFailure.invalidInput }
        let regex = try NSRegularExpression(pattern:"^<!-- sparkle-signatures:\\nedSignature: ([A-Za-z0-9+/=]+)\\nlength: ([0-9]+)\\n-->\\s*$")
        let ns = suffix as NSString
        guard let match = regex.firstMatch(in:suffix,range:NSRange(location:0,length:ns.length)),
              let value = Data(base64Encoded:ns.substring(with:match.range(at:1))),
              let length = Int(ns.substring(with:match.range(at:2))), length == range.lowerBound else { throw VerificationFailure.invalidInput }
        signedData = Data(data[..<range.lowerBound]); signature = value
    }
    guard key.isValidSignature(signature,for:signedData) else { throw VerificationFailure.invalidSignature }
    print("Ed25519 signature verified: \(URL(fileURLWithPath:args[2]).lastPathComponent)")
} catch {
    FileHandle.standardError.write(Data("Update signature verification failed: \(error)\n".utf8))
    exit(1)
}
