import { ethers } from "hardhat";
import { Wallet, ContractFactory } from "ethers";
import { expect } from "chai"
import { BitrielToken, BitrielStake } from "../types"

describe("BitrielStake", () => {
  let accounts: Wallet[];
  let BitrielToken: ContractFactory;
  let BitrielStake: ContractFactory;
  let bitriel: BitrielToken;
  let bitrielStake: BitrielStake;

  before("get signers and contract factories", async () => {
    accounts = await (ethers as any).getSigners()
    BitrielToken = await ethers.getContractFactory("BitrielToken")
    BitrielStake = await ethers.getContractFactory("BitrielStake")
  })

  beforeEach(async () => {
    bitriel = await BitrielToken.deploy() as BitrielToken
    await bitriel.deployed()
    bitrielStake = await BitrielStake.deploy(bitriel.address) as BitrielStake
    await  bitrielStake.deployed()
    bitriel.mint(accounts[0].address, 275)
    bitriel.mint(accounts[1].address, 125)
    bitriel.mint(accounts[2].address, 12705)
  });

  it("not allow enter if not enough approve", async function () {
    await expect(bitrielStake.enter(100)).to.be.revertedWith("ERC20: transfer amount exceeds allowance")
    await bitriel.approve(bitrielStake.address, 50)
    await expect(bitrielStake.enter(100)).to.be.revertedWith("ERC20: transfer amount exceeds allowance")
    await bitriel.approve(bitrielStake.address, 100)
    await bitrielStake.enter(100)
    expect(await bitrielStake.balanceOf(accounts[0].address)).to.equal(100)
  })

  it("not allow withraw more than available balance", async function () {
    await bitriel.approve(bitrielStake.address, 127)
    await bitrielStake.enter(127)
    await expect(bitrielStake.leave(275)).to.be.revertedWith("ERC20: burn amount exceeds balance")
  })

  it("more than one participant", async function () {
    await bitriel.approve(bitrielStake.address, 100)
    await bitriel.connect(accounts[1]).approve(bitrielStake.address, 100)
    // Me enters and gets 20 shares. You enters and gets 10 shares.
    await bitrielStake.enter(20)
    await bitrielStake.connect(accounts[1]).enter(10)
    expect(await bitrielStake.balanceOf(accounts[0].address)).to.equal(20)
    expect(await bitrielStake.balanceOf(accounts[1].address)).to.equal(10)
    expect(await bitriel.balanceOf(bitrielStake.address)).to.equal(30)
    // get 20 more BTRs from an external source.
    await bitriel.connect(accounts[2]).transfer(bitrielStake.address, 20)
    // I deposits 10 more BTRs. I should receive 10*30/50 = 6 shares.
    await bitrielStake.enter(10)
    expect(await bitrielStake.balanceOf(accounts[0].address)).to.equal(26)
    expect(await bitrielStake.balanceOf(accounts[1].address)).to.equal(10)
    // You withdraws 5 shares. You should receive 5*60/36 = 8 shares
    await bitrielStake.connect(accounts[1]).leave(5)
    expect(await bitrielStake.balanceOf(accounts[0].address)).to.equal(26)
    expect(await bitrielStake.balanceOf(accounts[1].address)).to.equal(5)
    expect(await bitriel.balanceOf(bitrielStake.address)).to.equal(52)
    expect(await bitriel.balanceOf(accounts[0].address)).to.equal(245)
    expect(await bitriel.balanceOf(accounts[1].address)).to.equal(123)
  })
});