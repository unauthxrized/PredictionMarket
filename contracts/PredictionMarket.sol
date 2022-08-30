// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract PredictionMarket is ReentrancyGuard {
    AggregatorV3Interface public immutable _ORACLE;

    enum Position {
        Bull,
        Bear
    }

    struct Round {
        uint256 betsForBear;
        uint256 betsForBull;
        uint256 btcCostOnStart;
        uint256 btcCostOnEnd;
        bool isEnd;
        Position winner;
        Position lose;
    }

    struct BetInfo {
        uint256 amount;
        uint128 inviter;
        Position position;
        bool claimed;
    }

    uint128 private _currentEpoch = 1;
    uint128 private _inviters;

    address private _operator;
    address private immutable _ADMIN;
    address private immutable _FEEADDRESS;

    mapping(uint256 => Round) private _idToRound;
    mapping(address => mapping(uint => BetInfo)) private _userBet;
    mapping(uint128 => address) private _inviter;
    mapping(address => bool) private _isInviter;
    mapping(address => bool) private _whitelist;

    constructor(address _oracle, address _feeAddress) {
        _ORACLE = AggregatorV3Interface(_oracle);
        _ADMIN = msg.sender;
        _operator = msg.sender;
        _FEEADDRESS = _feeAddress;
    }

    modifier onlyAdmin() {
        require(msg.sender == _ADMIN);
        _;
    }

    modifier onlyOperator() {
        require(msg.sender == _operator);
        _;
    }

    modifier notContract() {
        require(!_isContract(msg.sender));
        require(msg.sender == tx.origin);
        _;
    }

    // PUBLIC

    function betBull(uint128 _inviterId) external payable notContract {
        require(msg.value >= 0.01 ether);
        require((msg.value / 10000) * 10000 == msg.value, "too small");

        Round storage currentRound = _idToRound[_currentEpoch + 1];
        currentRound.betsForBull += msg.value;

        BetInfo storage betInfo = _userBet[msg.sender][_currentEpoch + 1];
        require(betInfo.amount == 0);
        betInfo.amount += msg.value;
        betInfo.inviter = _inviterId;
        betInfo.position = Position.Bull;
    }

    function betBear(uint128 _inviterId) external payable notContract {
        require(msg.value >= 0.01 ether);
        require((msg.value / 10000) * 10000 == msg.value, "too small");

        Round storage currentRound = _idToRound[_currentEpoch + 1];
        currentRound.betsForBear += msg.value;

        BetInfo storage betInfo = _userBet[msg.sender][_currentEpoch + 1];
        require(betInfo.amount == 0);
        betInfo.amount += msg.value;
        betInfo.inviter = _inviterId;
        betInfo.position = Position.Bear;
    }

    function endEpoch() external onlyOperator {
        uint256 btcCost = _getCost();

        Round storage currentRound = _idToRound[_currentEpoch];

        currentRound.isEnd = true;
        currentRound.btcCostOnEnd = btcCost;
        currentRound.winner = _getWinner(currentRound.btcCostOnStart, btcCost);
        if (currentRound.winner == Position.Bear) {
            currentRound.lose = Position.Bull;
        }
        if (currentRound.winner == Position.Bull) {
            currentRound.lose = Position.Bear;
        }
        _currentEpoch++;

        Round storage nextRound = _idToRound[_currentEpoch];
        require(nextRound.betsForBear > 0 && nextRound.betsForBull > 0);
        nextRound.btcCostOnStart = btcCost;
    }

    function getReward(uint _round) external notContract nonReentrant {
        Round storage currentRound = _idToRound[_round];
        require(currentRound.isEnd == true, "Round is not over");

        BetInfo storage betInfo = _userBet[msg.sender][_round];
        require(betInfo.claimed == false, "Reward is sended");
        require(betInfo.position == currentRound.winner);

        address _roundInviter = _inviter[betInfo.inviter];

        if (_roundInviter == address(0)) {
            _roundInviter = _FEEADDRESS;
        }

        uint256 _win;

        if (currentRound.winner == Position.Bear) {
            _win = _calculateReward(betInfo.amount,currentRound.betsForBear,currentRound.betsForBull);
        }
        if (currentRound.winner == Position.Bull) {
            _win = _calculateReward(betInfo.amount,currentRound.betsForBull,currentRound.betsForBear);
        }

        betInfo.claimed = true;

        if (_whitelist[msg.sender]) {
            payable(msg.sender).transfer(_win);
        } else {
            uint256 _fee = _calculateAdminFee(_win);
            payable(msg.sender).transfer(_win - _fee * 2);
            payable(_FEEADDRESS).transfer(_fee);
            payable(_roundInviter).transfer(_fee);
        }
    }

    function becomeInviter() external notContract {
        require(!_isInviter[msg.sender]);
        _inviters++;
        _isInviter[msg.sender] = true;
        _inviter[_inviters] = msg.sender;
    }

    // ADMIN

    function changeOperator(address _newOperator) external onlyAdmin {
        _operator = _newOperator;
    }

    function addWhitelist(address _user) external onlyAdmin {
        _whitelist[_user] = true;
    }

    // GETTERS

    function getUserWins(address _user) public view returns (uint256[] memory, uint256) {
        uint256[] memory ownerRounds = new uint256[](10);
        uint256 ownedRoundIndex;
        uint256 whileRound;
        uint256 winAmount;
        while (ownedRoundIndex < 10 && whileRound < _currentEpoch) {
            Round memory round = _idToRound[whileRound];
            BetInfo memory userBet = _userBet[_user][whileRound];
            if (
                userBet.amount > 0 &&
                userBet.claimed == false &&
                userBet.position == round.winner
            ) {
                ownerRounds[ownedRoundIndex] = whileRound;
                ownedRoundIndex++;
                if (round.winner == Position.Bear) {
                    winAmount+= _calculateReward(userBet.amount,round.betsForBear,round.betsForBull);
                }
                if (round.winner == Position.Bull) {
                    winAmount+= _calculateReward(userBet.amount,round.betsForBull,round.betsForBear);
                }
            }
            whileRound++;
        }
        return (ownerRounds, winAmount);
    }

    function getCurrentAndNextRoundStatus() external view returns (Round memory, uint256, Round memory, uint256, Round memory, uint256) {
        return (
            _idToRound[_currentEpoch - 1],
            _currentEpoch - 1,
            _idToRound[_currentEpoch],
            _currentEpoch,
            _idToRound[_currentEpoch + 1],
            _currentEpoch + 1
        );
    }

    function getEpoch() external view returns (uint256) {
        return _currentEpoch;
    }

    function getInviterById(uint128 _id) external view returns (address) {
        return _inviter[_id];
    }

    function getInviterByAddress(address _inv) external view returns (uint256) {
        uint128 currentId;

        while (currentId < _inviters || _inviter[currentId] == _inv) {
            currentId++;
        }
        return currentId - 1;
    }

    function getRound(uint256 _round) external view returns (Round memory) {
        return _idToRound[_round];
    }

    function isInWhitelist(address _user) external view returns (bool) {
        return _whitelist[_user];
    }

    function getBalance() public view returns (uint256) {
        address _this = address(this);
        uint256 _balance = _this.balance;
        return _balance;
    }

    // PRIVATE
    function _getCost() private view returns (uint256) {
        (, int256 btcCost, , , ) = _ORACLE.latestRoundData();
        return SafeCast.toUint256(btcCost);
    }

    function _getWinner(uint256 _costOnStart, uint256 _costOnEnd)
        private
        pure
        returns (Position)
    {
        if (_costOnStart > _costOnEnd) {
            return Position.Bear;
        } else {
            return Position.Bull;
        }
    }

    function _calculateAdminFee(uint256 _win) private pure returns (uint256) {
        return (_win * 250) / 10000;
    }

    function _calculateReward(
        uint256 _userValue,
        uint256 _winBets,
        uint256 _loseBets
    ) private pure returns (uint256) {
        return _userValue + (_loseBets * _userValue) / _winBets;
    }

    function _isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }
}