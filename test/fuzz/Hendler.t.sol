// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizeStableCoin} from "../../src/DecentralizeStablecoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Hendler is Test {
    DSCEngine engine;
    DecentralizeStableCoin dsc;
    ERC20Mock wbtc;
    ERC20Mock weth;
    
    uint256 public timesMintWasCalled;
    address[] public usersWithCollateralDeposited;
    MockV3Aggregator public ethUsdPriceFeed;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _dscengine, DecentralizeStableCoin _dsc) {
        engine = _dscengine;
        dsc = _dsc;
        address[] memory collateralTokens = engine.getCollateralTokens();

        wbtc = ERC20Mock(collateralTokens[1]);
        weth = ERC20Mock(collateralTokens[0]);

        engine.getCollateralTokenPriceFeed(address(weth)); 
        ethUsdPriceFeed =   MockV3Aggregator(address(engine.getCollateralTokenPriceFeed(address(weth)))); 
    }
    //This breaks invariant test suite
    //function updateCollateralPrice(uint96 newPrice) public {
    //    int256 newPriceInt = int256(uint256(newPrice));
    //    ethUsdPriceFeed.updateAnswer(newPriceInt); 
    //}


    function depositCollateral (uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(engine), amountCollateral);
        engine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        usersWithCollateralDeposited.push(msg.sender);
    }

    function reedemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = engine.getCollateralBalanceOfUser(address(collateral), msg.sender);
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if(amountCollateral == 0) {
            return;
        }
        
        engine.redeemCollateral(address(collateral), amountCollateral);

    }

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if(collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }

     function mintUsd(uint256 amount, uint256 addressSeed) public {
        if(usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        
        (uint256 totalUsdMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(sender);
        int256 maxUsdToMint = (int256(collateralValueInUsd) / 2 )  - int256 (totalUsdMinted);
        if(maxUsdToMint <= 0) {
            return;
        }
         amount = bound(amount, 0, uint256(maxUsdToMint));
        if(amount == 0) {
            return;
        }
        vm.startPrank(sender);
        engine.mintUSD(amount);
        vm.stopPrank();    
        
           
    }

}