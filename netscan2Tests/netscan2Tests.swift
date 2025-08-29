//
//  netscan2Tests.swift
//  netscan2Tests
//
//  Created by Afonso Nóbrega on 29/08/2025.
//

import Testing
@testable import netscan2

struct netscan2Tests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }
    
    @Test func networkManagerDeleteNetwork() async throws {
        let networkManager = NetworkManager.shared
        
        // Create test network
        let testDevices: [Device] = []
        networkManager.addOrUpdateNetwork(ssid: "TestNetwork", devices: testDevices)
        
        // Find the created network
        guard let testNetwork = networkManager.networks.first(where: { $0.ssid == "TestNetwork" }) else {
            throw "Test network not found"
        }
        
        let initialCount = networkManager.networks.count
        let networkId = testNetwork.id
        
        // Select the network
        networkManager.selectedNetworkId = networkId
        
        // Delete the network
        networkManager.deleteNetwork(networkId)
        
        // Verify the network was deleted
        #expect(networkManager.networks.count == initialCount - 1)
        #expect(!networkManager.networks.contains { $0.id == networkId })
        #expect(networkManager.selectedNetworkId != networkId)
    }

}

extension String: Error {}
