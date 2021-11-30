%lang starknet
%builtins pedersen range_check ecdsa

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.math import assert_not_equal, assert_not_zero
from starkware.cairo.common.uint256 import (
    Uint256, uint256_add, uint256_sub, uint256_le, uint256_lt
)

#
# Storage
#

@storage_var
func _name() -> (res : felt):
end

@storage_var
func _symbol() -> (res : felt):
end

@storage_var
func owners(token_id_low : felt, token_id_high : felt) -> (res : felt):
end

@storage_var
func balances(owner : felt) -> (res : Uint256):
end

@storage_var
func token_approvals(token_id_low : felt, token_id_high : felt) -> (res : felt):
end

@storage_var
func operator_approvals(owner : felt, operator : felt) -> (res : felt):
end

#
# Constructor
#

@constructor
func constructor{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(name : felt, symbol : felt, recipient : felt):
    _name.write(name)
    _symbol.write(symbol)
    return()
end

#
# Getters
#

@view
func balanceOf{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*, 
        range_check_ptr
    }(owner : felt) -> (balance : Uint256):
    # checks that query is not for zero address
    assert_not_zero(owner)

    let (balance: Uint256) = balances.read(owner=owner)
    return (balance)
end

@view
func ownerOf{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*, 
        range_check_ptr
    }(token_id : Uint256) -> (owner : felt):
    let (owner) = owners.read(token_id.low, token_id.high)
    # ensuring the query is not for nonexistent token
    assert_not_zero(owner)

    return (owner)
end

@view
func name{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*, 
        range_check_ptr
    }() -> (name : felt):
    let (name) = _name.read()
    return (name)
end

@view
func symbol{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*, 
        range_check_ptr
    }() -> (symbol : felt):
    let (symbol) = _symbol.read()
    return (symbol)
end

@view
func getApproved{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*, 
        range_check_ptr
    }(token_id : Uint256) -> (approved : felt):
    let (exists) = _exists(token_id)
    assert exists = 1

    let (approved) = token_approvals.read(token_id.low, token_id.high)
    return (approved)
end

@view
func isApprovedForAll{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*, 
        range_check_ptr
    }(owner : felt, operator : felt) -> (is_approved : felt):
    let (is_approved) = operator_approvals.read(owner=owner, operator=operator)
    return (is_approved)
end

#
# Externals
#

@external
func approve{
        pedersen_ptr : HashBuiltin*, 
        syscall_ptr : felt*, 
        range_check_ptr
    }(approved : felt, token_id : Uint256):
    # checks caller is not zero address
    let (caller) = get_caller_address()
    assert_not_zero(caller)

    # ensures 'owner' does not equal 'to'
    let (owner) = owners.read(token_id.low, token_id.high)
    assert_not_equal(owner, approved)

    # checks that either caller equals owner or
    # caller isApprovedForAll on behalf of owner
    if caller == owner:
        _approve(approved, token_id)
        return()
    else:
        let (is_approved) = isApprovedForAll(owner, caller)
        assert_not_zero(is_approved)
        _approve(approved, token_id)
        return()
    end
end

@external
func setApprovalForAll{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*, 
        range_check_ptr
    }(operator : felt, approved : felt):
    let (caller) = get_caller_address()

    _set_approval_for_all(caller, operator, approved)
    return ()
end

@external
func transferFrom{
        pedersen_ptr : HashBuiltin*, 
        syscall_ptr : felt*, 
        range_check_ptr
    }(_from : felt, to : felt, token_id : Uint256):
    let (caller) = get_caller_address()
    _is_approved_or_owner(caller, token_id)

    _transfer(_from, to, token_id)
    return ()
end

#
# Test functions — will remove once extensibility is resolved
#

@external
func mint{
        pedersen_ptr : HashBuiltin*, 
        syscall_ptr : felt*, 
        range_check_ptr
    }(to : felt, token_id : Uint256):
    _mint(to, token_id)
    return ()
end

@external
func burn{
        pedersen_ptr : HashBuiltin*, 
        syscall_ptr : felt*, 
        range_check_ptr
    }(token_id : Uint256):
    _burn(token_id)
    return ()
end

#
# Internals
#

func _approve{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*, 
        range_check_ptr
    }(to : felt, token_id : Uint256):
    token_approvals.write(token_id.low, token_id.high, to)
    return ()
end

func _is_approved_or_owner{
        pedersen_ptr : HashBuiltin*, 
        syscall_ptr : felt*, 
        range_check_ptr
    }(spender : felt, token_id : Uint256) -> (res : felt):
    alloc_locals

    let (exists) = _exists(token_id)
    assert exists = 1

    let (owner) = ownerOf(token_id)
    if owner == spender:
        return (1)
    end

    let (approved_addr) = getApproved(token_id)
    if approved_addr == spender:
        return (1)
    end

    let (is_operator) = isApprovedForAll(owner, spender)
    if is_operator == 1:
        return (1)
    end

    return (0)
end

func _exists{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*, 
        range_check_ptr
    }(token_id : Uint256) -> (res : felt):
    let (res) = owners.read(token_id.low, token_id.high)

    if res == 0:
        return (0)
    else:
        return (1)
    end
end

func _mint{
        pedersen_ptr : HashBuiltin*, 
        syscall_ptr : felt*, 
        range_check_ptr
    }(to : felt, token_id : Uint256):
    assert_not_zero(to)

    let (exists) = _exists(token_id)
    assert exists = 0

    let (balance: Uint256) = balances.read(to)
    # overflow is not possible because token_id is guaranteed to be
    # a unique uint256
    let (new_balance: Uint256, _) = uint256_add(balance, Uint256(1, 0))
    balances.write(to, new_balance)

    # low + high felts = uint256
    owners.write(token_id.low, token_id.high, to)
    return ()
end

func _burn{
        pedersen_ptr : HashBuiltin*, 
        syscall_ptr : felt*, 
        range_check_ptr
    }(token_id : Uint256):
    let (owner) = ownerOf(token_id)

    # Clear approvals
    _approve(0, token_id)

    # Decrease owner balance
    let (balance: Uint256) = balances.read(owner)
    let (new_balance) = uint256_sub(balance, Uint256(1, 0))
    balances.write(owner, new_balance)

    # Delete owner
    owners.write(token_id.low, token_id.high, 0)
    return ()
end

func _transfer{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*, 
        range_check_ptr
    }(_from : felt, to : felt, token_id : Uint256):
    # ownerOf ensures '_from' is not the zero address
    let (_ownerOf) = ownerOf(token_id)
    assert _ownerOf = _from

    assert_not_zero(to)

    # Clear approvals
    _approve(0, token_id)

    # Decrease owner balance
    let (owner_bal) = balances.read(_from)
    let (new_balance) = uint256_sub(owner_bal, Uint256(1, 0))
    balances.write(_from, new_balance)

    # Increase receiver balance
    let (receiver_bal) = balances.read(to)
    # overflow not possible because token_id must be unique
    let (new_balance: Uint256, _) = uint256_add(receiver_bal, Uint256(1, 0))
    balances.write(to, new_balance)

    # Update token_id owner
    owners.write(token_id.low, token_id.high, to)
    return ()
end

func _set_approval_for_all{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*, 
        range_check_ptr
    }(owner : felt, operator : felt, approved : felt):
    assert_not_equal(owner, operator)

    # Make sure `approved` is a boolean (0 or 1)
    assert approved * (1 - approved) = 0

    operator_approvals.write(owner=owner, operator=operator, value=approved)
    return ()
end
