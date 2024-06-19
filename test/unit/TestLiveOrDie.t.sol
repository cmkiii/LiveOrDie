// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {LiveOrDie, LiveOrDieRoundTwo, AmountIsNotEnough, BarrelIsNotFull, PlayerAlreadyInTheBarrel, playerAddedToABarrel, playerEliminated, PlayerNeedLODTokenToPlay} from "../../src/LiveOrDie.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {DeployLiveOrDie} from "../../script/DeployLiveOrDie.s.sol";

contract TestLiveOrDie is Test, IERC20Errors {
    LiveOrDie public liveOrDie;
    LiveOrDieRoundTwo public liveOrDieRoundTwo;

    uint8 public constant MAX_PLAYERS_ROUND_ONE = 6;
    uint public constant PRICE_ROUND_ONE = 1 ether; // An expensive game at the moment :)

    function setUp() external {
        DeployLiveOrDie deployer = new DeployLiveOrDie();
        (liveOrDie, liveOrDieRoundTwo) = deployer.run();
    }

    /**
     * @notice Check the number of decimals used to get its user representation.
     * @dev The number of decimals should be 18.
     */

    function testNumberOfDecimals() public view {
        // Arrange
        uint256 expectedNumberOfDecimals = 18;
        // Act
        // Assert
        assert(expectedNumberOfDecimals == liveOrDie.decimals());
    }

    function testInitialTotalSupplyIsZero() public view {
        // Arrange
        uint256 expectedInitialSupply = 0;
        // Act
        // Assert
        assert(expectedInitialSupply == liveOrDie.totalSupply());
    }

    function testPayEntranceFeeToStartPlaying() public {
        address User1 = makeAddr("User1");
        address User2 = makeAddr("User2");
        hoax(User1, 10 ether);
        assertTrue(liveOrDie.payEntranceFee{value: PRICE_ROUND_ONE}()); // This should not revert as we are sending the minimum amount.
        hoax(User2, 10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(AmountIsNotEnough.selector, User2, 0.1 ether)
        );
        liveOrDie.payEntranceFee{value: 0.1 ether}(); // This should revert as we are not sending the minimum amount.
        assertEq(address(liveOrDie).balance, PRICE_ROUND_ONE); // Check that our smart contract received the funds from User1.
    }

    function testMintingATokenForAUser() public {
        address User1 = makeAddr("User1");
        uint256 initialAmount = 0;
        uint256 mintedAmount = 1 * 10 ** liveOrDie.decimals();
        assert(initialAmount == liveOrDie.balanceOf(User1));
        liveOrDie.mint(User1, mintedAmount);
        assert(mintedAmount == liveOrDie.balanceOf(User1));
    }

    function testTransferingAMintedTokenToAUser() public {
        address User1 = makeAddr("User1");
        uint256 initialAmount = 0;
        uint256 mintedAmount = 1 * 10 ** liveOrDie.decimals();
        assert(initialAmount == liveOrDie.balanceOf(liveOrDie.owner())); // Initially the owner balance should be empty.

        liveOrDie.mint(liveOrDie.owner(), mintedAmount);
        assert(mintedAmount == liveOrDie.balanceOf(liveOrDie.owner())); // Then he owner balance should contain one token.

        liveOrDie.transfer(User1, mintedAmount);
        assert(mintedAmount == liveOrDie.balanceOf(User1)); // The User1 balance should contain one token.
        assert(initialAmount == liveOrDie.balanceOf(liveOrDie.owner())); // The owner balance should be empty again.
    }

    function testTransferingAMintedTokenFromAUserToOwner() public {
        address User1 = makeAddr("User1");
        uint256 initialAmount = 0;
        uint256 mintedAmount = 1 * 10 ** liveOrDie.decimals();

        liveOrDie.mint(User1, mintedAmount);
        assert(mintedAmount == liveOrDie.balanceOf(User1)); // .

        vm.startPrank(User1);
        liveOrDie.approve(liveOrDie.owner(), mintedAmount);
        vm.stopPrank();
        liveOrDie.transferFrom(User1, liveOrDie.owner(), mintedAmount);
        assert(initialAmount == liveOrDie.balanceOf(User1));
        assert(mintedAmount == liveOrDie.balanceOf(liveOrDie.owner()));
    }

    function testCreateNewBarrelIncrementsBarrelIndex() public {
        liveOrDie.createNewBarrel();
        assertEq(liveOrDie.getBarrelIndex(), 1);
    }

    function testInsertFirstBarrelPlayers() public {
        address[MAX_PLAYERS_ROUND_ONE] memory Users;
        for (uint i = 0; i < Users.length; i++) {
            Users[i] = makeAddr(Strings.toString(i));
            liveOrDie.addPlayerToAvailableBarrel(Users[i]);
            assertEq(liveOrDie.getPlayerAddress(0, i), Users[i]);
        }
    }

    function testPlayerIsNotInTheBarrel() public {
        address User1 = makeAddr("User1");
        address User2 = makeAddr("User2");
        liveOrDie.addPlayerToAvailableBarrel(User1);
        assertFalse(liveOrDie.isPlayerInBarrel(0, User2));
    }

    function testCantHaveTheSamePlayerTwiceInTheSameBarrel() public {
        address User1 = makeAddr("User1");
        liveOrDie.addPlayerToAvailableBarrel(User1);
        vm.expectRevert(
            abi.encodeWithSelector(PlayerAlreadyInTheBarrel.selector, 0, User1)
        );
        liveOrDie.addPlayerToAvailableBarrel(User1);
    }

    function testPickRandomPlayerRevertsIfBarrelIsNotFull() public {
        address User1 = makeAddr("User1");
        liveOrDie.addPlayerToAvailableBarrel(User1);
        vm.expectRevert(abi.encodeWithSelector(BarrelIsNotFull.selector, 1));
        liveOrDie.pickRandomPlayer(MAX_PLAYERS_ROUND_ONE);
    }

    function testEventIsEmitedWhenAPlayerIsAdded() public {
        address User1 = makeAddr("User1");
        vm.expectEmit(true, false, false, true);
        emit playerAddedToABarrel(User1, 0);
        liveOrDie.addPlayerToAvailableBarrel(User1);
    }

    function testPullTheTriggerEmitsPlayerEliminatedEvent() public {
        address[MAX_PLAYERS_ROUND_ONE] memory Users;
        for (uint i = 0; i < Users.length; i++) {
            Users[i] = makeAddr(Strings.toString(i));
            liveOrDie.addPlayerToAvailableBarrel(Users[i]);
        }
        vm.expectEmit(false, false, false, true);
        emit playerEliminated(Users[1], 0);
        liveOrDie.pullTheTrigger();
    }

    function testPickedRandomPlayerIsInCurrentBarrel() public {
        address[MAX_PLAYERS_ROUND_ONE] memory Users;
        for (uint i = 0; i < Users.length; i++) {
            Users[i] = makeAddr(Strings.toString(i));
            liveOrDie.addPlayerToAvailableBarrel(Users[i]);
        }
        address player = liveOrDie.pickRandomPlayer(MAX_PLAYERS_ROUND_ONE);
        assertTrue(liveOrDie.isPlayerInBarrel(0, player));
    }

    uint8[] public fixtureNumberOfPlayers = [1, 5, 132]; // Todo: check if the fixture works

    function testInsertRandomNumberOfPlayers(uint8 numberOfPlayers) public {
        vm.assume(numberOfPlayers > 0);
        address[] memory Users = new address[](numberOfPlayers);

        for (uint8 i = 0; i < numberOfPlayers; i++) {
            Users[i] = makeAddr(Strings.toString(i));
            liveOrDie.addPlayerToAvailableBarrel(Users[i]);
            assertEq(
                liveOrDie.getPlayerAddress(
                    liveOrDie.getBarrelIndex(),
                    i % MAX_PLAYERS_ROUND_ONE
                ),
                Users[i]
            );
        }
        assertEq(
            liveOrDie.getBarrelIndex(),
            (numberOfPlayers - 1) / MAX_PLAYERS_ROUND_ONE
        );
    }

    function testIsThePlayerListCorrectlyFilled() public {
        uint numberOfPlayers = 13778;
        address[] memory Users = new address[](numberOfPlayers);

        // Create a list of players.
        // Then we add players into an available barrel, grouped by barrel size (MAX_PLAYERS_ROUND_ONE).

        for (uint i = 0; i < numberOfPlayers; i++) {
            Users[i] = makeAddr(Strings.toString(i));
            liveOrDie.addPlayerToAvailableBarrel(Users[i]);
        }

        // Make sure the mapping of the players is correct and that the players are correctly dispatched in the barrels.
        for (uint i = 0; i < numberOfPlayers; i++) {
            assertEq(
                liveOrDie.getPlayerAddress(
                    i / MAX_PLAYERS_ROUND_ONE,
                    i % MAX_PLAYERS_ROUND_ONE
                ),
                Users[i]
            );
        }
    }

    function testOnePlayerDidNotReceivedATokenAndAllOthersDid() public {
        uint numberOfPlayers = 13778;
        address[] memory Users = new address[](numberOfPlayers);

        // Create a list of players.
        // Then we add players into an available barrel, grouped by barrel size (MAX_PLAYERS_ROUND_ONE).

        for (uint i = 0; i < numberOfPlayers; i++) {
            Users[i] = makeAddr(Strings.toString(i));
            liveOrDie.addPlayerToAvailableBarrel(Users[i]);

            if (i > 0 && i % MAX_PLAYERS_ROUND_ONE == 0) {
                uint256 amount = 0;
                uint256 barrelIndex = liveOrDie.getBarrelIndex() - 1;

                // For each full barrel, count how many tokens have been created
                // by adding up the total number of tokens in that barrel.

                for (uint j = 0; j < MAX_PLAYERS_ROUND_ONE; j++) {
                    amount += liveOrDie.balanceOf(
                        liveOrDie.getPlayerAddress(barrelIndex, j)
                    );
                }

                // Make sure that for each full barrel, there is a "dead" player who has not received a token.
                // And that the other "living" players have received a token.
                assertEq(
                    amount,
                    (MAX_PLAYERS_ROUND_ONE - 1) * 10 ** liveOrDie.decimals()
                );
            }
        }
    }

    function testCanPlayRoundTwoOnlyIfYouHaveALiveOrDieToken() public {
        uint numberOfPlayers = 13;
        address[] memory Users = new address[](numberOfPlayers);

        // Create a list of players.
        // Then we add players into an available barrel, grouped by barrel size (MAX_PLAYERS_ROUND_ONE).

        for (uint i = 0; i < numberOfPlayers; i++) {
            Users[i] = makeAddr(Strings.toString(i));
            liveOrDie.addPlayerToAvailableBarrel(Users[i]);
        }

        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20InsufficientAllowance.selector,
                address(liveOrDieRoundTwo),
                0,
                1 * 10 ** liveOrDie.decimals()
            )
        );
        liveOrDieRoundTwo.addPlayerToAvailableBarrel(Users[0]);

        // Todo:
        // vm.deal / vm.prank to give allowance and test with allowance.
        // liveOrDieRoundTwo.addPlayerToAvailableBarrel(Users[1]);

        vm.expectRevert(
            abi.encodeWithSelector(PlayerNeedLODTokenToPlay.selector, Users[2])
        );
        liveOrDieRoundTwo.addPlayerToAvailableBarrel(Users[2]);
        // liveOrDieRoundTwo.addPlayerToAvailableBarrel(Users[3]);
        // liveOrDieRoundTwo.addPlayerToAvailableBarrel(Users[4]);
        // liveOrDieRoundTwo.addPlayerToAvailableBarrel(Users[5]);
    }

    function testGetMaxPlayersFirstRound() public view {
        assertEq(liveOrDie.getMaxPlayersFirstRound(), MAX_PLAYERS_ROUND_ONE);
    }
}
