// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0

pragma solidity ^0.8.20;

// Imports.

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// import {console} from "forge-std/Test.sol";

// Events.
event playerEliminated(address indexed _player, uint _barrelIndex);
event playerAddedToABarrel(address indexed _player, uint _barrelIndex);

// Errors.
error AmountIsNotEnough(address _player, uint amount);
error BarrelIsNotFull(uint8 _playerIndex);
error PlayerAlreadyInTheBarrel(uint _barrelIndex, address _player);
error PlayerNeedLODTokenToPlay(address _player);

// Constants.

uint8 constant MAX_PLAYERS_ROUND_ONE = 6;  // Maximum number of players for the first round of the game.
uint8 constant MAX_PLAYERS_ROUND_TWO = 5;  // Maximum number of players for the second round of the game.
uint constant PRICE_ROUND_ONE = 1 ether; // An expensive game at the moment :)

struct Barrel {
    // Define a pool of players. Maximum number of players in the barrel (pool) will be MAX_PLAYERS_ROUND_ONE players.
    address[MAX_PLAYERS_ROUND_ONE] players;
    uint8 playerIndex;
}

struct BarrelRoundTwo {
    // Define a pool of players. Maximum number of players in the barrel (pool) will be MAX_PLAYERS_ROUND_TWO players.
    address[MAX_PLAYERS_ROUND_TWO] players;
    uint8 playerIndex;
}

/**
 * @author CMkIII
 * @notice Smart Contract for a Russian roulette type game. 
 * @notice This contract manages the first round, where players can enter to play. When the barrel is full, a draw is made.
 * @notice One of the players is eliminated and the others receive a token as having participated in the first round.
 * @dev The random draw algo is not sufficiently random for large amounts, but can do the trick for small stakes. 
 * @dev The alternative, more reliable solution would be to use an oracle, but this would have an additional management cost.
 */

contract LiveOrDie is ERC20, ERC20Burnable, ERC20Permit, Ownable {
    uint internal randNonce = 0; // Random nonce.

    uint internal barrelIndex = 0; // Number of barrels.
    mapping(uint => Barrel) internal barrels; // Maaping between BarrelID and the barrels.
    mapping(address => bool) internal paidUsers; // Mapping to keep track of who paid to play round 1.

    constructor(address initialOwner) ERC20("LiveOrDie", "LOD") ERC20Permit("LiveOrDie") Ownable(initialOwner)  {
        barrelIndex = 0;
        for (uint8 i = 0; i < MAX_PLAYERS_ROUND_ONE; i++) {
            barrels[barrelIndex].players[i] = address(0);
        }
        barrels[barrelIndex].playerIndex = 0;
    }

    /**
     * @notice Function to receive payment to enter the game and take part in the first round. 
     * Todo: Could add more security, for example a blacklist of addresses.
     */
    function payEntranceFee() payable external returns (bool) {
        if (msg.value < PRICE_ROUND_ONE) {
            revert AmountIsNotEnough(msg.sender, msg.value);
        } else {
            // Todo: Change the way we track who has paid. For now, a player could pay once and play again several times. 
            // Todo: Use a mapping of mapping instead of a one level mapping. 
            // Todo: That way we would know for each new barrel.
            paidUsers[msg.sender] = true; // Keeps track of who has paid to take part of the game (for Roune One).
            return true;
        }
    }
    
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    /**
     * @notice Function to create and initialize a new RoundOne barrel. 
     */
    function createNewBarrel() public {
        barrelIndex++;
        for (uint8 i = 0; i < MAX_PLAYERS_ROUND_ONE; i++) {
            barrels[barrelIndex].players[i] = address(0);
        }
        barrels[barrelIndex].playerIndex = 0;
    }

    /**
     * @notice Check if a player is alreay part of the current barrel. 
     */
    function isPlayerInBarrel(uint _barrelId, address _player) public view returns (bool) {
        Barrel memory barrel = barrels[_barrelId];
        for (uint8 i = 0; i < barrel.playerIndex; i++) {
            if (barrel.players[i] == _player) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice Add a player to an available barrel. Create a new barrel if needed.
     * @notice If the barrel is full we pull the trigger to eliminate one of the players.
     */
    function addPlayerToAvailableBarrel(address _player) public {
        if (barrels[barrelIndex].playerIndex == MAX_PLAYERS_ROUND_ONE) {
            createNewBarrel();
        } else {
            if (isPlayerInBarrel(barrelIndex, _player) == true) {
                revert PlayerAlreadyInTheBarrel(barrelIndex, _player);
            }
        }

        barrels[barrelIndex].players[barrels[barrelIndex].playerIndex] = _player;
        barrels[barrelIndex].playerIndex++;
        emit playerAddedToABarrel(_player, barrelIndex);

        if (barrels[barrelIndex].playerIndex == MAX_PLAYERS_ROUND_ONE) {
            pullTheTrigger();
        }
    }

    /**
     * @notice Randomly eliminates one of the players.
     * @notice And mint a token to the remaining players as proof that they have participated and survived to the first round.
     */
    function pullTheTrigger() public {
        address deadPlayer = pickRandomPlayer(MAX_PLAYERS_ROUND_ONE);

        for (uint8 i = 0; i < MAX_PLAYERS_ROUND_ONE; i++) {
            if (barrels[barrelIndex].players[i] != deadPlayer) {
                mint(barrels[barrelIndex].players[i], 1 * 10 ** decimals());
            }
        }
        emit playerEliminated(deadPlayer, barrelIndex);
    }

    /**
     * @notice Function to pick a random player from a full barrel.
     * @notice This function is not secure for high-value applications.
     * @notice People with control of certain variable could potentially manipulate the outcome.
     * @notice A solution based on an Oracle like Chainlink VRF would be safer (but more expensive).
     */
    function pickRandomPlayer(uint _modulus) public returns (address) {
        if (barrels[barrelIndex].playerIndex < MAX_PLAYERS_ROUND_ONE) {
            revert BarrelIsNotFull(barrels[barrelIndex].playerIndex);
        }
        // Increase random nonce.
        randNonce++;
        uint randomIndex = uint(keccak256(abi.encodePacked(block.timestamp, msg.sender, randNonce))) % _modulus;
        return barrels[barrelIndex].players[randomIndex];
    }

    /**
     * @notice geter functions.
     */
    function getBarrelIndex() public view returns (uint256) {
        return barrelIndex;
    }

    function getPlayerAddress(uint _barrelIndex, uint _playerIndex) public view returns (address) {
        return barrels[_barrelIndex].players[_playerIndex];
    }

    function getMaxPlayersFirstRound() public pure returns (uint) {
        return MAX_PLAYERS_ROUND_ONE;
    }
}

/**
 * @author CMkIII
 * @notice Smart Contract for a Russian roulette type game. This contract manages the second round of the game.
 * @notice Players must have a token proving that they have passed and survived the first round in order to play (and pay for the second round).
 * @notice Again, when the barrel is full, a draw is made.
 * @notice One of the players is eliminated and the others receive a token as having participated in the second round.
 * @dev The random draw algo is not sufficiently random for large amounts, but can do the trick for small stakes. 
 * @dev The alternative, more reliable solution would be to use an oracle, but this would have an additional management cost.
 */
contract LiveOrDieRoundTwo is ERC20, ERC20Burnable, Ownable {

    uint internal barrelIndex; // Number of barrels.
    mapping(uint => BarrelRoundTwo) internal barrels; // Maaping between BarrelID and the barrels.
    mapping(address => bool) internal paidUsers; // Mapping to keep track of who paid to play round 1.
    LiveOrDie liveOrDie;

     constructor(address _initialOwner, LiveOrDie _liveOrDie) ERC20("LiveOrDieRoundTwo", "LODR2") Ownable(_initialOwner) {
        liveOrDie = _liveOrDie;
        barrelIndex = 0;

        for (uint8 i = 0; i < MAX_PLAYERS_ROUND_TWO; i++) {
            barrels[barrelIndex].players[i] = address(0);
        }
        barrels[barrelIndex].playerIndex = 0;
    }

        function addPlayerToAvailableBarrel(address _player) public {
            if (liveOrDie.balanceOf(_player) < 1 * 10 ** liveOrDie.decimals()) {
                revert PlayerNeedLODTokenToPlay(_player);
            } else {
                if (barrels[barrelIndex].playerIndex == MAX_PLAYERS_ROUND_ONE) {
                    createNewBarrel();
                   } else {
                    if (isPlayerInBarrel(barrelIndex, _player) == true) {
                        revert PlayerAlreadyInTheBarrel(barrelIndex, _player);
                   }
                }
                barrels[barrelIndex].players[barrels[barrelIndex].playerIndex] = _player;
                barrels[barrelIndex].playerIndex++;
                liveOrDie.burnFrom(_player, 1 * 10 ** liveOrDie.decimals());
                emit playerAddedToABarrel(_player, barrelIndex);
            }

        // Todo:
        // if (barrels[barrelIndex].playerIndex == MAX_PLAYERS_ROUND_ONE) {
        //     pullTheTrigger();
        // }
    }

    // Function to create and initialize a new RoundTwo barrel.
    function createNewBarrel() public {
        barrelIndex++;
        for (uint8 i = 0; i < MAX_PLAYERS_ROUND_TWO; i++) {
            barrels[barrelIndex].players[i] = address(0);
        }
        barrels[barrelIndex].playerIndex = 0;
    }

    function isPlayerInBarrel(uint _barrelId, address _player) public view returns (bool) {
        BarrelRoundTwo memory barrel = barrels[_barrelId];
        for (uint8 i = 0; i < barrel.playerIndex; i++) {
            if (barrel.players[i] == _player) {
                return true;
            }
        }
        return false;
    }

 }