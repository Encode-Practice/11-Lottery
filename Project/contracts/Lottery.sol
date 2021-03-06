// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {LotteryToken} from "./Token.sol";

/// @title A very simple lottery contract
/// @author Matheus Pagani
/// @notice You can use this contract for running a very simple lottery
/// @dev This contract implements a weak randomness source
/// @custom:teaching This is a contract meant for teaching only
contract Lottery is Ownable {
    /// @notice Address of the token used as payment for the bets
    LotteryToken public paymentToken;
    /// @notice Amount of ETH charged per Token purchased
    uint256 public purchaseRatio;
    /// @notice Amount of tokens required for placing a bet that goes for the prize pool
    uint256 public betPrice;
    /// @notice Amount of tokens required for placing a bet that goes for the owner pool
    uint256 public betFee;
    /// @notice Amount of tokens in the prize pool
    uint256 public prizePool;
    /// @notice Amount of tokens in the owner pool
    uint256 public ownerPool;
    /// @notice Flag indicating if the lottery is open for bets
    bool internal _betsOpen;
    /// @notice Timestamp of the lottery next closing date
    uint256 public betsClosingTime;
    /// @notice Mapping of prize available for withdraw for each account
    mapping(address => uint256) public prize;
    /// @dev List of bet slots
    address[] internal _slots;
    /// @notice seed for random number generation made by the contract owner. 
    bytes32 private sealedSeed;


    /// @notice Constructor function
    /// @param tokenName Name of the token used for payment
    /// @param tokenSymbol Symbol of the token used for payment
    /// @param _purchaseRatio Amount of ETH charged per Token purchased
    /// @param _betPrice Amount of tokens required for placing a bet that goes for the prize pool
    /// @param _betFee Amount of tokens required for placing a bet that goes for the owner pool
    /// @param _seed Secrete seed that is used to hash the random number. 
    constructor(
        string memory tokenName,
        string memory tokenSymbol,
        uint256 _purchaseRatio,
        uint256 _betPrice,
        uint256 _betFee, 
        string memory _seed
    ) {
        paymentToken = new LotteryToken(tokenName, tokenSymbol);
        purchaseRatio = _purchaseRatio;
        betPrice = _betPrice;
        betFee = _betFee;
        sealedSeed = keccak256(abi.encode(msg.sender, _seed));
    }

    ///@return _betsOpen, which is bool internal
    function betsOpen() public view returns (bool) {
        return _betsOpen;
    }

    /// @notice Open the lottery for receiving bets
    function openBets(uint256 closingTime) public onlyOwner whenBetsClosed {
        require(
            closingTime > block.timestamp,
            "Closing time must be in the future"
        );
        betsClosingTime = closingTime;
        _betsOpen = true;
    }

    /// @notice Give tokens based on the amount of ETH sent
    function purchaseTokens() public payable {
        paymentToken.mint(msg.sender, msg.value / purchaseRatio);
    }

    /// @notice Charge the bet price and create a new bet slot with the sender address
    function bet() public whenBetsOpen {
        paymentToken.transferFrom(msg.sender, address(this), betPrice + betFee);
        ownerPool += betFee;
        prizePool += betPrice;
        _slots.push(msg.sender);
    }

    /// @dev improvement over betMany0, saves more gas
    function betMany(uint256 times) public whenBetsOpen {
        require(times > 0);
        paymentToken.transferFrom(msg.sender, address(this), (betPrice + betFee)*times);
        ownerPool += betFee*times;
        prizePool += betPrice*times;
        for (uint i = 0; i < times; i++) {
            _slots.push(msg.sender);
        }
    }

    /// @notice Call the bet function `times` times
    function betMany0(uint256 times) public {
        require(times > 0);
        while (times > 0) {
            bet();
            times--;
        }
    }

    /// @notice Close the lottery and calculates the prize, if any. Must know secrete seed. 
    function closeLottery(string calldata seed) public {
        require(block.timestamp >= betsClosingTime, "Too soon to close");
        require(_betsOpen, "Already closed");
        require(sealedSeed == keccak256(abi.encode(owner(), seed)), "Wrong seed");
        _betsOpen = false; // security measure 
        if (_slots.length > 0) {
            uint256 winnerIndex = getRandomNumber(seed) % _slots.length;
            address winner = _slots[winnerIndex];
            prize[winner] += prizePool;
            prizePool = 0;
            delete (_slots);
        }
    }

    /// @notice Get a random number calculated from the block hash of last block
    /// @dev Only those who know the seed can expolit the random number. 
    function getRandomNumber(string calldata seed)
        public view returns (uint256 notQuiteRandomNumber){
        return uint256(keccak256(abi.encode(seed, blockhash(block.number-1))));
    }

    /// @notice Withdraw `amount` from that accounts prize pool
    function prizeWithdraw(uint256 amount) public{
        require(amount <= prize[msg.sender], "Not enough prize");
        prize[msg.sender] -= amount;
        paymentToken.transfer(msg.sender, amount);
    }

    /// @notice Withdraw `amount` from the owner pool
    function ownerWithdraw(uint256 amount) public onlyOwner {
        require(amount <= ownerPool, "Not enough fees collected");
        ownerPool -= amount;
        paymentToken.transfer(msg.sender, amount);
    }

    /// @notice Burn `amount` tokens and give the equivalent ETH back to user
    function returnTokens(uint256 amount) public {
        paymentToken.burnFrom(msg.sender, amount);
        payable(msg.sender).transfer(amount * purchaseRatio);
    }


    /// @notice Passes when the lottery is at closed state
    modifier whenBetsClosed() {
        require(!_betsOpen, "Lottery is open");
        _;
    }

    /// @notice Passes when the lottery is at open state and the current block timestamp is lower than the lottery closing date
    modifier whenBetsOpen() {
        require(
            _betsOpen && block.timestamp < betsClosingTime,
            "Lottery is closed"
        );
        _;
    }
}
