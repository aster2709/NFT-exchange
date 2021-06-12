//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./EnumerableMap.sol";

contract ExchangeNFT is ERC721Holder, Ownable, Pausable {
    // using Address for address;
    using EnumerableMap for EnumerableMap.UintToUintMap;
    using EnumerableSet for EnumerableSet.UintSet;

    struct Listing {
        uint256 tokenId;
        uint256 price;
    }

    uint256 public MAX_TRADABLE_TOKEN_ID = 10000;

    IERC721 public nft;
    IERC20 public quoteERC20;

    EnumerableMap.UintToUintMap private listings;

    mapping(uint256 => address) public tokenSellers;
    mapping(address => EnumerableSet.UintSet) private _userSellingTokens;

    event Trade(
        address indexed seller,
        address indexed buyer,
        uint256 indexed tokenId,
        uint256 price
    );
    event List(address indexed seller, uint256 indexed tokenId, uint256 price);
    event Unlist(address indexed seller, uint256 indexed tokenId);
    event UpdateMaxTradableTokenId(uint256 indexed oldId, uint256 newId);

    constructor(address _nft, address _quoteERC20) {
        require(_nft != address(0) && _quoteERC20 != address(0));
        nft = IERC721(_nft);
        quoteERC20 = IERC20(_quoteERC20);
    }

    function buyToken(uint256 _tokenId) public whenNotPaused {
        require(listings.contains(_tokenId), "Token not in sell book");
        uint256 price = listings.get(_tokenId);
        require(
            quoteERC20.transferFrom(msg.sender, tokenSellers[_tokenId], price),
            "Transfer from failed"
        );
        nft.safeTransferFrom(address(this), msg.sender, _tokenId);
        listings.remove(_tokenId);
        _userSellingTokens[tokenSellers[_tokenId]].remove(_tokenId);
        delete tokenSellers[_tokenId];
        emit Trade(tokenSellers[_tokenId], msg.sender, _tokenId, price);
    }

    function changeListingPrice(uint256 _tokenId, uint256 _price)
        public
        whenNotPaused
    {
        require(
            tokenSellers[_tokenId] == msg.sender,
            "Only seller can change listing price"
        );
        require(_price > 0, "Price must be granter than zero");
        listings.set(_tokenId, _price);
        emit List(msg.sender, _tokenId, _price);
    }

    function createListing(uint256 _tokenId, uint256 _price)
        public
        whenNotPaused
    {
        require(
            msg.sender == nft.ownerOf(_tokenId),
            "Only Token Owner can sell token"
        );
        require(
            tokenSellers[_tokenId] != msg.sender,
            "Token listing already exists"
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
        emit List(msg.sender, _tokenId, _price);
    }

    function removeListing(uint256 _tokenId) public whenNotPaused {
        require(
            tokenSellers[_tokenId] == msg.sender,
            "only seller can remove listing"
        );
        nft.safeTransferFrom(address(this), msg.sender, _tokenId);
        listings.remove(_tokenId);
        _userSellingTokens[tokenSellers[_tokenId]].remove(_tokenId);
        delete tokenSellers[_tokenId];
        emit Unlist(msg.sender, _tokenId);
    }

    function totalListings() public view returns (uint256) {
        return listings.length();
    }

    function getAllListings() public view returns (Listing[] memory) {
        Listing[] memory list = new Listing[](listings.length());
        for (uint256 i = 1; i <= listings.length(); i++) {
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

    // function getAsksByPage(uint256 page, uint256 size)
    //     public
    //     view
    //     returns (AskEntry[] memory)
    // {
    //     if (_asksMap.length() > 0) {
    //         uint256 from = page == 0 ? 0 : (page - 1) * size;
    //         uint256 to =
    //             Math.min((page == 0 ? 1 : page) * size, _asksMap.length());
    //         AskEntry[] memory asks = new AskEntry[]((to - from));
    //         for (uint256 i = 0; from < to; ++i) {
    //             (uint256 tokenId, uint256 price) = _asksMap.at(from);
    //             asks[i] = AskEntry({tokenId: tokenId, price: price});
    //             ++from;
    //         }
    //         return asks;
    //     } else {
    //         return new AskEntry[](0);
    //     }
    // }

    // function getAsksByPageDesc(uint256 page, uint256 size)
    //     public
    //     view
    //     returns (AskEntry[] memory)
    // {
    //     if (_asksMap.length() > 0) {
    //         uint256 from =
    //             _asksMap.length() - 1 - (page == 0 ? 0 : (page - 1) * size);
    //         uint256 to =
    //             _asksMap.length() -
    //                 1 -
    //                 Math.min(
    //                     (page == 0 ? 1 : page) * size - 1,
    //                     _asksMap.length() - 1
    //                 );
    //         uint256 resultSize = from - to + 1;
    //         AskEntry[] memory asks = new AskEntry[](resultSize);
    //         if (to == 0) {
    //             for (uint256 i = 0; from > to; ++i) {
    //                 (uint256 tokenId, uint256 price) = _asksMap.at(from);
    //                 asks[i] = AskEntry({tokenId: tokenId, price: price});
    //                 --from;
    //             }
    //             (uint256 tokenId, uint256 price) = _asksMap.at(0);
    //             asks[resultSize - 1] = AskEntry({
    //                 tokenId: tokenId,
    //                 price: price
    //             });
    //         } else {
    //             for (uint256 i = 0; from >= to; ++i) {
    //                 (uint256 tokenId, uint256 price) = _asksMap.at(from);
    //                 asks[i] = AskEntry({tokenId: tokenId, price: price});
    //                 --from;
    //             }
    //         }
    //         return asks;
    //     }
    //     return new AskEntry[](0);
    // }

    function getListingsByUser(address user)
        public
        view
        returns (Listing[] memory)
    {
        Listing[] memory list =
            new Listing[](_userSellingTokens[user].length());
        for (uint256 i = 1; i <= _userSellingTokens[user].length(); i++) {
            uint256 tokenId = _userSellingTokens[user].at(i);
            uint256 price = listings.get(tokenId);
            list[i] = Listing({tokenId: tokenId, price: price});
        }
        return list;
    }

    // function getAsksByUserDesc(address user)
    //     public
    //     view
    //     returns (AskEntry[] memory)
    // {
    //     AskEntry[] memory asks =
    //         new AskEntry[](_userSellingTokens[user].length());
    //     if (_userSellingTokens[user].length() > 0) {
    //         for (
    //             uint256 i = _userSellingTokens[user].length() - 1;
    //             i > 0;
    //             --i
    //         ) {
    //             uint256 tokenId = _userSellingTokens[user].at(i);
    //             uint256 price = _asksMap.get(tokenId);
    //             asks[_userSellingTokens[user].length() - 1 - i] = AskEntry({
    //                 tokenId: tokenId,
    //                 price: price
    //             });
    //         }
    //         uint256 tokenId = _userSellingTokens[user].at(0);
    //         uint256 price = _asksMap.get(tokenId);
    //         asks[_userSellingTokens[user].length() - 1] = AskEntry({
    //             tokenId: tokenId,
    //             price: price
    //         });
    //     }
    //     return asks;
    // }

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
