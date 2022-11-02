// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";

contract EmpireCollectionV2 is Initializable,ERC721Upgradeable {
    uint _tokenIds;

    uint256 public royalty; //percent divisible to 1000 like 500 is actually 5%
    uint256 public totalSupply;
    mapping (uint => address) itemCreator;
    mapping (uint => string) Items;
    address public collectionOwner;
    address public hello;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    function initialize(string memory _name, string memory _symbol, uint256 _royalty) public initializer  {
        ERC721Upgradeable.__ERC721_init(_name, _symbol);
        royalty = _royalty;
        collectionOwner = msg.sender;
        _tokenIds  = 1000;
    }

    modifier onlyOwner{
        require(msg.sender == collectionOwner, 'Only Owner Can Execute');
        _;
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(collectionOwner, newOwner);
        collectionOwner = newOwner;
    }

    function createItem(string memory uri) public {
        _tokenIds++;
        _safeMint(msg.sender, _tokenIds);
        totalSupply += 1;
        Items[_tokenIds] = uri;
        itemCreator[_tokenIds] = msg.sender;
    }


    function bulkMinter(uint numOfTokens, string memory uri)public virtual {
        require( numOfTokens <= 40, "Number of Collections Exceeds Count");
        uint i;
        for (i = _tokenIds+1; i < numOfTokens+_tokenIds+1; i++) {
            _safeMint(msg.sender, i);
            Items[i] = uri;
            itemCreator[i] = msg.sender;
        }
        _tokenIds = i;
        totalSupply += numOfTokens;
    }

    function bulkTransfer(address[] memory to, uint[] memory tokenIds) public virtual{
        require( to.length == tokenIds.length, "Lenght not matched, Invalid Format");
        require( to.length <= 40, "You can transfer max 40 tokens");
        for(uint i = 0; i < to.length; i++){
            safeTransferFrom(msg.sender, to[i], tokenIds[i]);
        }
    }

    function multiSendTokens(address to, uint[] memory tokenIds) public virtual{
        require( tokenIds.length <= 40, "You can transfer max 40 tokens");
        for(uint i = 0; i < tokenIds.length; i++){
            safeTransferFrom(msg.sender, to, tokenIds[i]);
        }
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        return Items[tokenId];
    }

    function tokenCreator(uint256 tokenId) public view returns (address) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        return itemCreator[tokenId];
    }

    function setRoyalty(uint256 _royalty) public onlyOwner{
        require(_royalty < 3000,'Royalty must less than 30%');
        royalty = _royalty;
    }

    function Fee() public view returns (uint256){
        return royalty;
    }
} 