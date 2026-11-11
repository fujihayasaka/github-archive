package hydro

import (
	"errors"
	"net"

	"github.com/IBM/sarama"
)

// IsPermanentHydroError returns true if the error is permanent for the hydro consumer.
func IsPermanentHydroError(err error) bool {
	var dnsErr *net.DNSError
	if errors.As(err, &dnsErr) {
		return !dnsErr.IsTemporary
	}

	retryableErrorsTypes := []error{
		// This looks reacable if some issue connecting to all the brokers
		sarama.ErrOutOfBrokers,
		// Returned when a producer receives a message during shutdown.
		sarama.ErrShuttingDown,
		// This happens on parsing failures
		sarama.ErrIncompleteResponse,
		// Decoding can throw this
		sarama.ErrInsufficientData,

		// https://kafka.apache.org/31/protocol.html
		// CORRUPT_MESSAGE
		sarama.ErrInvalidMessage,
		// LEADER_NOT_AVAILABLE - this can happen during leader election
		sarama.ErrLeaderNotAvailable,
		// NOT_LEADER_OR_FOLLOWER
		sarama.ErrNotLeaderForPartition,
		// REQUEST_TIMED_OUT
		sarama.ErrRequestTimedOut,
		// REPLICA_NOT_AVAILABLE
		sarama.ErrReplicaNotAvailable,
		// NETWORK_EXCEPTION
		sarama.ErrNetworkException,
		// COORDINATOR_LOAD_IN_PROGRESS - The coordinator is loading and hence can't process requests.
		sarama.ErrOffsetsLoadInProgress,
		// COORDINATOR_NOT_AVAILABLE
		sarama.ErrConsumerCoordinatorNotAvailable,
		// NOT_COORDINATOR - This is not the correct coordinator.
		sarama.ErrNotCoordinatorForConsumer,
		// NOT_ENOUGH_REPLICAS_AFTER_APPEND
		sarama.ErrNotEnoughReplicasAfterAppend,
		// KAFKA_STORAGE_ERROR - Disk error when trying to access log file on the disk.
		sarama.ErrKafkaStorageError,
		// FENCED_LEADER_EPOCH - The leader epoch in the request is older than the epoch on the broker.
		sarama.ErrFencedLeaderEpoch,
		// UNKNOWN_LEADER_EPOCH - The leader epoch in the request is newer than the epoch on the broker.
		sarama.ErrUnknownLeaderEpoch,
		// OFFSET_NOT_AVAILABLE - The leader high watermark has not caught up from a recent leader election so the offsets cannot be guaranteed to be monotonically increasing.
		sarama.ErrOffsetNotAvailable,
		// PREFERRED_LEADER_NOT_AVAILABLE
		sarama.ErrPreferredLeaderNotAvailable,
		// ELIGIBLE_LEADERS_NOT_AVAILABLE
		sarama.ErrEligibleLeadersNotAvailable,
		// ELECTION_NOT_NEEDED - Leader election not needed for topic partition.
		sarama.ErrElectionNotNeeded,
		// UNSTABLE_OFFSET_COMMIT - There are unstable offsets that need to be cleared.
		sarama.ErrUnstableOffsetCommit,
		// THROTTLING_QUOTA_EXCEEDED
		sarama.ErrThrottlingQuotaExceeded,

		// additional notes:
		// The following are flagged as retryable, but look more like config errors
		// UNKNOWN_TOPIC_OR_PARTITION - More likely a config problem
		// NOT_CONTROLLER - This would require a metadata refresh
		// FETCH_SESSION_ID_NOT_FOUND - Requires a session reset
		// INVALID_FETCH_SESSION_EPOCH - Requires a new session
		// LISTENER_NOT_FOUND - More likely a config problem
		// MEMBER_ID_REQUIRED - Would require client to jump through several hoops
	}

	for _, retryableErrorType := range retryableErrorsTypes {
		if errors.Is(err, retryableErrorType) {
			return false
		}
	}

	return true
}
