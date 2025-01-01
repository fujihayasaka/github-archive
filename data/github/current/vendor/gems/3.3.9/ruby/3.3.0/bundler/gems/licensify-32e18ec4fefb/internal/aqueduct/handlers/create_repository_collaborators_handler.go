package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/licensify/internal/cosmos"
	"github.com/github/licensify/internal/engines"
	"github.com/github/licensify/internal/models"
	repositoriesApiV1 "github.com/github/licensify/lib/monolith-twirp/repositories/v1"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
)

// CreateRepositoryCollaboratorsHandler is an aqueduct message handler for creating repository collaborators.
type CreateRepositoryCollaboratorsHandler struct {
	statter               stats.Client
	tracer                trace.Tracer
	repositoriesAPI       repositoriesApiV1.RepositoriesAPI
	customerLicenseEngine *engines.CustomerLicenseEngine
	licenseeLicenseEngine *engines.LicenseeLicenseEngine
}

// NewCreateRepositoryCollaboratorsHandler creates a new aqueduct message handler for creating repository collaborators.
func NewCreateRepositoryCollaboratorsHandler(statter stats.Client, tracer trace.Tracer, repositoriesAPI repositoriesApiV1.RepositoriesAPI, customerLicenseEngine *engines.CustomerLicenseEngine, licenseeLicenseEngine *engines.LicenseeLicenseEngine) *CreateRepositoryCollaboratorsHandler {
	return &CreateRepositoryCollaboratorsHandler{
		statter:               statter,
		tracer:                tracer,
		repositoriesAPI:       repositoriesAPI,
		customerLicenseEngine: customerLicenseEngine,
		licenseeLicenseEngine: licenseeLicenseEngine,
	}
}

// ProcessMessage takes an aqueduct message for creating repository collaborators.
//
// Note: This method does not check the visibility of the repository. It leaves that
// responsibility & desired behaviour to the enqueuer.
//
// For example: when a repository is restored from a soft delete, we let the
// results of the request from Dotcom determine all private repository collaborators.
// If we were to block on the repository visibility, no collaborators would be synced.
func (h *CreateRepositoryCollaboratorsHandler) ProcessMessage(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult) error {
	ctx, span := h.tracer.Start(ctx, "CreateRepositoryCollaboratorsHandler.ProcessMessage")
	defer span.End()

	var msg *models.CreateRepositoryCollaboratorsJob
	if err := json.Unmarshal(rr.Payload, &msg); err != nil {
		logger.WithError(err).Error("Failed to unmarshal message")
		return err
	}

	logger = logger.WithFields(msg.GetLoggerFields()...)
	logger.Info("Processing create repository collaborators message", kvp.String("gh.aqueduct.job.payload", fmt.Sprintf("%+v", *msg)))

	req := &repositoriesApiV1.GetRepositoryInformationRequest{
		Id:                   msg.RepositoryID,
		IncludeCollaborators: true,
	}
	res, err := h.repositoriesAPI.GetRepositoryInformation(ctx, req)
	if err != nil {
		err := fmt.Errorf("failed to get repository from monolith with request %+v: %w", req, err)
		h.trackError(err, "get-repository-error", span, logger)
		return err
	}

	repository := &models.Repository{
		ID:                  res.Repository.Id,
		Visibility:          models.RepositoryVisibility(res.Repository.Visibility.Number()),
		ParentID:            res.Repository.ParentId,
		CustomerID:          uint64(res.Repository.OwnerCustomerId),
		IsAdvisoryWorkspace: res.Repository.IsAdvisoryWorkspace,
		IsFork:              res.Repository.IsFork,
		IsActive:            res.Repository.IsActive,
		CollaboratorIDs:     res.CollaboratorIds,
	}
	logger = logger.WithFields(repository.GetLoggerFields()...)
	logger.Info("Fetched repository information")

	if repository.MissingRequiredIDs() {
		logger.Info("unable to process repository, skipping")
		h.statter.Counter("create_repository_collaborators_handler.skipped", stats.Tags{"reason": "unable-to-process"}, int64(1))
		return nil
	}
	if !repository.IsActive {
		logger.Info("repository is not active, skipping")
		h.statter.Counter("create_repository_collaborators_handler.skipped", stats.Tags{"reason": "repository-not-active"}, int64(1))
		return nil
	}
	if repository.IsAdvisoryWorkspace {
		logger.Info("repository is advisory workspace, skipping")
		h.statter.Counter("create_repository_collaborators_handler.skipped", stats.Tags{"reason": "repo-advisory-workspace"}, int64(1))
		return nil
	}
	if repository.Fork() {
		logger.Info("repository is a fork, skipping")
		h.statter.Counter("create_repository_collaborators_handler.skipped", stats.Tags{"reason": "repo-is-fork"}, int64(1))
		return nil
	}
	if !repository.HasCollaborators() {
		logger.Info("repository has no collaborators, skipping")
		h.statter.Counter("create_repository_collaborators_handler.skipped", stats.Tags{"reason": "no-collaborators"}, int64(1))
		return nil
	}

	return h.createCollaborators(ctx, logger, repository)
}

func (h *CreateRepositoryCollaboratorsHandler) createCollaborators(ctx context.Context, logger log.Logger, repository *models.Repository) error {
	ctx, span := h.tracer.Start(ctx, "CreateRepositoryCollaboratorsHandler.createCollaborators",
		trace.WithAttributes(
			attribute.String("gh.repository.id", strconv.FormatUint(repository.ID, 10)),
		),
	)
	defer span.End()
	start := time.Now()

	customerLicenseOps := make(map[operation][]uint64)
	licenseeLicenseOps := make(map[operation][]uint64)

	for _, collaboratorID := range repository.CollaboratorIDs {
		customerLicenseOp, licenseeLicenseOp, err := h.createCollaboratorWithRetries(
			ctx,
			logger,
			repository.CustomerID,
			collaboratorID,
			repository.ID,
		)
		if err != nil {
			return err
		}

		h.trackOperation(customerLicenseOp, "customer-license")
		h.trackOperation(licenseeLicenseOp, "licensee-license")
		customerLicenseOps[customerLicenseOp] = append(customerLicenseOps[customerLicenseOp], collaboratorID)
		licenseeLicenseOps[licenseeLicenseOp] = append(licenseeLicenseOps[licenseeLicenseOp], collaboratorID)
	}

	logger.Info("created repository collaborators",
		kvp.Int("customer_license.updated_count", len(customerLicenseOps[operationUpdated])),
		kvp.Int("customer_license.created_count", len(customerLicenseOps[operationCreated])),
		kvp.Any("customer_license.updated_ids", customerLicenseOps[operationUpdated]),
		kvp.Any("customer_license.created_ids", customerLicenseOps[operationCreated]),
		kvp.Int("licensee_license.upserted_count", len(licenseeLicenseOps[operationUpserted])),
		kvp.Duration("duration", time.Since(start)),
	)

	return nil
}

func (h *CreateRepositoryCollaboratorsHandler) createCollaboratorWithRetries(
	ctx context.Context,
	logger log.Logger,
	customerID, collaboratorID, repoID uint64,
) (customerLicenseOp, licenseeLicenseOp operation, err error) {
	ctx, sp := h.tracer.Start(ctx, "CreateRepositoryCollaboratorsHandler.createCollaboratorWithRetries")
	defer sp.End()

	const retries = 10

	for i := range retries {
		logger := logger.WithFields(kvp.Int("retry", i))

		customerLicenseKey := models.NewCustomerLicenseKey(
			customerID,
			models.ProductSDLC,
			models.LicenseeTypeUser,
			strconv.FormatUint(collaboratorID, 10),
		)
		customerLicense, err := h.customerLicenseEngine.Get(ctx, *customerLicenseKey)
		if err != nil {
			h.trackError(err, "get-customer-license", sp, logger)
			return "", "", fmt.Errorf("failed to get customerLicense: %w", err)
		}

		customerLicenseOp, licenseeLicenseOp, err = h.createCollaborator(ctx, logger, customerID, collaboratorID, repoID, customerLicense)
		if err != nil {
			if cosmos.IsPreconditionFailedError(err) {
				continue
			}
			return "", "", fmt.Errorf("failed to sync user: %w", err)
		}
		return customerLicenseOp, licenseeLicenseOp, nil
	}

	err = fmt.Errorf("failed to sync user after %d retries: %w", retries, err)
	h.trackError(err, "sync-user-retries-exhausted", sp, logger)
	return "", "", err
}

func (h *CreateRepositoryCollaboratorsHandler) createCollaborator(
	ctx context.Context,
	logger log.Logger,
	customerID, collaboratorID, repoID uint64,
	customerLicense *models.CustomerLicense,
) (customerLicenseOp, licenseeLicenseOp operation, err error) {
	ctx, sp := h.tracer.Start(ctx, "CreateRepositoryCollaboratorsHandler.createCollaborator")
	defer sp.End()

	var modified bool
	if customerLicense == nil {
		customerLicense = models.NewCustomerLicenseForUserWithRepositoryCollaborator(customerID, collaboratorID, repoID)
		customerLicense.AddETag()
		modified = true
	} else {
		modified = customerLicense.AddRepositoryCollaborators(repoID)
	}

	logger = logger.WithFields(customerLicense.GetLoggerFields()...)
	licenseeLicense := models.NewLicenseeLicenseForCustomerLicense(customerLicense)

	var opts *azcosmos.ItemOptions
	if customerLicense.ETag != nil {
		opts = &azcosmos.ItemOptions{IfMatchEtag: customerLicense.ETag}
	}

	logger.Info("is modified", kvp.Bool("is_modified", modified))

	if modified {
		if err := h.customerLicenseEngine.Upsert(ctx, logger, customerLicense, opts); err != nil {
			origin := "upsert-customer-license"
			if cosmos.IsPreconditionFailedError(err) {
				origin = "upsert-customer-license-precondition-failed"
			}
			h.trackError(err, origin, sp, logger)
			return "", "", fmt.Errorf("failed to upsert customerLicense: %w", err)
		}
		customerLicenseOp = operationUpdated
		if customerLicense.IsNewDocument() {
			customerLicenseOp = operationCreated
		}
	}

	// Upsert a licensee license if it doesn't exist
	foundLicenseeLicense, err := h.licenseeLicenseEngine.Get(ctx, logger, *licenseeLicense.Key)
	if err != nil {
		h.trackError(err, "get-licensee-license-error", sp, logger)
		return "", "", fmt.Errorf("failed to get licensee license: %w", err)
	}
	if foundLicenseeLicense == nil {
		err := h.licenseeLicenseEngine.Upsert(ctx, logger, licenseeLicense, nil)
		if err != nil {
			h.trackError(err, "upsert-licensee-license-error", sp, logger)
			return "", "", fmt.Errorf("failed to upsert licensee license: %w", err)
		}
		licenseeLicenseOp = operationUpserted
	}

	return customerLicenseOp, licenseeLicenseOp, nil
}

func (h *CreateRepositoryCollaboratorsHandler) trackOperation(operation operation, documentType string) {
	h.statter.Counter("create_repository_collaborators.license_operations", stats.Tags{"operation": string(operation), "document": documentType}, int64(1))
}

func (h *CreateRepositoryCollaboratorsHandler) trackError(err error, origin string, span trace.Span, logger log.Logger) {
	if cosmos.IsPreconditionFailedError(err) {
		origin = fmt.Sprintf("%s-precondition-failed", origin)
	}
	h.statter.Counter("create_repository_collaborators_error",
		stats.Tags{"origin": origin},
		int64(1),
	)
	logger.WithError(err).Error("error processing CreateRepositoryCollaborators message")
	span.RecordError(err)
	span.SetStatus(codes.Error, origin)
}
