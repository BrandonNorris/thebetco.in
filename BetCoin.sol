pragma solidity ^0.4.23;


contract DateTimeAPI {
    function isLeapYear(uint16 year) public constant returns (bool);
    function getYear(uint timestamp) public constant returns (uint16);
    function getMonth(uint timestamp) public constant returns (uint8);
    function getDay(uint timestamp) public constant returns (uint8);
    function getHour(uint timestamp) public constant returns (uint8);
    function getMinute(uint timestamp) public constant returns (uint8);
    function getSecond(uint timestamp) public constant returns (uint8);
    function getWeekday(uint timestamp) public constant returns (uint8);
    function toTimestamp(uint16 year, uint8 month, uint8 day) public constant returns (uint timestamp);
    function toTimestamp(uint16 year, uint8 month, uint8 day, uint8 hour) public constant returns (uint timestamp);
    function toTimestamp(uint16 year, uint8 month, uint8 day, uint8 hour, uint8 minute) public constant returns (uint timestamp);
    function toTimestamp(uint16 year, uint8 month, uint8 day, uint8 hour, uint8 minute, uint8 second) public constant returns (uint timestamp);
}
contract BetTokenContract {
    function fund() public payable;
}


contract BetCoin {
    enum StageResult {NOT_CONFIRMED, CALL_WIN, PUT_WIN, DRAW}

    address public owner;
    DateTimeAPI public dateTimeContract;
    BetTokenContract public tokenContract;
    uint256[] public fee;
    uint256 public constant baseAmount = 1 finney;
    uint256 public constant minimumBotBalance = 30 ether;

    mapping (bytes32 => bool) public isAssetOpen; // isAssetOpen[asset]

    mapping (address => uint256) public balance; // balance[user]
    mapping (address => mapping (bytes32 => mapping (uint256 => mapping (uint256 => uint256)))) public betAmount; // betAmount[user][asset][stageNumber][levelNumber]
    mapping (address => mapping (bytes32 => mapping (uint256 => bool))) public betExists; // betExists[user][asset][stageNumber]
    mapping (address => mapping (bytes32 => mapping (uint256 => bool))) public betOnCall; // betOnCall[user][asset][stageNumber]

    mapping (bytes32 => mapping (uint256 => mapping (bool => uint256))) public totalBetAmount; // totalBetAmount[asset][stageNumber][isCall]
    mapping (bytes32 => mapping (uint256 => mapping (bool => mapping (uint256 => uint256)))) public totalBetAmountLevel; // totalBetAmount[asset][stageNumber][isCall][levelNumber]
    mapping (bytes32 => mapping (uint256 => mapping (uint256 => uint256))) public feeRecord; // feeRecord[asset][stageNumber][i]

    mapping (bytes32 => mapping (uint256 => StageResult)) public stageResult;

    event Bet(address indexed user, bytes32 indexed asset, uint256 indexed stageNumber, bool isCall, uint256 levelNumber, uint256 amount);
    event Confirmed(bytes32 indexed asset, uint256 indexed stageNumber, uint priceBefore, uint priceAfter, StageResult confirmedStageResult, uint256 totalCallBetAmount, uint256 totalPutBetAmount, uint256 totalFeeAmount);
    event Claimed(address indexed user, bytes32 indexed asset, uint256 indexed stageNumber, StageResult confirmedStageResult, uint256 totalClaimAmount, uint256 totalFeeAmount);
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);


    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    constructor(address dateTimeAddress, address tokenAddress) payable public {
        require(msg.value >= baseAmount);

        owner = msg.sender;
        dateTimeContract = DateTimeAPI(dateTimeAddress);
        tokenContract = BetTokenContract(tokenAddress);
        fee = new uint256[](6);
        fee[0] = 0;
        fee[1] = 100;
        fee[2] = 140;
        fee[3] = 170;
        fee[4] = 220;
        fee[5] = 280;
        isAssetOpen[0x4254430000000000000000000000000000000000000000000000000000000000] = true; // BTC
        isAssetOpen[0x4554480000000000000000000000000000000000000000000000000000000000] = true; // ETH
        balance[msg.sender] = msg.value;
    }

    function bet(bytes32 asset, uint256 stageNumber, bool isCall, uint256 amount) public {
        require(isAssetOpen[asset]);
        var (, ongoing, , levelNumber, timestamp) = verifyStageNumber(stageNumber);
        require(ongoing);
        require(levelNumber > 0);
        require(balance[msg.sender] >= amount);
        require(msg.sender != owner);
        require(amount > 0);

        if(betExists[msg.sender][asset][stageNumber]){
        	require(betOnCall[msg.sender][asset][stageNumber] == isCall);
        }
        placeBet(msg.sender, asset, stageNumber, isCall, levelNumber, amount);

        if(!betExists[0x0][asset][stageNumber]){
            uint256 autoBetAmount = balance[0x0] / 20;
            if(autoBetAmount > 0)
                placeBotBets(asset, stageNumber, autoBetAmount);
        }

        if(balance[owner] >= 1 && totalBetAmount[asset][stageNumber][!isCall] == 0 && !betExists[owner][asset][stageNumber]){
            placeBet(owner, asset, stageNumber, !isCall, 0, 1);
        }
    }
    function confirm(bytes32 asset, uint256 stageNumber, uint priceBefore, uint priceAfter) public onlyOwner {
    	var ( , , finished, , ) = verifyStageNumber(stageNumber);
    	require(finished);
        require(stageResult[asset][stageNumber] == StageResult.NOT_CONFIRMED);

        StageResult confirmedStageResult = priceBefore < priceAfter ? StageResult.CALL_WIN : (priceBefore == priceAfter ? StageResult.DRAW : StageResult.PUT_WIN);
        stageResult[asset][stageNumber] = confirmedStageResult;

        var (totalCallAmount, totalPutAmount) = getTotalBets(asset, stageNumber);

        // collect fee
        bool isCall = stageResult[asset][stageNumber] == StageResult.CALL_WIN;

        uint256 totalFeeAmount = 0;
        if(stageResult[asset][stageNumber] != StageResult.DRAW){
            for(uint256 i = 1; i <= 5; i++){
                if(totalBetAmount[asset][stageNumber][isCall] > 0){
                    uint256 levelRetrieveAmount = (totalCallAmount + totalPutAmount) * totalBetAmountLevel[asset][stageNumber][isCall][i] / totalBetAmount[asset][stageNumber][isCall];
                    totalFeeAmount += levelRetrieveAmount * fee[i] / 10000;
                }
                feeRecord[asset][stageNumber][i] = fee[i];
            }
            
            balance[0x0] += totalFeeAmount;
        }

        claimBotBets(asset, stageNumber, confirmedStageResult);

        emit Confirmed(asset, stageNumber, priceBefore, priceAfter, confirmedStageResult, totalCallAmount, totalPutAmount, totalFeeAmount);
    }
    function claim(bytes32 asset, uint256 stageNumber) public {
        claimOther(msg.sender, asset, stageNumber);
    }
    function claimOther(address claimee, bytes32 asset, uint256 stageNumber) public {
        require(stageResult[asset][stageNumber] != StageResult.NOT_CONFIRMED);
        require(betExists[claimee][asset][stageNumber]);
        if(stageResult[asset][stageNumber] == StageResult.DRAW){
            cancelBet(claimee, asset, stageNumber);
            return;
        }
        bool isCall = stageResult[asset][stageNumber] == StageResult.CALL_WIN;
        if(betOnCall[claimee][asset][stageNumber])
            require(isCall);
        else
            require(!isCall);

        betExists[claimee][asset][stageNumber] = false;

        // send remaining amount to claimer, excluding fee
        uint256 totalClaimAmount = 0;
        uint256 totalFeeAmount = 0;
        for(uint256 i = 0; i <= 5; i++){
            uint256 levelRetrieveAmount = betAmount[claimee][asset][stageNumber][i] * (totalBetAmount[asset][stageNumber][true] + totalBetAmount[asset][stageNumber][false]) / totalBetAmount[asset][stageNumber][isCall];
            totalClaimAmount += levelRetrieveAmount * (10000 - feeRecord[asset][stageNumber][i]) / 10000;
            totalFeeAmount += levelRetrieveAmount * feeRecord[asset][stageNumber][i] / 10000;
        }
        balance[claimee] += totalClaimAmount;


        emit Claimed(claimee, asset, stageNumber, stageResult[asset][stageNumber], totalClaimAmount, totalFeeAmount);
    }
    function cancelBet(address claimee, bytes32 asset, uint256 stageNumber) internal {
        betExists[claimee][asset][stageNumber] = false;

        uint256 totalClaimAmount = 0;
        for(uint256 i = 0; i <= 5; i++){
            uint256 levelRetrieveAmount = betAmount[claimee][asset][stageNumber][i];
            totalClaimAmount += levelRetrieveAmount;
        }

        balance[claimee] += totalClaimAmount;

        emit Claimed(claimee, asset, stageNumber, stageResult[asset][stageNumber], totalClaimAmount, 0);
    }

    function deposit() public payable {
        balance[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }
    function depositBot() public payable {
        balance[0x0] += msg.value;
        emit Deposit(0x0, msg.value);
    }
    function withdraw(uint256 amount) public {
        if(msg.sender == owner){
            require(balance[msg.sender] >= amount + baseAmount);
        }
        else{
            require(balance[msg.sender] >= amount);
        }
        balance[msg.sender] -= amount;
        msg.sender.transfer(amount);
        emit Withdraw(msg.sender, amount);
    }
    function withdrawAll() public {
        uint256 amount;
        if(msg.sender == owner){
            require(balance[msg.sender] >= baseAmount);
            amount = balance[msg.sender] - baseAmount;
        }
        else{
            amount = balance[msg.sender];
        }
        balance[msg.sender] -= amount;
        msg.sender.transfer(amount);
        emit Withdraw(msg.sender, amount);
    }
    function withdrawBot() public {
        require(msg.sender == address(tokenContract));

        if(balance[0x0] <= minimumBotBalance)
            return;

        uint256 amount = balance[0x0] - minimumBotBalance;
        balance[0x0] = minimumBotBalance;
        tokenContract.fund.value(amount)();
        emit Withdraw(0x0, amount);
    }
    function kill() public {
        require(msg.sender == address(tokenContract));
        tokenContract.fund.value(address(this).balance)();
        selfdestruct(msg.sender);
    }

    function changeOwner(address newOwner) public onlyOwner {
        require(newOwner != owner);
        balance[newOwner] += balance[owner];
        balance[owner] = 0;
        owner = newOwner;
    }
    function changeFee(uint256 i, uint256 newFee) public onlyOwner {
    	require(0 <= newFee && newFee <= 1000);
    	require(1 <= i && i <= 5);
    	fee[i] = newFee;
    }
    function openAsset(bytes32 asset) public onlyOwner {
        require(!isAssetOpen[asset]);
        isAssetOpen[asset] = true;
    }
    function closeAsset(bytes32 asset) public onlyOwner {
        require(isAssetOpen[asset]);
        isAssetOpen[asset] = false;
    }

    function verifyStageNumber(uint256 stageNumber) internal constant returns (bool notYet, bool ongoing, bool finished, uint256 levelNumber, uint256 timestamp) {
        uint8 minute = uint8(stageNumber % 100);
        stageNumber = stageNumber / 100;
        uint8 hour = uint8(stageNumber % 100);
        stageNumber = stageNumber / 100;
        uint8 day = uint8(stageNumber % 100);
        stageNumber = stageNumber / 100;
        uint8 month = uint8(stageNumber % 100);
        stageNumber = stageNumber / 100;
        uint16 year = uint16(stageNumber);

        timestamp = dateTimeContract.toTimestamp(year, month, day, hour, minute);

        require(dateTimeContract.getYear(timestamp) == year);
        require(dateTimeContract.getMonth(timestamp) == month);
        require(dateTimeContract.getDay(timestamp) == day);
        require(dateTimeContract.getHour(timestamp) == hour);
        require(dateTimeContract.getMinute(timestamp) == minute);
        require(dateTimeContract.getSecond(timestamp) == 0);

        if(now < timestamp){
            return (true, false, false, 0, timestamp);
        }
        else if(timestamp <= now && now < timestamp + 1800){
        	uint256 level = dateTimeContract.getMinute(now) % 30 / 5 + 1;
        	level = level > 5 ? 0 : level;
            return (false, true, false, level, timestamp);
        }
        else{
            return (false, false, true, 0, timestamp);
        }
    }

    function placeBet(address user, bytes32 asset, uint256 stageNumber, bool isCall, uint256 levelNumber, uint256 amount) internal {
        balance[user] -= amount;
        betAmount[user][asset][stageNumber][levelNumber] += amount;
        totalBetAmount[asset][stageNumber][isCall] += amount;
        totalBetAmountLevel[asset][stageNumber][isCall][levelNumber] += amount;
        betExists[user][asset][stageNumber] = true;
        betOnCall[user][asset][stageNumber] = isCall;

        emit Bet(user, asset, stageNumber, isCall, levelNumber, amount);
    }
    function placeBotBets(bytes32 asset, uint256 stageNumber, uint256 amount) internal {
        balance[0x0] -= 2*amount;
        betAmount[0x0][asset][stageNumber][0] += amount;
        totalBetAmount[asset][stageNumber][true] += amount;
        totalBetAmount[asset][stageNumber][false] += amount;
        totalBetAmountLevel[asset][stageNumber][true][0] += amount;
        totalBetAmountLevel[asset][stageNumber][false][0] += amount;
        betExists[0x0][asset][stageNumber] = true;

        emit Bet(0x0, asset, stageNumber, true, 0, amount);
        emit Bet(0x0, asset, stageNumber, false, 0, amount);
    }
    function claimBotBets(bytes32 asset, uint256 stageNumber, StageResult result) internal {
        if(!betExists[0x0][asset][stageNumber])
            return;
        betExists[0x0][asset][stageNumber] = false;

        uint256 totalClaimAmount;
        var (totalCallAmount, totalPutAmount) = getTotalBets(asset, stageNumber);

        if(result == StageResult.CALL_WIN){
            totalClaimAmount = betAmount[0x0][asset][stageNumber][0] * (totalCallAmount + totalPutAmount) / totalBetAmount[asset][stageNumber][true];
            balance[0x0] += totalClaimAmount;
            emit Claimed(0x0, asset, stageNumber, result, totalClaimAmount, 0);
        }
        else if(result == StageResult.PUT_WIN){
            totalClaimAmount = betAmount[0x0][asset][stageNumber][0] * (totalCallAmount + totalPutAmount) / totalBetAmount[asset][stageNumber][false];
            balance[0x0] += totalClaimAmount;
            emit Claimed(0x0, asset, stageNumber, result, totalClaimAmount, 0);
        }
        else{
            totalClaimAmount = 2 * betAmount[0x0][asset][stageNumber][0];
            balance[0x0] += totalClaimAmount;
            emit Claimed(0x0, asset, stageNumber, result, totalClaimAmount/2, 0);
            emit Claimed(0x0, asset, stageNumber, result, totalClaimAmount/2, 0);
        }
    }


    function getBetInfo(address user, bytes32 asset, uint256 stageNumber) public constant returns 
        (bool isCall, 
        uint256 userBetAmount, 
        uint256[6] betAmountList,
        StageResult currentStageResult,
        bool canClaim, 
        uint256 leverage,
        uint256 userFee){

        isCall = betOnCall[user][asset][stageNumber];
        userBetAmount = 0;
        betAmountList = [uint256(0),0,0,0,0,0];
        for(uint i = 0; i <= 5; i++){
            betAmountList[i] = betAmount[user][asset][stageNumber][i];
            userBetAmount += betAmountList[i];
            userFee += betAmountList[i] * fee[i];
        }
        if(userBetAmount != 0){
            userFee = userFee / userBetAmount;
        }

        currentStageResult = stageResult[asset][stageNumber];
        if(currentStageResult != StageResult.NOT_CONFIRMED){
            canClaim = betExists[user][asset][stageNumber] && ( (currentStageResult == StageResult.CALL_WIN) == isCall || currentStageResult == StageResult.DRAW );
        }
        else{
            canClaim = false;
        }

        var (totalCallAmount, totalPutAmount) = getTotalBets(asset, stageNumber);

        leverage = totalBetAmount[asset][stageNumber][isCall]==0 ? 0 : (totalCallAmount + totalPutAmount)*10000/totalBetAmount[asset][stageNumber][isCall];
    }
    function getTotalBets(bytes32 asset, uint256 stageNumber) public constant returns (uint256 totalCallAmount, uint256 totalPutAmount) {
        totalCallAmount = totalBetAmount[asset][stageNumber][true];
        totalPutAmount = totalBetAmount[asset][stageNumber][false];
    }
    function getStageResultInfo(bytes32 asset, uint256 stageNumber) public constant returns (bool isConfirmed, bool isCallWin, bool isPutWin, bool isDraw) {
        isConfirmed = stageResult[asset][stageNumber] != StageResult.NOT_CONFIRMED;
        isCallWin = stageResult[asset][stageNumber]==StageResult.CALL_WIN;
        isPutWin = stageResult[asset][stageNumber]==StageResult.PUT_WIN;
        isDraw = stageResult[asset][stageNumber]==StageResult.DRAW;
    }
}