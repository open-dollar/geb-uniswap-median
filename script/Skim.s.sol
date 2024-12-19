pragma solidity 0.6.7;
pragma experimental ABIEncoderV2;

import {Script} from "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";

import {UniswapConverterBasicAveragePriceFeedMedianizer} from
    "../src/UniswapConverterBasicAveragePriceFeedMedianizer.sol";

import {MockRewardRelayer} from "../src/test/relayer/MockRewardRelayer.sol";

import {IUniswapV2Pair} from "../src/univ2/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "../src/univ2/interfaces/IUniswapV2Factory.sol";
import {IERC20} from "../src/univ2/interfaces/IERC20.sol";
import "forge-std/console2.sol";

// BROADCAST
// source .env && forge script Skim --with-gas-price 2000000000 -vvvvv --rpc-url $ARB_MAINNET_RPC --broadcast --verify --etherscan-api-key $ARB_ETHERSCAN_API_KEY --sender $DEFAULT_KEY_PUBLIC_ADDRESS --account defaultKey

// SIMULATE
// source .env && forge script Skim --with-gas-price 2000000000 -vvvvv --rpc-url $ARB_MAINNET_RPC --sender $DEFAULT_KEY_PUBLIC_ADDRESS

contract Skim is Script, Test {
    IUniswapV2Factory public camelotV2Factory;

    IERC20 public token0;
    IERC20 public token1;

    address constant MAINNET_CAMELOT_V2_FACTORY = 0x6EcCab422D763aC031210895C81787E87B43A652;
    address constant MAINNET_PENDLE = 0x0c880f6761F1af8d9Aa9C466984b80DAb9a8c9e8;
    address constant MAINNET_E_PENDLE = 0x3EaBE18eAE267D1B57f917aBa085bb5906114600;

    function run() public {
        vm.startBroadcast();
        camelotV2Factory = IUniswapV2Factory(MAINNET_CAMELOT_V2_FACTORY);

        uint256 allPairsLength = camelotV2Factory.allPairsLength();

        // for (uint256 i = 78; i < allPairsLength; i++) {
        for (uint256 i = 151; i < 400; i++) {
            address pairAddress = camelotV2Factory.allPairs(i);
            IUniswapV2Pair pair = IUniswapV2Pair(pairAddress);

            IERC20 token0 = IERC20(pair.token0());
            IERC20 token1 = IERC20(pair.token1());

            try pair.skim(msg.sender) {
                uint256 balance0 = token0.balanceOf(msg.sender);
                uint256 balance1 = token1.balanceOf(msg.sender);

                if (balance0 != 0 || balance1 != 0) {
                    emit log_named_address("Pair Address:", pairAddress);

                    emit log_named_string("Token 0 Symbol:", token0.symbol());
                    emit log_named_decimal_uint("Token 0 Balance:", balance0, 18);

                    emit log_named_string("Token 1 Symbol:", token1.symbol());
                    emit log_named_decimal_uint("Token 1 Balance:", balance1, 18);
                }
            } catch {}
        }

        vm.stopBroadcast();
    }
}

// 0xC0658411564271c780a7B9C82eEd6E5F7d7b1804::skim fails due to decimals 6
