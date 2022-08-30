import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { PredictionMarket } from "../typechain-types"

describe("Prediction Market", async () => {

    let owner: SignerWithAddress;
    let operator: SignerWithAddress;
    let user1: SignerWithAddress;
    let user2: SignerWithAddress;

    let prediction: PredictionMarket;

    before(async () => {
        [owner, operator, user1, user2] = await ethers.getSigners();

        const AggregatorV3FakeContract = await ethers.getContractFactory("AggregatorV3Fake");
        const aggregator = await AggregatorV3FakeContract.deploy();

        const PredictionMarketContract = await ethers.getContractFactory("PredictionMarket");
        prediction = await PredictionMarketContract.deploy(aggregator.address, owner.address);
    })

    it("Users prediction", async () => {
        prediction.connect(user1).betBear(0, { value: ethers.utils.parseEther("1")});
        prediction.connect(user2).betBull(0, { value: ethers.utils.parseEther("1")});
        
        const roundData = await prediction.getRound(2);
        expect(roundData.betsForBear).to.equal(roundData.betsForBull).to.equal(ethers.utils.parseEther("1"));
    });

    it("Set operator", async () => {
        await prediction.connect(owner).changeOperator(operator.address);
        await prediction.connect(operator).endEpoch();
        const epoch = await prediction.getEpoch();
        expect(epoch).to.equal(2);
    });

    it("First round winner bull", async () => {
        const roundData = await prediction.getRound(1);
        expect(roundData[4]).to.equal(true);
        expect(roundData[5]).to.equal(0);
    });

    it("End second round", async () => {
        await prediction.connect(user1).betBear(0, { value: ethers.utils.parseEther("1")});
        await prediction.connect(user2).betBull(0, { value: ethers.utils.parseEther("1")});
        await prediction.connect(operator).endEpoch();
        const epoch = await prediction.getEpoch();
        expect(epoch).to.equal(3);
    });

    it("Get user wins", async () => {
        const wins = await prediction.getUserWins(user2.address);
        expect(wins[0][0]).to.equal(2);
        expect(wins[1]).to.equal(ethers.utils.parseEther("2"));
    });

    it("Get prediction reward", async () => {
        const balanceBefore = await user2.getBalance();
        await prediction.connect(user2).getReward(2);
        const balanceAfter = await user2.getBalance()
        expect(balanceAfter).greaterThan(balanceBefore);
    });
});