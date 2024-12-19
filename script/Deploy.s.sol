pragma experimental ABIEncoderV2;

import {UniswapConverterBasicAveragePriceFeedMedianizer} from
    "../src/UniswapConverterBasicAveragePriceFeedMedianizer.sol";
import {Script} from "forge-std/Script.sol";
import {MockRewardRelayer} from "../src/test/relayer/MockRewardRelayer.sol";
import {Test} from "forge-std/Test.sol";
import "ds-test/test.sol";

// BROADCAST
// source .env && forge script DeployUniswapConverterBasicAveragePriceFeedMedianizer --with-gas-price 2000000000 -vvvvv --rpc-url $ARB_MAINNET_RPC --broadcast --verify --etherscan-api-key $ARB_ETHERSCAN_API_KEY --sender $DEFAULT_KEY_PUBLIC_ADDRESS --account defaultKey

// SIMULATE
// source .env && forge script DeployUniswapConverterBasicAveragePriceFeedMedianizer --with-gas-price 2000000000 -vvvvv --rpc-url $ARB_MAINNET_RPC --sender $DEFAULT_KEY_PUBLIC_ADDRESS

contract DeployUniswapConverterBasicAveragePriceFeedMedianizer is Script, DSTest {
    UniswapConverterBasicAveragePriceFeedMedianizer public uniswapEPendleUsdMedianizer;
    MockRewardRelayer noRewardRelayer;

    address constant MAINNET_PENDLE_USD_DENOMINATED_ORACLE = 0x07f2b47d5Ca2ee488c1Fb013f8d63181e22B9dAa;
    address constant MAINNET_CAMELOT_V2_FACTORY = 0x6EcCab422D763aC031210895C81787E87B43A652;
    address constant MAINNET_E_PENDLE = 0x3EaBE18eAE267D1B57f917aBa085bb5906114600;
    address constant MAINNET_PENDLE = 0x0c880f6761F1af8d9Aa9C466984b80DAb9a8c9e8;

    uint256 uniswapMedianizerDefaultAmountIn = 1 ether;
    uint256 uniswapMedianizerWindowSize = 86400; // 24 hours
    uint256 converterScalingFactor = 1 ether;
    uint8 uniswapMedianizerGranularity = 24; // 1 hour (ie. 86400 / 24 = 3600)

    function run() public {
        vm.startBroadcast();

        uniswapEPendleUsdMedianizer = new UniswapConverterBasicAveragePriceFeedMedianizer(
            MAINNET_PENDLE_USD_DENOMINATED_ORACLE,
            MAINNET_CAMELOT_V2_FACTORY,
            uniswapMedianizerDefaultAmountIn,
            uniswapMedianizerWindowSize,
            converterScalingFactor,
            uniswapMedianizerGranularity
        );

        noRewardRelayer = new MockRewardRelayer();

        uniswapEPendleUsdMedianizer.modifyParameters("relayer", address(noRewardRelayer));
        uniswapEPendleUsdMedianizer.modifyParameters("targetToken", MAINNET_E_PENDLE);
        uniswapEPendleUsdMedianizer.modifyParameters("denominationToken", MAINNET_PENDLE);

        uniswapEPendleUsdMedianizer.updateResult(address(0));
        (uint256 result,) = uniswapEPendleUsdMedianizer.getResultWithValidity();
        emit log_uint(result);

        emit log_uint(block.timestamp);
        vm.warp(block.timestamp + 30 minutes);
        vm.roll(100);
        emit log_uint(block.timestamp);

        uniswapEPendleUsdMedianizer.updateResult(address(0));

        uniswapEPendleUsdMedianizer.getResultWithValidity();
    }
}
