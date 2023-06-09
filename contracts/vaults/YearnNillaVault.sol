// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "OpenZeppelin/openzeppelin-contracts@4.7.3/contracts/token/ERC20/IERC20.sol";
import "OpenZeppelin/openzeppelin-contracts@4.7.3/contracts/token/ERC20/utils/SafeERC20.sol";
import "../BaseNillaEarn.sol";

import "../../interfaces/IYVToken.sol";
import "../../interfaces/IYearnPartnerTracker.sol";

contract YearnNillaVault is BaseNillaEarn {
    using SafeERC20 for IERC20;

    address public PARTNER_ADDRESS;

    IYVToken public yvToken;
    IYearnPartnerTracker public yearnPartnerTracker;

    IERC20 public baseToken;
    uint8 private _decimals;

    event Deposit(address indexed depositor, address indexed receiver, uint256 amount);
    event Withdraw(
        address indexed withdrawer,
        address indexed receiver,
        uint256 amount,
        uint256 maxLoss
    );
    event SetNewPartnerAddress(address newAddress);

    function initialize(
        address _yvToken,
        address _yearnPartnerTracker,
        address _multisig,
        string memory _name,
        string memory _symbol,
        uint16 _depositFeeBPS,
        uint16 _withdrawFeeBPS,
        uint16 _performanceFeeBPS
    ) external {
        __initialize__(_name, _symbol, _depositFeeBPS, _withdrawFeeBPS, _performanceFeeBPS);
        yvToken = IYVToken(_yvToken);
        yearnPartnerTracker = IYearnPartnerTracker(_yearnPartnerTracker);

        IERC20 _baseToken = IERC20(address(IYVToken(_yvToken).token()));
        baseToken = _baseToken;
        _baseToken.safeApprove(_yearnPartnerTracker, type(uint256).max);
        _decimals = IYVToken(_yvToken).decimals();

        PARTNER_ADDRESS = _multisig;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function SetPartnerAddress(address _newAddress) external onlyOwner {
        require(_newAddress != address(0), "Set to empty address");
        PARTNER_ADDRESS = _newAddress;
        emit SetNewPartnerAddress(_newAddress);
    }

    function deposit(uint256 _amount, address _receiver) external nonReentrant returns (uint256) {
        //gas saving
        IERC20 _baseToken = baseToken;
        IYVToken _yvToken = yvToken;
        uint256 principal = principals[_receiver];
        uint256 pricePerShare = _yvToken.pricePerShare();
        uint256 exchangeRatePrecision = 10 ** _decimals;
        // calculate performace fee
        uint256 depositFee = _calculatePerformanceFee(
            _receiver,
            principal,
            pricePerShare,
            exchangeRatePrecision
        );
        // transfer fund.
        uint256 baseTokenBefore = _baseToken.balanceOf(address(this));
        _baseToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 receivedBaseToken = _baseToken.balanceOf(address(this)) - baseTokenBefore;
        // deposit to yearn.
        uint256 yvBefore = _yvToken.balanceOf(address(this));
        yearnPartnerTracker.deposit(address(_yvToken), PARTNER_ADDRESS, receivedBaseToken);
        uint256 receivedYVToken = _yvToken.balanceOf(address(this)) - yvBefore;
        // collect protocol's fee.
        depositFee += (receivedYVToken * depositFeeBPS) / BPS;
        reserves[address(_yvToken)] += depositFee;
        _mint(_receiver, receivedYVToken - depositFee);
        // calculate new receiver's principal
        _updateNewPrincipals(_receiver, _yvToken.pricePerShare(), exchangeRatePrecision);
        emit Deposit(msg.sender, _receiver, _amount);
        return receivedYVToken - depositFee;
    }

    function redeem(
        uint256 _shares,
        address _receiver,
        uint256 _maxLoss
    ) external nonReentrant returns (uint256) {
        // gas saving
        IERC20 _baseToken = baseToken;
        IYVToken _yvToken = yvToken;
        uint256 principal = principals[_receiver];
        uint256 pricePerShare = _yvToken.pricePerShare();
        uint256 exchangeRatePrecision = 10 ** _decimals;
        // calculate performance fee
        uint256 withdrawFee = _calculatePerformanceFee(
            _receiver,
            principal,
            pricePerShare,
            exchangeRatePrecision
        );
        // burn user's shares
        _burn(_receiver, _shares);
        // collect protocol's fee
        withdrawFee += (_shares * withdrawFeeBPS) / BPS;
        reserves[address(_yvToken)] += withdrawFee;
        uint256 baseTokenBefore = _baseToken.balanceOf(address(this));
        // withdraw user's fund.
        _yvToken.withdraw(_shares - withdrawFee, _receiver, _maxLoss);
        uint256 receivedBaseToken = _baseToken.balanceOf(address(this)) - baseTokenBefore;
        // calculate new receiver's principal
        _updateNewPrincipals(_receiver, _yvToken.pricePerShare(), exchangeRatePrecision);
        emit Withdraw(msg.sender, _receiver, receivedBaseToken, _maxLoss);
        return receivedBaseToken;
    }

    // internal function to calculate performance fee
    function _calculatePerformanceFee(
        address _receiver,
        uint256 _principal,
        uint256 _pricePerShare,
        uint256 _exchangeRatePrecision
    ) internal view returns (uint256 performanceFee) {
        // get current balance from current shares
        if (_principal != 0) {
            // get current balance from share
            uint256 currentBal = (_pricePerShare * balanceOf(_receiver)) / _exchangeRatePrecision;
            // calculate profit from current balance compared to latest known principal
            uint256 profit = currentBal > _principal ? (currentBal - _principal) : 0;
            // calculate performance fee
            uint256 fee = (profit * performanceFeeBPS) / BPS;
            // sum fee into the performanceFee, convert to share
            performanceFee = (fee * _exchangeRatePrecision) / _pricePerShare;
        } else performanceFee = 0;
    }

    // internal function to update receiver's latest principal
    function _updateNewPrincipals(
        address _receiver,
        uint256 _pricePerShare,
        uint256 _exchangeRatePrecision
    ) internal {
        // update new receiver's principal
        principals[_receiver] = (_pricePerShare * balanceOf(_receiver)) / _exchangeRatePrecision;
    }
}
