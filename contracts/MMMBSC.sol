// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;


import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

interface IFundHolder {
    function withdraw(address token) external;
    function withdraw(address token, uint256 amount) external;
}

interface IToken is IERC20MetadataUpgradeable {

    function reduce(address account, uint256 amount) external;

    function produce(address account, uint256 amount) external;
}

interface IRandom {
    function randomMixCode(uint256 length) external returns (string memory);
}

contract MMMBSC is Initializable, OwnableUpgradeable {

    using ECDSAUpgradeable for bytes32;

    using SafeMathUpgradeable for uint256;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    uint256 public constant MAX = ~uint256(0);

    // FundHolder public _accumulateHolder; 1
    // FundHolder public _readyHolder;  2
    // FundHolder public _refundHolder; 3
    // FundHolder public _exforeHolder; 4

    mapping (uint256 => IFundHolder) public _holderByType;

    IERC20MetadataUpgradeable public _baseToken;
    IToken public _score;
    IToken public _fund;
    IRandom public _random;

    uint256 public baseUint = 10**6;

    uint256 public round = 0;
    

    mapping (uint256 => EnumerableSetUpgradeable.AddressSet) private _buyers;

    mapping (uint256 => EnumerableSetUpgradeable.UintSet) private _withdrawIds;

    uint256 public _waitPayIndex;

    mapping (uint256 => WithDrawInfo[]) private _waitPayInfos;


    mapping (uint256 => mapping (address => EnumerableSetUpgradeable.UintSet) ) private _orderIdsByOwner;


    mapping (uint256 => EnumerableSetUpgradeable.UintSet) private _orderIds;
    
    mapping (uint256 => mapping (address => EnumerableSetUpgradeable.AddressSet)) private _referralByOwner;

    bool public _paused;

    mapping (address => address) public referrerByOwner;

    mapping (address => UserInfo) public _userInfoByOwner;

    TotalInfo public _totalInfo;
    
    uint256 public keepTimes = MAX;
    uint256 public startTimes = MAX;

    uint256 public currentId;

    mapping (uint256 => uint256[]) public roundLimit;// 0 -> [0(min), 1(max)]
    mapping (uint256 => OrderInfo) private _orderInfoById;

    mapping (address => string) _codeByOwner;
    mapping (string => address) _ownerByCode;

    address public _signer;

    mapping (address => FundInfo) private _fundInfoByOwner;

    mapping (address => FundInfo[]) private _activeFundInfos;// not buy order


    mapping (address => LastOrdrIdInfo) private _lastOrderByOwner;

    mapping(uint256 => ShowOrderInfo[]) private _allOrders;

    mapping(uint256 => ShowOrderInfo[]) private _helpOrders;
    mapping(uint256 => ShowOrderInfo[]) private _getHlpOrders;

    struct ShowOrderInfo {
        uint256 id;
        uint256 time;
        uint256 oType;
    }

    struct LastOrdrIdInfo {
        uint256 buyFundId;
        uint256 helpId;
        uint256 getHelpId;
    }

    struct FundHolderInfo {
        uint256 aBalance;
        uint256 bBalance;
        uint256 cBalance;
        uint256 dBalance;
    }

    struct UserInfo {
        uint256 score;// user's total score
        uint256 buyValue;// user's total buy value
        uint256 beInviters;// beInviter num
        uint256 lastDoneId;// last dont order's id
        uint256 lastDoneIndex;// last done order index
        address referrer;//  user's referrer
        string code;// user's invite code
        uint256 fund;// user's fund
        uint256 registTime;
    }

    struct TotalInfo {
        uint256 baseTokens;
        uint256 addrs;
        uint256 clockTimes;
        uint256 clockStartTimes;
        uint256 memberCount;
    }

    struct OrderInfo {
        uint256 id;// order's id
        address owner;// order's owner
        uint256 buyValue;// order amount
        uint256 buyTime;
        uint256 keepTime;
        uint256 baseReward;
        uint256 buyDoneTime;
        uint256 matchTime;
        uint256 rewardValue;
        uint256 relaseTime;
        uint256 withdrawTime;
        uint256 doneTime;
        uint256 status;//404 -> expiration
    }

    struct FundInfo {
        uint256 id;
        uint256 used;
        uint256 totalBuy;
        uint256 buyValue;
        uint256 balance;
        uint256 time;
    }

    event UpdateOrder(
        uint256 id,
        address owner,
        uint256 buyValue,
        uint256 buyTime,
        uint256 keepTime,
        uint256 baseReward,
        uint256 buyDoneTime,
        uint256 matchTime,
        uint256 rewardValue,
        uint256 relaseTime,
        uint256 withdrawTime,
        uint256 doneTime,
        uint256 status//404 -> expiration
        );
    event Bind(
        address owner,
        address referrer,
        uint256 time
    );
    event NewCode(
        address owner,
        string code,
        uint256 time
    );

    event BuyFund(address owner, uint256 id, uint256 balance, uint256 buyValue, uint256 totalUsed, uint256 totalBuyValue, uint256 time);

    // event ReleaseSuccess(address owner, uint256 releaseId, uint256[] releaseAmounts, uint256 totalRelease, uint256 time);

    event WaitWithdraw(address owner, uint256 withdrawId, uint256[] withdrawAmounts, uint256 totalWithdraw, uint256 time);

    event WithdrawSuccess(address owner, uint256 withdrawId, uint256[] withdrawAmounts, uint256 totalWithdraw, uint256 time);

    event DepositDiff(address owner, uint256 pid, uint256 id, uint256 time, uint256 buyValue);


    struct WithDrawInfo {
        address owner;
        uint256 withdrawId;
        uint256[] withdrawAmounts;
        uint256 totalWithdraw;
        uint256 time;
    }

    

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize() initializer public {
        __Ownable_init();
    }

    function init() public onlyOwner {
        _start();
    }

    function _start() internal {
        roundLimit[0] = [10 *10**6, 2000 *10**6];
        roundLimit[1] = [2000 *10**6, 5000 *10**6];
        roundLimit[2] = [5000 *10**6, 10000 *10**6];

         baseUint = 10**6;

        _baseToken = IERC20MetadataUpgradeable(0xc2132D05D31c914a87C6611C10748AEb04B58e8F);
        _signer = 0xaDF6B5F2CBFBe44655f2049a27Bf94a8959e454b;

        _fund = IToken(address(0x5357a79d4421e25C7B3854Bb5a273EC1FC7d5afC));
        _score = IToken(address(0xb03Abf23c29CA4B7c5d3920484693719FC3E1334));
        _random = IRandom(address(0x85be96Eb1a76A9Ff8a3800581fB28Da25ab178aD));
        _createCode(address(0x1));
        
        _holderByType[1] = IFundHolder(0xE5E21257e7bf9Ac6dfCb3117fbae80FbB11E85b4);
        _holderByType[2] = IFundHolder(0xb7c350F0ad9Ad9b5d7A3c34f0a6B1DcBBBe7F275);
        _holderByType[3] = IFundHolder(0xaD193455550872e6656d213de5fB5072eAfBB92a);
        _holderByType[4] = IFundHolder(0x3046147ece3C34694cFB2063E174D3fB612D733a);
        if (currentId == 0) {
            currentId = 886888;
        }
        
    }

    function setRandom(address _t) public onlyOwner {
        _random = IRandom(_t);
    }

    function setScore(address _t) public onlyOwner {
        _score = IToken(address(_t));
    }

    function setFund(address _t) public onlyOwner {
        _fund = IToken(address(_t));
    }

    function pause() public onlyOwner {
        _paused = true;
    }

    function unPause() public onlyOwner {
        _paused = false;
    }

    function start(uint256 values) public onlyOwner {
        startTimes = values;
    }

    function updateHolderForType(address _holder, uint256 _type) public onlyOwner {
        _holderByType[_type] = IFundHolder(_holder);
    }

    function updateKeepTimes(uint256 value) public onlyOwner {
        keepTimes = value;
    }
    

    function buyFund(uint256 amount) public {
        require(!_paused, "paused");
        require(amount%(10**6) == 0, "invalid amount");
        
        require(_baseToken.balanceOf(msg.sender) >= amount, "Insufficient USDT");
        UserInfo storage _userInfo = _userInfoByOwner[msg.sender];
        require(_userInfo.referrer != address(0), "not bind");

        _baseToken.transferFrom(msg.sender, address(_fund), amount);
        
        // _userInfoByOwner[msg.sender].buyBalance += amount;
        _fund.produce(msg.sender, amount);
        
        currentId += 1;

        FundInfo storage _fundInfo = _fundInfoByOwner[msg.sender];

        _fundInfo.buyValue = amount;
        _fundInfo.totalBuy += amount;

        _activeFundInfos[msg.sender].push(FundInfo({
            id: currentId,
            balance: _fund.balanceOf(msg.sender),
            totalBuy: _fundInfoByOwner[msg.sender].totalBuy,
            buyValue: amount,
            used: _fundInfoByOwner[msg.sender].used,
            time: block.timestamp
        }));

        _lastOrderByOwner[msg.sender].buyFundId = currentId;
        
        emit BuyFund(msg.sender, currentId, _fund.balanceOf(msg.sender), amount, _fundInfo.used, _fundInfo.totalBuy, block.timestamp);
        // event BuyFund(address indexed owner, uint256 id, uint256 balance, uint256 buyValue, uint256 totalUsed, uint256 totalBuyValue, uint256 time);
    }

    function bind(string calldata _code) public {
        require(!_paused, "paused");
        UserInfo storage _userInfo = _userInfoByOwner[msg.sender];
        address account = _ownerByCode[_code];
        require(account != address(0) && account != msg.sender, "invalid referrer");
        require(_userInfo.referrer == address(0), "have bind");
        _userInfo.referrer = account;
        _score.produce(msg.sender, 200 ether);

        _userInfo.registTime = block.timestamp;

        emit Bind(msg.sender, account, block.timestamp);
    }

    event TestLog(uint256 amount, uint256 balance, address sender, address token);
    function depositX(uint256 amount, uint256 _keepDays, bytes calldata sign, uint256 deadline) public nonReentrant nonProxy {

        require(!_paused, "paused");
        require(startTimes <= block.timestamp, "not start");
        require(block.timestamp >= keepTimes, "end");
        
        require(amount > 0 && amount.mod(10*baseUint) == 0, "not allow");

        UserInfo storage _userInfo = _userInfoByOwner[msg.sender];

        require(_userInfo.referrer != address(0), "not bind");

        _referralByOwner[round][_userInfo.referrer].add(msg.sender);

        delete _activeFundInfos[msg.sender];

        {
            require(_baseToken.balanceOf(msg.sender) >= amount.div(2), "Insufficient USDT");
            
            _baseToken.transferFrom(msg.sender, address(this), amount.div(2));
        
            _score.reduce(msg.sender, 100 ether);
            _fund.reduce(msg.sender, amount.div(50));
            _fundInfoByOwner[msg.sender].used += amount.div(50);
        }
        
        require(_validDepositSign(sign, _keepDays, deadline, 15 minutes, msg.sender, amount) == _signer, "invalid sign");

        currentId += 1;
        
        uint256 _keepTime = _keepDays < 15 ? 15 : _keepDays;
        _keepTime = _keepTime * (1 days);
        // _keepTime = _keepTime * (24 minutes);
        

        _orderInfoById[currentId] = OrderInfo({
            id: currentId, 
            owner: msg.sender,
            buyValue: amount, 
            buyTime: block.timestamp, 
            keepTime: _keepTime, 
            baseReward: _buyers[round].contains(msg.sender) ? 0 : amount.div(20), 
            buyDoneTime: 0,
            matchTime: 0,
            rewardValue: 0,
            relaseTime: 0,
            withdrawTime: 0,
            doneTime: 0,
            status: 1
        });

        
        _buyers[round].add(msg.sender);
        _createCode(msg.sender);
        
        // FundHolder public _accumulateHolder; 1 -> 0.5%
        // FundHolder public _readyHolder;  3 -> 0.2%
        // FundHolder public _refundHolder; 2 -> 0.5%
        // FundHolder public _exforeHolder; 4 -> 0.8%

        // mapping (uint256 => IFundHolder) public _holderByType;
        {
            _baseToken.transfer(address(_holderByType[1]), amount.mul(5).div(1000));
            _baseToken.transfer(address(_holderByType[2]), amount.mul(5).div(1000));
            _baseToken.transfer(address(_holderByType[3]), amount.mul(2).div(1000));
            _baseToken.transfer(address(_holderByType[4]), amount.mul(8).div(1000));
        }

        OrderInfo memory _orderInfo = _orderInfoById[currentId];
        _orderIds[round].add(currentId);
        // _waitMatchPayIds[round].add(currentId);

        _orderIdsByOwner[round][msg.sender].add(currentId);
        // _waitMatchPayIdsByOwner[round][msg.sender].add(currentId);

        {
            _allOrders[round].push(ShowOrderInfo({
                id: currentId,
                oType: 0,
                time: block.timestamp
            }));
            _helpOrders[round].push(ShowOrderInfo({
                id: currentId,
                oType: 0,
                time: block.timestamp
            }));
        }

        emit UpdateOrder(
            _orderInfo.id,
            _orderInfo.owner,
            _orderInfo.buyValue,
            _orderInfo.buyTime,
            _orderInfo.keepTime,
            _orderInfo.baseReward,
            _orderInfo.buyDoneTime,
            _orderInfo.matchTime,
            _orderInfo.rewardValue,
            _orderInfo.relaseTime,
            _orderInfo.withdrawTime,
            _orderInfo.doneTime,
            _orderInfo.status
        );

        _limitPay();
    }
    
    function depositDiffX(uint256 orderId, uint256 deadline, bytes calldata sign) public {
        require(!_paused, "paused");
        currentId += 1;

        OrderInfo storage _orderInfo = _orderInfoById[orderId];
        require(_orderInfo.buyValue != 0, "invalid order");
        require(_orderInfo.buyDoneTime == 0, "have already pay balance payment");
        require(_validDepositDiffSign(sign, orderId, deadline, 15 minutes, msg.sender) == _signer, "invalid sign");
        _orderInfo.buyDoneTime = block.timestamp;
        _baseToken.transferFrom(msg.sender, address(this), _orderInfo.buyValue.div(2));

        _lastOrderByOwner[msg.sender].helpId = currentId;

        emit DepositDiff(msg.sender, orderId, currentId, block.timestamp, _orderInfo.buyValue);
        // event DepositDiff(address owner, uint256 pid, uint256 id, uint256 buyDoneTime, uint256 buyValue);

        _limitPay();
    }

    // struct WithDrawInfo {
    //     address owner;
    //     uint256 withdrawId;
    //     uint256[] withdrawAmounts;
    //     uint256 totalWithdraw;
    //     uint256 time;
    // }

    function withdrawX(uint256 withdrawId, uint256[] calldata withdrawAmounts, uint256 totalWithdraw, uint256 deadline, bytes calldata sign) public nonReentrant nonProxy {
        require(!_paused, "paused");
        require(!_withdrawIds[round].contains(withdrawId), "have withdraw");

        require(_validWithdrawSign(sign, withdrawId, withdrawAmounts, totalWithdraw, deadline, 15 minutes, msg.sender) == _signer, "invalid sign");
        _withdrawIds[round].add(withdrawId);

        
        // event WaitWithdraw(address owner, uint256 withdrawId, uint256 id, uint256[] withdrawAmounts, uint256 totalWithdraw, uint256 time);

        // event WithdrawSuccess(address owner, uint256 withdrawId, uint256 id, uint256[] withdrawAmounts, uint256 totalWithdraw, uint256 time);

        if (_baseToken.balanceOf(address(this)) < totalWithdraw) { // wait
            emit WaitWithdraw(msg.sender, withdrawId, withdrawAmounts, totalWithdraw, block.timestamp);
            _waitPayInfos[round].push(WithDrawInfo({
                owner: msg.sender,
                withdrawId: withdrawId,
                withdrawAmounts: withdrawAmounts,
                totalWithdraw: totalWithdraw,
                time: block.timestamp
            }));
        } else {
            _baseToken.transfer(msg.sender, totalWithdraw);
            emit WithdrawSuccess(msg.sender, withdrawId, withdrawAmounts, totalWithdraw, block.timestamp);
        }

        _lastOrderByOwner[msg.sender].getHelpId = withdrawId;

        {
            _allOrders[round].push(ShowOrderInfo({
                id: withdrawId,
                oType: 2,
                time: block.timestamp
            }));
            _getHlpOrders[round].push(ShowOrderInfo({
                id: withdrawId,
                oType: 2,
                time: block.timestamp
            }));
        }
    }

    function _limitPay() public {
        require(!_paused, "paused");
        if (_waitPayInfos[round].length <= _waitPayIndex) return;
        if (_waitPayIndex >= _waitPayInfos[round].length) {
            delete _waitPayInfos[round];
            _waitPayIndex = 0;
            return;
        }

        for (uint256 i = _waitPayIndex;  i < _waitPayInfos[round].length; i++) {
            WithDrawInfo memory _waitPayInfo = _waitPayInfos[round][i];
            if (_baseToken.balanceOf(address(this)) < _waitPayInfo.totalWithdraw) { // wait
                break;
            } else {
                _waitPayIndex += 1;
                delete _waitPayInfos[round][i];
                _baseToken.transfer(msg.sender, _waitPayInfo.totalWithdraw);
                emit WithdrawSuccess(msg.sender, _waitPayInfo.withdrawId, _waitPayInfo.withdrawAmounts, _waitPayInfo.totalWithdraw, block.timestamp);
            }
        }

    }

    function orderLengthOf(address _o, uint256 _round) public view returns (uint256) {
        return _orderIdsByOwner[_round][_o].length();
    }

    function orderIdOfByIndex(address _o, uint256 _i, uint256 _round) public view returns (uint256) {
        return _orderIdsByOwner[_round][_o].at(_i);
    }


    function orderInfoById(uint256 _id) public view returns (OrderInfo memory) {
        return _orderInfoById[_id];
    }

    function referralList(uint256 _s, uint256 _l, address _o) public view returns (address[] memory _list) {

    }

    // FundHolder public _accumulate Holder; 1 -> 0.5%
    // FundHolder public _ready Holder;  3 -> 0.2%
    // FundHolder public _refund Holder; 2 -> 0.5%
    // FundHolder public _exfore Holder; 4 -> 0.8%
    
    function fundHolderInfo() public view returns (FundHolderInfo memory) {
        return FundHolderInfo({
            aBalance: _baseToken.balanceOf(address(_holderByType[1])),
            bBalance: _baseToken.balanceOf(address(_holderByType[2])),
            cBalance: _baseToken.balanceOf(address(_holderByType[3])),
            dBalance: _baseToken.balanceOf(address(_holderByType[4]))
        });
    }

    function userInfoOf(address _owner) public view returns (UserInfo memory _userInfo) {
        _userInfo = _userInfoByOwner[_owner];
        _userInfo.code = _codeByOwner[_owner];
        _userInfo.score = _score.balanceOf(_owner);
        _userInfo.fund = _fund.balanceOf(_owner);
        _userInfo.beInviters = _referralByOwner[round][_owner].length();
    }

    function fundInfoOf(address _owner) public view returns (FundInfo memory _fundInfo) {
        return FundInfo({
            id: 0,
            balance: _fund.balanceOf(_owner),
            totalBuy: _fundInfoByOwner[_owner].totalBuy,
            buyValue: 0,
            used: _fundInfoByOwner[_owner].used,
            time: 0
        });
    }

    function userInfoWithSignOf(address _owner, bytes memory sign, uint256 deadline) public view returns (UserInfo memory _userInfo) {
        if (validSign(sign, deadline) == address(0x401)) {
            return _userInfo;
        }
        _userInfo = _userInfoByOwner[_owner];
        _userInfo.code = _codeByOwner[_owner];
        _userInfo.score = _score.balanceOf(_owner);
        _userInfo.fund = _fund.balanceOf(_owner);
    }

    function activeFundInfosOf(address _owner) public view returns (FundInfo[] memory) {
        return _activeFundInfos[_owner];
    }

    function lastOrderByOwner(address _owner) public view returns (LastOrdrIdInfo memory) {
        return _lastOrderByOwner[_owner];
    }

    function getNewShow(uint256 _g, uint256 _h) public view returns (ShowOrderInfo[] memory, ShowOrderInfo[] memory) {
        ShowOrderInfo[] memory _gOrders = new ShowOrderInfo[](_g);
        ShowOrderInfo[] memory _hOrders = new ShowOrderInfo[](_h);
        if (_getHlpOrders[round].length > 0) {
            uint256 index = 0;
            for (uint256 i = _getHlpOrders[round].length-1; i >= 0; i--) {
                if (index >= _g) break;
                _gOrders[index] = _getHlpOrders[round][i];
                index += 1;
                if (index >= _getHlpOrders[round].length) {
                    break;
                }
            }
        }

        if (_helpOrders[round].length > 0) {
            uint256 index = 0;
            for (uint256 i = _helpOrders[round].length-1; i >= 0; i--) {
                if (index >= _h) break;
                _hOrders[index] = _helpOrders[round][i];
                index += 1;
                if (index >= _helpOrders[round].length) {
                    break;
                }
            }
        }
        
        return (_gOrders, _hOrders);

    }

    function createCode(address _owner) public onlyOwner {
        _createCode(_owner);
    }

    function _createCode(address _owner) internal returns (string memory) {
        if (bytes(_codeByOwner[_owner]).length != 0) {
            return _codeByOwner[_owner];
        }
        
        while (true) {
            string memory _code = _random.randomMixCode(8);
            if (_ownerByCode[_code] != address(0)) {
                continue;
            }
            _codeByOwner[_owner] = _code;
            _ownerByCode[_code] = _owner;
            emit NewCode(_owner, _code, block.timestamp);
            break;
        }
        
        return _codeByOwner[_owner];
    }

    function validSign(bytes memory sign, uint256 deadline) internal view returns (address) {
        return _validSign(sign, deadline, 24 hours);
    }

    function _validDepositSign(bytes memory sign, uint256 _keepDays, uint256 deadline, uint256 _keepLive, address _owner, uint256 amount) internal view returns (address) {
        if (deadline + _keepLive < block.timestamp) {
            return address(0x401);
        }
        bytes32 hash = keccak256(abi.encodePacked(deadline, _keepDays, _owner, amount));
        address signer = hash.toEthSignedMessageHash().recover(sign);
        return signer;
    }

    function _validWithdrawSign(bytes memory sign, uint256 withdrawId, uint256[] calldata withdrawAmounts, uint256 totalWithdraw, uint256 deadline, uint256 _keepLive, address _owner) internal view returns (address) {
        if (deadline + _keepLive < block.timestamp) {
            return address(0x401);
        }
        bytes32 hash = keccak256(abi.encodePacked(deadline, withdrawId, withdrawAmounts, totalWithdraw, _owner));
        address signer = hash.toEthSignedMessageHash().recover(sign);
        return signer;
    }

    // function _validDepositSign(bytes memory sign, uint256 withdrawId, uint256[] calldata withdrawAmounts, uint256 totalAmount, uint256 _keepDays, uint256 deadline, uint256 _keepLive) public view returns (address) {
    //     if (deadline + _keepLive < block.timestamp) {
    //         return address(0x401);
    //     }
    //     bytes32 hash = keccak256(abi.encodePacked(deadline, withdrawId, withdrawAmounts, totalAmount, _keepDays, msg.sender));
    //     address signer = hash.toEthSignedMessageHash().recover(sign);
    //     return signer;
    // }

    function _validDepositDiffSign(bytes memory sign, uint256 orderId, uint256 deadline, uint256 _keepLive, address _owner) internal view returns (address) {
        if (deadline + _keepLive < block.timestamp) {
            return address(0x401);
        }
        bytes32 hash = keccak256(abi.encodePacked(orderId, deadline, _owner));
        address signer = hash.toEthSignedMessageHash().recover(sign);
        return signer;
    }
    
    function _validSign(bytes memory sign, uint256 deadline, uint256 _keepLive) internal view returns (address) {
        if (deadline + _keepLive < block.timestamp) {
            return address(0x401);
        }
        bytes32 hash = keccak256(abi.encodePacked(deadline));
        address signer = hash.toEthSignedMessageHash().recover(sign);
        return signer;
    }

    uint256 private _status;
    modifier nonReentrant() {
        require(_status != 2, "reentrant");
        _status = 2;
        _;
        _status = 1;
    }

    modifier nonProxy() {
        require(msg.sender == tx.origin, "proxy");
        _;
    }

}
