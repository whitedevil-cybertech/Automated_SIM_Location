"""Domain Enumerations and State Machine Definitions.

Defines all lifecycle states, user roles, and audit event types required
by the IFSO Location Request Management System architecture.
"""

from enum import Enum
from typing import Dict, Set


class RequestState(str, Enum):
    """Lifecycle states for a location request.

    States are strictly defined per project architecture:
    CREATED -> PENDING_IO_REVIEW -> EXECUTING -> WAITING_RESPONSE -> COMPLETED
    Terminal or failure branches: SMS_FAILED, TIMEOUT, RESPONSE_INVALID.
    """

    CREATED = "CREATED"
    PENDING_IO_REVIEW = "PENDING_IO_REVIEW"
    EXECUTING = "EXECUTING"
    WAITING_RESPONSE = "WAITING_RESPONSE"
    COMPLETED = "COMPLETED"
    SMS_FAILED = "SMS_FAILED"
    TIMEOUT = "TIMEOUT"
    RESPONSE_INVALID = "RESPONSE_INVALID"

    @property
    def is_terminal(self) -> bool:
        """Indicate whether this state terminates the request lifecycle."""
        return self in {
            RequestState.COMPLETED,
            RequestState.SMS_FAILED,
            RequestState.TIMEOUT,
            RequestState.RESPONSE_INVALID,
        }

    @property
    def is_active(self) -> bool:
        """Indicate whether the request is actively in progress."""
        return not self.is_terminal


# Valid state machine transitions to prevent illegal jumps
ALLOWED_STATE_TRANSITIONS: Dict[RequestState, Set[RequestState]] = {
    RequestState.CREATED: {
        RequestState.PENDING_IO_REVIEW,
        RequestState.RESPONSE_INVALID,
    },
    RequestState.PENDING_IO_REVIEW: {
        RequestState.EXECUTING,
        RequestState.RESPONSE_INVALID,
    },
    RequestState.EXECUTING: {
        RequestState.WAITING_RESPONSE,
        RequestState.SMS_FAILED,
        RequestState.TIMEOUT,
    },
    RequestState.WAITING_RESPONSE: {
        RequestState.COMPLETED,
        RequestState.SMS_FAILED,
        RequestState.TIMEOUT,
        RequestState.RESPONSE_INVALID,
    },
    RequestState.SMS_FAILED: set(),  # Terminal
    RequestState.TIMEOUT: set(),  # Terminal
    RequestState.RESPONSE_INVALID: set(),  # Terminal
    RequestState.COMPLETED: set(),  # Terminal
}


def is_valid_transition(current_state: RequestState, target_state: RequestState) -> bool:
    """Validate whether transitioning from current_state to target_state is permitted."""
    allowed = ALLOWED_STATE_TRANSITIONS.get(current_state, set())
    return target_state in allowed


class UserRole(str, Enum):
    """System user roles."""

    OFFICER = "OFFICER"
    IO = "IO"  # Investigating Officer
    ADMIN = "ADMIN"


class AuditEventType(str, Enum):
    """Categorized audit log event types."""

    REQUEST_CREATED = "REQUEST_CREATED"
    SHAREABLE_LINK_ACCESSED = "SHAREABLE_LINK_ACCESSED"
    IO_REVIEW_STARTED = "IO_REVIEW_STARTED"
    EXECUTION_TRIGGERED = "EXECUTION_TRIGGERED"
    SMS_DISPATCHED = "SMS_DISPATCHED"
    SMS_DELIVERY_CONFIRMED = "SMS_DELIVERY_CONFIRMED"
    SMS_FAILED = "SMS_FAILED"
    SMS_RESPONSE_RECEIVED = "SMS_RESPONSE_RECEIVED"
    RESPONSE_PARSED = "RESPONSE_PARSED"
    REQUEST_COMPLETED = "REQUEST_COMPLETED"
    REQUEST_TIMEOUT = "REQUEST_TIMEOUT"
    REQUEST_INVALIDATED = "REQUEST_INVALIDATED"
