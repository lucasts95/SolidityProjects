// SPDX-License-Identifier: GPL-3.0
pragma solidity  ^0.8.4;

//import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/master/contracts/utils/introspection/IERC165.sol";
//import "https://raw.githubusercontent.com/OpenZeppelin/contracts-upgradeable/master/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface IERC721 is IERC165Upgradeable {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    function balanceOf(address owner) external view returns (uint256 balance);
    function Fee() external view returns (uint256 royalty);
    function collectionOwner() external view returns (address owner);
    function ownerOf(uint256 tokenId) external view returns (address owner);
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;
    function approve(address to, uint256 tokenId) external;
    function getApproved(uint256 tokenId) external view returns (address operator);
    function setApprovalForAll(address operator, bool _approved) external;
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external;
}
contract EmpireMarketplaceV5 is Initializable{
    using SafeMath for uint256;
    struct AuctionItem {
        uint256 id;
        address tokenAddress;
        uint256 tokenId;
        uint256 askingPrice;
        bool isSold;
        bool bidItem;
        uint256 bidPrice;
        address bidderAddress;
        address ERC20;
    }

    uint256 public serviceFee; //2.5% serviceFee
    address public feeAddress; // admin address where serviceFee will be sent
    address public marketplaceOwner;
    address public empireToken;
    AuctionItem[] public itemsForSale;

    //to check if item is open to market
    mapping (address => mapping (uint256 => bool)) public activeItems;
    mapping(address => bool) public validERC;
    mapping (address => mapping(uint256=>uint256)) public auctionItemId;
    mapping (address => mapping (address => mapping(uint256 => uint256))) public pendingReturns;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event ItemAdded(uint id, uint tokenId, address tokenAddress, uint256 askingPrice, bool bidItem);
    event ItemSold(uint id, address buyer, uint256 askingPrice);
    event BidPlaced(uint tokenID, address bidder, uint256 bidPrice, address CollectionAdd);
    address public feeAggregatorAddress;
    uint256 public AggregatorFee;
    function initialize(address _empireToken) public initializer {
        marketplaceOwner = msg.sender;
        empireToken = _empireToken;
        validERC[_empireToken] = true;
        serviceFee = 250;
        feeAddress = address(0x6baC3dF9Bf14c26448014f7fCc462606E22A65de); // TODO: hard code
    }

    modifier onlyOwner{
        require(marketplaceOwner == msg.sender);
        _;
    }
    modifier OnlyItemOwner(address tokenAddress, uint256 tokenId){
        IERC721 tokenContract = IERC721(tokenAddress); //
        require(tokenContract.ownerOf(tokenId) == msg.sender);
        _;
    }

    modifier OnlyItemOwnerAuc(uint256 aucItemId){
        IERC721 tokenContract = IERC721(itemsForSale[aucItemId-1].tokenAddress);
        require(tokenContract.ownerOf(itemsForSale[aucItemId-1].tokenId) == msg.sender);
        _;
    }
    modifier HasTransferApproval(address tokenAddress, uint256 tokenId){
        IERC721 tokenContract = IERC721(tokenAddress);
        require(tokenContract.getApproved(tokenId) == address(this));
        _;
    }
    modifier ItemExists(uint256 id){
        require(itemsForSale[id-1].id == id, "Could not find Item");
        _;
    }
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(marketplaceOwner, newOwner);
        marketplaceOwner = newOwner;
    }

    function changeFeeAddress(address newFeeAddress) public onlyOwner{
        feeAddress = newFeeAddress; // todo no emit event & no 0 address validation
    }

    function changeFeeAggregatorAddress(address newFeeAggregatorAddress) public onlyOwner{
        feeAggregatorAddress = newFeeAggregatorAddress;  // todo no emit event & no 0 address validation
    }

    function changeServiceFee(uint256 newFee) public onlyOwner{
        require(newFee < 3000, 'Service Should be less than 30%');
        serviceFee = newFee; // todo no emit event
    }

    function changeAggregatorFee(uint256 newFee) public onlyOwner{
        require(newFee < 3000, 'Aggregator Should be less than 30%');
        require(serviceFee > newFee, 'Aggregator Fee must be greater than serviceFee');
        AggregatorFee = newFee;
    }

    function addItemToMarket(uint256 tokenId, address tokenAddress, uint256 askingPrice, bool bidItem, address tokenERC20) OnlyItemOwner(tokenAddress, tokenId) HasTransferApproval(tokenAddress, tokenId) external returns(uint256) {
        require(activeItems[tokenAddress][tokenId] == false, "Item is already up for sale");

        if(tokenERC20 == address(0)){
            return _addItemSimple(tokenId, tokenAddress, askingPrice, bidItem);
        }else{
            require(validERC[tokenERC20], "ERC20 Token is not in valid list");
            return _addItemERC(tokenId, tokenAddress, askingPrice, bidItem, tokenERC20);
        }
    }

    function _addItemSimple(uint256 tokenId, address tokenAddress, uint256 askingPrice, bool bidItem) internal returns (uint256){
        if (auctionItemId[tokenAddress][tokenId] == 0){ //item is being added for the first time in marketplace
            uint256 newItemId = itemsForSale.length + 1;
            itemsForSale.push(AuctionItem(newItemId, tokenAddress, tokenId, askingPrice, false, bidItem, 0, address(0), address(0)));
            activeItems[tokenAddress][tokenId] = true;
            auctionItemId[tokenAddress][tokenId] = newItemId;

            assert(itemsForSale[newItemId - 1].id == newItemId);
            emit ItemAdded(newItemId, tokenId, tokenAddress, askingPrice, bidItem);
            return newItemId;
        }
        else{
            itemsForSale[auctionItemId[tokenAddress][tokenId] - 1].isSold = false;
            itemsForSale[auctionItemId[tokenAddress][tokenId] - 1].bidItem = bidItem;
            itemsForSale[auctionItemId[tokenAddress][tokenId] - 1].askingPrice = askingPrice;
            activeItems[tokenAddress][tokenId] = true;

            assert(itemsForSale[auctionItemId[tokenAddress][tokenId] - 1].id == auctionItemId[tokenAddress][tokenId]);
            emit ItemAdded(auctionItemId[tokenAddress][tokenId], tokenId, tokenAddress, askingPrice, bidItem);
            return auctionItemId[tokenAddress][tokenId];
        }
    }

    function _addItemERC(uint256 tokenId, address tokenAddress, uint256 askingPrice, bool bidItem, address tokenERC20) internal  returns (uint256){
        if (auctionItemId[tokenAddress][tokenId] == 0){ //item is being added for the first time in marketplace
            uint256 newItemId = itemsForSale.length + 1;
            itemsForSale.push(AuctionItem(newItemId, tokenAddress, tokenId, askingPrice, false, bidItem, 0, address(0), tokenERC20));
            activeItems[tokenAddress][tokenId] = true;
            auctionItemId[tokenAddress][tokenId] = newItemId;

            assert(itemsForSale[newItemId - 1].id == newItemId);
            emit ItemAdded(newItemId, tokenId, tokenAddress, askingPrice, bidItem); // TODO: no need to distinguish whether is  ERC20 or not?
        return newItemId;
        }
        else{
            itemsForSale[auctionItemId[tokenAddress][tokenId] - 1].isSold = false;
            itemsForSale[auctionItemId[tokenAddress][tokenId] - 1].bidItem = bidItem;
            itemsForSale[auctionItemId[tokenAddress][tokenId] - 1].askingPrice = askingPrice;
            itemsForSale[auctionItemId[tokenAddress][tokenId] - 1].ERC20 = tokenERC20;
            activeItems[tokenAddress][tokenId] = true;

            assert(itemsForSale[auctionItemId[tokenAddress][tokenId] - 1].id == auctionItemId[tokenAddress][tokenId]);
            emit ItemAdded(auctionItemId[tokenAddress][tokenId], tokenId, tokenAddress, askingPrice, bidItem);
            return auctionItemId[tokenAddress][tokenId];
        }
    }

    function removeItem(uint256 id) public{
        address collectionAddress = itemsForSale[id-1].tokenAddress;
        require(activeItems[collectionAddress][itemsForSale[id-1].tokenId],'Already not listed in market');
        require(IERC721(collectionAddress).ownerOf(itemsForSale[id-1].tokenId) == msg.sender,'Only Item Can Remove From Market'); // TODO:[INFO] error code inaccurate,  => `Item Owner`
        activeItems[collectionAddress][itemsForSale[id-1].tokenId] = false;
        if(itemsForSale[id-1].isSold == false && itemsForSale[id-1].bidItem == true){
            pendingReturns[itemsForSale[id-1].bidderAddress][itemsForSale[id-1].ERC20][itemsForSale[id-1].id] = itemsForSale[id-1].bidPrice;
            itemsForSale[id - 1].bidItem = false;
            itemsForSale[id - 1].bidderAddress = address(0);
            itemsForSale[id - 1].bidPrice = 0;
        } // :[review] 
        itemsForSale[id - 1].askingPrice = 0;

    }
    // 1. ITEM is for sale 2. address(this) has approval
    function BuyItem(uint256 id) external payable ItemExists(id) HasTransferApproval(itemsForSale[id-1].tokenAddress, itemsForSale[id-1].tokenId) {
        require(activeItems[itemsForSale[id - 1].tokenAddress][itemsForSale[id-1].tokenId],'Item not listed in market');
        require(itemsForSale[id-1].isSold == false,"Item already sold");
        require(itemsForSale[id-1].bidItem == false, "Item not for instant buy");
        IERC721 Collection = IERC721(itemsForSale[id - 1].tokenAddress);
        address itemOwner = Collection.ownerOf(itemsForSale[id - 1].tokenId);
        require(msg.sender != itemOwner, "Seller cannot buy item");

        if(itemsForSale[id-1].ERC20 == address(0)){
            require(msg.value >= itemsForSale[id - 1].askingPrice, "Not enough funds set");
            _buyitemSimple(id);
        }else{
            _buyitemERC(id);
        }
    }

    function printOwner(address _collectionAddress) public view returns(address){
        return IERC721(_collectionAddress).collectionOwner();
    }

    function _buyitemSimple(uint256 id) internal{
        IERC721 Collection = IERC721(itemsForSale[id - 1].tokenAddress);
        address itemOwner = Collection.ownerOf(itemsForSale[id - 1].tokenId);

        uint256 sFee = _calculateServiceFee(msg.value);
        uint256 aFee = _calculateAggregatorFee(msg.value);
        uint256 rFee = _calculateRoyaltyFee(msg.value, Collection.Fee());


        (bool success, ) = itemOwner.call{value: msg.value.sub(sFee).sub(aFee).sub(rFee)}("");
        //(bool success, ) = itemOwner.call{value: msg.value}("");
        require(success, "Failed to send Ether");

        (bool success1, ) = feeAddress.call{value: sFee}("");
        require(success1, "Failed to send Ether (Service FEE)");

        if(aFee > 0){
            (bool success3, ) = feeAggregatorAddress.call{value: aFee}("");
            require(success3, "Failed to send Ether (Aggregator FEE)");
        }

        if(rFee > 0){
            (bool success2, ) = Collection.collectionOwner().call{value: rFee}("");
            require(success2, "Failed to send Ether");
        }
        itemsForSale[id - 1].isSold = true;
        activeItems[itemsForSale[id - 1].tokenAddress][itemsForSale[id - 1].tokenId] = false;
        IERC721(itemsForSale[id - 1].tokenAddress).safeTransferFrom(Collection.ownerOf(itemsForSale[id - 1].tokenId), msg.sender, itemsForSale[id - 1].tokenId);
        //itemsForSale[id - 1].seller.transfer(msg.value);

        //itemsForSale[id - 1].seller = payable(msg.sender);
        emit ItemSold(id, msg.sender, itemsForSale[id - 1].askingPrice); // TODO:[INFO] askingPrice => actual msg.value? no refund?
    }

    function _buyitemERC(uint256 id) internal{
        IERC20Upgradeable tokenERC = IERC20Upgradeable(itemsForSale[id-1].ERC20);
        IERC721 Collection = IERC721(itemsForSale[id - 1].tokenAddress);
        address itemOwner = Collection.ownerOf(itemsForSale[id - 1].tokenId);
        uint256 val =  itemsForSale[id - 1].askingPrice;
        require(tokenERC.allowance(msg.sender,address(this)) >= val , "Not enough token funds");
        uint256 sFee = _calculateServiceFee(val);
        uint256 aFee = _calculateAggregatorFee(val);
        uint256 rFee = _calculateRoyaltyFee(val, Collection.Fee());
        if(itemsForSale[id-1].ERC20 == empireToken){                            // empireToken only sub rFee
            tokenERC.transferFrom(msg.sender,itemOwner, itemsForSale[id - 1].askingPrice.sub(rFee));
            if(rFee > 0){
                tokenERC.transferFrom(msg.sender,Collection.collectionOwner(), rFee);
            }
        }else{
            tokenERC.transferFrom(msg.sender,itemOwner, val.sub(sFee).sub(aFee).sub(rFee));
            tokenERC.transferFrom(msg.sender,feeAddress, sFee);
            if(aFee > 0){
                tokenERC.transferFrom(msg.sender,feeAggregatorAddress, aFee);
            }
            if(rFee > 0){
                tokenERC.transferFrom(msg.sender,Collection.collectionOwner(), rFee);
            }
        }

        itemsForSale[id - 1].isSold = true;
        itemsForSale[id - 1].ERC20 = address(0);
        activeItems[itemsForSale[id - 1].tokenAddress][itemsForSale[id - 1].tokenId] = false;
        IERC721(itemsForSale[id - 1].tokenAddress).safeTransferFrom(Collection.ownerOf(itemsForSale[id - 1].tokenId), msg.sender, itemsForSale[id - 1].tokenId);
        //itemsForSale[id - 1].seller.transfer(msg.value);

        //itemsForSale[id - 1].seller = payable(msg.sender);
        emit ItemSold(id, msg.sender, itemsForSale[id - 1].askingPrice);
    }

    function _calculateServiceFee(uint256 _amount) public view returns(uint256){
        return _amount.mul(serviceFee-AggregatorFee).div( // : loss of precision, use `sub` so it is ok
            10**4
        );
    }

    function _calculateAggregatorFee(uint256 _amount) public view returns(uint256){
        return _amount.mul(AggregatorFee).div(
            10**4
        );
    }

    function _calculateRoyaltyFee(uint256 _amount, uint256 _royalty) public pure returns(uint256){
        return _amount.mul(_royalty).div(
            10**4
        );
    }

    function addERC20tokens(address erc20) public onlyOwner{
        validERC[erc20] = true;  // todo no emit event & no 0 address validation
    }

    function removeERC20tokens(address erc20) public onlyOwner{
        validERC[erc20] = false;  // todo no emit event & no 0 address validation
    }

    // put a bid on an item
    // modifiers: ItemExists, IsForSale, IsForBid, HasTransferApproval
    // args: auctionItemId
    // check if a bid already exists, if yes: check if this bid value is higher then prev

    function PlaceABid(uint256 aucItemId, uint256 amount) external payable ItemExists(aucItemId) HasTransferApproval(itemsForSale[aucItemId-1].tokenAddress, itemsForSale[aucItemId-1].tokenId) {
        require(activeItems[itemsForSale[aucItemId - 1].tokenAddress][itemsForSale[aucItemId-1].tokenId],'Item not listed in market');
        require(itemsForSale[aucItemId-1].isSold == false,"Item already sold");
        require(itemsForSale[aucItemId-1].bidItem == true, "Item not for bidding");

        if(itemsForSale[aucItemId-1].ERC20 == address(0)){
            require(msg.value >= itemsForSale[aucItemId - 1].askingPrice, "Not enough funds set");
            _placeBidSimple(aucItemId);
        }else{
            _placeBidERC(aucItemId, amount);
        }
    }
    function _placeBidSimple(uint256 id) internal{
        uint256 totalPrice = 0;
        if (pendingReturns[msg.sender][address(0)][itemsForSale[id-1].id] == 0){
            totalPrice = msg.value; // first bid
        }
        else{
            totalPrice = msg.value + pendingReturns[msg.sender][address(0)][itemsForSale[id-1].id];
        }
        require(totalPrice > itemsForSale[id-1].askingPrice, "There is already a higher asking price");
        require(totalPrice > itemsForSale[id-1].bidPrice, "There is already a higher price");

        pendingReturns[msg.sender][address(0)][itemsForSale[id-1].id] = 0;
        if (itemsForSale[id - 1].bidPrice != 0){
            pendingReturns[itemsForSale[id-1].bidderAddress][address(0)][itemsForSale[id-1].id] = itemsForSale[id-1].bidPrice;
        }
        itemsForSale[id-1].bidPrice = totalPrice;
        itemsForSale[id-1].bidderAddress = msg.sender;

        emit BidPlaced(itemsForSale[id-1].tokenId,msg.sender,totalPrice,itemsForSale[id-1].tokenAddress);
    }
    function _placeBidERC(uint256 id, uint256 amount) internal{
        uint256 totalPrice = 0;
        IERC20Upgradeable tokenERC = IERC20Upgradeable(itemsForSale[id-1].ERC20);
        require(tokenERC.allowance(msg.sender,address(this)) >= amount , "Not enough token funds");

        if (pendingReturns[msg.sender][itemsForSale[id-1].ERC20][itemsForSale[id-1].id] == 0){
            totalPrice = amount;
        }
        else{
            totalPrice = amount + pendingReturns[msg.sender][itemsForSale[id-1].ERC20][itemsForSale[id-1].id];
        }
        require(totalPrice > itemsForSale[id-1].askingPrice, "There is already a higher asking price");
        require(totalPrice > itemsForSale[id-1].bidPrice, "There is already a higher price");
        tokenERC.transferFrom(msg.sender,address(this),amount);
        pendingReturns[msg.sender][itemsForSale[id-1].ERC20][itemsForSale[id-1].id] = 0;
        if (itemsForSale[id - 1].bidPrice != 0){
            pendingReturns[itemsForSale[id-1].bidderAddress][itemsForSale[id-1].ERC20][itemsForSale[id-1].id] = itemsForSale[id-1].bidPrice;
        }
        itemsForSale[id-1].bidPrice = totalPrice;
        itemsForSale[id-1].bidderAddress = msg.sender; // : no emit
    }
    function withdrawPrevBid(uint256 aucItemId,address _erc20) external returns(bool) {
        uint256 amount = pendingReturns[msg.sender][_erc20][aucItemId];
        require(amount > 0, 'No Amount To Withdraw');
        if (amount > 0){
            pendingReturns[msg.sender][_erc20][aucItemId] = 0;
            if(_erc20 == address(0)){
                if (!payable(msg.sender).send(amount)) {
                    // No need to call throw here, just reset the amount owing
                    pendingReturns[msg.sender][_erc20][aucItemId] = amount;
                    return false;
                }
            }else{
                IERC20Upgradeable(_erc20).transfer(msg.sender, amount);
            }
        }
        return true;
    }
    function EndAuction(uint256 aucItemId) external payable ItemExists(aucItemId) OnlyItemOwnerAuc(aucItemId) HasTransferApproval(itemsForSale[aucItemId-1].tokenAddress, itemsForSale[aucItemId-1].tokenId){
        require(activeItems[itemsForSale[aucItemId - 1].tokenAddress][itemsForSale[aucItemId-1].tokenId],'Item not listed in market');
        //require(itemsForSale[aucItemId - 1].bidPrice > itemsForSale[aucItemId - 1].askingPrice, "No Bids Exist!");
        require(itemsForSale[aucItemId-1].isSold == false,"Item already sold");
        require(itemsForSale[aucItemId-1].bidItem == true, "Item not for bidding");
        //just EndAuction
        if(itemsForSale[aucItemId-1].bidPrice == 0){
            _endAuctionOnly(aucItemId);
        }
        //End And Distribute bidPrice
        else if(itemsForSale[aucItemId-1].ERC20 == address(0)){
            //require(msg.value >= itemsForSale[aucItemId - 1].askingPrice, "Not enough funds set");
            _endAuctionSimple(aucItemId);
        }else{
            _endAuctionERC(aucItemId);
        }
    }
    function _endAuctionSimple(uint256 id) internal{
        IERC721 Collection = IERC721(itemsForSale[id - 1].tokenAddress);
        address itemOwner = Collection.ownerOf(itemsForSale[id - 1].tokenId);
        uint256 sFee = _calculateServiceFee(itemsForSale[id - 1].bidPrice);
        uint256 aFee = _calculateAggregatorFee(itemsForSale[id-1].bidPrice);
        uint256 rFee = _calculateRoyaltyFee(itemsForSale[id - 1].bidPrice, Collection.Fee());
        (bool success, ) = itemOwner.call{value: itemsForSale[id - 1].bidPrice.sub(sFee).sub(aFee).sub(rFee)}("");
        require(success, "Failed to send Ether");
        (bool success1, ) = feeAddress.call{value: sFee}("");
        require(success1, "Failed to send Ether");
        if(aFee > 0){
            (bool success3, ) = feeAggregatorAddress.call{value: aFee}("");
            require(success3, "Failed to send Ether");
        }
        if(rFee > 0){
            (bool success2, ) = Collection.collectionOwner().call{value: rFee}("");
            require(success2, "Failed to send Ether");
        }
        Collection.safeTransferFrom(itemOwner, itemsForSale[id - 1].bidderAddress, itemsForSale[id - 1].tokenId);
        activeItems[itemsForSale[id - 1].tokenAddress][itemsForSale[id - 1].tokenId] = false;
        itemsForSale[id - 1].isSold = true;
        pendingReturns[itemsForSale[id - 1].bidderAddress][address(0)][itemsForSale[id - 1].tokenId] = 0;
        //itemsForSale[aucItemId - 1].seller = payable(itemsForSale[aucItemId - 1].bidderAddress);
        itemsForSale[id - 1].bidderAddress = address(0);
        itemsForSale[id - 1].bidPrice = 0;
        itemsForSale[id - 1].bidItem = false;
    }
    function _endAuctionERC(uint256 id) internal{
        IERC20Upgradeable tokenERC = IERC20Upgradeable(itemsForSale[id-1].ERC20);
        IERC721 Collection = IERC721(itemsForSale[id - 1].tokenAddress);
        address itemOwner = Collection.ownerOf(itemsForSale[id - 1].tokenId);
        uint256 val = itemsForSale[id - 1].bidPrice;
        uint256 sFee = _calculateServiceFee(val);
        uint256 aFee = _calculateAggregatorFee(val);
        uint256 rFee = _calculateRoyaltyFee(val, Collection.Fee());

        if(itemsForSale[id-1].ERC20 == empireToken){
            tokenERC.transfer(itemOwner, val.sub(rFee));
            if(rFee > 0){
                tokenERC.transfer(Collection.collectionOwner(), rFee);
            }
        }else{
            tokenERC.transfer(itemOwner, val.sub(sFee).sub(aFee).sub(rFee));
            tokenERC.transfer(feeAddress, sFee);
            if(aFee > 0){
                tokenERC.transfer(feeAggregatorAddress, aFee);
            }
            if(rFee > 0){
                tokenERC.transfer(Collection.collectionOwner(), rFee);
            }
        }
        Collection.safeTransferFrom(itemOwner, itemsForSale[id - 1].bidderAddress, itemsForSale[id - 1].tokenId);
        activeItems[itemsForSale[id - 1].tokenAddress][itemsForSale[id - 1].tokenId] = false;
        itemsForSale[id - 1].isSold = true;
        pendingReturns[itemsForSale[id - 1].bidderAddress][itemsForSale[id-1].ERC20][itemsForSale[id - 1].tokenId] = 0;
        //itemsForSale[aucItemId - 1].seller = payable(itemsForSale[aucItemId - 1].bidderAddress);
        itemsForSale[id - 1].bidderAddress = address(0);
        itemsForSale[id - 1].bidPrice = 0;
        itemsForSale[id - 1].bidItem = false;
        itemsForSale[id - 1].ERC20 = address(0);
    }
    function _endAuctionOnly(uint256 id) internal{
        activeItems[itemsForSale[id - 1].tokenAddress][itemsForSale[id - 1].tokenId] = false;
        itemsForSale[id - 1].isSold = true;
        pendingReturns[itemsForSale[id - 1].bidderAddress][address(0)][itemsForSale[id - 1].tokenId] = 0;
        //itemsForSale[aucItemId - 1].seller = payable(itemsForSale[aucItemId - 1].bidderAddress);
        itemsForSale[id - 1].bidderAddress = address(0);
        itemsForSale[id - 1].bidPrice = 0;
        itemsForSale[id - 1].bidItem = false; // TODO [INFO] erc20? 
    }
}