package notify

import (
	"math"

	schema_pb "github.com/github/notifyd/hydro/schemas/notifyd/v0"
	matchengine_dto "github.com/github/notifyd/internal/pkg/notify/matchengine/dto"
)

// RecipientIDToReasons is a map of recipient IDs to reasons.
type RecipientIDToReasons map[int64][]string

// DeliveryMetadata represents the metadata for a delivery.
type DeliveryMetadata struct {
	Reasons  []string
	Channels matchengine_dto.ChannelsMap
}

// RecipientToDeliveryMetadata is a map of recipient IDs to delivery metadata.
type RecipientToDeliveryMetadata map[int64]DeliveryMetadata

// ToPB converts a map of recipient IDs to reasons to protobuf recipient groups.
func (recipients RecipientIDToReasons) ToPB() []*schema_pb.Notify_RecipientGroup {
	reasonsToUserIDs := make(map[string][]int32)
	for userID := range recipients {
		for _, reason := range recipients[userID] {
			//nolint:gosec // Known issue https://github.com/github/notifyd/issues/3113
			reasonsToUserIDs[reason] = append(reasonsToUserIDs[reason], int32(userID))
		}
	}

	var notifyRecipientGroups []*schema_pb.Notify_RecipientGroup
	for reason := range reasonsToUserIDs {
		notifyRecipientGroups = append(notifyRecipientGroups, &schema_pb.Notify_RecipientGroup{
			Reason:  reason,
			UserIds: reasonsToUserIDs[reason],
		})
	}
	return notifyRecipientGroups
}

// ExplicitRecipients is a list of recipient groups.
type ExplicitRecipients []*schema_pb.Notify_RecipientGroup

// ToRecipientIDToReasons converts a list of recipient groups to a map of recipient IDs to reasons.
func (e ExplicitRecipients) ToRecipientIDToReasons() RecipientIDToReasons {
	recipients := RecipientIDToReasons{}

	for _, group := range e {
		reason := group.GetReason()
		for _, recipientID := range group.GetUserIds() {
			recptID := int64(recipientID)
			recipients[recptID] = append(recipients[recptID], reason)
		}
	}

	return recipients
}

// Batcher takes a map of recipient IDs to reasons and prepares a list of recipients for a batched
// check.
//
// This way we can batch the requests to the batch check endpoint that has a limit of 250 recipients
// for performance reasons.
type Batcher struct {
	// size is the desired max number of recipients on each batch.
	Size uint
}

// Split splits a list of recipients into batches
func (b Batcher) Split(recipients RecipientIDToReasons) []RecipientIDToReasons {
	partitionIdx := 0
	partitions := make([]RecipientIDToReasons, b.NumberOfBatches(recipients))
	for userID := range recipients {
		if uint(len(partitions[partitionIdx])) == b.batchSize(recipients) {
			partitionIdx++
		}
		if partitions[partitionIdx] == nil {
			partitions[partitionIdx] = RecipientIDToReasons{}
		}
		partitions[partitionIdx][userID] = recipients[userID]
	}
	return partitions
}

// NumberOfBatches returns how many batches to use to partition the list of recipients into the
// desired size.
func (b Batcher) NumberOfBatches(recipients RecipientIDToReasons) int {
	if b.Size == 0 {
		return 1
	}

	numberOfBatches := math.Ceil(float64(len(recipients)) / float64(b.Size))

	return int(numberOfBatches)
}

// batchSize returns how many recipients should fit on each one of the batches, taking into account
// that when the desired size is 0, then the number of batches should still be 1 batch that
// contains all the recipients.
func (b Batcher) batchSize(recipients RecipientIDToReasons) uint {
	if b.Size == 0 {
		return uint(len(recipients))
	}

	return b.Size
}
