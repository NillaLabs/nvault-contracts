pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "OpenZeppelin/openzeppelin-contracts@4.7.3/contracts/token/ERC20/IERC20.sol";
import "OpenZeppelin/openzeppelin-contracts@4.7.3/contracts/token/ERC20/utils/SafeERC20.sol";

import "../contracts/ProxyAdminImpl.sol";
import "../contracts/TransparentUpgradeableProxyImplNative.sol";
import "../contracts/liquidity_staking/LidoNillaLiquidityStaking.sol";

import "../interfaces/IstETH.sol";
import "../interfaces/ICurvePool.sol";

contract LidoTest is Test {
    using SafeERC20 for IERC20;
    using Math for uint256;

    TransparentUpgradeableProxyImplNative public proxy;
    address public impl;
    address public admin;
    address public user = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    uint256 public mainnetFork;

    IERC20 public baseToken;
    IstETH public lido = IstETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    ICurvePool swapRouter = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);

    LidoNillaLiquidityStaking public nilla;

    function setUp() public {
        mainnetFork = vm.createFork(
            "https://mainnet.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161"
        );
        vm.selectFork(mainnetFork);
        startHoax(user);

        admin = address(new ProxyAdminImpl());
        impl = address(new LidoNillaLiquidityStaking(address(lido)));

        proxy = new TransparentUpgradeableProxyImplNative(
            impl,
            admin,
            abi.encodeWithSelector(
                LidoNillaLiquidityStaking.initialize.selector,
                address(swapRouter),
                "ETH Staking",
                "ETH",
                1,
                1,
                500
            ),
            address(swapRouter)
        );

        nilla = LidoNillaLiquidityStaking(payable(address(proxy)));

        vm.label(address(nilla), "#### Nilla ####");
        vm.label(address(baseToken), "#### Lido / stETH ####");
        vm.label(address(swapRouter), "#### Curve Pool ####");
    }

    function testDeposit() public {
        uint256 amount = 1e19;

        uint256 sharesBefore = lido.sharesOf(address(nilla));
        uint256 reserveBefore = nilla.reserves(address(lido));

        nilla.deposit{ value: amount }(user);
        uint256 principal = nilla.principals(user);
        uint256 reserveAfter = nilla.reserves(address(lido));
        uint256 sharesAfter = lido.sharesOf(address(nilla));
        uint256 depositFee = ((sharesAfter - sharesBefore) * 1) / 10_000;

        assertEq(reserveAfter - reserveBefore, depositFee);
        assertEq(nilla.balanceOf(user), sharesAfter - depositFee);
        assertEq(
            nilla.reserves(address(lido)) + nilla.totalSupply(),
            lido.sharesOf(address(nilla))
        );
        assertEq(principal, lido.getPooledEthByShares(nilla.balanceOf(user)));
    }

    function testFuzzyDeposit(uint256 amount) public {
        amount = bound(amount, 1e15, 1e22);

        uint256 sharesBefore = lido.sharesOf(address(nilla));
        uint256 reserveBefore = nilla.reserves(address(lido));

        nilla.deposit{ value: amount }(user);

        uint256 reserveAfter = nilla.reserves(address(lido));
        uint256 sharesAfter = lido.sharesOf(address(nilla));
        uint256 depositFee = ((sharesAfter - sharesBefore) * 1) / 10_000;

        assertEq(reserveAfter - reserveBefore, depositFee);
        assertEq(nilla.balanceOf(user), sharesAfter - depositFee);
        assertEq(
            nilla.reserves(address(lido)) + nilla.totalSupply(),
            lido.sharesOf(address(nilla))
        );
        assertEq(nilla.principals(user), lido.getPooledEthByShares(nilla.balanceOf(user)));
    }

    function testDepositTooLarge() public {
        uint256 amount = 1e30;

        vm.expectRevert(bytes("STAKE_LIMIT"));
        nilla.deposit{ value: amount }(user);
    }

    function testDepositInvalidAmount() public {
        uint256 amount = 0;
        vm.expectRevert();
        nilla.deposit{ value: amount }(user);
    }

    function testRedeemNormal() public {
        uint256 amount = 1e18;
        nilla.deposit{ value: amount }(user);

        vm.warp(block.timestamp + 1_000_000);

        uint256 shares = nilla.balanceOf(user) / 2; // Redeem half shares
        uint256 withdrawFee = (shares * 1) / 10_000;
        uint256 reserveBefore = nilla.reserves(address(lido));

        uint256 currentBal = lido.getPooledEthByShares(nilla.balanceOf(user));
        uint256 profit = currentBal > nilla.principals(user)
            ? (currentBal - nilla.principals(user))
            : 0;
        uint256 fee = profit.mulDiv(500, 10_000);
        withdrawFee += lido.getSharesByPooledEth(fee);

        nilla.redeem(shares, user, lido.getPooledEthByShares(shares) / 10);

        uint256 reserveAfter = nilla.reserves(address(lido));

        assertEq(reserveAfter - reserveBefore, withdrawFee);
        assertEq(nilla.principals(user), lido.getPooledEthByShares(nilla.balanceOf(user)));
        require(
            lido.sharesOf(address(nilla)) - (nilla.reserves(address(lido)) + nilla.totalSupply()) <=
                1,
            "Error: Rounding more than 1"
        );
    }

    function testFuzzyRedeem(uint256 amount) public {
        amount = bound(amount, 1e15, 1e22);
        nilla.deposit{ value: amount }(user);
        console.log("Total supply:", nilla.totalSupply());

        vm.warp(block.timestamp + 1_000_000);

        uint256 shares = nilla.balanceOf(user) / 2; // Redeem total shares
        uint256 withdrawFee = (shares * 1) / 10_000;
        uint256 reserveBefore = nilla.reserves(address(lido));

        uint256 currentBal = lido.getPooledEthByShares(nilla.balanceOf(user));
        uint256 profit = currentBal > nilla.principals(user)
            ? (currentBal - nilla.principals(user))
            : 0;
        uint256 fee = profit.mulDiv(500, 10_000);
        withdrawFee += lido.getSharesByPooledEth(fee);

        nilla.redeem(shares, user, lido.getPooledEthByShares(shares) / 10);

        uint256 reserveAfter = nilla.reserves(address(lido));

        assertEq(reserveAfter - reserveBefore, withdrawFee);
        assertEq(nilla.principals(user), lido.getPooledEthByShares(nilla.balanceOf(user)));
        require(
            lido.sharesOf(address(nilla)) - (nilla.reserves(address(lido)) + nilla.totalSupply()) <=
                1,
            "Error: Rounding more than 1"
        );
    }
}
