// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {Script} from "forge-std/Script.sol";
import {RisedleMetaAggregator} from "src/MetaAggregator.sol";

contract DeployMetaAggregator is Script {
  address feeRecipient = 0x56b4a9675c52144C99F676835e83d5625CB47202;
  uint256 feePercentage = 0.001 ether;
  address[] aggregators = [
    0x1111111254EEB25477B68fb85Ed929f73A960582, // 1inch
    0xDef1C0ded9bec7F1a1670819833240f027b25EfF, // 0x / Matcha
    0xDEF171Fe48CF0115B1d80b88dc8eAB59176FEe57, // ParaSwap
    0x6131B5fae19EA4f9D964eAc0408E4408b66337b5, // KyberSwap
    0x6352a56caadC4F1E25CD6c75970Fa768A3304e64 // OpenOcean
  ];

  function setUp() public {}

  function run() public {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);

    RisedleMetaAggregator agg =
      new RisedleMetaAggregator(feeRecipient, aggregators, feePercentage);

    vm.stopBroadcast();
  }
}
