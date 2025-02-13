import Foundation

extension SolanaSDK {
    public struct FeeAmount: Equatable {
        public struct OtherFee: Equatable {
            public init(amount: Double, unit: String) {
                self.amount = amount
                self.unit = unit
            }
            
            public var amount: Double
            public var unit: String
        }
        
        public init(transaction: UInt64, accountBalances: UInt64, deposit: UInt64 = 0, others: [OtherFee]? = nil) {
            self.transaction = transaction
            self.accountBalances = accountBalances
            self.others = others
            self.deposit = deposit
        }
        
        public var transaction: UInt64
        public var accountBalances: UInt64
        public var deposit: UInt64
        public var others: [OtherFee]?
        public var total: UInt64 {
            transaction + accountBalances + deposit
        }
        
        public static var zero: Self {
            .init(transaction: 0, accountBalances: 0)
        }
    }
}
