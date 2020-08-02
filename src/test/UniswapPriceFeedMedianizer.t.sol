pragma solidity ^0.6.7;

import "ds-test/test.sol";
import "ds-weth/weth9.sol";
import "ds-token/token.sol";

import "./orcl/MockMedianizer.sol";
import "./geb/MockTreasury.sol";

import "../uni/UniswapV2Factory.sol";
import "../uni/UniswapV2Pair.sol";
import "../uni/UniswapV2Router02.sol";

import { UniswapPriceFeedMedianizer } from  "../UniswapPriceFeedMedianizer.sol";

abstract contract Hevm {
    function warp(uint256) virtual public;
}

// --- Token Contracts ---
contract USDC is DSToken {
    constructor(bytes32 symbol) public DSToken(symbol) {
        decimals = 6;
        mint(100 ether);
    }
}

// --- Median Contracts ---
contract ETHMedianizer is MockMedianizer {
    constructor() public {
        symbol = "ETHUSD";
    }
}
contract USDCMedianizer is MockMedianizer {
    constructor() public {
        symbol = "USDCUSD";
    }
}

contract UniswapPriceFeedMedianizerTest is DSTest {
    Hevm hevm;

    MockTreasury treasury;

    ETHMedianizer converterETHPriceFeed;
    USDCMedianizer converterUSDCPriceFeed;

    UniswapPriceFeedMedianizer uniswapRAIWETHMedianizer;
    UniswapPriceFeedMedianizer uniswapRAIUSDCMedianizer;

    UniswapV2Factory uniswapFactory;
    UniswapV2Router02 uniswapRouter;

    UniswapV2Pair raiWETHPair;
    UniswapV2Pair raiUSDCPair;

    DSToken rai;
    USDC usdc;
    WETH9_ weth;

    uint256 startTime = 1577836800;

    uint256 initTokenAmount  = 100000000 ether;
    uint256 initETHUSDPrice  = 250 * 10 ** 18;
    uint256 initUSDCUSDPrice = 10 ** 18;

    uint256 initETHRAIPairLiquidity = 5 ether;               // 1250 USD
    uint256 initRAIETHPairLiquidity = 294.672324375E18;      // 1 RAI = 4.242 USD

    uint256 initUSDCRAIPairLiquidity = 4.242E6;
    uint256 initRAIUSDCPairLiquidity = 1 ether;

    uint8   uniswapMedianizerGranularity            = 24;           // 1 hour
    uint256 converterScalingFactor                  = 1 ether;
    uint256 uniswapMedianizerWindowSize             = 86400;        // 24 hours
    uint256 uniswapETHRAIMedianizerDefaultAmountIn  = 1 ether;
    uint256 uniswapUSDCRAIMedianizerDefaultAmountIn = 10 ** 12 * 1 ether;

    uint256 simulatedConverterPriceChange = 2; // 2%

    uint256 ethRAISimulationExtraRAI = 100 ether;
    uint256 ethRAISimulationExtraETH = 0.5 ether;

    uint256 usdcRAISimulationExtraRAI = 10 ether;
    uint256 usdcRAISimulationExtraUSDC = 25E6;

    uint256 callerReward = 15 ether;

    address alice = address(0x4567);
    address me;

    function setUp() public {
        me = address(this);

        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(startTime);

        // Setup Uniswap
        uniswapFactory = new UniswapV2Factory(address(this));
        createUniswapPairs();
        uniswapRouter = new UniswapV2Router02(address(uniswapFactory), address(weth));

        // Setup converter medians
        converterETHPriceFeed = new ETHMedianizer();
        converterETHPriceFeed.modifyParameters("medianPrice", initETHUSDPrice);

        converterUSDCPriceFeed = new USDCMedianizer();
        converterUSDCPriceFeed.modifyParameters("medianPrice", initUSDCUSDPrice);

        // Create treasury
        treasury = new MockTreasury(address(rai));
        rai.transfer(address(treasury), 100 * callerReward);

        // Setup Uniswap medians
        uniswapRAIWETHMedianizer = new UniswapPriceFeedMedianizer(
            address(0),
            address(uniswapFactory),
            address(treasury),
            uniswapETHRAIMedianizerDefaultAmountIn,
            uniswapMedianizerWindowSize,
            converterScalingFactor,
            callerReward,
            uniswapMedianizerGranularity
        );
        uniswapRAIUSDCMedianizer = new UniswapPriceFeedMedianizer(
            address(0),
            address(uniswapFactory),
            address(treasury),
            uniswapUSDCRAIMedianizerDefaultAmountIn,
            uniswapMedianizerWindowSize,
            converterScalingFactor,
            callerReward,
            uniswapMedianizerGranularity
        );

        // Set converter addresses
        uniswapRAIWETHMedianizer.modifyParameters("converterFeed", address(converterETHPriceFeed));
        uniswapRAIUSDCMedianizer.modifyParameters("converterFeed", address(converterUSDCPriceFeed));

        // Set target and denomination tokens
        uniswapRAIWETHMedianizer.modifyParameters("targetToken", address(rai));
        uniswapRAIWETHMedianizer.modifyParameters("denominationToken", address(weth));

        uniswapRAIUSDCMedianizer.modifyParameters("targetToken", address(rai));
        uniswapRAIUSDCMedianizer.modifyParameters("denominationToken", address(usdc));

        assertTrue(uniswapRAIWETHMedianizer.uniswapPair() != address(0));
        assertTrue(uniswapRAIUSDCMedianizer.uniswapPair() != address(0));

        // Add pair liquidity
        addPairLiquidityRouter(address(rai), address(weth), initRAIETHPairLiquidity, initETHRAIPairLiquidity);
        addPairLiquidityRouter(address(rai), address(usdc), initRAIUSDCPairLiquidity, initUSDCRAIPairLiquidity);
    }

    // --- Math ---
    function multiply(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, 'mul-overflow');
    }

    // --- Uniswap utils ---
    function createUniswapPairs() internal {
        // Create Tokens
        weth = new WETH9_();

        rai = new DSToken("RAI");
        rai.mint(initTokenAmount);

        usdc = new USDC("USDC");

        // Create WETH
        weth.deposit{value: initTokenAmount}();

        // Setup WETH/RAI pair
        uniswapFactory.createPair(address(weth), address(rai));
        raiWETHPair = UniswapV2Pair(uniswapFactory.getPair(address(weth), address(rai)));

        // Setup USDC/RAI pair
        uniswapFactory.createPair(address(usdc), address(rai));
        raiUSDCPair = UniswapV2Pair(uniswapFactory.getPair(address(usdc), address(rai)));
    }
    function addPairLiquidityRouter(address token1, address token2, uint256 amount1, uint256 amount2) internal {
        DSToken(token1).approve(address(uniswapRouter), uint(-1));
        DSToken(token2).approve(address(uniswapRouter), uint(-1));
        uniswapRouter.addLiquidity(token1, token2, amount1, amount2, amount1, amount2, address(this), now);
        UniswapV2Pair updatedPair = UniswapV2Pair(uniswapFactory.getPair(token1, token2));
        updatedPair.sync();
    }
    function addPairLiquidityTransfer(UniswapV2Pair pair, address token1, address token2, uint256 amount1, uint256 amount2) internal {
        DSToken(token1).transfer(address(pair), amount1);
        DSToken(token2).transfer(address(pair), amount2);
        pair.sync();
    }

    // --- Simulation Utils ---
    function simulateETHRAISamePrices() internal {
        hevm.warp(now + 10);
        for (uint i = 0; i < uint(uniswapMedianizerGranularity) + 1; i++) {
          uniswapRAIWETHMedianizer.updateResult(address(this));
          raiWETHPair.sync();
          hevm.warp(now + uniswapRAIWETHMedianizer.periodSize());
        }
    }
    function simulateUSDCRAISamePrices() internal {
        hevm.warp(now + 10);
        for (uint i = 0; i < uint(uniswapMedianizerGranularity) + 1; i++) {
          uniswapRAIUSDCMedianizer.updateResult(address(this));
          raiUSDCPair.sync();
          hevm.warp(now + uniswapRAIUSDCMedianizer.periodSize());
        }
    }
    function simulateWETHRAIPrices() internal {
        uint256 i;
        hevm.warp(now + 10);

        for (i = 0; i < uint(uniswapMedianizerGranularity) / 2; i++) {
          addPairLiquidityTransfer(raiWETHPair, address(rai), address(weth), ethRAISimulationExtraRAI, 0);
          uniswapRAIWETHMedianizer.updateResult(address(this));
          hevm.warp(now + uniswapRAIWETHMedianizer.periodSize());
        }
        for (i = 0; i < uint(uniswapMedianizerGranularity) / 2; i++) {
          addPairLiquidityTransfer(raiWETHPair, address(rai), address(weth), 0, ethRAISimulationExtraETH);
          uniswapRAIWETHMedianizer.updateResult(address(this));
          hevm.warp(now + uniswapRAIWETHMedianizer.periodSize());
        }
    }
    function simulateUSDCRAIPrices() internal {
        uint256 i;
        hevm.warp(now + 10);

        for (i = 0; i < uint(uniswapMedianizerGranularity) / 2; i++) {
          addPairLiquidityTransfer(raiUSDCPair, address(rai), address(usdc), usdcRAISimulationExtraRAI, 0);
          uniswapRAIUSDCMedianizer.updateResult(address(this));
          hevm.warp(now + uniswapRAIUSDCMedianizer.periodSize());
        }
        for (i = 0; i < uint(uniswapMedianizerGranularity) / 2; i++) {
          addPairLiquidityTransfer(raiUSDCPair, address(rai), address(usdc), 0, usdcRAISimulationExtraUSDC);
          uniswapRAIUSDCMedianizer.updateResult(address(this));
          hevm.warp(now + uniswapRAIUSDCMedianizer.periodSize());
        }
    }

    function test_correct_setup() public {
        assertEq(uniswapRAIWETHMedianizer.authorizedAccounts(me), 1);
        assertEq(uniswapRAIUSDCMedianizer.authorizedAccounts(me), 1);

        assertTrue(address(uniswapRAIWETHMedianizer.converterFeed()) == address(converterETHPriceFeed));
        assertTrue(address(uniswapRAIUSDCMedianizer.converterFeed()) == address(converterUSDCPriceFeed));

        assertTrue(address(uniswapRAIWETHMedianizer.uniswapFactory()) == address(uniswapFactory));
        assertTrue(address(uniswapRAIUSDCMedianizer.uniswapFactory()) == address(uniswapFactory));

        assertEq(uniswapRAIWETHMedianizer.defaultAmountIn(), uniswapETHRAIMedianizerDefaultAmountIn);
        assertEq(uniswapRAIUSDCMedianizer.defaultAmountIn(), uniswapUSDCRAIMedianizerDefaultAmountIn);

        assertEq(uniswapRAIWETHMedianizer.windowSize(), uniswapMedianizerWindowSize);
        assertEq(uniswapRAIUSDCMedianizer.windowSize(), uniswapMedianizerWindowSize);

        assertEq(uniswapRAIWETHMedianizer.periodSize(), 3600);
        assertEq(uniswapRAIUSDCMedianizer.periodSize(), 3600);

        assertEq(uniswapRAIWETHMedianizer.converterFeedScalingFactor(), converterScalingFactor);
        assertEq(uniswapRAIUSDCMedianizer.converterFeedScalingFactor(), converterScalingFactor);

        assertEq(uint256(uniswapRAIWETHMedianizer.granularity()), uniswapMedianizerGranularity);
        assertEq(uint256(uniswapRAIUSDCMedianizer.granularity()), uniswapMedianizerGranularity);

        assertTrue(uniswapRAIWETHMedianizer.targetToken() == address(rai));
        assertTrue(uniswapRAIUSDCMedianizer.targetToken() == address(rai));

        assertTrue(uniswapRAIWETHMedianizer.denominationToken() == address(weth));
        assertTrue(uniswapRAIUSDCMedianizer.denominationToken() == address(usdc));

        assertTrue(uniswapRAIWETHMedianizer.uniswapPair() == address(raiWETHPair));
        assertTrue(uniswapRAIUSDCMedianizer.uniswapPair() == address(raiUSDCPair));

        assertTrue(address(uniswapRAIWETHMedianizer.treasury()) == address(treasury));
        assertTrue(address(uniswapRAIUSDCMedianizer.treasury()) == address(treasury));

        assertEq(uniswapRAIWETHMedianizer.updateCallerReward(), callerReward);
        assertEq(uniswapRAIUSDCMedianizer.updateCallerReward(), callerReward);

        (uint256 medianPrice, bool isValid) = uniswapRAIWETHMedianizer.getResultWithValidity();
        assertEq(medianPrice, 0);
        assertTrue(!isValid);

        (medianPrice, isValid) = uniswapRAIUSDCMedianizer.getResultWithValidity();
        assertEq(medianPrice, 0);
        assertTrue(!isValid);

        (uint256 uniObservationsListLength, uint256 converterObservationsListLength) = uniswapRAIWETHMedianizer.getObservationListLength();
        assertEq(uniObservationsListLength, converterObservationsListLength);
        assertTrue(uniObservationsListLength > 0);

        (uniObservationsListLength, converterObservationsListLength) = uniswapRAIUSDCMedianizer.getObservationListLength();
        assertEq(uniObservationsListLength, converterObservationsListLength);
        assertTrue(uniObservationsListLength > 0);
    }
    function testFail_small_granularity() public {
        uniswapRAIWETHMedianizer = new UniswapPriceFeedMedianizer(
            address(converterETHPriceFeed),
            address(uniswapFactory),
            address(treasury),
            uniswapETHRAIMedianizerDefaultAmountIn,
            uniswapMedianizerWindowSize,
            converterScalingFactor,
            callerReward,
            1
        );
    }
    function testFail_window_not_evenly_divisible() public {
        uniswapRAIWETHMedianizer = new UniswapPriceFeedMedianizer(
            address(converterETHPriceFeed),
            address(uniswapFactory),
            address(treasury),
            uniswapETHRAIMedianizerDefaultAmountIn,
            uniswapMedianizerWindowSize,
            converterScalingFactor,
            callerReward,
            23
        );
    }
    function test_change_converter_feed() public {
        uniswapRAIWETHMedianizer.modifyParameters("converterFeed", address(0x123));
        uniswapRAIUSDCMedianizer.modifyParameters("converterFeed", address(0x123));

        assertTrue(address(uniswapRAIWETHMedianizer.converterFeed()) == address(0x123));
        assertTrue(address(uniswapRAIUSDCMedianizer.converterFeed()) == address(0x123));
    }

    function test_update_result_converter_throws() public {
        converterETHPriceFeed.modifyParameters("revertUpdate", 1);
        converterUSDCPriceFeed.modifyParameters("revertUpdate", 1);

        hevm.warp(now + 3599);
        assertEq(rai.balanceOf(alice), 0);

        // RAI/WETH
        uniswapRAIWETHMedianizer.updateResult(alice);
        (uint uniTimestamp, uint price0Cumulative, uint price1Cumulative) =
          uniswapRAIWETHMedianizer.uniswapObservations(0);
        (uint converterTimestamp, uint converterPrice) = uniswapRAIWETHMedianizer.converterFeedObservations(0);
        (uint256 medianPrice, bool isValid) = uniswapRAIWETHMedianizer.getResultWithValidity();
        uint256 converterPriceCumulative = uniswapRAIWETHMedianizer.converterPriceCumulative();

        assertEq(uint256(uniswapRAIWETHMedianizer.observationIndexOf(now)), 0);
        assertEq(converterPriceCumulative, initETHUSDPrice);
        assertEq(medianPrice, 0);
        assertTrue(!isValid);
        assertEq(converterTimestamp, now);
        assertEq(converterPrice, initETHUSDPrice);
        assertEq(uniTimestamp, now);
        assertEq(price0Cumulative, 1101312847350787220573278491526876720617);
        assertEq(price1Cumulative, 317082312251449702080310206411507700);
        assertEq(rai.balanceOf(alice), callerReward);

        // RAI/USDC
        uniswapRAIUSDCMedianizer.updateResult(alice);
        (uniTimestamp, price0Cumulative, price1Cumulative) =
          uniswapRAIUSDCMedianizer.uniswapObservations(0);
        (converterTimestamp, converterPrice) = uniswapRAIUSDCMedianizer.converterFeedObservations(0);
        (medianPrice, isValid) = uniswapRAIUSDCMedianizer.getResultWithValidity();
        converterPriceCumulative = uniswapRAIUSDCMedianizer.converterPriceCumulative();

        assertEq(uint256(uniswapRAIUSDCMedianizer.observationIndexOf(now)), 0);
        assertEq(converterPriceCumulative, initUSDCUSDPrice);
        assertEq(medianPrice, 0);
        assertTrue(!isValid);
        assertEq(converterTimestamp, now);
        assertEq(converterPrice, initUSDCUSDPrice);
        assertEq(uniTimestamp, now);
        assertEq(price0Cumulative, 4405251389407554133682521520241189416313059876349);
        assertEq(price1Cumulative, 79270578062783154942013374);
        assertEq(rai.balanceOf(alice), 2 * callerReward);
    }
    function test_update_treasury_throws() public {
        MockRevertableTreasury revertTreasury = new MockRevertableTreasury();
        uniswapRAIWETHMedianizer.modifyParameters("treasury", address(revertTreasury));
        uniswapRAIUSDCMedianizer.modifyParameters("treasury", address(revertTreasury));

        hevm.warp(now + 3599);
        assertEq(rai.balanceOf(alice), 0);

        // RAI/WETH
        uniswapRAIWETHMedianizer.updateResult(alice);
        // RAI/USDC
        uniswapRAIUSDCMedianizer.updateResult(alice);

        assertEq(rai.balanceOf(alice), 0);
    }
    function test_update_treasury_reward_treasury() public {
        hevm.warp(now + 3599);
        assertEq(rai.balanceOf(alice), 0);

        uint treasuryBalance = rai.balanceOf(address(treasury));

        // RAI/WETH
        uniswapRAIWETHMedianizer.updateResult(address(treasury));
        // RAI/USDC
        uniswapRAIUSDCMedianizer.updateResult(address(treasury));

        assertEq(rai.balanceOf(address(treasury)), treasuryBalance);
    }
    function testFail_update_ETHRAI_again_immediately() public {
        converterETHPriceFeed.modifyParameters("revertUpdate", 1);

        hevm.warp(now + 1);
        uniswapRAIWETHMedianizer.updateResult(address(this));

        hevm.warp(now + 1);
        uniswapRAIWETHMedianizer.updateResult(address(this));
    }
    function testFail_update_USDCRAI_again_immediately() public {
        converterUSDCPriceFeed.modifyParameters("revertUpdate", 1);

        hevm.warp(now + 1);
        uniswapRAIUSDCMedianizer.updateResult(address(this));

        hevm.warp(now + 1);
        uniswapRAIUSDCMedianizer.updateResult(address(this));
    }
    function testFail_update_result_ETH_converter_invalid_value() public {
        converterETHPriceFeed.modifyParameters("medianPrice", 0);
        hevm.warp(now + 3599);
        uniswapRAIWETHMedianizer.updateResult(address(this));
    }
    function testFail_update_result_USDC_converter_invalid_value() public {
        converterUSDCPriceFeed.modifyParameters("medianPrice", 0);
        hevm.warp(now + 3599);
        uniswapRAIUSDCMedianizer.updateResult(address(this));
    }
    function test_update_result() public {
        hevm.warp(now + 3599);

        // RAI/WETH
        uniswapRAIWETHMedianizer.updateResult(address(this));
        (uint uniTimestamp, uint price0Cumulative, uint price1Cumulative) =
          uniswapRAIWETHMedianizer.uniswapObservations(0);
        (uint converterTimestamp, uint converterPrice) = uniswapRAIWETHMedianizer.converterFeedObservations(0);
        (uint256 medianPrice, bool isValid) = uniswapRAIWETHMedianizer.getResultWithValidity();
        uint256 converterPriceCumulative = uniswapRAIWETHMedianizer.converterPriceCumulative();

        assertEq(uint256(uniswapRAIWETHMedianizer.observationIndexOf(now)), 0);
        assertEq(converterPriceCumulative, initETHUSDPrice);
        assertEq(medianPrice, 0);
        assertTrue(!isValid);
        assertEq(converterTimestamp, now);
        assertEq(converterPrice, initETHUSDPrice);
        assertEq(uniTimestamp, now);
        assertEq(price0Cumulative, 1101312847350787220573278491526876720617);
        assertEq(price1Cumulative, 317082312251449702080310206411507700);

        // RAI/USDC
        uniswapRAIUSDCMedianizer.updateResult(address(this));
        (uniTimestamp, price0Cumulative, price1Cumulative) =
          uniswapRAIUSDCMedianizer.uniswapObservations(0);
        (converterTimestamp, converterPrice) = uniswapRAIUSDCMedianizer.converterFeedObservations(0);
        (medianPrice, isValid) = uniswapRAIUSDCMedianizer.getResultWithValidity();
        converterPriceCumulative = uniswapRAIUSDCMedianizer.converterPriceCumulative();

        assertEq(uint256(uniswapRAIUSDCMedianizer.observationIndexOf(now)), 0);
        assertEq(converterPriceCumulative, initUSDCUSDPrice);
        assertEq(medianPrice, 0);
        assertTrue(!isValid);
        assertEq(converterTimestamp, now);
        assertEq(converterPrice, initUSDCUSDPrice);
        assertEq(uniTimestamp, now);
        assertEq(price0Cumulative, 4405251389407554133682521520241189416313059876349);
        assertEq(price1Cumulative, 79270578062783154942013374);
    }
    function test_simulate_same_prices() public {
        simulateETHRAISamePrices();
        simulateUSDCRAISamePrices();

        // RAI/WETH
        (uint256 medianPrice, bool isValid) = uniswapRAIWETHMedianizer.getResultWithValidity();
        assertTrue(isValid);
        assertEq(medianPrice, 4242000000004242000);

        // RAI/USDC
        (medianPrice, isValid) = uniswapRAIUSDCMedianizer.getResultWithValidity();
        assertTrue(isValid);
        assertEq(medianPrice, 4241999999999999999);
    }
    function test_thin_liquidity_one_round_simulate_prices() public {
        simulateWETHRAIPrices();
        simulateUSDCRAIPrices();

        // RAI/WETH
        (uint256 medianPrice, bool isValid) = uniswapRAIWETHMedianizer.getResultWithValidity();
        assertTrue(isValid);
        assertEq(medianPrice, 1453372414506689500);

        // RAI/USDC
        (medianPrice, isValid) = uniswapRAIUSDCMedianizer.getResultWithValidity();
        assertTrue(isValid);
        assertEq(medianPrice, 664202706237287046);
    }
    function test_thin_liquidity_multi_round_simulate_prices() public {
        for (uint i = 0; i < 2; i++) {
          simulateWETHRAIPrices();
          simulateUSDCRAIPrices();
        }

        // RAI/WETH
        (uint256 medianPrice, bool isValid) = uniswapRAIWETHMedianizer.getResultWithValidity();
        assertTrue(isValid);
        assertEq(medianPrice, 1308371543155184750);

        // RAI/USDC
        (medianPrice, isValid) = uniswapRAIUSDCMedianizer.getResultWithValidity();
        assertTrue(isValid);
        assertEq(medianPrice, 1786193702567375880);
    }
    function test_deep_liquidity_one_round_simulate_prices() public {
        // Add WETH/RAI liquidity
        addPairLiquidityRouter(address(rai), address(weth), initRAIETHPairLiquidity * 10000, initETHRAIPairLiquidity * 10000);
        // Add USDC/RAI liquidity
        addPairLiquidityRouter(address(rai), address(usdc), initRAIUSDCPairLiquidity * 10000, initUSDCRAIPairLiquidity * 10000);

        // Simulate market making
        simulateWETHRAIPrices();
        simulateUSDCRAIPrices();

        // RAI/WETH
        (uint256 medianPrice, bool isValid) = uniswapRAIWETHMedianizer.getResultWithValidity();
        assertTrue(isValid);
        assertEq(medianPrice, 4240807885365798250);

        // RAI/USDC
        (medianPrice, isValid) = uniswapRAIUSDCMedianizer.getResultWithValidity();
        assertTrue(isValid);
        assertEq(medianPrice, 4210768085959207427);
    }
}
