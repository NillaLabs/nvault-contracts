// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "OpenZeppelin/openzeppelin-contracts@4.7.3/contracts/token/ERC20/IERC20.sol";
import "OpenZeppelin/openzeppelin-contracts@4.7.3/contracts/token/ERC20/utils/SafeERC20.sol";
import "OpenZeppelin/openzeppelin-contracts@4.7.3/contracts/utils/math/Math.sol";

import "../BaseNillaEarn.sol";

import "../../interfaces/IWNative.sol";
import "../../interfaces/IAToken.sol";
import "../../interfaces/IAaveLendingPoolV3.sol";
import "../../interfaces/IUniswapRouterV2.sol";

contract AaveV3NillaLendingPoolNoRewards is BaseNillaEarn {
    using SafeERC20 for IERC20;
    using Math for uint256;

    IWNative public immutable WNATIVE;

    IAToken public aToken;
    IERC20 public baseToken;
    uint8 internal _decimals;
    IAaveLendingPoolV3 public immutable POOL;

    uint256 internal constant RAY = 1e27;

    event Deposit(address indexed depositor, address indexed receiver, uint256 amount);
    event Withdraw(address indexed withdrawer, address indexed receiver, uint256 amount);

    function initialize(
        address _aToken,
        string calldata _name,
        string calldata _symbol,
        uint16 _depositFeeBPS,
        uint16 _withdrawFeeBPS,
        uint16 _performanceFeeBPS
    ) external {
        __initialize__(_name, _symbol, _depositFeeBPS, _withdrawFeeBPS, _performanceFeeBPS);
        aToken = IAToken(_aToken);
        IERC20 _baseToken = IERC20(IAToken(_aToken).UNDERLYING_ASSET_ADDRESS());
        baseToken = _baseToken;
        _baseToken.safeApprove(IAToken(_aToken).POOL(), type(uint256).max);
        _decimals = IAToken(_aToken).decimals();
    }

    constructor(address _wNative, address _pool) {
        WNATIVE = IWNative(_wNative);
        POOL = IAaveLendingPoolV3(_pool);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function deposit(uint256 _amount, address _receiver) external nonReentrant returns (uint256) {
        // gas saving
        IERC20 _baseToken = baseToken;
        IAaveLendingPoolV3 _POOL = POOL;
        IAToken _aToken = aToken;
        uint256 principal = principals[_receiver];
        // calculate performance fee
        uint256 depositFee = _calculatePerformanceFee(
            _receiver,
            principal,
            _POOL.getReserveNormalizedIncome(address(_baseToken))
        );
        // transfer fund.
        uint256 baseTokenBefore = _baseToken.balanceOf(address(this));
        _baseToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 receivedBaseToken = _baseToken.balanceOf(address(this)) - baseTokenBefore;
        // supply to Aave V3, using share instead.
        uint256 aTokenShareBefore = _aToken.scaledBalanceOf(address(this));
        _POOL.supply(address(_baseToken), receivedBaseToken, address(this), 0);
        uint256 receivedAToken = _aToken.scaledBalanceOf(address(this)) - aTokenShareBefore;
        // collect protocol's fee.
        depositFee += receivedAToken.mulDiv(depositFeeBPS, BPS);
        reserves[address(_aToken)] += depositFee;
        _mint(_receiver, receivedAToken - depositFee);
        // calculate new receiver's principal
        _updateNewPrincipals(_receiver, _POOL.getReserveNormalizedIncome(address(_baseToken)));
        emit Deposit(msg.sender, _receiver, _amount);
        return (receivedAToken - depositFee);
    }

    function redeem(uint256 _shares, address _receiver) external nonReentrant returns (uint256) {
        // gas saving
        IAaveLendingPoolV3 _POOL = POOL;
        address _baseToken = address(baseToken);
        IAToken _aToken = aToken;
        uint256 principal = principals[_receiver];
        uint256 reserveNormalizedIncome = _POOL.getReserveNormalizedIncome(address(_baseToken));
        // calculate performance fee
        uint256 withdrawFee = _calculatePerformanceFee(
            _receiver,
            principal,
            reserveNormalizedIncome
        );
        // burn user's shares
        _burn(_receiver, _shares);
        // collect protocol's fee.
        withdrawFee += _shares.mulDiv(withdrawFeeBPS, BPS);
        uint256 shareAfterFee = _shares - withdrawFee;
        // withdraw user's fund.
        uint256 aTokenShareBefore = _aToken.scaledBalanceOf(address(this));
        uint256 receivedBaseToken = _POOL.withdraw(
            _baseToken,
            shareAfterFee.mulDiv(reserveNormalizedIncome, RAY, Math.Rounding.Down), // aToken amount rounding down
            _receiver
        );
        uint256 burnedATokenShare = aTokenShareBefore - _aToken.scaledBalanceOf(address(this));
        // dust after burn rounding.
        uint256 dust = shareAfterFee - burnedATokenShare;
        reserves[address(aToken)] += (withdrawFee + dust);
        // calculate new receiver's principal
        _updateNewPrincipals(_receiver, _POOL.getReserveNormalizedIncome(address(_baseToken)));
        emit Withdraw(msg.sender, _receiver, receivedBaseToken);
        return receivedBaseToken;
    }

    function withdrawReserve(address _token, uint256 _amount) external override {
        require(msg.sender == worker, "only worker");
        IAToken _aToken = aToken; // gas saving
        if (_token != address(_aToken)) {
            reserves[_token] -= _amount;
            IERC20(_token).safeTransfer(msg.sender, _amount);
            emit WithdrawReserve(msg.sender, _token, _amount);
        } else {
            // using shares for aToken
            uint256 aTokenShareBefore = _aToken.scaledBalanceOf(address(this));
            IERC20(_token).safeTransfer(msg.sender, _amount);
            uint256 transferedATokenShare = aTokenShareBefore -
                _aToken.scaledBalanceOf(address(this));
            reserves[_token] -= transferedATokenShare;
            emit WithdrawReserve(msg.sender, _token, transferedATokenShare);
        }
    }

    // internal function to calculate performance fee
    function _calculatePerformanceFee(
        address _receiver,
        uint256 _principal,
        uint256 _reserveNormalizedIncome
    ) internal view returns (uint256 performanceFee) {
        // get current balance from current shares
        if (_principal != 0) {
            uint256 currentBal = balanceOf(_receiver).mulDiv(
                _reserveNormalizedIncome,
                RAY,
                Math.Rounding.Down
            );
            // calculate profit from current balance compared to latest known principal
            uint256 profit = currentBal > _principal ? (currentBal - _principal) : 0;
            // calculate performance fee
            uint256 fee = profit.mulDiv(performanceFeeBPS, BPS);
            // sum fee into the fee
            performanceFee = fee.mulDiv(RAY, _reserveNormalizedIncome, Math.Rounding.Down);
        } else {
            performanceFee = 0;
        }
    }

    // internal function to update receiver's latest principal
    function _updateNewPrincipals(address _receiver, uint256 _reserveNormalizedIncome) internal {
        // update new receiver's principal
        principals[_receiver] = balanceOf(_receiver).mulDiv(
            _reserveNormalizedIncome,
            RAY,
            Math.Rounding.Up
        );
    }
}
