// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/*
*@Title: DSCEngine
*@author: Danil Kychkin
* The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our USD system should always be "overcollateralized". At no point, should the value of
 * all collateral <= the $ backed value of all the USD.
 *
 * @notice This contract is the core of the USD system. It handles all the logic
 * for minting and redeeming USD, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system

*/

import {DecentralizeStableCoin} from './DecentralizeStablecoin.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from './libraries/OracleLib.sol';

contract DSCEngine is ReentrancyGuard {
    //Errors
    error DSCEngine__NeedsMoreThatZero();
    error DSCEngine__TokenAdressesAndPriceFeedMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintedFailed();
    error DSCEngine__HealthFactorIsOK();
    error DSCEngine__HealthFactorNotImproved();



    //Types

    using OracleLib for AggregatorV3Interface;



    //State variables
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; 
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;
    mapping (address => bool) private s_tokenToAllowed;
    mapping (address token => address priceFeed) private s_priceFeeds;
    mapping (address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping (address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;
    
    DecentralizeStableCoin private immutable i_dsc;



    //Events
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedemmed(address indexed redeemedFrom,address indexed redeemedTo , address indexed token, uint256 amount);
    //Modifiers
    modifier moreThanZero(uint256 amount) {
        if(amount == 0){
            revert DSCEngine__NeedsMoreThatZero();
        }
        _;
    }
    modifier isAllowedToken(address token) {
        if(s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }


    //Functions
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if(tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAdressesAndPriceFeedMustBeSameLength();
        }
        for (uint256 i=0; i<tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizeStableCoin(dscAddress);
    }


    //External functions
    /*
    *@param tokenCollateralAddress: The addresss of the token to deposit as Collateral
    *@param amountCollateral: The amount of collateral to deposit
    *@param amountUsdToMint: The amount of USD to mint
    *@notice This function deposit collateral and mints USD in one transaction
    */
    function depositCollateralAndMintUsd(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountUsdToMint) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintUSD(amountUsdToMint);
    }
/*
*@Param tokenCollateralAddress: The addresss of the token to deposit as Collateral
*@param amountCollateral: The amount of collateral to deposit
*/
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)  public moreThanZero(amountCollateral) isAllowedToken(tokenCollateralAddress) nonReentrant {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool succsess = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if(!succsess) {
            revert DSCEngine__TransferFailed();
        }
    }


    function redeemCollateralForUSD(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountUsdToBurn) external {
        burnUSD(amountUsdToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) public moreThanZero(amountCollateral) nonReentrant {
        _redemmCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
        
    }

    function mintUSD(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        //if user minted too much
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if(!minted) {
            revert DSCEngine__MintedFailed();
        }
    }

    function burnUSD(uint256 amount) public moreThanZero(amount){
        _burnUSD(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); //not sure it needs it
    }

    /*
    * @param collateral: The ERC 20 addresss of Collateral to liquidate from user
    * @param user: The address of the user who broke the health factor (<1)
    * @param debtToCover: The amount of USD to burn in order to improve health factor
    * @notice You fill take a bonus for liquidating user funds
    * @notice This function will be working only if protocol will be roughl overcollataralize on 200%
    */

    function liquidate(address collateral, address user, uint256 debtToCover) external moreThanZero(debtToCover) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsOK();
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral,debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;

        _redemmCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
        _burnUSD(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);

        if (endingUserHealthFactor <= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }



    //Private & Internal view Functions 

    function _burnUSD(uint256 amountUsdToBurn, address onBehalfeOf, address usdFrom) private {
         s_DSCMinted[onBehalfeOf] -= amountUsdToBurn;
        bool success = i_dsc.transferFrom(usdFrom, address(this), amountUsdToBurn);
        if(!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountUsdToBurn);
    }

    function _redemmCollateral (address tokenCollateralAddress, uint256 amountCollateral, address from, address to) private {
         s_collateralDeposited[msg.sender][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedemmed(from, to, tokenCollateralAddress, amountCollateral);
        bool succsess = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if(!succsess) {
            revert DSCEngine__TransferFailed();
        }
        
    }


    function _getAccountInformation(address user) private view returns (uint256 totalDscMinted, uint256 collateralValueInUsd) {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    // Returns how close user to liquidation 
    // if a user goes below 1, then they can get liquidated
    function _healthFactor(address user) private view returns (uint256) {
        //total DSC mint
        //total collateral value
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
        //return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }
    
    function _revertIfHealthFactorIsBroken(address user) internal view {
        //Check HF (do they have enough collateral)
        // Revert if not
        uint256 userHealthFactor = _healthFactor(user);
        if(userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }
    //Publc and exernal view functions 

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns(uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    } 


function getAccountCollateralValue(address user) public view returns(uint256 totalCollateralInUsd){
     for (uint256 i=0; i<s_collateralTokens.length; i++) {
        address token = s_collateralTokens[i];
        uint256 amount = s_collateralDeposited[user][token];
        totalCollateralInUsd += getUsdValue(token, amount);
     }
     return totalCollateralInUsd;
}

function getUsdValue(address token, uint256 amount) public view returns(uint256){
    AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
    (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
    return ((uint256(price)* ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;

}

function getCollateralTokens () external view returns (address[] memory) {
    return s_collateralTokens;
}

function getCollateralBalanceOfUser (address user, address token) external view returns (uint256) {
    return s_collateralDeposited[user][token];
}

function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

function getAccountInformation(address user) external view returns (uint256 totalDscMinted, uint256 collateralValueInUsd) {

    (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);

}




}