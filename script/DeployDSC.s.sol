// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from 'forge-std/Script.sol';
import {DecentralizeStableCoin} from '../src/DecentralizeStablecoin.sol';
import {DSCEngine} from '../src/DSCEngine.sol';
import {Helper} from "./Helper.s.sol";

contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns(DecentralizeStableCoin, DSCEngine, Helper) {
        Helper config = new Helper();
        (address wethUsdPrice, address wbtcUsdPrice, address weth, address wbtc, uint256 deployerKey) = config.activeNetworkConfig();
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses=[wethUsdPrice, wbtcUsdPrice];
        vm.startBroadcast(deployerKey);
        DecentralizeStableCoin usd = new DecentralizeStableCoin();
        DSCEngine dscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(usd));
        usd.transferOwnership(address(dscEngine));
        vm.stopBroadcast();
        return (usd, dscEngine, config);
    }
}