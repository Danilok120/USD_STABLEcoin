// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizeStableCoin} from "../../src/DecentralizeStablecoin.sol";
import {Helper} from "../../script/Helper.s.sol";
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {Hendler} from "./Hendler.t.sol";
import {console} from "forge-std/console.sol";

contract invarianceTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine engine;
    DecentralizeStableCoin dsc;
    Helper config;
    address weth;
    address wbtc;
    Hendler hendler;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (,,weth,wbtc,)=config.activeNetworkConfig();   
        hendler = new Hendler(engine, dsc);
        targetContract(address (hendler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply () public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(engine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(engine));
        uint256 totalWethValue = engine.getUsdValue(weth, totalWethDeposited);
        uint256 totalWbtcValue = engine.getUsdValue(wbtc, totalWbtcDeposited);


       

        assert(totalWethValue + totalWbtcValue >= totalSupply);
}           


   /* function invariant_checkAllgetters() public view {
    engine.getAccountCollateralValue();
    engine.getAccountInformation();
    engine.getCollateralBalanceOfUser(address,address);
    engine.getCollateralTokens();
    engine.getHealthFactor();
    engine.getTokenAmountFromUsd(address,uint256) ;
    engine.getUsdValue(address,uint256);
    }
    */




}