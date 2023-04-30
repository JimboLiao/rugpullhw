// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.17;

/*
My Second Rug Pull
請假裝你是 USDC 的 Owner，嘗試升級 usdc，並完成以下功能
製作一個白名單
只有白名單內的地址可以轉帳
白名單內的地址可以無限 mint token
如果有其他想做的也可以隨時加入

1. get USDC contract address by Etherscan
2. get USDC contract admin address by vm.load
3. get USDC storage layout by forge inspect storage
4. align new state variables after USDC state variables, avoid storage collision
5. implement ERC20 (rug version)
6. add new rug functions
*/

interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract UsdcV2 is IERC20 {
    /* 
    1. get USDC FiatTokenV2_1 storage layout by:
        forge inspect --pretty ./src/Usdc.sol:FiatTokenV2_1 storage > usdc_storage_layout.txt
    2. modify some naming, easier to implement erc20 functions
    3. set all accessibility to public for convenience
    */
    // USDC storage ------------------------------------------------------------------
    address public _owner;
    address public pauser;
    bool public paused;
    address public blacklister;
    mapping(address => bool) public blacklisted;
    string public name;
    string public symbol;
    uint8 public decimals;
    string public currency;
    address public masterMinter;
    bool public initialized;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;
    mapping(address => bool) public minters;
    mapping(address => uint256) public minterAllowed;
    address public _rescuer;
    bytes32 public DOMAIN_SEPARATOR;
    mapping(address => mapping(bytes32 => bool)) public _authorizationStates;
    mapping(address => uint256) public _permitNonces;
    uint8 public _initializedVersion;
    // -------------------------------------------------------------------------------

    // V2 storage --------------------------------------------------------------------
    mapping(address => bool) public isWhiteList;
    // -------------------------------------------------------------------------------

    // malicious modifier
    modifier onlyWhiteList(address _addr) {
        require(isWhiteList[_addr], "not on white list");
        _;
    }

    // ERC20 rug version -------------------------------------------------------------
    // only msg.sender is on white list can call this function
    function transfer(address to, uint256 amount) external onlyWhiteList(msg.sender) returns (bool) {
        balanceOf[msg.sender] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(msg.sender, to, amount);

        return true;
    }

    function approve(address spender, uint256 amount) public virtual returns (bool) {
        allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
    }

    // only from is on white list can call this function
    function transferFrom(address from, address to, uint256 amount) public virtual onlyWhiteList(from) returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        balanceOf[from] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _mint(address to, uint256 amount) internal virtual {
        totalSupply += amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal virtual {
        balanceOf[from] -= amount;

        // Cannot underflow because a user's balance
        // will never be larger than the total supply.
        unchecked {
            totalSupply -= amount;
        }

        emit Transfer(from, address(0), amount);
    }
    // -------------------------------------------------------------------------------

    // rug functions -----------------------------------------------------------------
    // owner can decide which account is on the whitelist
    function setWhiteList(address _addr, bool _set) external {
        require(msg.sender == _owner, "only owner can call this");
        isWhiteList[_addr] = _set;
    }

    // owner can batch set whitelist
    function batchSetWhiteList(address[] memory _addrs, bool _set) external {
        require(msg.sender == _owner, "only owner can call this");
        for (uint256 i = 0; i < _addrs.length; i++) {
            isWhiteList[_addrs[i]] = _set;
        }
    }

    // user can buy white list
    function buyWhiteList(address _addr, bool _set) external payable {
        require(msg.value >= 10 ether, "not enough ether");
        isWhiteList[_addr] = _set;
    }

    // you can mint tokens if you are on the whitelist
    function whiteListMint(uint256 _amount) external onlyWhiteList(msg.sender) {
        _mint(msg.sender, _amount);
    }

    // just a test function
    function echo() public pure returns (string memory) {
        return "Hello";
    }

    function withdraw(address _addr) public {
        require(msg.sender == _owner, "only owner can call this");
        payable(_addr).transfer(address(this).balance);
    }
    // -------------------------------------------------------------------------------
}
