import { ethers } from "hardhat";
import { Wallet, ContractFactory } from "ethers";
import { expect } from "chai"
import { BitrielToken } from "../types"

describe("BitrielToken", () => {
  let accounts: Wallet[];
  let BitrielToken: ContractFactory;
  let bitriel: BitrielToken;

  before("get signers and contract factories", async () => {
    accounts = await (ethers as any).getSigners()
    BitrielToken = await ethers.getContractFactory("BitrielToken")
  })

  beforeEach(async () => {
    bitriel = await BitrielToken.deploy() as BitrielToken
    await bitriel.deployed()
  });

  it("correct name, symbol and decimals", async () => {
    expect(await bitriel.name(), "Bitriel")
    expect(await bitriel.symbol(), "BTR")
    expect(await bitriel.decimals(), "18")
  });

  it("allow only owner to mint", async () => {
    await bitriel.mint(accounts[0].address, 12705)
    await bitriel.mint(accounts[2].address, 127)
    await expect(
      bitriel.connect(accounts[1]).mint(
        accounts[3].address, 
        100, 
      )).revertedWith("Ownable: caller is not the owner")
    expect(await bitriel.balanceOf(accounts[0].address)).equal(12705)
    expect(await bitriel.balanceOf(accounts[1].address)).equal(0)
    expect(await bitriel.balanceOf(accounts[2].address)).equal(127)
    expect(await bitriel.balanceOf(accounts[3].address)).equal(0)
    expect(await bitriel.totalSupply()).equal(12705 + 127)
  })

  it("transfers supply token successfully", async () => {
    await bitriel.mint(accounts[0].address, 127)
    await bitriel.mint(accounts[1].address, 100)
    await bitriel.transfer(accounts[2].address, 27)
    await bitriel.connect(accounts[1]).transfer(accounts[0].address, 50)
    expect(await bitriel.balanceOf(accounts[0].address)).equal(150)
    expect(await bitriel.balanceOf(accounts[1].address)).equal(50)
    expect(await bitriel.balanceOf(accounts[2].address)).equal(27)
    expect(await bitriel.balanceOf(accounts[3].address)).equal(0)
    expect(await bitriel.totalSupply()).equal(127 + 100)
  })

  it("fail if try to do transfers", async () => {
    await bitriel.mint(accounts[0].address, 127)
    await expect(
      bitriel.transfer(accounts[1].address, 275)
    ).revertedWith("ERC20: transfer amount exceeds balance")
    await expect(
      bitriel.connect(accounts[2]).transfer(accounts[0].address, 1)
    ).revertedWith("ERC20: transfer amount exceeds balance")
  })

  it("delegate votes", async () => {
    await bitriel.mint(accounts[0].address, 127)
    await bitriel.delegate(accounts[1].address)
    expect(await bitriel.delegates(accounts[0].address)).equal(accounts[1].address)
    expect(await bitriel.getCurrentVotes(accounts[1].address)).equal(127)
  })
});