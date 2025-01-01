// Package transitions provides the transitions that can be run against the licensify data in CosmosDB
package transitions

import (
	"context"
	"encoding/json"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/licensify/internal/aqueduct/jobs"
	"github.com/github/licensify/internal/aqueduct/queues"
	"github.com/github/licensify/internal/config"
	"github.com/github/licensify/internal/models"
)

// AddLicenseStatusTransition is a transition that adds the LicenseStatus field to all CustomerLicense and LicenseeLicense documents
type AddLicenseStatusTransition struct {
	cfg            *config.Config
	logger         log.Logger
	aqueductClient aqueduct.Client
}

// NewAddLicenseStatusTransition creates a new AddLicenseStatusTransition
func NewAddLicenseStatusTransition(cfg *config.Config, logger log.Logger, aqueductClient aqueduct.Client) *AddLicenseStatusTransition {
	return &AddLicenseStatusTransition{
		cfg:            cfg,
		logger:         logger,
		aqueductClient: aqueductClient,
	}
}

// Run runs the transition
func (t *AddLicenseStatusTransition) Run(ctx context.Context, startCustomerID, endCustomerID uint64, dryRun bool) error {
	logger := t.logger.WithFields(
		kvp.Uint64("gh.licensify.transition.start_customer_id", startCustomerID),
		kvp.Uint64("gh.licensify.transition.end_customer_id", endCustomerID),
	)
	logger.Info("running addLicenseStatus transition...")

	var count int
	failed := make([]uint64, 0)
	for customerID := startCustomerID; customerID <= endCustomerID; customerID++ {
		cLogger := logger.WithFields(kvp.Uint64("gh.customer.id", customerID))
		cLogger.Info("processing customer")
		if !dryRun {
			backfillJob := models.BackfillLicenseStatusJob{CustomerID: customerID}
			payload, err := json.Marshal(backfillJob)
			if err != nil {
				cLogger.WithError(err).Error("failed to marshal backfill job")
				failed = append(failed, customerID)
			}

			headers := make(map[string]string)
			headers[jobs.JobNameHeader] = jobs.JobNameBackfillLicenseStatus
			aqueductJob := aqueduct.Job{
				App:     t.cfg.AqueductApp,
				Queue:   queues.QueueBackfillLicenseStatus,
				Payload: payload,
				Headers: headers,
			}

			jobID, err := t.aqueductClient.Send(ctx, aqueductJob)
			if err != nil {
				cLogger.WithError(err).Error("failed to send backfill job")
				failed = append(failed, customerID)
			}
			cLogger.Info("sent backfill job", kvp.String("gh.aqueduct.job.id", jobID))
		}
		count++
	}
	logger.Info("finished addLicenseStatus transition",
		kvp.Int("customers.processed_count", count),
		kvp.Int("customers.failed_count", len(failed)),
		kvp.Any("customers.failed", failed),
	)
	return nil
}
