// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizeStableCoin} from "../../src/DecentralizeStablecoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {Helper} from "../../script/Helper.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";


contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizeStableCoin usd;
    DSCEngine engine;
    Helper config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;


    function setUp() public {
        deployer = new DeployDSC();
        (usd, engine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed,weth, wbtc,) = config.activeNetworkConfig();
    }

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }


    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThatZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    address[] tokenAddresses;
    address[] priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAdressesAndPriceFeedMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(usd));
    }

    function getTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedEth = 0.05 ether;
        uint256 actualEth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedEth, actualEth);
    }
}