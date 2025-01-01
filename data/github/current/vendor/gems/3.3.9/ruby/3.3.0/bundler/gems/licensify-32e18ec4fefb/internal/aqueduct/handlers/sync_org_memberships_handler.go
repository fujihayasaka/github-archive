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
	customersV1 "github.com/github/licensify/lib/monolith-twirp/customers/v1"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
)

// SyncOrgMembershipsHandler is an aqueduct message handler for syncing organization memberships.
type SyncOrgMembershipsHandler struct {
	customerEngine        *engines.CustomerEngine
	customerLicenseEngine *engines.CustomerLicenseEngine
	licenseeLicenseEngine *engines.LicenseeLicenseEngine
	monolithClient        customersV1.UsersAPI
	statter               stats.Client
	tracer                trace.Tracer
}

// NewSyncOrgMembershipsHandler creates a new aqueduct message handler for syncing organization memberships.
func NewSyncOrgMembershipsHandler(customerEngine *engines.CustomerEngine, customerLicenseEngine *engines.CustomerLicenseEngine, licenseeLicenseEngine *engines.LicenseeLicenseEngine, monolithClient customersV1.UsersAPI, statter stats.Client, tracer trace.Tracer) *SyncOrgMembershipsHandler {
	return &SyncOrgMembershipsHandler{
		customerEngine:        customerEngine,
		customerLicenseEngine: customerLicenseEngine,
		licenseeLicenseEngine: licenseeLicenseEngine,
		monolithClient:        monolithClient,
		statter:               statter,
		tracer:                tracer,
	}
}

// ProcessMessage takes an aqueduct message for syncing organization and repo memberships with github/github.
// The message should be a JSON object with the following structure:
// { "entityType": "organization" | "customer", "entityId": 123 }
// When the entityType is "customer", all orgs for the customer will be synced (org and repo memberships).
// When the entityType is "organization", only the org with the given entityId will be synced (only org memberships).
func (h *SyncOrgMembershipsHandler) ProcessMessage(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult) error {
	var msg *models.SyncOrganizationMembershipsJob
	if err := json.Unmarshal(rr.Payload, &msg); err != nil {
		logger.WithError(err).Error("Failed to unmarshal message")
		return err
	}

	logger = logger.WithFields(msg.GetLoggerFields()...)
	logger.Info("Processing sync organization memberships message", kvp.String("gh.aqueduct.job.payload", fmt.Sprintf("%+v", *msg)))

	if msg.EntityType == models.SyncEntityTypeUnspecified {
		logger.Info("EntityType is unspecified, skipping")
		return nil
	}
	if msg.EntityID == 0 {
		logger.Info("EntityID is 0, skipping")
		return nil
	}

	// Only drop the page size on the final retry
	decreasePageSize := rr.DeliveryAttempt == rr.MaxDeliveryAttempts

	customerID, users, err := h.getMonolithUsers(ctx, logger, msg.EntityType, msg.EntityID, decreasePageSize)
	if err != nil {
		return err
	}

	logger = logger.WithFields(kvp.Uint64("gh.customer.id", customerID))

	if customerID == 0 {
		logger.Info("customer ID is 0, skipping")
		return nil
	}

	// Only sync a single organization if the entity type is organization
	var singleOrgID uint64
	if msg.EntityType == models.SyncEntityTypeOrganization {
		singleOrgID = msg.EntityID
	}

	err = h.syncMemberships(ctx, logger, customerID, singleOrgID, users)
	if err != nil {
		return err
	}

	logger.Info("Successfully synced organization memberships")

	return nil
}

func (h *SyncOrgMembershipsHandler) getMonolithUsers(ctx context.Context, logger log.Logger, entityType models.SyncEntityType, entityID uint64, decreasePageSize bool) (uint64, map[uint64]*customersV1.User, error) {
	start := time.Now()
	ctx, sp := h.tracer.Start(ctx, "SyncOrgMembershipsHandler.getMonolithUsers")
	defer func() {
		sp.End()
		h.statter.Timing("get_monolith_users", stats.Tags{}, time.Since(start))
	}()

	var customerID uint64
	users := make(map[uint64]*customersV1.User)

	// This helps to prevent request timeouts when fetching organizations with a
	// large number of members (especially collaborators).
	var pageSize uint32
	if decreasePageSize {
		pageSize = 1
	}

	req := &customersV1.GetUsersRequest{
		EntityType: customersV1.EntityType(entityType),
		EntityId:   entityID,
	}
	var pageToken string
	for {
		req.PageToken = pageToken
		req.PageSize = pageSize

		ctx, sp := h.tracer.Start(ctx, "SyncOrgMembershipsHandler.getMonolithUsers.request.page")
		monolithResp, err := h.monolithClient.GetUsers(ctx, req)
		sp.End()

		if err != nil {
			err := fmt.Errorf("failed to get users from monolith with request %+v: %w", req, err)
			h.trackError(err, "get-users-error", sp, logger)
			return 0, nil, err
		}

		logger.Debug("monolith response", kvp.String("response", fmt.Sprintf("%+v", monolithResp)))

		customerID = monolithResp.CustomerId

		// merge user data with previous pages
		for _, user := range monolithResp.Users {
			if _, ok := users[user.Id]; !ok {
				users[user.Id] = user
			} else {
				users[user.Id].OrganizationMemberships = append(users[user.Id].OrganizationMemberships, user.OrganizationMemberships...)
				users[user.Id].CollaboratingRepositories = append(users[user.Id].CollaboratingRepositories, user.CollaboratingRepositories...)
			}
		}

		pageToken = monolithResp.NextPageToken
		if pageToken == "" {
			break
		}
	}

	return customerID, users, nil
}

func (h *SyncOrgMembershipsHandler) syncMemberships(ctx context.Context, logger log.Logger, customerID, singleOrgID uint64, users map[uint64]*customersV1.User) error {
	start := time.Now()
	ctx, sp := h.tracer.Start(ctx, "SyncOrgMembershipsHandler.syncMemberships")
	defer func() {
		sp.End()
		h.statter.Timing("sync_org_memberships", stats.Tags{}, time.Since(start))
	}()

	// get all existing licenses for the customer and update the memberships
	existingCustomerLicenses, err := h.customerLicenseEngine.GetAll(
		ctx, logger, customerID, models.ProductSDLC,
	)
	if err != nil {
		err = fmt.Errorf("failed to get all customer licenses: %w", err)
		h.trackError(err, "get-customer-licenses-error", sp, logger)
		return err
	}

	shouldDeactivateLicenses, err := h.customerEngine.HasHighWatermarkSDLCLicensing(ctx, customerID)
	if err != nil {
		err := fmt.Errorf("failed to get customer: %w", err)
		h.trackError(err, "get-customer-error", sp, logger)
		return err
	}

	customerLicenseOps := make(map[operation][]uint64)
	licenseeLicenseOps := make(map[operation][]uint64)

	for _, cl := range existingCustomerLicenses {
		licenseeID, err := strconv.ParseUint(cl.Licensee.ID, 10, 64)
		if err != nil {
			h.trackError(err, "parse-licensee-id-error", sp, logger)
			return fmt.Errorf("failed to parse licensee ID: %w", err)
		}

		customerLicenseOp, licenseeLicenseOp, err := h.syncUserWithRetries(
			ctx,
			shouldDeactivateLicenses,
			customerID,
			licenseeID,
			users[licenseeID],
			cl,
			singleOrgID,
			logger,
		)
		if err != nil {
			return err
		}

		h.trackOperation(customerLicenseOp, "customer-license")
		h.trackOperation(licenseeLicenseOp, "licensee-license")
		customerLicenseOps[customerLicenseOp] = append(customerLicenseOps[customerLicenseOp], licenseeID)
		licenseeLicenseOps[licenseeLicenseOp] = append(licenseeLicenseOps[licenseeLicenseOp], licenseeID)

		delete(users, licenseeID)
	}
	// create licenses for leftover users not in existing licenses
	for userID, ghUser := range users {
		customerLicenseOp, licenseeLicenseOp, err := h.syncUserWithRetries(
			ctx,
			shouldDeactivateLicenses,
			customerID,
			userID,
			ghUser,
			nil,
			singleOrgID,
			logger,
		)
		if err != nil {
			return err
		}

		h.trackOperation(customerLicenseOp, "customer-license")
		h.trackOperation(licenseeLicenseOp, "licensee-license")
		customerLicenseOps[customerLicenseOp] = append(customerLicenseOps[customerLicenseOp], userID)
		licenseeLicenseOps[licenseeLicenseOp] = append(licenseeLicenseOps[licenseeLicenseOp], userID)
	}

	logger.Info("Sync duration", kvp.Duration("duration", time.Since(start)))

	logger.Info("customer license operations summary",
		kvp.Int("customer_license.updated_count", len(customerLicenseOps[operationUpdated])),
		kvp.Int("customer_license.created_count", len(customerLicenseOps[operationCreated])),
		kvp.Int("customer_license.deleted_count", len(customerLicenseOps[operationDeleted])),
		kvp.Any("customer_license.updated_ids", customerLicenseOps[operationUpdated]),
		kvp.Any("customer_license.created_ids", customerLicenseOps[operationCreated]),
		kvp.Any("customer_license.deleted_ids", customerLicenseOps[operationDeleted]),
	)

	logger.Info("licensee license operations summary",
		kvp.Int("licensee_license.upserted_count", len(licenseeLicenseOps[operationUpserted])),
		kvp.Int("licensee_license.deleted_count", len(licenseeLicenseOps[operationDeleted])),
		kvp.Any("licensee_license.upserted_ids", licenseeLicenseOps[operationUpserted]),
		kvp.Any("licensee_license.deleted_ids", licenseeLicenseOps[operationDeleted]),
	)

	return nil
}

func (h *SyncOrgMembershipsHandler) syncUserWithRetries(
	ctx context.Context,
	shouldDeactivateLicenses bool,
	customerID, userID uint64,
	ghUser *customersV1.User,
	customerLicense *models.CustomerLicense,
	singleOrgID uint64,
	logger log.Logger,
) (customerLicenseOp, licenseeLicenseOp operation, err error) {
	ctx, sp := h.tracer.Start(ctx, "SyncOrgMembershipsHandler.syncUserWithRetries")
	defer sp.End()

	const retries = 10

	for i := range retries {
		logger := logger.WithFields(kvp.Int("retry", i))
		latestCustomerLicense := customerLicense
		if i > 0 {
			// If we're retrying, get the latest version of the CustomerLicense.
			licenseeID := strconv.FormatUint(userID, 10)
			customerLicenseKey := models.NewCustomerLicenseKey(
				customerID,
				models.ProductSDLC,
				models.LicenseeTypeUser,
				licenseeID,
			)
			latestCustomerLicense, err = h.customerLicenseEngine.Get(ctx, *customerLicenseKey)
			if err != nil {
				h.trackError(err, "get-customer-license", sp, logger)
				return "", "", fmt.Errorf("failed to get customerLicense: %w", err)
			}
		}
		customerLicenseOp, licenseeLicenseOp, err = h.syncUser(ctx, customerID, userID, shouldDeactivateLicenses, ghUser, latestCustomerLicense, singleOrgID, logger)
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

func (h *SyncOrgMembershipsHandler) syncUser(
	ctx context.Context,
	customerID, userID uint64,
	shouldDeactivateLicenses bool,
	ghUser *customersV1.User,
	customerLicense *models.CustomerLicense,
	singleOrgID uint64,
	logger log.Logger,
) (customerLicenseOp, licenseeLicenseOp operation, err error) {
	ctx, sp := h.tracer.Start(ctx, "SyncOrgMembershipsHandler.syncUser")
	defer sp.End()

	var orgIDs, repoIDs []uint64
	if ghUser != nil {
		orgIDs = ghUser.OrganizationMemberships
		repoIDs = ghUser.CollaboratingRepositories
	}

	var modified bool
	if customerLicense == nil {
		customerLicense = models.NewCustomerLicenseForUserWithMemberships(
			customerID,
			userID,
			orgIDs,
			repoIDs,
		)
		handleSuspension(customerLicense, ghUser)
		customerLicense.AddETag()
		modified = true
	} else {
		// single org sync requested in job
		if singleOrgID != 0 {
			if orgIDs == nil {
				modified = customerLicense.RemoveOrgMemberships(singleOrgID)
			} else {
				modified = customerLicense.AddOrgMemberships(singleOrgID)
			}
			statusModified := handleSuspension(customerLicense, ghUser)
			modified = modified || statusModified
		} else {
			orgsModified := customerLicense.ReplaceOrgMemberships(orgIDs...)
			reposModified := customerLicense.ReplaceRepositoryCollaborators(repoIDs...)
			statusModified := handleSuspension(customerLicense, ghUser)
			modified = orgsModified || reposModified || statusModified
		}
	}

	logger = logger.WithFields(customerLicense.GetLoggerFields()...)

	if customerLicense.IsEmpty() {
		if shouldDeactivateLicenses {
			return h.deactivateLicenses(ctx, logger, customerLicense)
		}
		return h.deleteLicenses(ctx, logger, customerLicense)
	}

	return h.upsertLicenses(ctx, logger, customerLicense, modified)
}

func (h *SyncOrgMembershipsHandler) trackError(err error, origin string, span trace.Span, logger log.Logger) {
	h.statter.Counter("sync_org_memberships_error",
		stats.Tags{"origin": origin},
		int64(1),
	)
	logger.WithError(err).Error("error syncing org memberships")
	span.RecordError(err)
	span.SetStatus(codes.Error, origin)
}

func (h *SyncOrgMembershipsHandler) trackOperation(operation operation, documentType string) {
	h.statter.Counter("sync_org_memberships.license_operations", stats.Tags{"operation": string(operation), "document": documentType}, int64(1))
}

func (h *SyncOrgMembershipsHandler) deleteLicenses(ctx context.Context, logger log.Logger, customerLicense *models.CustomerLicense) (customerLicenseOp, licenseeLicenseOp operation, err error) {
	ctx, sp := h.tracer.Start(ctx, "SyncOrgMembershipsHandler.deleteLicenses")
	defer sp.End()

	var opts *azcosmos.ItemOptions
	if customerLicense.ETag != nil {
		opts = &azcosmos.ItemOptions{IfMatchEtag: customerLicense.ETag}
	}

	if err := h.customerLicenseEngine.Delete(ctx, logger, *customerLicense.Key, opts); err != nil && !cosmos.IsNotFoundError(err) {
		origin := "delete-customer-license"
		if cosmos.IsPreconditionFailedError(err) {
			origin = "delete-customer-license-precondition-failed"
		}
		h.trackError(err, origin, sp, logger)
		return "", "", fmt.Errorf("failed to delete customerLicense: %w", err)
	}
	customerLicenseOp = operationDeleted

	licenseeLicenseKey := customerLicense.GetLicenseeLicenseKey()
	if err := h.licenseeLicenseEngine.Delete(ctx, logger, *licenseeLicenseKey, nil); err != nil && !cosmos.IsNotFoundError(err) {
		h.trackError(err, "delete-licensee-license-error", sp, logger)
		return "", "", fmt.Errorf("failed to delete licensee license: %w", err)
	}
	licenseeLicenseOp = operationDeleted
	return customerLicenseOp, licenseeLicenseOp, nil
}

func (h *SyncOrgMembershipsHandler) deactivateLicenses(ctx context.Context, logger log.Logger, customerLicense *models.CustomerLicense) (customerLicenseOp, licenseeLicenseOp operation, err error) {
	ctx, sp := h.tracer.Start(ctx, "SyncOrgMembershipsHandler.deactivateLicenses")
	defer sp.End()

	var opts *azcosmos.ItemOptions
	if customerLicense.ETag != nil {
		opts = &azcosmos.ItemOptions{IfMatchEtag: customerLicense.ETag}
	}

	customerLicense.Deactivate()

	if err := h.customerLicenseEngine.Upsert(ctx, logger, customerLicense, opts); err != nil {
		origin := "upsert-customer-license"
		if cosmos.IsPreconditionFailedError(err) {
			origin = "upsert-customer-license-precondition-failed"
		}
		h.trackError(err, origin, sp, logger)
		return "", "", fmt.Errorf("failed to upsert customer license: %w", err)
	}
	customerLicenseOp = operationDeactivated

	licenseeLicense := models.NewLicenseeLicenseForCustomerLicense(customerLicense)
	if err = h.licenseeLicenseEngine.Upsert(ctx, logger, licenseeLicense, nil); err != nil {
		h.trackError(err, "upsert-licensee-license", sp, logger)
		return "", "", fmt.Errorf("failed to upsert licensee license: %w", err)
	}
	licenseeLicenseOp = operationDeactivated

	return customerLicenseOp, licenseeLicenseOp, nil
}

func (h *SyncOrgMembershipsHandler) upsertLicenses(ctx context.Context, logger log.Logger, customerLicense *models.CustomerLicense, modified bool) (customerLicenseOp, licenseeLicenseOp operation, err error) {
	ctx, sp := h.tracer.Start(ctx, "SyncOrgMembershipsHandler.upsertLicenses")
	defer sp.End()

	var opts *azcosmos.ItemOptions
	if customerLicense.ETag != nil {
		opts = &azcosmos.ItemOptions{IfMatchEtag: customerLicense.ETag}
	}

	if modified {
		if err := h.customerLicenseEngine.Upsert(ctx, logger, customerLicense, opts); err != nil {
			origin := "upsert-customer-license"
			if cosmos.IsPreconditionFailedError(err) {
				origin = "upsert-customer-license-precondition-failed"
			}
			h.trackError(err, origin, sp, logger)
			return "", "", fmt.Errorf("failed to upsert customer license: %w", err)
		}
		customerLicenseOp = operationUpdated
		if customerLicense.IsNewDocument() {
			customerLicenseOp = operationCreated
		}
	}

	// Upsert a licensee license if it doesn't exist or should be updated (status changed)
	licenseeLicense := models.NewLicenseeLicenseForCustomerLicense(customerLicense)
	foundLicenseeLicense, err := h.licenseeLicenseEngine.Get(ctx, logger, *licenseeLicense.Key)
	if err != nil {
		h.trackError(err, "get-licensee-license-error", sp, logger)
		return "", "", fmt.Errorf("failed to get licensee license: %w", err)
	}
	if foundLicenseeLicense == nil || !foundLicenseeLicense.Equal(licenseeLicense) {
		err := h.licenseeLicenseEngine.Upsert(ctx, logger, licenseeLicense, nil)
		if err != nil {
			h.trackError(err, "upsert-licensee-license-error", sp, logger)
			return "", "", fmt.Errorf("failed to upsert licensee license: %w", err)
		}
		licenseeLicenseOp = operationUpserted
	}

	return customerLicenseOp, licenseeLicenseOp, nil
}

func handleSuspension(customerLicense *models.CustomerLicense, ghUser *customersV1.User) bool {
	var suspendedAt *int64
	if ghUser != nil && ghUser.SuspendedAt != nil {
		suspendedAtUnix := ghUser.SuspendedAt.AsTime().Unix()
		suspendedAt = &suspendedAtUnix
	}
	if suspendedAt == nil {
		return customerLicense.Activate()
	}
	return customerLicense.Suspend(*suspendedAt)
}
