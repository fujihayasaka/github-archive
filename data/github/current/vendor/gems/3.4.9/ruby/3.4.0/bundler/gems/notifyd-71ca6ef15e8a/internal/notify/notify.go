// Package notify implements the Notify topic handler.
package notify

import "github.com/github/notifyd/internal/pkg/notify/stages"

// Service represents the Notify service.
type Service interface {
	stages.ICalculateRecipientsStage
	stages.IRouteRecipientsStage
	stages.IQueueBatchedRecipientsStage
}
