//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./EnumerableMap.sol";
import "hardhat/console.sol";

contract ExchangeNFT is ERC721Holder, Ownable, Pausable {
    using EnumerableMap for EnumerableMap.UintToUintMap;
    using EnumerableSet for EnumerableSet.UintSet;

    uint256 public MAX_TRADABLE_TOKEN_ID = 10000;

    IERC721 public nft;
    IERC20 public quoteERC20;

    EnumerableMap.UintToUintMap private listings;

    mapping(uint256 => address) public tokenSellers;
    mapping(address => EnumerableSet.UintSet) private _userSellingTokens;

    // tokenId to bid array, eg tokenId 5 => [1000 erc20, 2000 erc20, 3000 erc20]
    mapping(uint256 => uint256[]) public tokenBids;

    // tracks index of the bidder in the bid array and vice versa
    mapping(uint256 => mapping(uint256 => address)) public indexToAddress;
    mapping(uint256 => mapping(address => uint256)) public addressToIndex;

    // users bid on a particular token
    mapping(address => mapping(uint256 => uint256)) public userBids;

    event Trade(
        address indexed seller,
        address indexed buyer,
        uint256 indexed tokenId,
        uint256 price
    );
    event List(address indexed seller, uint256 indexed tokenId, uint256 price);
    event Unlist(address indexed seller, uint256 indexed tokenId);
    event UpdateMaxTradableTokenId(uint256 indexed oldId, uint256 newId);

    event Bid(address indexed bidder, uint256 indexed tokenId, uint256 amount);
    event Unbid(
        address indexed bidder,
        uint256 indexed tokenId,
        uint256 amount
    );

    modifier listingExists(uint256 _tokenId) {
        require(listings.contains(_tokenId), "listing doesnt exist");
        _;
    }

    constructor(address _nft, address _quoteERC20) {
        require(_nft != address(0) && _quoteERC20 != address(0));
        nft = IERC721(_nft);
        quoteERC20 = IERC20(_quoteERC20);
    }

    function createListing(uint256 _tokenId, uint256 _price)
        public
        whenNotPaused
    {
        require(!listings.contains(_tokenId), "listing already exists");
        require(
            msg.sender == nft.ownerOf(_tokenId),
            "you are not the owner of this token"
        );
        require(_price > 0, "Price must be granter than zero");
        require(
            _tokenId <= MAX_TRADABLE_TOKEN_ID,
            "TokenId must be less than MAX_TRADABLE_TOKEN_ID"
        );
        nft.safeTransferFrom(msg.sender, address(this), _tokenId);
        listings.set(_tokenId, _price);
        tokenSellers[_tokenId] = msg.sender;
        _userSellingTokens[msg.sender].add(_tokenId);

        tokenBids[_tokenId].push();
        emit List(msg.sender, _tokenId, _price);
    }

    function changeListingPrice(uint256 _tokenId, uint256 _price)
        public
        listingExists(_tokenId)
        whenNotPaused
    {
        require(
            tokenSellers[_tokenId] == msg.sender,
            "only seller can change listing price"
        );
        require(_price > 0, "Price must be granter than zero");

        listings.set(_tokenId, _price);

        emit List(msg.sender, _tokenId, _price);
    }

    function removeListing(uint256 _tokenId)
        public
        listingExists(_tokenId)
        whenNotPaused
    {
        require(
            tokenSellers[_tokenId] == msg.sender,
            "only seller can remove listing"
        );

        nft.safeTransferFrom(address(this), msg.sender, _tokenId);

        uint256 length = tokenBids[_tokenId].length;

        // clearing listing
        listings.remove(_tokenId);
        delete tokenSellers[_tokenId];
        _userSellingTokens[tokenSellers[_tokenId]].remove(_tokenId);

        // clearing bids
        for (uint256 i = 0; i < length; i++) {
            address addr = indexToAddress[_tokenId][i];
            delete indexToAddress[_tokenId][i];
            delete addressToIndex[_tokenId][addr];
            delete userBids[addr][_tokenId];
        }
        delete tokenBids[_tokenId];

        emit Unlist(msg.sender, _tokenId);
    }

    function buyToken(uint256 _tokenId)
        public
        listingExists(_tokenId)
        whenNotPaused
    {
        uint256 price = listings.get(_tokenId);
        require(
            quoteERC20.transferFrom(msg.sender, tokenSellers[_tokenId], price),
            "TransferFrom failed"
        );
        nft.safeTransferFrom(address(this), msg.sender, _tokenId);

        uint256 length = tokenBids[_tokenId].length;

        // clearing listing
        listings.remove(_tokenId);
        delete tokenSellers[_tokenId];
        _userSellingTokens[tokenSellers[_tokenId]].remove(_tokenId);

        // clearing bids
        for (uint256 i = 0; i < length; i++) {
            address addr = indexToAddress[_tokenId][i];
            delete indexToAddress[_tokenId][i];
            delete addressToIndex[_tokenId][addr];
            delete userBids[addr][_tokenId];
        }
        delete tokenBids[_tokenId];

        emit Trade(tokenSellers[_tokenId], msg.sender, _tokenId, price);
    }

    // eg
    // tokenBids: [0 erc20, 1000 erc20, 2000 erc20, 3000 erc20]
    // indexToAddress: 0 => 0x00, 1 => 0x094, 2 => 0x064, 3 => 0x45
    // addressToIndex: 0x00 => 0, 0x094 => 1, 0x064 => 2, 0x45 => 3;
    function bidOnToken(uint256 _tokenId, uint256 _amount)
        public
        whenNotPaused
    {
        require(listings.contains(_tokenId), "listing doesnt exist");
        require(
            userBids[msg.sender][_tokenId] == 0,
            "you already have a bid, cancel it first"
        );
        uint256 length = tokenBids[_tokenId].length;
        require(
            _amount > tokenBids[_tokenId][length - 1],
            "bid should be greater than previous bidder"
        );

        tokenBids[_tokenId].push(_amount);
        length = tokenBids[_tokenId].length;
        indexToAddress[_tokenId][length - 1] = msg.sender;
        addressToIndex[_tokenId][msg.sender] = length - 1;
        userBids[msg.sender][_tokenId] = _amount;

        emit Bid(msg.sender, _tokenId, _amount);
    }

    // eg
    // tokenBids: [0 erc20, 1000 erc20, 2000 erc20, 3000 erc20]
    // indexToAddress: 0 => 0x00, 1 => 0x094, 2 => 0x064, 3 => 0x45
    // addressToIndex: 0x00 => 0, 0x094 => 1, 0x064 => 2, 0x45 => 3;
    function cancelBid(uint256 _tokenId) public whenNotPaused {
        require(listings.contains(_tokenId), "listing doesnt exist");
        require(
            userBids[msg.sender][_tokenId] != 0,
            "you dont have a bid on this listing"
        );
        uint256 index = addressToIndex[_tokenId][msg.sender];
        uint256 length = tokenBids[_tokenId].length;

        if (index == length - 1) {
            tokenBids[_tokenId].pop();
            delete indexToAddress[_tokenId][index];
        } else {
            for (uint256 i = index; i < length - 1; i++) {
                tokenBids[_tokenId][i] = tokenBids[_tokenId][i + 1];
                indexToAddress[_tokenId][i] = indexToAddress[_tokenId][i + 1];
            }
            tokenBids[_tokenId].pop();
        }
        delete addressToIndex[_tokenId][msg.sender];
        delete userBids[msg.sender][_tokenId];
    }

    function sellViaBidding(uint256 _tokenId)
        public
        listingExists(_tokenId)
        whenNotPaused
    {
        require(
            tokenSellers[_tokenId] == msg.sender,
            "only owner of token can call"
        );

        uint256 length = tokenBids[_tokenId].length;
        uint256 price = tokenBids[_tokenId][length - 1];
        address buyer = indexToAddress[_tokenId][length - 1];
        address seller = tokenSellers[_tokenId];
        require(quoteERC20.transferFrom(buyer, seller, price));
        nft.safeTransferFrom(address(this), buyer, _tokenId);

        // clearing listing
        listings.remove(_tokenId);
        delete tokenSellers[_tokenId];
        _userSellingTokens[msg.sender].remove(_tokenId);

        // clearing bids
        for (uint256 i = 0; i < length; i++) {
            address addr = indexToAddress[_tokenId][i];
            delete indexToAddress[_tokenId][i];
            delete addressToIndex[_tokenId][addr];
            delete userBids[addr][_tokenId];
        }
        delete tokenBids[_tokenId];

        emit Trade(seller, buyer, _tokenId, price);
    }

    // helper methods

    struct Listing {
        uint256 tokenId;
        uint256 price;
    }

    function totalListings() public view returns (uint256) {
        return listings.length();
    }

    function getAllListings() public view returns (Listing[] memory) {
        Listing[] memory list = new Listing[](listings.length());
        for (uint256 i = 0; i < listings.length(); i++) {
            (uint256 tokenId, uint256 price) = listings.at(i);
            list[i] = Listing({tokenId: tokenId, price: price});
        }
        return list;
    }

    function getAllListingsInReverse() public view returns (Listing[] memory) {
        Listing[] memory list = new Listing[](listings.length());
        for (uint256 i = listings.length(); i > 0; i--) {
            (uint256 tokenId, uint256 price) = listings.at(i);
            list[listings.length() - i] = Listing({
                tokenId: tokenId,
                price: price
            });
        }

        return list;
    }

    function getListingsByUser(address user)
        public
        view
        returns (Listing[] memory)
    {
        Listing[] memory list =
            new Listing[](_userSellingTokens[user].length());
        for (uint256 i = 0; i < _userSellingTokens[user].length(); i++) {
            uint256 tokenId = _userSellingTokens[user].at(i);
            uint256 price = listings.get(tokenId);
            list[i] = Listing({tokenId: tokenId, price: price});
        }
        return list;
    }

    function getBidByUser(uint256 _tokenId, address addr)
        public
        view
        returns (uint256)
    {
        return userBids[addr][_tokenId];
    }

    function getAllBids(uint256 _tokenId)
        public
        view
        returns (uint256[] memory)
    {
        return tokenBids[_tokenId];
    }

    function getMaxBidder(uint256 _tokenId) public view returns (address) {
        return indexToAddress[_tokenId][tokenBids[_tokenId].length - 1];
    }

    function pause() public onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() public onlyOwner whenPaused {
        _unpause();
    }

    function updateMaxTradableTokenId(uint256 _max_tradable_token_id)
        public
        onlyOwner
    {
        emit UpdateMaxTradableTokenId(
            MAX_TRADABLE_TOKEN_ID,
            _max_tradable_token_id
        );
        MAX_TRADABLE_TOKEN_ID = _max_tradable_token_id;
    }
}
