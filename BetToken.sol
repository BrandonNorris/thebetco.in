pragma solidity ^0.4.23;

contract BetCoin {
	function withdrawBot() public;
	function kill() public;
}

contract ERC20Interface {
	function totalSupply() public constant returns (uint supply);
	function balanceOf(address _owner) public constant returns (uint balance);
	function transfer(address _to, uint _value) public returns (bool success);
	function transferFrom(address _from, address _to, uint _value) public returns (bool success);
	function approve(address _spender, uint _value) public returns (bool success);
	function allowance(address _owner, address _spender) public constant returns (uint remaining);
	event Transfer(address indexed _from, address indexed _to, uint _value);
	event Approval(address indexed _owner, address indexed _spender, uint _value);
}

/**
 * @title Ownable
 * @dev The Ownable contract has an owner address, and provides basic authorization control
 * functions, this simplifies the implementation of "user permissions".
 */
contract Ownable {
    address public owner;


    event OwnershipRenounced(address indexed previousOwner);
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );


    /**
     * @dev The Ownable constructor sets the original `owner` of the contract to the sender
     * account.
     */
    constructor() public {
        owner = msg.sender;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    /**
     * @dev Allows the current owner to relinquish control of the contract.
     * @notice Renouncing to ownership will leave the contract without an owner.
     * It will not be possible to call the functions with the `onlyOwner`
     * modifier anymore.
     */
    function renounceOwnership() public onlyOwner {
        emit OwnershipRenounced(owner);
        owner = address(0);
    }

    /**
     * @dev Allows the current owner to transfer control of the contract to a newOwner.
     * @param _newOwner The address to transfer ownership to.
     */
    function transferOwnership(address _newOwner) public onlyOwner {
        _transferOwnership(_newOwner);
    }

    /**
     * @dev Transfers control of the contract to a newOwner.
     * @param _newOwner The address to transfer ownership to.
     */
    function _transferOwnership(address _newOwner) internal {
        require(_newOwner != address(0));
        emit OwnershipTransferred(owner, _newOwner);
        owner = _newOwner;
    }
}

contract BetTokenContract is ERC20Interface, Ownable {
	string public constant symbol = "BT";
	string public constant name = "BetToken";
	uint8 public constant decimals = 0;
	uint private constant _totalSupply = 100;

	uint public cumulativePayout;
	uint public remainderCollection;
	uint public recentPayoutTime;

	BetCoin public betCoinContract;

	mapping (address => uint) public balances;
	mapping (address => uint) public lastCumulativePayouts;
	mapping (address => uint) public payoutBalances;
	mapping (address => mapping (address => uint)) public allowed;

	mapping (address => bool) public agreeOnCollect;
	mapping (address => bool) public agreeOnSelfdestruct;

	event Payout(address receiver, uint amount);


	constructor(address betCoinAddress) public {
		betCoinContract = BetCoin(betCoinAddress);

		balances[msg.sender] = _totalSupply;
		recentPayoutTime = now;

		emit Transfer(0, msg.sender, _totalSupply);
	}

	function() public payable {
		if(msg.value > 0)
			fund();
		else
			withdrawPayout(msg.sender);
	}

// ERC20 FUNCTIONS
	function totalSupply() public constant returns (uint supply){
		return _totalSupply;
	}
	function balanceOf(address _owner) public constant returns (uint balance){
		return balances[_owner];
	}
	function transfer(address _to, uint _value) public returns (bool success){
		if(balances[msg.sender] < _value)
			return false;

		updatePayout(msg.sender);
		updatePayout(_to);

		balances[msg.sender] -= _value;
		balances[_to] += _value;

		emit Transfer(msg.sender, _to, _value);
		return true;
	}
	function transferFrom(address _from, address _to, uint _value) public returns (bool success){
		if(balances[_from] >= _value
			&& allowed[_from][msg.sender] >= _value){

			updatePayout(_from);
			updatePayout(_to);

			balances[_from] -= _value;
			allowed[_from][msg.sender] -= _value;
			balances[_to] += _value;

			emit Transfer(_from, _to, _value);
			return true;
		}
		else{
			return false;
		}
	}
	function approve(address _spender, uint _value) public returns (bool success){
		allowed[msg.sender][_spender] = _value;
		emit Approval(msg.sender, _spender, _value);
		return true;
	}
	function allowance(address _owner, address _spender) public constant returns (uint remaining){
		return allowed[_owner][_spender];
	}

// PAYOUT FUNCTIONS

	function fund() public payable {
		cumulativePayout += msg.value;
	}
	function withdrawPayout(address _owner) public {
		updatePayout(_owner);
		uint withdrawValue = payoutBalances[_owner];
		if(withdrawValue == 0)
			return;
		payoutBalances[_owner] = 0;
		_owner.transfer(withdrawValue);

		emit Payout(_owner, withdrawValue);
	}
	function collectFund(address[] list) public {
		uint totalAgreeAmount = 0;
		for(uint i = 0; i < list.length; i++){
			if(agreeOnCollect[list[i]]){
				totalAgreeAmount += balances[list[i]];
				agreeOnCollect[list[i]] = false;
			}
		}

		require(totalAgreeAmount >= 50);

		betCoinContract.withdrawBot();
	}
	function voteToCollectFund(bool agree) public {
		agreeOnCollect[msg.sender] = agree;
	}
	function betCoinSelfdestruct(address[] list) public {
		uint totalAgreeAmount = 0;
		for(uint i = 0; i < list.length; i++){
			if(agreeOnSelfdestruct[list[i]]){
				totalAgreeAmount += balances[list[i]];
				agreeOnSelfdestruct[list[i]] = false;
			}
		}

		require(totalAgreeAmount >= 100);

		betCoinContract.kill();
	}
	function voteToSelfdestruct(bool agree) public {
		agreeOnSelfdestruct[msg.sender] = agree;
	}

	function changeBetCoinAddress(address newBetCoin) public onlyOwner {
		betCoinContract = BetCoin(newBetCoin);
	} 

	function updatePayout(address _owner) internal {
		if(cumulativePayout == lastCumulativePayouts[_owner])
			return;
		uint extraPayoutValue = getExtraPayoutValue(_owner);
		lastCumulativePayouts[_owner] = cumulativePayout;
		payoutBalances[_owner] += extraPayoutValue;
	}

	function getExtraPayoutValue(address _owner) public constant returns (uint value) {
		value = balances[_owner] * (cumulativePayout - lastCumulativePayouts[_owner]) / _totalSupply;
	}
	function getWithdrawablePayoutValue(address _owner) public constant returns (uint value) {
		value = payoutBalances[_owner] + getExtraPayoutValue(_owner);
	}
}