import json
import os
from dotenv import load_dotenv
from eth_account import Account
from brownie import Contract, accounts
from brownie import (
    ProxyAdminImpl,
    AaveV3NillaLendingPoolNoRewards,
    YearnNillaVault,
    TransparentUpgradeableProxyImpl,
    TransparentUpgradeableProxyImplNative,
    NativeGateway,
    NativeGatewayVault,
)
from scripts.utils.utils import *

network.gas_price("0.001 gwei")

load_dotenv()

CHAIN_ID = set_network("optimism")

f_address = open(
    "./scripts/constants/address.json",
)

data_address = json.load(f_address)

aave_v3_address = data_address[CHAIN_ID]["AAVEV3_ATOKEN"]
yearn_address = data_address[CHAIN_ID]["YEARN_VAULT"]

WETH = data_address[CHAIN_ID]["WETH"]
AAVE_V3_POOL = data_address[CHAIN_ID]["AAVEV3_POOL"]

DEPOSIT_FEE_BPS = 0
WITHDRAW_FEE_BPS = 0
PERFORMANCE_FEE_BPS = 500

deployer = Account.from_mnemonic(os.getenv("MNEMONIC"))  # NOTE: Change address later
accounts.add(deployer.privateKey)
deployer = accounts[0]

HARVEST_BOT = "0x6f650AE486eFc27BeEFb8Dc84000F63acA99735f"  # NOTE Change later
WORKER_BOT = "0x6f650AE486eFc27BeEFb8Dc84000F63acA99735f"  # NOTE Change later
MULTISIG_WALLET = "0x6f650AE486eFc27BeEFb8Dc84000F63acA99735f"  # OP's


def main():
    # Can globally deploy once for each network!
    admin = ProxyAdminImpl.at("0x85774d5Fc82EDC9633624c009F0edfAD2DDebA1C")

    # gateway = NativeGateway.deploy(WETH, {'from': deployer})
    # gateway_vault = NativeGatewayVault.deploy(WETH, {'from': deployer})

    # ---------- Deploy AAVE V3's ----------
    # impl_aave_v3_no_rewards = AaveV3NillaLendingPoolNoRewards.at(
    #     "0xf216e98136d9d4F86bE951641be0fDB076B6be30"
    # )

    # for token in aave_v3_address:
    #     aave_v3_initilize_encoded = encode_function_data(
    #         impl_aave_v3_no_rewards.initialize,
    #         aave_v3_address[token],
    #         f"{token} AAVE V3-Nilla LP",
    #         "na" + str(token),
    #         DEPOSIT_FEE_BPS,
    #         WITHDRAW_FEE_BPS,
    #         PERFORMANCE_FEE_BPS,
    #     )
    #     proxy_impl_aave_v3_no_rewards = TransparentUpgradeableProxyImplNative.deploy(
    #         impl_aave_v3_no_rewards,
    #         admin,
    #         aave_v3_initilize_encoded,
    #         WETH,
    #         {"from": deployer},
    #     )
    #     aave_v3_lp = Contract.from_abi(
    #         "AaveV3NillaLendingPool",
    #         proxy_impl_aave_v3_no_rewards.address,
    #         impl_aave_v3_no_rewards.abi,
    #     )
    #     print(
    #         f"AAVE V3:- Proxy LP {token}",
    #         aave_v3_lp,
    #         "\n -----------------------------------------------------",
    #     )
