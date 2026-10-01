"""Request Lifecycle States and Transition Tests."""

import pytest
from backend.app.models.enums import (
    RequestState,
    is_valid_transition,
)


def test_all_lifecycle_states_exist():
    """Verify that all required Phase 1 lifecycle states are present."""
    expected_states = {
        "CREATED",
        "PENDING_IO_REVIEW",
        "EXECUTING",
        "WAITING_RESPONSE",
        "COMPLETED",
        "SMS_FAILED",
        "TIMEOUT",
        "RESPONSE_INVALID",
    }
    actual_states = {s.value for s in RequestState}
    assert expected_states == actual_states


def test_state_terminal_and_active_properties():
    """Verify terminal and active state properties."""
    assert RequestState.CREATED.is_active is True
    assert RequestState.CREATED.is_terminal is False

    assert RequestState.PENDING_IO_REVIEW.is_active is True
    assert RequestState.EXECUTING.is_active is True
    assert RequestState.WAITING_RESPONSE.is_active is True

    assert RequestState.COMPLETED.is_terminal is True
    assert RequestState.COMPLETED.is_active is False

    assert RequestState.SMS_FAILED.is_terminal is True
    assert RequestState.TIMEOUT.is_terminal is True
    assert RequestState.RESPONSE_INVALID.is_terminal is True


def test_valid_state_transitions():
    """Verify legitimate sequential state transitions."""
    assert is_valid_transition(RequestState.CREATED, RequestState.PENDING_IO_REVIEW)
    assert is_valid_transition(RequestState.PENDING_IO_REVIEW, RequestState.EXECUTING)
    assert is_valid_transition(RequestState.EXECUTING, RequestState.WAITING_RESPONSE)
    assert is_valid_transition(RequestState.WAITING_RESPONSE, RequestState.COMPLETED)
    assert is_valid_transition(RequestState.WAITING_RESPONSE, RequestState.TIMEOUT)
    assert is_valid_transition(RequestState.WAITING_RESPONSE, RequestState.SMS_FAILED)


def test_invalid_state_transitions():
    """Verify illegal transitions and jumps are prevented."""
    # Cannot jump from CREATED directly to COMPLETED
    assert not is_valid_transition(RequestState.CREATED, RequestState.COMPLETED)
    # Cannot jump from CREATED directly to EXECUTING
    assert not is_valid_transition(RequestState.CREATED, RequestState.EXECUTING)
    # Cannot transition out of terminal state
    assert not is_valid_transition(RequestState.COMPLETED, RequestState.EXECUTING)
    assert not is_valid_transition(RequestState.SMS_FAILED, RequestState.WAITING_RESPONSE)
    assert not is_valid_transition(RequestState.TIMEOUT, RequestState.COMPLETED)
