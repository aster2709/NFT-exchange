import { ethers } from "hardhat";
import { Signer } from "ethers";
import {
  NFT,
  MyToken,
  ExchangeNFT,
  NFT__factory,
  MyToken__factory,
  ExchangeNFT__factory,
} from "../typechain";
import { expect } from "chai";

describe("Tests Suite", function () {
  let NFTArtifact: NFT__factory,
    MyTokenArtifact: MyToken__factory,
    ExchangeNFTArtifact: ExchangeNFT__factory;
  let nft: NFT,
    myToken: MyToken,
    exchangeNFT: ExchangeNFT,
    signers: Signer[],
    signer: Signer;

  before(async function () {
    NFTArtifact = (await ethers.getContractFactory("NFT")) as NFT__factory;
    ExchangeNFTArtifact = (await ethers.getContractFactory(
      "ExchangeNFT"
    )) as ExchangeNFT__factory;
    MyTokenArtifact = (await ethers.getContractFactory(
      "MyToken"
    )) as MyToken__factory;
  });
  beforeEach(async function () {
    nft = await NFTArtifact.deploy();
    myToken = await MyTokenArtifact.deploy();
    await myToken.mint();
    exchangeNFT = await ExchangeNFTArtifact.deploy(
      nft.address,
      myToken.address
    );
    signers = await ethers.getSigners();
    signer = signers[0];
    await myToken.approve(exchangeNFT.address, ethers.utils.parseEther("1000"));
  });

  describe("NFT Tests", function () {
    it("creates an NFT", async function () {
      const addr = await signer.getAddress();

      await expect(nft.mint(addr))
        .to.emit(nft, "Transfer")
        .withArgs(ethers.constants.AddressZero, addr, 0);
    });
    it("has correct tokenURI", async function () {
      const addr = await signer.getAddress();

      await nft.mint(addr);
      expect(await nft.balanceOf(addr)).to.equal(1);
      expect(await nft.tokenURI(0)).to.equal(
        "https://my-json-server.typicode.com/aster2709/json-server/tokens/0"
      );
    });
  });

  describe("ERC20 Tests", function () {
    it("creates an erc20", async function () {
      const addr = await signer.getAddress();
      expect(await myToken.balanceOf(addr)).to.equal(
        ethers.utils.parseEther("1000")
      );
    });
  });

  describe("Listing Tests", function () {
    let addr: any;
    beforeEach(async function () {
      addr = await signer.getAddress();
      await nft.mint(addr);
      await nft.setApprovalForAll(exchangeNFT.address, true);

      await exchangeNFT.createListing(0, ethers.utils.parseEther("20"));
    });
    it("creates a listing", async function () {
      expect(await exchangeNFT.totalListings()).to.equal(1);
      const res = await exchangeNFT.getAllListings();
      expect(res[0].tokenId).to.equal(0);
      expect(res[0].price).to.equal(ethers.utils.parseEther("20"));
    });
    it("changes listing price", async function () {
      await expect(
        exchangeNFT.changeListingPrice(0, ethers.utils.parseEther("10"))
      )
        .to.emit(exchangeNFT, "List")
        .withArgs(addr, 0, ethers.utils.parseEther("10"));
    });
    it("removes listing", async function () {
      expect(await exchangeNFT.removeListing(0))
        .to.emit(exchangeNFT, "Unlist")
        .withArgs(addr, 0);
    });
    it("sells listing", async function () {
      expect(await nft.ownerOf(0)).to.not.equal(addr);
      await exchangeNFT.buyToken(0);
      expect(await nft.ownerOf(0)).to.equal(addr);
      expect(await exchangeNFT.getAllListings()).to.be.an("array").that.is
        .empty;
      expect(await exchangeNFT.getAllBids(0)).to.be.an("array").that.is.empty;
    });
  });

  describe("Bidding Tests", function () {
    let addr: any, signer2: Signer, addr2: any, signer3: Signer, addr3: any;
    beforeEach(async function () {
      addr = await signer.getAddress();
      await nft.setApprovalForAll(exchangeNFT.address, true);
      signer2 = await signers[1];
      addr2 = await signer2.getAddress();
      signer3 = signers[2];
      addr3 = await signer3.getAddress();
      await myToken.connect(signer2).mint();
      await myToken
        .connect(signer2)
        .approve(exchangeNFT.address, ethers.utils.parseEther("1000"));
      await myToken.connect(signer3).mint();
      await myToken
        .connect(signer3)
        .approve(exchangeNFT.address, ethers.utils.parseEther("1000"));
      await nft.mint(addr);
      await nft.setApprovalForAll(exchangeNFT.address, true);
      await exchangeNFT.createListing(0, ethers.utils.parseEther("20"));
      await exchangeNFT
        .connect(signer2)
        .bidOnToken(0, ethers.utils.parseEther("5"));
      await exchangeNFT
        .connect(signer3)
        .bidOnToken(0, ethers.utils.parseEther("10"));
    });
    it("puts a bid", async function () {
      const res = await exchangeNFT.getAllBids(0);
      expect(res[1]).to.equal(ethers.utils.parseEther("5"));
    });
    it("puts multiple bids", async function () {
      const res = await exchangeNFT.getAllBids(0);
      expect(res[1]).to.equal(ethers.utils.parseEther("5"));
      expect(res[2]).to.equal(ethers.utils.parseEther("10"));
    });
    it("cancels bid", async function () {
      let res = await exchangeNFT.getAllBids(0);
      expect(res[1]).to.equal(ethers.utils.parseEther("5"));
      expect(res[2]).to.equal(ethers.utils.parseEther("10"));
      await exchangeNFT.connect(signer2).cancelBid(0);
      res = await exchangeNFT.getAllBids(0);
      expect(res[1]).to.equal(ethers.utils.parseEther("10"));
    });
    it("throws on incorrect bid", async function () {
      await expect(
        exchangeNFT
          .connect(signer2)
          .bidOnToken(0, ethers.utils.parseEther("15"))
      ).to.be.reverted;
      await expect(
        exchangeNFT.connect(signer3).bidOnToken(0, ethers.utils.parseEther("7"))
      ).to.be.reverted;
    });
    it("sells via the maximum bid", async function () {
      let res = await exchangeNFT.getListingsByUser(addr);
      expect(res[0].price).to.equal(ethers.utils.parseEther("20"));
      expect(await myToken.balanceOf(addr)).to.equal(
        ethers.utils.parseEther("1000")
      );
      expect(await nft.ownerOf(0)).to.not.equal(addr3);
      expect(await exchangeNFT.getMaxBidder(0)).to.equal(addr3);
      await exchangeNFT.sellViaBidding(0);
      expect(await nft.ownerOf(0)).to.equal(addr3);
      expect(await myToken.balanceOf(addr)).to.equal(
        ethers.utils.parseEther("1010")
      );
    });
  });
});
