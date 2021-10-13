//
//  OrcaSwap.swift
//  
//
//  Created by Chung Tran on 13/10/2021.
//

import Foundation
import RxSwift

private var cache: OrcaSwap.SwapInfo?

public class OrcaSwap {
    // MARK: - Properties
    let apiClient: OrcaSwapAPIClient
    let solanaClient: OrcaSwapSolanaClient
    
    private var info: OrcaSwap.SwapInfo?
    private let lock = NSLock()
    
    // MARK: - Initializer
    public init(apiClient: OrcaSwapAPIClient, solanaClient: OrcaSwapSolanaClient) {
        self.apiClient = apiClient
        self.solanaClient = solanaClient
    }
    
    // MARK: - Methods
    /// Prepare all needed infos for swapping
    public func load() -> Single<SwapInfo> {
        if let cached = info {return .just(cached)}
        return Single.zip(
            apiClient.getTokens(),
            apiClient.getPools(),
            apiClient.getProgramID()
        )
            .observe(on: ConcurrentDispatchQueueScheduler(qos: .userInteractive))
            .map { tokens, pools, programId in
                let routes = findAllAvailableRoutes(tokens: tokens, pools: pools)
                let tokenNames = tokens.reduce([String: String]()) { result, token in
                    var result = result
                    result[token.value.mint] = token.key
                    return result
                }
                return .init(
                    routes: routes,
                    tokens: tokens,
                    pools: pools,
                    programIds: programId,
                    tokenNames: tokenNames
                )
            }
            .do(onSuccess: {[weak self] info in
                self?.lock.lock()
                self?.info = info
                self?.lock.unlock()
            })
    }
    
    /// Find posible destination token (symbol)
    /// - Parameter fromTokenName: from token name (symbol)
    /// - Returns: List of token symbols that can be swapped to
    public func findPosibleDestinations(
        fromTokenName: String
    ) throws -> [String] {
        let routes = try findRoutes(fromTokenName: fromTokenName, toTokenName: nil)
        return routes.keys.compactMap {$0.components(separatedBy: "/").first(where: {$0 != fromTokenName})}
            .unique
            .sorted(by: <)
    }
    
    /// Find best pool to swap
    public func findBestPool(
        fromTokenName: String?,
        toTokenName: String?,
        inputAmount: UInt64?,
        outputAmount: UInt64?
    ) throws -> Pool? {
        // Check for availability
        guard let fromTokenName = fromTokenName,
           let toTokenName = toTokenName,
           inputAmount != nil || outputAmount != nil
        else {
            return nil
        }
        
        
        // find all available routes for this pair
        let routes = try findRoutes(fromTokenName: fromTokenName, toTokenName: toTokenName)
        guard !routes.isEmpty else {return nil}

        // find the best route
        for route in routes {
            if let inputAmount = inputAmount {
                // find the pool that returns the best price
            } else {
                // find the pool that required least inputAmount for receiving outputAmount
                let outputAmount = outputAmount!
            }
        }
    }
    
    /// Execute swap
//    public func swap(
//        fromWallet: SolanaSDK.Wallet,
//        toWallet: SolanaSDK.Wallet,
//        amount: Double,
//        slippage: Double,
//        isSimulation: Bool = false
//    ) -> Single<SolanaSDK.TransactionID> {
//
//    }
    
    /// Find routes for from and to token name, aka symbol
    func findRoutes(
        fromTokenName: String?,
        toTokenName: String?
    ) throws -> Routes {
        guard let info = info else { throw OrcaSwapError.swapInfoMissing }
        
        // if fromToken isn't selected
        guard let fromTokenName = fromTokenName else {return [:]}

        // if toToken isn't selected
        guard let toTokenName = toTokenName else {
            // get all routes that have token A
            let routes = info.routes.filter {$0.key.components(separatedBy: "/").contains(fromTokenName)}
            return routes
        }

        // get routes with fromToken and toToken
        let pair = [fromTokenName, toTokenName]
        let validRoutesNames = [
            pair.joined(separator: "/"),
            pair.reversed().joined(separator: "/")
        ]
        return info.routes.filter {validRoutesNames.contains($0.key)}
    }
    
    func getRouteExecutionFromInput(
        route: Route,
        pools: Pools,
        inputAmount: UInt64,
        inputTokenName: String
    ) -> Single<Pool?> {
        guard route.count > 0 else {return .just(nil)}
        
        let getPoolsRequests = route.map { route -> Single<Pool?> in
            pools.fixedPool(forRoute: route, inputTokenName: inputTokenName, solanaClient: solanaClient)
        }
        
        return Single.zip(getPoolsRequests)
            .map { pools -> Pool? in
                let pools = pools.compactMap {$0}
                guard pools.count > 0 else {return nil}
                
            }
    }
}

// MARK: - Helpers
//private func orderRoutes(
//    pools: OrcaSwap.Pools,
//    routes: [OrcaSwap.Route],
//    inputTokenName: String
//) -> [OrcaSwap.Route] {
//    // get all pools
//
//}

private func findAllAvailableRoutes(tokens: OrcaSwap.Tokens, pools: OrcaSwap.Pools) -> OrcaSwap.Routes {
    let tokens = tokens.filter {$0.value.poolToken != true}
        .map {$0.key}
    let pairs = getPairs(tokens: tokens)
    return getAllRoutes(pairs: pairs, pools: pools)
}

private func getPairs(tokens: [String]) -> [[String]] {
    var pairs = [[String]]()
    
    guard tokens.count > 0 else {return pairs}
    
    for i in 0..<tokens.count-1 {
        for j in i+1..<tokens.count {
            let tokenA = tokens[i]
            let tokenB = tokens[j]
            
            pairs.append(orderTokenPair(tokenA, tokenB))
        }
    }
    
    return pairs
}

private func orderTokenPair(_ tokenX: String, _ tokenY: String) -> [String] {
    if (tokenX == "USDC" && tokenY == "USDT") {
        return [tokenX, tokenY];
    } else if (tokenY == "USDC" && tokenX == "USDT") {
        return [tokenY, tokenX];
    } else if (tokenY == "USDC" || tokenY == "USDT") {
        return [tokenX, tokenY];
    } else if (tokenX == "USDC" || tokenX == "USDT") {
        return [tokenY, tokenX];
    } else if tokenX < tokenY {
        return [tokenX, tokenY];
    } else {
        return [tokenY, tokenX];
    }
}

private func getAllRoutes(pairs: [[String]], pools: OrcaSwap.Pools) -> OrcaSwap.Routes {
    var routes: OrcaSwap.Routes = [:]
    pairs.forEach { pair in
        guard let tokenA = pair.first,
              let tokenB = pair.last
        else {return}
        routes[getTradeId(tokenA, tokenB)] = getRoutes(tokenA: tokenA, tokenB: tokenB, pools: pools)
    }
    return routes
}

private func getTradeId(_ tokenX: String, _ tokenY: String) -> String {
    orderTokenPair(tokenX, tokenY).joined(separator: "/")
}

private func getRoutes(tokenA: String, tokenB: String, pools: OrcaSwap.Pools) -> [OrcaSwap.Route] {
    var routes = [OrcaSwap.Route]()
    
    // Find all pools that contain the same tokens.
    // Checking tokenAName and tokenBName will find Stable pools.
    for (poolId, poolConfig) in pools {
        if (poolConfig.tokenAName == tokenA && poolConfig.tokenBName == tokenB) ||
            (poolConfig.tokenAName == tokenB && poolConfig.tokenBName == tokenA)
        {
            routes.append([poolId])
        }
    }
    
    // Find all pools that contain the first token but not the second
    let firstLegPools = pools
        .filter {
            ($0.value.tokenAName == tokenA && $0.value.tokenBName != tokenB) ||
                ($0.value.tokenBName == tokenA && $0.value.tokenAName != tokenB)
        }
        .reduce([String: String]()) { result, pool in
            var result = result
            result[pool.key] = pool.value.tokenBName == tokenA ? pool.value.tokenAName: pool.value.tokenBName
            return result
        }
    
    // Find all routes that can include firstLegPool and a second pool.
    firstLegPools.forEach { firstLegPoolId, intermediateTokenName in
        pools.forEach { secondLegPoolId, poolConfig in
            if (poolConfig.tokenAName == intermediateTokenName && poolConfig.tokenBName == tokenB) ||
                (poolConfig.tokenBName == intermediateTokenName && poolConfig.tokenAName == tokenB)
            {
                routes.append([firstLegPoolId, secondLegPoolId])
            }
        }
    }
    
    return routes
}
