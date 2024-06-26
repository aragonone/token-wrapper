/*
 * SPDX-License-Identitifer:    GPL-3.0-or-later
 */

pragma solidity 0.4.24;

import "@aragon/os/contracts/apps/AragonApp.sol";
import "@aragon/os/contracts/common/IForwarder.sol";
import "@aragon/os/contracts/common/IsContract.sol";
import "@aragon/os/contracts/lib/math/SafeMath.sol";
import "@aragon/os/contracts/lib/token/ERC20.sol";

import "./interfaces/ERC721.sol";
import "@aragonone/voting-connectors-contract-utils/contracts/StaticInvoke.sol";
import "@aragonone/voting-connectors-contract-utils/contracts/interfaces/IERC20WithCheckpointing.sol";


/**
 * @title NFTSample
 * @notice Checkpoint wrapper around an ERC721 NFT that provide a "view-only" checkpointed ERC20 implementation for use with Voting apps.
 * @dev Inspired by:
 *   - MiniMe token
 */
contract NFTSample is IERC20WithCheckpointing, IForwarder, IsContract, AragonApp {
    using SafeMath for uint256;
    using StaticInvoke for address;

    // TODO: just use keccak hashes
    bytes32 public constant RESET_SAMPLE_ROLE = keccak256("RESET_SAMPLE_ROLE");

    uint256 internal constant MAX_UINT128 = uint256(uint128(-1));

    string private constant ERROR_NFT_NOT_CONTRACT = "NC_NFT_NOT_CONTRACT";
    string private constant ERROR_GIVEN_NO_OWNERS = "NC_GIVEN_NO_OWNERS";
    string private constant ERROR_CAN_NOT_FORWARD = "NC_CAN_NOT_FORWARD";
    string private constant ERROR_UINT128_NUMBER_TOO_BIG = "NC_UINT128_NUMBER_TOO_BIG";
    string private constant ERROR_NFT_BALANCE_REVERTED = "NC_NFT_BALANCE_REVERTED";

    // Checkpoint struct for keeping track of token balances at particular block numbers
    struct Checkpoint {
        // `fromBlock` is the block number that the value was generated from
        uint128 fromBlock;
        // `value` is the amount of tokens at a specific block number
        uint128 value;
    }

    struct Epoch {
        // Checkpointed history of the sampled NFT balances
        mapping (address => Checkpoint[]) balances;

        // Checkpointed total supply of the sampled balances
        Checkpoint[] totalSupplyHistory;
    }

    ERC721 public sampledNFT;
    string public name;
    string public symbol;

    mapping (uint256 => Epoch) internal epochs;
    uint256 public currentEpoch;

    event UpdateHolder(address indexed entity, uint256 balance);

    /**
     * @notice Create a new checkpointed wrapper around an NFT
     * @param _sampledNFT The sampled NFT
     * @param _name The wrapped token's name
     * @param _symbol The wrapped token's symbol
     */
    function initialize(ERC721 _sampledNFT, string _name, string _symbol) external onlyInit {
        initialized();

        require(isContract(_sampledNFT), ERROR_NFT_NOT_CONTRACT);

        sampledNFT = _sampledNFT;
        name = _name;
        symbol = _symbol;
    }

    function sample(address _owner) external onlyInit {
        _sample(_owner);
    }

    function sampleMany(address[] _owners) external onlyInit {
        uint256 ownersLength = _owners.length;
        require(ownersLength > 0, ERROR_GIVEN_NO_OWNERS);

        for (uint256 i = 0; i < ownersLength; i++) {
            _sample(_owners[i]);
        }
    }

    function resetSamples() external auth(RESET_SAMPLE_ROLE) {
        ++currentEpoch;
    }

    // ERC20 fns - note that this token is a non-transferrable "view-only" implementation.
    // Users should only be changing balances by re-sampling.
    // These functions do **NOT** revert if the app is uninitialized to stay compatible with normal ERC20s.

    function approve(address, uint256) public returns (bool) {
        return false;
    }

    function transfer(address, uint256) public returns (bool) {
        return false;
    }

    function transferFrom(address, address, uint256) public returns (bool) {
        return false;
    }

    function allowance(address, address) public view returns (uint256) {
        return 0;
    }

    function balanceOf(address _owner) public view returns (uint256) {
        return _balanceOfAt(_owner, getBlockNumber());
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupplyAt(getBlockNumber());
    }

    // Checkpointed fns
    // These functions do **NOT** revert if the app is uninitialized to stay compatible with normal ERC20s.

    function balanceOfAt(address _owner, uint256 _blockNumber) public view returns (uint256) {
        return _balanceOfAt(_owner, _blockNumber);
    }

    function totalSupplyAt(uint256 _blockNumber) public view returns (uint256) {
        return _totalSupplyAt(_blockNumber);
    }

    // Forwarding fns

    /**
    * @notice Tells whether the TokenWrapper app is a forwarder or not
    * @dev IForwarder interface conformance
    * @return Always true
    */
    function isForwarder() public pure returns (bool) {
        return true;
    }

    /**
     * @notice Execute desired action as a token holder
     * @dev IForwarder interface conformance. Forwards any token holder action.
     * @param _evmScript Script being executed
     */
    function forward(bytes _evmScript) public {
        require(canForward(msg.sender, _evmScript), ERROR_CAN_NOT_FORWARD);
        bytes memory input = new bytes(0);

        // No blacklist needed as this contract should not hold any power over the sampled NFT
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

    // Internal fns

    function _sample(address _owner) internal {
        Epoch storage epoch = epochs[currentEpoch];

        // We diff against the previous known balance so that we only incrementally commit changes
        // to total supply and avoid spurious checkpointing
        uint256 currentBalance = _staticBalanceOf(_owner);
        uint256 previousKnownBalance = balanceOf(_owner);
        uint256 currentTotalSupply = totalSupply();

        Checkpoint[] storage totalSupplyHistory = epoch.totalSupplyHistory;
        uint256 diff;
        uint256 newTotalSupply;
        if (previousKnownBalance < currentBalance) {
            diff = currentBalance.sub(previousKnownBalance);
            newTotalSupply = currentTotalSupply.add(diff);
        } else if (previousKnownBalance > currentBalance) {
            diff = previousKnownBalance.sub(currentBalance);
            newTotalSupply = currentTotalSupply.sub(diff);
        }

        // Commit updates, if there was actually a difference
        if (diff != 0) {
            _updateValueAtNow(epoch.balances[_owner], _toUint128(currentBalance));
            _updateValueAtNow(totalSupplyHistory, _toUint128(newTotalSupply));
        }
    }

    function _updateValueAtNow(Checkpoint[] storage _checkpoints, uint128 _value) internal {
        uint256 checkpointsLength = _checkpoints.length;

        if ((checkpointsLength == 0) || (_checkpoints[checkpointsLength - 1].fromBlock < getBlockNumber())) {
            Checkpoint storage newCheckPoint = _checkpoints[checkpointsLength + 1];
            newCheckPoint.fromBlock = uint128(getBlockNumber64());
            newCheckPoint.value = _value;
        } else {
            Checkpoint storage oldCheckPoint = _checkpoints[checkpointsLength - 1];
            oldCheckPoint.value = _value;
        }
    }

    function _balanceOfAt(address _owner, uint256 _blockNumber) internal view returns (uint256) {
        Epoch storage epoch = epochs[currentEpoch];
        _getCheckpointedValueAt(epoch.balances[_owner], _blockNumber);
    }

    function _totalSupplyAt(uint256 _blockNumber) internal view returns (uint256) {
        Epoch storage epoch = epochs[currentEpoch];
        _getCheckpointedValueAt(epoch.totalSupplyHistory, _blockNumber);
    }

    function _getCheckpointedValueAt(Checkpoint[] storage _checkpoints, uint256 _blockNumber) internal view returns (uint256) {
        uint256 checkpointsLength = _checkpoints.length;

        // Short circuit if there's no checkpoints yet
        // Note that this also lets us avoid using SafeMath later on, as we've established that
        // there must be at least one checkpoint
        if (checkpointsLength == 0) {
            return 0;
        }

        // Check last checkpoint
        uint256 lastCheckpointIndex = checkpointsLength - 1;
        Checkpoint storage lastCheckpoint = _checkpoints[lastCheckpointIndex];
        if (_blockNumber >= lastCheckpoint.fromBlock) {
            return uint256(lastCheckpoint.value);
        }

        // Check first checkpoint (if not already checked with the above check on last)
        if (checkpointsLength == 1 || _blockNumber < _checkpoints[0].fromBlock) {
            return 0;
        }

        // Binary search through checkpoints
        uint256 min = 0;
        uint256 max = checkpointsLength - 1;
        while (max > min) {
            uint256 mid = (max + min + 1) / 2;
            if (_checkpoints[mid].fromBlock <= _blockNumber) {
                min = mid;
            } else {
                // Note that we don't need SafeMath here because mid must always be greater than 0
                // from the while condition
                max = mid - 1;
            }
        }
        return uint256(_checkpoints[min].value);
    }

    function _toUint128(uint256 _a) internal pure returns (uint128) {
        require(_a <= MAX_UINT128, ERROR_UINT128_NUMBER_TOO_BIG);
        return uint128(_a);
    }

    // Private fns

    function _staticBalanceOf(address _owner) internal view returns (uint256) {
        bytes memory balanceOfCallData = abi.encodeWithSelector(
            sampledNFT.balanceOf.selector,
            _owner
        );

        (bool success, uint256 tokenBalance) = address(sampledNFT).staticInvoke(balanceOfCallData);
        require(success, ERROR_NFT_BALANCE_REVERTED);

        return tokenBalance;
    }
}
