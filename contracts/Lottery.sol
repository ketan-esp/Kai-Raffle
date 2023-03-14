// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Lottery {
    address public owner;
    address payable[] public ticketHolders; //list of players
    uint256 public currentLotteryId = 0;
    uint256 public currentOfferId = 0;
    uint256 public numberOfLoterries = 0;
    uint256 public prizeAmount;
    uint256 public activePlayers;
    uint256 public ticketCount;
    uint256 public maxPlayersAllowed = 1000;
    uint256 public constant TOTAL_HOURS = 168; // 1 week
    mapping(address => uint256) public ticketBalances; //tickets
    mapping(uint256 => LotteryStruct) public lotteries; //mapping for lottery struct
    mapping(uint256 => WinningTicket) public winningTickets; //mapping for ticket struck
    mapping(uint256 => Offer) public offers; //mapping for offer struct
    mapping(uint256 => uint256) public prizes;
    mapping(address => bool) public players;
    mapping(uint256 => mapping(address => uint256)) public pendingWithdrawals;
    IERC20 public token;

    struct LotteryStruct {
        uint256 lotteryId;
        uint256 startTime;
        uint256 endTime;
        bool isCompleted;
        bool isCreated;
        bool isActive;
    }

    struct Offer {
        uint256 numTickets;
        uint256 price;
    }

    struct TicketDistribution {
        address playerAddress;
        uint256 startIndex;
        uint256 endIndex;
    }

    struct WinningTicket {
        uint256 currentLotteryId;
        uint256 winningTicketIndex;
        address winningAddress;
    }

    WinningTicket public winningTicket;
    TicketDistribution[] public ticketDistribution;

    event NewLottery(address creator, uint256 startTime, uint256 endTime);

    constructor(address _token, uint256 _ticketPrice) {
        owner = msg.sender;
        token = IERC20(_token);
        //ticketPrice = _ticketPrice;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can pick winner");
        _;
    }

    modifier isValid() {
        LotteryStruct memory lottery = lotteries[currentLotteryId];
        if (lottery.isActive == true) {
            revert("Lottery already exists");
        }
        _;
    }

    modifier isCompleted() {
        if (
            !((lotteries[currentLotteryId].isActive == true &&
                lotteries[currentLotteryId].endTime < block.timestamp) ||
                lotteries[currentLotteryId].isActive == false)
        ) {
            revert("Lottery not completed");
        }
        _;
    }

    function setMaxPlayersAllowed(uint256 _maxPlayersAllowed)
        external
        onlyOwner
    {
        maxPlayersAllowed = _maxPlayersAllowed;
    }

    function createOffer(uint256 _price, uint256 _numTickets) public onlyOwner {
        offers[currentOfferId] = Offer({
            numTickets: _numTickets,
            price: _price
        });
    }

    function createLottery(uint256 _startTime, uint256 _numHours)
        external
        onlyOwner
    {
        if (_numHours == 0) {
            _numHours = TOTAL_HOURS;
        }
        uint256 endTime = _startTime + (_numHours * 1 hours);
        lotteries[currentLotteryId] = LotteryStruct({
            lotteryId: currentLotteryId,
            startTime: _startTime,
            endTime: endTime,
            isCompleted: false,
            isCreated: true,
            isActive: true
        });
        numberOfLoterries = numberOfLoterries + 1;
        emit NewLottery(msg.sender, _startTime, endTime);
    }

    function buyTickets(bytes32 offerId, bytes32 lotteryId) external payable {
        // uint _numTickets = msg.value;
        uint256 _activePlayers = activePlayers;
        if (ticketHolders[msg.sender] == false) {
            require(_activePlayers + 1 <= maxPlayersAllowed);
            if (ticketHolders.length > _activePlayers) {
                ticketHolders[_activePlayers] = msg.sender;
            } else {
                ticketHolders.push(payable(msg.sender));
            }
            players[msg.sender] = true;
            activePlayers = _activePlayers + 1;
            ticketBalances[msg.sender] += _numTickets;
            prizeAmount = prizeAmount + (msg.value);
            ticketCount += _numTickets;
        }
    }

    function triggerLottery() external onlyOwner {
        prizes[currentLotteryId] = prizeAmount;
        _playerTicketDistribution();
        uint256 winningTicketIndex = uint256(
            keccak256(
                abi.encodePacked(
                    block.prevrandao,
                    block.timestamp,
                    ticketHolders
                )
            )
        ) % ticketCount;
        winningTicket.currentLotteryId = currentLotteryId;
        winningTicket.winningTicketIndex = winningTicketIndex;
        findWinningAddress(winningTicketIndex);
    }

    function depositWinnings() public {
        pendingWithdrawals[currentLotteryId][winningTicket.addr] = prizeAmount;
        prizeAmount = 0;
        lotteries[currentLotteryId].isCompleted = true;
        winningTickets[currentLotteryId] = winningTicket;
        reset();
    }

    function getTicketDistribution(uint256 _playerIndex)
        public
        view
        returns (
            address playerAddress,
            uint256 startIndex,
            uint256 endIndex
        )
    {
        return (
            ticketDistribution[_playerIndex].playerAddress,
            ticketDistribution[_playerIndex].startIndex,
            ticketDistribution[_playerIndex.endIndex]
        );
    }

    function _playerTicketDistribution() private {
        uint256 distLength = ticketDistribution.length;
        uint256 ticketIndex = 0;
        for (uint256 i = ticketIndex; i < activePlayers; i++) {
            address _playerAddress = ticketHolders[i];
            uint256 _numTickets = ticketBalances[_playerAddress];
            TicketDistribution memory newDistribution = TicketDistribution({
                playerAddress: _playerAddress,
                startIndex: ticketIndex,
                endIndex: ticketIndex + _numTickets - 1
            });
            if (distLength > i) {
                ticketDistribution[i] = newDistribution;
            } else {
                ticketDistribution.push(newDistribution);
            }

            ticketBalances[_playerAddress] = 0;
            ticketIndex = ticketIndex + _numTickets;
        }
    }

    function findWinningAddress(uint256 _winningTicketIndex) public {
        uint256 _activePlayers = activePlayers;
        if (_activePlayers == 1) {
            winningTicket.addr = ticketDistribution[0].playerAddress;
        } else {
            uint256 _winningPlayerIndex = binarySearch(
                0,
                _activePlayers - 1,
                _winningTicketIndex
            );
            if (_winningPlayerIndex >= _activePlayers) {
                revert("Invalid");
            }
            winningTicket.addr = ticketDistribution[_winningPlayerIndex]
                .playerAddress;
        }
    }

    function binarySearch(
        uint256 _leftIndex,
        uint256 _rightIndex,
        uint256 _ticketIndexToFind
    ) private returns (uint256) {
        uint256 maxLoops = 10;
        uint256 loopCount = 0;
        uint256 _searchIndex = (_rightIndex - _leftIndex) / (2) + (_leftIndex);
        uint256 _loopCount = loopCount;
        loopCount = _loopCount + 1;
        if (_loopCount + 1 > maxLoops) {
            return activePlayers;
        }
        if (
            ticketDistribution[_searchIndex].startIndex <= _ticketIndexToFind &&
            ticketDistribution[_searchIndex].endIndex >= _ticketIndexToFind
        ) {
            return _searchIndex;
        } else if (
            ticketDistribution[_searchIndex].startIndex > _ticketIndexToFind
        ) {
            _rightIndex = _searchIndex - (_leftIndex);
            return binarySearch(_leftIndex, _rightIndex, _ticketIndexToFind);
        } else if (
            ticketDistribution[_searchIndex].endIndex < _ticketIndexToFind
        ) {
            _leftIndex = _searchIndex + (_leftIndex) + 1;
            return binarySearch(_leftIndex, _rightIndex, _ticketIndexToFind);
            return activePlayers;
        }
    }

    function reset() private {
        ticketCount = 0;
        activePlayers = 0;
        lotteries[currentLotteryId].isActive = false;
        lotteries[currentLotteryId].isCompleted = true;
        winningTicket = WinningTicket({
            currentLotteryid: 0,
            winningTicketIndex: 0,
            addr: address(0)
        });
        currentLotteryId = currentLotteryId + (1);
    }

    function withdraw(uint256 _lotteryId) external payable {
        uint256 _pendingWithdrawals = pendingWithdrawals[_lotteryId][
            msg.sender
        ];
        if (_pendingWithdrawals == 0) {
            revert("No funds to withdraw");
        }
        pendingWithdrawals[_lotteryId][msg.sender] = 0;
        (bool sent, ) = msg.sender.call{value: _pendingWithdrawals}("");
        if (sent == false) {
            revert("withdrawal failed, contact admin");
        }
    }
}
