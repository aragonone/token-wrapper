/*
 * SPDX-License-Identitifer:    GPL-3.0-or-later
 */

pragma solidity 0.4.24;

import "@aragon/os/contracts/apps/AragonApp.sol";
import "@aragon/os/contracts/common/IForwarder.sol";
import "@aragon/os/contracts/common/IsContract.sol";
import "@aragon/os/contracts/lib/math/SafeMath.sol";
import "@aragon/os/contracts/lib/token/ERC20.sol";

import "@aragonone/voting-connectors-contract-utils/contracts/ActivePeriod.sol";
import "@aragonone/voting-connectors-contract-utils/contracts/ERC20ViewOnly.sol";
import "@aragonone/voting-connectors-contract-utils/contracts/StaticInvoke.sol";
import "@aragonone/voting-connectors-contract-utils/contracts/interfaces/IERC20WithCheckpointing.sol";

import "./interfaces/IERC900History.sol";

/**
 * @title VotingAggregator
 * @notice Voting power aggregator across many sources that provides a "view-only" checkpointed
 *         ERC20 implementation.
 */
contract VotingAggregator is IERC20WithCheckpointing, IForwarder, IsContract, ERC20ViewOnly, AragonApp {
    using SafeMath for uint256;
    using StaticInvoke for address;
    using ActivePeriod for ActivePeriod.History;

    /* Hardcoded constants to save gas
    bytes32 public constant ADD_POWER_SOURCE_ROLE = keccak256("ADD_POWER_SOURCE_ROLE");
    bytes32 public constant MANAGE_POWER_SOURCE_ROLE = keccak256("MANAGE_POWER_SOURCE_ROLE");
    bytes32 public constant MANAGE_WEIGHTS_ROLE = keccak256("MANAGE_WEIGHTS_ROLE");
    */
    bytes32 public constant ADD_POWER_SOURCE_ROLE = 0x10f7c4af0b190fdd7eb73fa36b0e280d48dc6b8d355f89769b4f1a50a61d1929;
    bytes32 public constant MANAGE_POWER_SOURCE_ROLE = 0x79ac9d2706bbe6bcdb60a65ba8145a498f6d506aaa455baa7675dff5779cb99f;
    bytes32 public constant MANAGE_WEIGHTS_ROLE = 0xa36fcade8375289791865312a33263fdc82d07e097c13524c9d6436c0de396ff;

    // Arbitrary number, but having anything close to this number would most likely be unwieldy.
    // Note the primary protection this provides is to ensure that one cannot continue adding
    // sources to break gas limits even with all sources disabled.
    uint256 internal constant MAX_SOURCES = 20;

    string private constant ERROR_NO_POWER_SOURCE = "VA_NO_POWER_SOURCE";
    string private constant ERROR_POWER_SOURCE_TYPE_INVALID = "VA_POWER_SOURCE_TYPE_INVALID";
    string private constant ERROR_POWER_SOURCE_INVALID = "VA_POWER_SOURCE_INVALID";
    string private constant ERROR_POWER_SOURCE_ALREADY_ADDED = "VA_POWER_SOURCE_ALREADY_ADDED";
    string private constant ERROR_TOO_MANY_POWER_SOURCES = "VA_TOO_MANY_POWER_SOURCES";
    string private constant ERROR_ZERO_WEIGHT = "VA_ZERO_WEIGHT";
    string private constant ERROR_SAME_WEIGHT = "VA_SAME_WEIGHT";
    string private constant ERROR_CAN_NOT_FORWARD = "VA_CAN_NOT_FORWARD";
    string private constant ERROR_SOURCE_CALL_FAILED = "VA_SOURCE_CALL_FAILED";
    string private constant ERROR_INVALID_CALL_OR_SELECTOR = "VA_INVALID_CALL_OR_SELECTOR";

    enum PowerSourceType {
        Invalid,
        ERC20WithCheckpointing,
        ERC900
    }

    enum CallType {
        BalanceOfAt,
        TotalSupplyAt
    }

    struct PowerSource {
        PowerSourceType sourceType;
        uint256 weight;
        ActivePeriod.History activationHistory;
    }

    string public name;
    string public symbol;
    uint8 public decimals;

    mapping (address => PowerSource) internal powerSourceDetails;
    address[] public powerSources;

    event AddPowerSource(address indexed sourceAddress, PowerSourceType sourceType, uint256 weight);
    event ChangePowerSourceWeight(address indexed sourceAddress, uint256 newWeight);
    event DisablePowerSource(address indexed sourceAddress);
    event EnablePowerSource(address indexed sourceAddress);

    modifier sourceExists(address _sourceAddr) {
        require(_powerSourceExists(_sourceAddr), ERROR_NO_POWER_SOURCE);
        _;
    }

    /**
     * @notice Create a new voting power aggregator
     * @param _name The aggregator's display name
     * @param _symbol The aggregator's display symbol
     * @param _decimals The aggregator's display decimal units
     */
    function initialize(string _name, string _symbol, uint8 _decimals) external onlyInit {
        initialized();

        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    /**
     * @notice Add a new power source (`_sourceAddr`) with `_weight` weight
     * @param _sourceAddr Address of the power source
     * @param _sourceType Interface type of the power source
     * @param _weight Weight to assign to the source
     */
    function addPowerSource(address _sourceAddr, PowerSourceType _sourceType, uint256 _weight)
        external
        authP(ADD_POWER_SOURCE_ROLE, arr(_sourceAddr, _weight))
    {
        // Sanity check arguments
        require(
            _sourceType == PowerSourceType.ERC20WithCheckpointing || _sourceType == PowerSourceType.ERC900,
            ERROR_POWER_SOURCE_TYPE_INVALID
        );
        require(_weight > 0, ERROR_ZERO_WEIGHT);
        require(_sanityCheckSource(_sourceAddr, _sourceType), ERROR_POWER_SOURCE_INVALID);

        // Ensure internal consistency
        require(!_powerSourceExists(_sourceAddr), ERROR_POWER_SOURCE_ALREADY_ADDED);
        require(powerSources.length < MAX_SOURCES, ERROR_TOO_MANY_POWER_SOURCES);

        // Add source
        powerSources.push(_sourceAddr);

        PowerSource storage source = powerSourceDetails[_sourceAddr];
        source.sourceType = _sourceType;
        source.weight = _weight;

        // Start activation history with [current block, max block)
        source.activationHistory.startNextPeriodFrom(getBlockNumber());

        emit AddPowerSource(_sourceAddr, _sourceType, _weight);
    }

    /**
     * @notice Change weight of power source at `_sourceAddr` to `_weight`
     * @param _sourceAddr Power source's address
     * @param _weight New weight to assign
     */
    function changeSourceWeight(address _sourceAddr, uint256 _weight)
        external
        authP(MANAGE_WEIGHTS_ROLE, arr(_weight, powerSourceDetails[_sourceAddr].weight))
        sourceExists(_sourceAddr)
    {
        require(_weight > 0, ERROR_ZERO_WEIGHT);
        require(powerSourceDetails[_sourceAddr].weight != _weight, ERROR_SAME_WEIGHT);
        powerSourceDetails[_sourceAddr].weight = _weight;
        emit ChangePowerSourceWeight(_sourceAddr, _weight);
    }

    /**
     * @notice Disable power source at `_sourceAddr`
     * @param _sourceAddr Power source's address
     */
    function disableSource(address _sourceAddr)
        external
        authP(MANAGE_POWER_SOURCE_ROLE, arr(uint256(0)))
        sourceExists(_sourceAddr)
    {
        PowerSource storage source = powerSourceDetails[_sourceAddr];

        // Disable after this block
        // This makes sure any queries to this aggregator this block are still consistent until the
        // end of the block
        // Ignore SafeMath here; we will have bigger issues if this overflows
        source.activationHistory.stopCurrentPeriodAt(getBlockNumber() + 1);

        emit DisablePowerSource(_sourceAddr);
    }

    /**
     * @notice Enable power source at `_sourceAddr`
     * @param _sourceAddr Power source's address
     */
    function enableSource(address _sourceAddr)
        external
        sourceExists(_sourceAddr)
        authP(MANAGE_POWER_SOURCE_ROLE, arr(uint256(1)))
    {
        PowerSource storage source = powerSourceDetails[_sourceAddr];

        // Add new activation period with [current block, max block)
        source.activationHistory.startNextPeriodFrom(getBlockNumber());

        emit EnablePowerSource(_sourceAddr);
    }

    // ERC20 fns - note that this token is a non-transferrable "view-only" implementation.
    // Users should only be changing balances by changing their balances in the underlying tokens.
    // These functions do **NOT** revert if the app is uninitialized to stay compatible with normal ERC20s.

    function balanceOf(address _owner) public view returns (uint256) {
        return balanceOfAt(_owner, getBlockNumber());
    }

    function totalSupply() public view returns (uint256) {
        return totalSupplyAt(getBlockNumber());
    }

    // Checkpointed fns
    // These functions do **NOT** revert if the app is uninitialized to stay compatible with normal ERC20s.

    function balanceOfAt(address _owner, uint256 _blockNumber) public view returns (uint256) {
        return _aggregateAt(_blockNumber, CallType.BalanceOfAt, abi.encode(_owner, _blockNumber));
    }

    function totalSupplyAt(uint256 _blockNumber) public view returns (uint256) {
        return _aggregateAt(_blockNumber, CallType.TotalSupplyAt, abi.encode(_blockNumber));
    }

    // Forwarding fns

    /**
    * @notice Tells whether the VotingAggregator app is a forwarder or not
    * @dev IForwarder interface conformance
    * @return Always true
    */
    function isForwarder() public pure returns (bool) {
        return true;
    }

    /**
     * @notice Execute desired action if you have voting power
     * @dev IForwarder interface conformance
     * @param _evmScript Script being executed
     */
    function forward(bytes _evmScript) public {
        require(canForward(msg.sender, _evmScript), ERROR_CAN_NOT_FORWARD);
        bytes memory input = new bytes(0);

        // No blacklist needed as this contract should not hold any tokens from its sources
        runScript(_evmScript, input, new address[](0));
    }

    /**
    * @notice Tells whether `_sender` can forward actions or not
    * @dev IForwarder interface conformance
    * @param _sender Address of the account intending to forward an action
    * @return True if the given address can forward actions, false otherwise
    */
    function canForward(address _sender, bytes) public view returns (bool) {
        return hasInitialized() && balanceOf(_sender) > 0;
    }

    // Getter fns

    /**
     * @dev Return information about a power source
     * @param _sourceAddr Power source's address
     * @return Power source type
     * @return Power source weight
     * @return Number of activation history points
     */
    function getPowerSourceDetails(address _sourceAddr)
        public
        view
        sourceExists(_sourceAddr)
        returns (
            PowerSourceType sourceType,
            uint256 weight,
            uint256 historyLength
        )
    {
        PowerSource storage source = powerSourceDetails[_sourceAddr];

        sourceType = source.sourceType;
        weight = source.weight;
        historyLength = source.activationHistory.history.length;
    }

    /**
     * @dev Return information about a power source's activation history
     * @param _sourceAddr Power source's address
     * @param _periodIndex Index of activation history
     * @return Start block of activation period
     * @return End block of activation period
     */
    function getPowerSourceActivationPeriod(address _sourceAddr, uint256 _periodIndex)
        public
        view
        sourceExists(_sourceAddr)
        returns (
            uint128 enabledFromBlock,
            uint128 disabledOnBlock
        )
    {
        ActivePeriod.Period storage period = powerSourceDetails[_sourceAddr].activationHistory.getPeriod(_periodIndex);

        enabledFromBlock = period.enabledFromTime;
        disabledOnBlock = period.disabledOnTime;
    }

    /**
     * @dev Return number of added power sources
     * @return Number of added power sources
     */
    function getPowerSourcesLength() public view isInitialized returns (uint256) {
        return powerSources.length;
    }

    // Internal fns

    function _aggregateAt(uint256 _blockNumber, CallType _callType, bytes memory _paramdata) internal view returns (uint256) {
        uint256 aggregate = 0;

        for (uint256 i = 0; i < powerSources.length; i++) {
            address sourceAddr = powerSources[i];
            PowerSource storage source = powerSourceDetails[sourceAddr];

            if (source.activationHistory.isEnabledAt(_blockNumber)) {
                bytes memory invokeData = abi.encodePacked(_selectorFor(_callType, source.sourceType), _paramdata);
                (bool success, uint256 value) = sourceAddr.staticInvoke(invokeData);
                require(success, ERROR_SOURCE_CALL_FAILED);

                aggregate = aggregate.add(source.weight.mul(value));
            }
        }

        return aggregate;
    }

    function _powerSourceExists(address _sourceAddr) internal view returns (bool) {
        // All attached power sources must have a valid source type
        return powerSourceDetails[_sourceAddr].sourceType != PowerSourceType.Invalid;
    }

    function _selectorFor(CallType _callType, PowerSourceType _sourceType) internal pure returns (bytes4) {
        if (_sourceType == PowerSourceType.ERC20WithCheckpointing) {
            if (_callType == CallType.BalanceOfAt) {
                return IERC20WithCheckpointing(0).balanceOfAt.selector;
            }
            if (_callType == CallType.TotalSupplyAt) {
                return IERC20WithCheckpointing(0).totalSupplyAt.selector;
            }
        }

        if (_sourceType == PowerSourceType.ERC900) {
            if (_callType == CallType.BalanceOfAt) {
                return IERC900History(0).totalStakedForAt.selector;
            }
            if (_callType == CallType.TotalSupplyAt) {
                return IERC900History(0).totalStakedAt.selector;
            }
        }

        revert(ERROR_INVALID_CALL_OR_SELECTOR);
    }

    // Private functions
    function _sanityCheckSource(address _sourceAddr, PowerSourceType _sourceType) private view returns (bool) {
        if (!isContract(_sourceAddr)) {
            return false;
        }

        // Sanity check that the source and its declared type work for at least the current block
        bytes memory balanceOfCalldata = abi.encodePacked(
            _selectorFor(CallType.BalanceOfAt, _sourceType),
            abi.encode(this, getBlockNumber())
        );
        (bool balanceOfSuccess,) = _sourceAddr.staticInvoke(balanceOfCalldata);

        bytes memory totalSupplyCalldata = abi.encodePacked(
            _selectorFor(CallType.TotalSupplyAt, _sourceType),
            abi.encode(getBlockNumber())
        );
        (bool totalSupplySuccess,) = _sourceAddr.staticInvoke(totalSupplyCalldata);

        return balanceOfSuccess && totalSupplySuccess;
    }
}
