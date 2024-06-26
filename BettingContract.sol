// SPDX-License-Identifier: UNLICENSED 
pragma solidity ^0.8.0;

contract BettingContract {
    
    enum BetState {PENDING, WON, LOST, PAID_OUT}
    enum GameState {OPEN, CLOSED, WAITING_FOR_WINNERS, WINNERS_DECLARED}
    
    struct Bet {
        address user;
        uint256 amount;
        uint256 gameID;
        uint256 betOption;
        BetState state;
        uint256 price;
        uint256 totalShares;
        mapping(address => uint256) shares;
    }

    struct Game {
        string description;
        bool isOpen;
        uint256[] bets;
        GameState state;
        uint256 totalFunds;
        uint256 numBets;
    }
    
    Game[] public games;
    mapping(uint256 => mapping(uint256 => Bet)) public bets;
    uint256 public numGames;
    mapping(uint256 => uint256[]) public winningBets;
    
    event NewGame(string description);
    event NewBet(uint256 gameID, uint256 betOption);
    event GameClosed(uint256 gameID);
    event BetStateChanged(uint256 gameID, uint256 betOption, BetState newState);
    event WinningsDistributed(uint256 gameID, uint256[] winningBets, uint256 totalWinnings);
    event BetSold(uint256 gameID, uint256 betID, address newOwner, uint256 price);
    
    constructor() {
        numGames = 0;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner());
        _;
    }
    
    function owner() public view returns (address) {
        return payable(address(this));
    }
    
    function createGame(string memory _description) public onlyOwner {
        games.push(Game(_description, true, new uint256[](0), GameState.OPEN, 0, 0));
        numGames++;
        emit NewGame(_description);
    }
    
    function closeGame(uint256 _gameId) public onlyOwner {
        require(_gameId < numGames, "Invalid game ID");
        Game storage game = games[_gameId];
        require(game.isOpen, "Game is already closed");
        game.isOpen = false;
        uint256 totalFunds = 0;
        for (uint256 i = 0; i < game.bets.length; i++) {
            Bet storage bet = bets[_gameId][i];
            totalFunds += bet.amount;
        }
        payable(owner()).transfer(totalFunds);
        emit GameClosed(_gameId);
    }

    function placeBet(uint256 _gameId, uint256 _betOption) public payable {
        require(_gameId < numGames, "Invalid game ID");
        Game storage game = games[_gameId];
        require(game.isOpen, "Game is not open");
        require(msg.value > 0, "Bet amount must be greater than 0");
        Bet storage bet = bets[_gameId][game.bets.length];
        bet.user = msg.sender;
        bet.amount = msg.value;
        bet.gameID = _gameId;
        bet.betOption = _betOption;
        bet.state = BetState.PENDING;
        game.bets.push(game.bets.length);
        emit NewBet(_gameId, _betOption);
    }
    
    function sellBet(uint256 _gameId, uint256 _betId, uint256 _price, uint256 _shares) public {
        Bet storage bet = bets[_gameId][_betId];
        require(bet.shares[msg.sender] >= _shares, "You don't own enough shares of this bet to sell");
        require(bet.state == BetState.PENDING, "The bet must be pending to be sold");
        bet.price = _price;
        bet.totalShares -= _shares;
        bet.shares[msg.sender] -= _shares;
    }

    function buyBet(uint256 _gameId, uint256 _betId, uint256 _shares) public payable {
        Bet storage bet = bets[_gameId][_betId];
        require(bet.price > 0, "The bet is not for sale");
        require(msg.value >= bet.price * _shares, "Sent value must be at least the price of the bet");

        // Transfer the price to the seller
        payable(bet.user).transfer(bet.price * _shares);

        // Update the bet
        bet.shares[msg.sender] += _shares;
        bet.totalShares += _shares;
    }
    
    function removeBet(uint256 _gameId) public {
        require(_gameId < numGames, "Invalid game ID");
        Game storage game = games[_gameId];
        require(game.isOpen, "Game is not open");
        uint256[] storage betsForGame = game.bets;
        for (uint256 i = 0; i < betsForGame.length; i++) {
            Bet storage bet = bets[_gameId][i];
            if (bet.user == msg.sender) {
                payable(msg.sender).transfer(bet.amount);
                betsForGame[i] = betsForGame[betsForGame.length - 1];
                betsForGame.pop();
                emit BetStateChanged(_gameId, bet.betOption, BetState.LOST);
                delete bets[_gameId][i];
                break;
            }
        }
    }

    function declareWinners(uint256 _gameId, uint256[] memory _winningBets) public onlyOwner {
        require(games[_gameId].state == GameState.CLOSED, "Game is not yet closed");
        require(winningBets[_gameId].length == 0, "Winning bets have already been declared for this game");
        require(_winningBets.length > 0, "At least one winning bet must be provided");

        // Mark winning bets
        for (uint i = 0; i < _winningBets.length; i++) {
            uint256 betId = _winningBets[i];
            Bet storage bet = bets[_gameId][betId];
            require(bet.state == BetState.PENDING, "Bet is already declared as a winner or loser");
            bet.state = BetState.WON;
        }

        // Mark losing bets
        for (uint i = 0; i < games[_gameId].bets.length; i++) {
            Bet storage bet = bets[_gameId][games[_gameId].bets[i]];
            if (bet.state == BetState.PENDING) {
                bet.state = BetState.LOST;
            }
        }

        // Store winning bets
        winningBets[_gameId] = _winningBets;

        // Move all funds to the contract owner
        uint256 totalFunds = games[_gameId].totalFunds;
        payable(owner()).transfer(totalFunds);

        // Update game state to "WAITING_FOR_WINNERS"
        games[_gameId].state = GameState.WAITING_FOR_WINNERS;
    }
    
    function distributeWinnings(uint256 _gameId) public onlyOwner {
        require(games[_gameId].state == GameState.WAITING_FOR_WINNERS, "Game is not waiting for winners");
    
        uint256 totalFunds = games[_gameId].totalFunds;
        uint256 numWinningBets = winningBets[_gameId].length;
        uint256 winningsPerBet = totalFunds / numWinningBets;
    
        for (uint i = 0; i < numWinningBets; i++) {
            uint256 betId = winningBets[_gameId][i];
            Bet storage bet = bets[_gameId][betId];
            require(bet.state == BetState.WON, "Bet is not a winning bet");
            payable(bet.user).transfer(winningsPerBet);
            bet.state = BetState.PAID_OUT;
        }
    
        // Update game state to "WINNERS_DECLARED"
        games[_gameId].state = GameState.WINNERS_DECLARED;
    }
}