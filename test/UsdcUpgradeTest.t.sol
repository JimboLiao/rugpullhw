// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "solmate/tokens/ERC20.sol";
import {UsdcV2} from "../src/UsdcV2.sol";

// get interface by `cast interface`
interface IUsdcProxy {
    event AdminChanged(address previousAdmin, address newAdmin);
    event Upgraded(address implementation);

    function admin() external view returns (address);
    function changeAdmin(address newAdmin) external;
    function implementation() external view returns (address);
    function upgradeTo(address newImplementation) external;
    function upgradeToAndCall(address newImplementation, bytes memory data) external payable;
}

interface IERC20 {
    function balanceOf(address account) external returns (uint256);
}

contract UsdcUpgradeTest is Test {
    bytes32 private constant ADMIN_SLOT = 0x10d6a54a4754c8869d6886b5f5d7fbfa5b4522237ea5c60d11bc4e7a1ff9390b;
    bytes32 private constant IMPLEMENTATION_SLOT = 0x7050c9e0f4ca769c69bd3a8ef740bc37934f8e2c036e5a723fd8ee048ed3f8c3;
    address public constant usdcProxy = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public admin;
    address public owner;
    address public whiteUser;
    address public whiteUser2;
    address public normalUser;
    address public vitalik = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045; // vitalik.eth
    address public machibigbrother = 0x020cA66C30beC2c4Fe3861a94E4DB4A498A35872; // machibigbrother.eth
    uint256 public vitalikUsdcBalance;
    uint256 public machiUsdcBalance;
    uint256 public initialUsdcValue = 10 ether;
    UsdcV2 usdcV2;

    /*
    run in fork mode (./run_test_fork.sh)
    Setup : 
        1. set users' address and some value before upgrade
        2. upgrade
    */
    function setUp() public {
        // fork mode
        vm.createSelectFork("mainnet", 17148972);

        // get admin address
        bytes32 adminSlotValue = vm.load(usdcProxy, ADMIN_SLOT);
        // console.logBytes32(adminSlotValue);
        // 0x000000000000000000000000807a96288a1a408dbc13de2b1d087d10356395d2
        admin = address(uint160(uint256(adminSlotValue)));

        // get owner address
        bytes32 ownerSlotValue = vm.load(usdcProxy, 0); //owner address is at slot 0
        owner = address(uint160(uint256(ownerSlotValue)));
        usdcV2 = new UsdcV2();

        vm.label(usdcProxy, "USDC Proxy");
        vm.label(admin, "Admin");
        vm.label(owner, "Owner");
        vm.label(vitalik, "vitalik.eth");
        vm.label(machibigbrother, "machibigbrother.eth");

        // get some value before upgrade, we can compare this value after upgrade
        machiUsdcBalance = IERC20(usdcProxy).balanceOf(machibigbrother);
        // console.logUint(machiUsdcBalance); // 625000000000
        // console.logUint(machibigbrother.balance); // 1804515314895886078380
        vitalikUsdcBalance = IERC20(usdcProxy).balanceOf(vitalik);
        // console.logUint(vitalikUsdcBalance); // 400400761835
        // console.logUint(vitalik.balance); // 5149649178668713610207

        // upgrade to V2
        upgrade();
    }

    function upgrade() public {
        // only admin can upgrade proxy
        vm.prank(admin);
        IUsdcProxy(usdcProxy).upgradeTo(address(usdcV2));
    }

    // test upgrade successfully or not
    function testUpgrade() public {
        // can call functions in V2
        assertEq(UsdcV2(usdcProxy).echo(), "Hello");
        // balance before and after upgrade should be equal
        assertEq(UsdcV2(usdcProxy).balanceOf(machibigbrother), machiUsdcBalance);
        assertEq(UsdcV2(usdcProxy).balanceOf(vitalik), vitalikUsdcBalance);
    }

    // owner can put any account on the white list
    function testSetWhiteList() public {
        // cannot call setWhiteList if you are not owner
        vm.prank(machibigbrother);
        vm.expectRevert("only owner can call this");
        UsdcV2(usdcProxy).setWhiteList(machibigbrother, true);

        // only owner can set white list
        vm.prank(owner);
        UsdcV2(usdcProxy).setWhiteList(vitalik, true);
        assertTrue(UsdcV2(usdcProxy).isWhiteList(vitalik));
    }

    // owner can put lots account on white list at one time
    function testBatchSetWhiteList() public {
        // prepare inputs
        address[] memory whiteList = new address[](2);
        whiteList[0] = vitalik;
        whiteList[1] = machibigbrother;
        // cannot call batchSetWiteList if you are not owner
        vm.prank(machibigbrother);
        vm.expectRevert("only owner can call this");
        UsdcV2(usdcProxy).batchSetWhiteList(whiteList, true);
        // only owner can call batchSetWiteList
        vm.prank(owner);
        UsdcV2(usdcProxy).batchSetWhiteList(whiteList, true);
        assertTrue(UsdcV2(usdcProxy).isWhiteList(vitalik));
        assertTrue(UsdcV2(usdcProxy).isWhiteList(machibigbrother));
    }

    // you can pay ether to buy white list
    function testBuyWhiteList() public {
        uint256 machiEthBalance = machibigbrother.balance;
        vm.prank(machibigbrother);
        UsdcV2(usdcProxy).buyWhiteList{value: 10 ether}(machibigbrother, true);
        assertTrue(UsdcV2(usdcProxy).isWhiteList(machibigbrother));
        assertEq(machibigbrother.balance, machiEthBalance - 10 ether);
    }

    // you can also pay for kicking somebody out of the white list
    function testPayToKickWhiteListOut() public {
        vm.prank(owner);
        UsdcV2(usdcProxy).setWhiteList(vitalik, true);
        assertTrue(UsdcV2(usdcProxy).isWhiteList(vitalik));

        vm.prank(machibigbrother);
        UsdcV2(usdcProxy).buyWhiteList{value: 10 ether}(vitalik, false);
        assertFalse(UsdcV2(usdcProxy).isWhiteList(vitalik));
    }

    // you can buy white list... but owner can kick you out without cost
    function testBuyWhiteListAndKickOutByOwner() public {
        vm.prank(machibigbrother);
        UsdcV2(usdcProxy).buyWhiteList{value: 10 ether}(machibigbrother, true);
        assertTrue(UsdcV2(usdcProxy).isWhiteList(machibigbrother));

        vm.prank(owner);
        UsdcV2(usdcProxy).setWhiteList(machibigbrother, false);
        assertFalse(UsdcV2(usdcProxy).isWhiteList(machibigbrother));
    }

    // you can mint tokens if you are on the white list
    function testWhiteListMint(uint256 _amount) public {
        // mint amount should avoid totalSupply overflow
        vm.assume(_amount < type(uint256).max - UsdcV2(usdcProxy).totalSupply());

        // set white list
        vm.prank(owner);
        UsdcV2(usdcProxy).setWhiteList(vitalik, true);
        assertTrue(UsdcV2(usdcProxy).isWhiteList(vitalik));

        // mint amount tokens
        vm.prank(vitalik);
        UsdcV2(usdcProxy).whiteListMint(_amount);
        assertEq(UsdcV2(usdcProxy).balanceOf(vitalik), vitalikUsdcBalance + _amount);
    }

    // only msg.sender is on the white list can transfer
    function testTransfer(uint256 _amount) public {
        vm.assume(_amount <= vitalikUsdcBalance && _amount <= machiUsdcBalance);

        // only white list can transfer
        // normal user not on white list should revert
        vm.prank(machibigbrother);
        vm.expectRevert("not on white list");
        UsdcV2(usdcProxy).transfer(vitalik, _amount);

        // set white list
        vm.prank(owner);
        UsdcV2(usdcProxy).setWhiteList(vitalik, true);
        assertTrue(UsdcV2(usdcProxy).isWhiteList(vitalik));

        // whitelist can transfer
        vm.prank(vitalik);
        assertTrue(UsdcV2(usdcProxy).transfer(machibigbrother, _amount));
        assertEq(UsdcV2(usdcProxy).balanceOf(vitalik), vitalikUsdcBalance - _amount);
        assertEq(UsdcV2(usdcProxy).balanceOf(machibigbrother), machiUsdcBalance + _amount);
    }

    // only `from` on white list can transfer
    function testTransferFrom(uint256 _amount) public {
        vm.assume(_amount <= vitalikUsdcBalance && _amount <= machiUsdcBalance);

        // only from white list can transfer
        // normal user not on white list should revert
        vm.prank(machibigbrother);
        UsdcV2(usdcProxy).approve(address(this), _amount);
        vm.expectRevert("not on white list");
        UsdcV2(usdcProxy).transferFrom(machibigbrother, vitalik, _amount);

        // set white list
        vm.prank(owner);
        UsdcV2(usdcProxy).setWhiteList(vitalik, true);
        assertTrue(UsdcV2(usdcProxy).isWhiteList(vitalik));

        // whitelist can transfer
        vm.prank(vitalik);
        UsdcV2(usdcProxy).approve(address(this), _amount);
        assertTrue(UsdcV2(usdcProxy).transferFrom(vitalik, machibigbrother, _amount));
        assertEq(UsdcV2(usdcProxy).balanceOf(vitalik), vitalikUsdcBalance - _amount);
        assertEq(UsdcV2(usdcProxy).balanceOf(machibigbrother), machiUsdcBalance + _amount);
    }

    // owner can withdraw ether from proxy contract to specific address
    function testWithdraw(uint256 _amount) public {
        vm.assume(_amount < type(uint256).max - vitalik.balance);

        vm.deal(usdcProxy, _amount);
        assertEq(usdcProxy.balance, _amount);
        // if you're not owner, you cannot call withdraw
        vm.prank(machibigbrother);
        vm.expectRevert("only owner can call this");
        UsdcV2(usdcProxy).withdraw(machibigbrother);

        // only owner can call withdraw
        uint256 vitalikEthBalance = vitalik.balance;
        vm.prank(owner);
        UsdcV2(usdcProxy).withdraw(vitalik);

        assertEq(vitalik.balance, vitalikEthBalance + _amount);
        assertEq(usdcProxy.balance, 0);
    }
}
