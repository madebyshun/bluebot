import Foundation

@main
enum EVMTests {
    static func main() {
        // BigUInt round trips
        let big = BigUInt(decimal: "123456789012345678901234567890")!
        precondition(big.decimalString == "123456789012345678901234567890")
        precondition(BigUInt(hex: big.hexString)! == big)
        precondition(BigUInt(hex: "0xff")!.decimalString == "255")
        precondition(BigUInt.zero.hexString == "0x0")
        precondition(BigUInt(decimal: "1000")!.multiplied(by: 25).divided(by: 100).decimalString == "250")
        precondition(BigUInt(decimal: "1000")!.minus(BigUInt(decimal: "1")!)!.decimalString == "999")
        precondition(BigUInt(decimal: "1")!.minus(BigUInt(decimal: "2")!) == nil)
        precondition(BigUInt(decimal: "2")! > BigUInt(decimal: "1")!)

        // Units
        precondition(Units.parse("12.5", decimals: 6)!.decimalString == "12500000")
        precondition(Units.parse("0.000001", decimals: 6)!.decimalString == "1")
        precondition(Units.parse("0.0000001", decimals: 6) == nil)      // too many decimals
        precondition(Units.parse("1,000", decimals: 0)!.decimalString == "1000")
        precondition(Units.parse("abc", decimals: 6) == nil)
        precondition(Units.parse("1.5", decimals: 18)!.decimalString == "1500000000000000000")
        precondition(Units.format(BigUInt(decimal: "12500000")!, decimals: 6) == "12.5")
        precondition(Units.format(BigUInt(decimal: "1")!, decimals: 6) == "0.000001")
        precondition(Units.format(BigUInt(decimal: "1500000000000000000")!, decimals: 18) == "1.5")

        // ABI approve(0x1111…, 25 USDC)
        let a = ABI.approve(spender: "0x0000000000001fF3684f28c67538d4D072C22734", amount: Units.parse("25", decimals: 6)!)
        precondition(a == "0x095ea7b30000000000000000000000000000000000001ff3684f28c67538d4d072c2273400000000000000000000000000000000000000000000000000000000017d7840", a)

        // SIWE message — compared against the server's own function by scripts/test-evm.sh
        print(SIWE.message(domain: "app.blueagent.dev", address: "0xAbCdEf0123456789aBcDeF0123456789AbCdEf01", nonce: "n0nce"), terminator: "")
    }
}
