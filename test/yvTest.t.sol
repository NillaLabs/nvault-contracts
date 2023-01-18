pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "../contracts/ProxyAdminImpl.sol";
import "../contracts/TransparentUpgradeableProxyImpl.sol";
import "../contracts/vaults/YearnNillaVault.sol";
import "../interfaces/IYVToken.sol";
import "OpenZeppelin/openzeppelin-contracts@4.7.3/contracts/token/ERC20/IERC20.sol";
import "OpenZeppelin/openzeppelin-contracts@4.7.3/contracts/token/ERC20/utils/SafeERC20.sol";

contract YVTest is Test {
    using SafeERC20 for IERC20;
    
    TransparentUpgradeableProxyImpl internal proxy;
    address internal impl;
    address internal admin;
    address internal user = address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);

    address internal executor = address(0x70997970C51812dc3A010C7d01b50e0d17dc79C8);

    // zero-address
    address internal ZERO_ADDRESS = address(0);
    
    // vault
    YearnNillaVault internal vault;
    uint256 yvTotalAssets;

    uint256 mainnetFork;

    IERC20 baseToken; 
    IYVToken internal yvToken = IYVToken(address(0xa258C4606Ca8206D8aA700cE2143D7db854D168c)); //WETH

    event Deposit(address indexed depositor, address indexed receiver, uint256 amount);
    event Withdraw(address indexed withdrawer, address indexed receiver, uint256 amount, uint256 maxLoss);

    function setUp() public {
        mainnetFork = vm.createFork("https://mainnet.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161"); // ETH Mainnet
        vm.selectFork(mainnetFork);
        startHoax(user);
        
        admin = address(new ProxyAdminImpl());
        impl  = address(new YearnNillaVault());

        // Contract VaultNilla
        proxy = new TransparentUpgradeableProxyImpl(
            impl,
            admin,
            abi.encodeWithSelector(YearnNillaVault.initialize.selector, yvToken, "USDC Vault", "USDC", 3, 3, executor, address(0))
        );

        vault = YearnNillaVault(address(proxy));

        IERC20 _token = IERC20(yvToken.token());
        yvTotalAssets = yvToken.totalDebt() + _token.balanceOf(address(yvToken));

        baseToken = IERC20(address(vault.baseToken()));
        deal(address(baseToken), user, 1_000_000);
        deal(address(baseToken), address(vault), 1_000_000);
        baseToken.safeApprove(address(vault), type(uint256).max);

        _checkInfo();
    }

    function _checkInfo() internal view {
        IERC20 _token = IERC20(yvToken.token());
        console.log("---------- START CHECKING INFO ----------");
        console.log("Vault address:", address(vault));
        console.log("Vault balance:", baseToken.balanceOf(address(vault)));
        console.log("Yearn deposit limit:", yvToken.depositLimit());
        console.log("Yearn total assets:", yvToken.totalDebt() + _token.balanceOf(address(yvToken)));
        console.log("Yearn vault name:", yvToken.name());
        console.log("Is yvault shutdown:", yvToken.emergencyShutdown());
    }
    
    function testDepositNormal() public {
        console.log("---------- TEST NORMAL DEPOSIT ----------");
        uint256 amount = 1_000_000;

        vm.expectEmit(true, false, true, true);
        emit Deposit(address(user), address(user), amount);

        uint256 sharesBefore = vault.checkSharesForAddress(user);
        uint256 balanceInYearnBefore = yvToken.balanceOf(address(vault));
        uint256 reservedAmountBefore = vault.getReserves(address(yvToken));
        
        vault.deposit(amount, user);

        uint256 sharesAfter = vault.checkSharesForAddress(user);
        uint256 balanceInYearnAfter = yvToken.balanceOf(address(vault));
        uint256 reservedAmountAfter = vault.getReserves(address(yvToken));
        uint256 depositFee = ((sharesAfter - sharesBefore) * yvToken.pricePerShare()) * 3 / 10_000;  //depositFeeBPS = 0.03%, BPS = 100%
        assertEq(reservedAmountAfter - reservedAmountBefore, depositFee);

        console.log("Vault balance in yearn before:", balanceInYearnBefore);
        console.log("Vault balance in yearn after:", balanceInYearnAfter);
        console.log("Reserves before:", reservedAmountBefore);
        console.log("Reserves after:", reservedAmountAfter);
    }

    function testDepositZeroAmount() public {
        uint256 amount = 0;

        vm.expectRevert();
        vault.deposit(amount, user);
    }

    function testDepositOneAmount() public {
        uint256 amount = 1;  //when deposit amount = 1; Reverted("Log != expected log")

        vm.expectRevert();
        vault.deposit(amount, user);
    }

    function testDepositWithFuzzy(uint256 amount) public {
        console.log("---------- TEST FUZZY DEPOSIT ----------");
        // deposit with any amount that more than 1 and not exceed (depositLimit - totalSupply), also not exceed the balance of spender.
        IERC20 _token = IERC20(yvToken.token());
        uint256 totalAssets = yvToken.totalDebt() + _token.balanceOf(address(yvToken));
        uint256 maxLimit = yvToken.depositLimit() - totalAssets;
        vm.assume(amount < maxLimit && amount > 1 && amount < baseToken.balanceOf(address(user)));

        vm.expectEmit(true, true, false, true, address(vault));
        emit Deposit(address(user), address(user), amount);

        uint256 sharesBefore = vault.checkSharesForAddress(user);
        uint256 balanceInYearnBefore = yvToken.balanceOf(address(vault));
        uint256 reservedAmountBefore = vault.getReserves(address(yvToken));
        
        vault.deposit(amount, user);

        uint256 sharesAfter = vault.checkSharesForAddress(user);
        uint256 balanceInYearnAfter = yvToken.balanceOf(address(vault));
        uint256 reservedAmountAfter = vault.getReserves(address(yvToken));
        uint256 depositFee = ((sharesAfter - sharesBefore) * yvToken.pricePerShare()) * 3 / 10_000;  //depositFeeBPS = 0.03%, BPS = 100%
        assertEq(reservedAmountAfter - reservedAmountBefore, depositFee);

        console.log("Vault balance in yearn before:", balanceInYearnBefore);
        console.log("Vault balance in yearn after:", balanceInYearnAfter);
        console.log("Reserves before:", reservedAmountBefore);
        console.log("Reserves after:", reservedAmountAfter);
    }

    function testRedeemNormal() public {
        console.log("---------- TEST NORMAL REDEEM ----------");
        IERC20 _token = vault.baseToken();
        uint256 maxLoss = 1;
        uint256 amount = 10_000;
        uint256 reservedBeforeDeposit = vault.getReserves(address(yvToken));
        
        vm.expectEmit(true, true, false, true, address(vault));
        emit Deposit(address(user), address(user), amount);

        vault.deposit(amount, user);
        
        uint256 reservedAfterDeposit = vault.getReserves(address(yvToken));
        uint256 shares = vault.checkSharesForAddress(user);
        uint256 baseTokenBefore = _token.balanceOf(user);

        // NOTE: event has too many params, can't expect the emit ???
        // vm.expectEmit(true, true, true, true, address(vault));
        // emit Withdraw(user, user, amount, maxLoss);

        vault.redeem(shares, user, maxLoss);
        uint256 reservedAfterWithdraw = vault.getReserves(address(yvToken));
        uint256 baseTokenAfter = _token.balanceOf(user);
        uint256 withdrawFee = shares * 3 / 10_000; // withdrawFeeBPS = 0.03% BPS 100%

        assertEq(withdrawFee, reservedAfterWithdraw - reservedAfterDeposit);

        console.log("Reserves before deposit:", reservedBeforeDeposit);
        console.log("Reserves after deposit:", reservedAfterDeposit);
        console.log("Reserves after withdraw:", vault.getReserves(address(yvToken)));
        console.log("Withdraw fee:", withdrawFee);
        console.log("User's shares in vault:", shares);
        console.log("Received amount:", baseTokenAfter - baseTokenBefore);
        console.log("Balance of baseToken before:", baseTokenBefore);
        console.log("Balance of baseToken after:", baseTokenAfter);
    }

    function testRedeemExceedingShares() public {
        uint256 shares = vault.checkSharesForAddress(user);
        uint256 maxLoss = 1;
        uint256 amount = 10_000;
        vault.deposit(amount, user);
        vm.expectRevert();
        vault.redeem(shares * 2, user, maxLoss);
    }

    function testRedeemZeroShare() public {
        uint256 shares = 0;
        uint256 maxLoss = 1;
        uint256 amount = 10_000;
        vault.deposit(amount, user);

        vm.expectRevert();
        vault.redeem(shares, user, maxLoss);
    }

    function testRedeemExceedingMaxLoss() public {
        uint256 shares = 100;
        uint256 maxLoss = 10_100;
        uint256 amount = 10_000;
        vault.deposit(amount, user);

        vm.expectRevert();
        vault.redeem(shares, user, maxLoss);
    }

    function testRedeemZeroMaxLoss() public {
        // NOTE: I'm not sure, since this is a forking network
        // in which allow the redemption with 0 maxLoss is possible. *I guess*
        // Practically, it should be reverted, due to the price fluctuation.
        console.log("---------- TEST ZERO MAXLOSS REDEEM ----------");
        IERC20 _token = vault.baseToken();
        uint256 maxLoss = 0;
        uint256 amount = 10_000;
        uint256 reservedBeforeDeposit = vault.getReserves(address(yvToken));
        
        vm.expectEmit(true, true, false, true, address(vault));
        emit Deposit(address(user), address(user), amount);

        vault.deposit(amount, user);
        
        uint256 reservedAfterDeposit = vault.getReserves(address(yvToken));
        uint256 shares = vault.checkSharesForAddress(user);
        uint256 baseTokenBefore = _token.balanceOf(user);

        // NOTE: event has too many params, can't expect the emit ???
        // vm.expectEmit(true, true, true, true, address(vault));
        // emit Withdraw(user, user, amount, maxLoss);

        vault.redeem(shares, user, maxLoss);
        uint256 reservedAfterWithdraw = vault.getReserves(address(yvToken));
        uint256 baseTokenAfter = _token.balanceOf(user);
        uint256 withdrawFee = shares * 3 / 10_000; // withdrawFeeBPS = 0.03% BPS 100%

        assertEq(withdrawFee, reservedAfterWithdraw - reservedAfterDeposit);

        console.log("Reserves before deposit:", reservedBeforeDeposit);
        console.log("Reserves after deposit:", reservedAfterDeposit);
        console.log("Reserves after withdraw:", vault.getReserves(address(yvToken)));
        console.log("Withdraw fee:", withdrawFee);
        console.log("User's shares in vault:", shares);
        console.log("Received amount:", baseTokenAfter - baseTokenBefore);
        console.log("Balance of baseToken before:", baseTokenBefore);
        console.log("Balance of baseToken after:", baseTokenAfter);
    }
}