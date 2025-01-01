// Package api provides the API handlers for the Licensify service.
package api

import (
	"context"
	"encoding/json"
	"strconv"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/licensify/internal/aqueduct/jobs"
	"github.com/github/licensify/internal/aqueduct/queues"
	"github.com/github/licensify/internal/config"
	"github.com/github/licensify/internal/engines"
	"github.com/github/licensify/internal/models"
	proto "github.com/github/licensify/lib/twirp/proto/licensify/services/v1"
	"github.com/twitchtv/twirp"
)

// CustomerLicenseAPI provides the API handlers for the CustomerLicense service.
type CustomerLicenseAPI struct {
	customerLicenseEngine *engines.CustomerLicenseEngine
	licenseeLicenseEngine *engines.LicenseeLicenseEngine
	aqueductClient        aqueduct.Client
	logger                log.Logger
	cfg                   *config.Config
}

// NewCustomerLicenseAPI creates a new CustomerLicenseAPI.
func NewCustomerLicenseAPI(customerLicenseEngine *engines.CustomerLicenseEngine, licenseeLicenseEngine *engines.LicenseeLicenseEngine, aqueductClient aqueduct.Client, logger log.Logger, cfg *config.Config) *CustomerLicenseAPI {
	return &CustomerLicenseAPI{
		customerLicenseEngine: customerLicenseEngine,
		licenseeLicenseEngine: licenseeLicenseEngine,
		aqueductClient:        aqueductClient,
		logger:                logger.Named("CustomerLicenseAPI"),
		cfg:                   cfg,
	}
}

// GetCustomerLicense returns the customer licenses for a customer and products matching the Licensee
// Leave products empty to return licenses for all products.
func (api *CustomerLicenseAPI) GetCustomerLicense(ctx context.Context, request *proto.GetCustomerLicenseRequest) (*proto.GetCustomerLicenseResponse, error) {
	if request == nil {
		return nil, twirp.RequiredArgumentError("request")
	}
	if request.CustomerId == 0 {
		return nil, twirp.RequiredArgumentError("request.customerId")
	}
	if request.Licensee == nil {
		return nil, twirp.RequiredArgumentError("request.licensee")
	}

	hasGlobalID := request.Licensee.GlobalId != ""
	hasType := request.Licensee.Type != proto.LicenseeType_LICENSEE_TYPE_UNSPECIFIED
	//nolint:staticcheck // Use IdDeprecated for backward compatibility
	hasID := request.Licensee.IdDeprecated > 0 || request.Licensee.Id != ""

	// Validate that either a globalId or a type and an id are present in the request
	if (hasGlobalID && (hasType || hasID)) || (!hasGlobalID && !(hasType && hasID)) {
		return nil, twirp.InvalidArgumentError("request", "Either a licensee.globalId or a licensee.type and a licensee.id must be present")
	}

	var licensee *models.Licensee

	if hasGlobalID {
		var err error
		licensee, err = models.NewLicenseeFromGlobalID(request.Licensee.GlobalId)
		if err != nil {
			return nil, twirp.InvalidArgumentError("request.GlobalId", err.Error())
		}
	} else {
		//nolint:staticcheck // Use IdDeprecated for backward compatibility
		licenseeID := strconv.FormatUint(request.Licensee.IdDeprecated, 10)
		if request.Licensee.Id != "" {
			licenseeID = request.Licensee.Id
		}

		licensee = models.NewLicensee(models.LicenseeType(request.Licensee.Type), licenseeID)
	}

	products := []models.Product{models.ProductSDLC, models.ProductGhas}

	if len(request.Products) > 1 {
		return nil, twirp.InvalidArgumentError("request.products", "Only zero or one product can be specified")
	}

	if len(request.Products) == 1 {
		requestProduct := models.Product(request.Products[0])
		if requestProduct != models.ProductUnspecified {
			products = []models.Product{requestProduct}
		}
	}

	customerLicenses := make([]*models.CustomerLicense, 0, len(products))

	for _, product := range products {
		key := models.NewCustomerLicenseKey(
			request.CustomerId,
			product,
			licensee.Type,
			licensee.ID,
		)

		customerLicense, err := api.customerLicenseEngine.Get(ctx, *key)
		if err != nil {
			return nil, err
		}

		if customerLicense != nil {
			customerLicenses = append(customerLicenses, customerLicense)
		}
	}

	customerLicenseProtos := make([]*proto.CustomerLicense, len(customerLicenses))
	for i, cl := range customerLicenses {
		customerLicenseProtos[i] = cl.ToProto()
	}

	if len(customerLicenseProtos) == 0 {
		return nil, twirp.NotFound.Error("No Licenses Found")
	}

	return &proto.GetCustomerLicenseResponse{CustomerLicenses: customerLicenseProtos}, nil
}

// GetCustomerLicenses returns all licenses for a customer and product.
func (api *CustomerLicenseAPI) GetCustomerLicenses(ctx context.Context, request *proto.GetCustomerLicensesRequest) (*proto.GetCustomerLicensesResponse, error) {
	if request == nil {
		return nil, twirp.RequiredArgumentError("request")
	}
	if request.CustomerId == 0 {
		return nil, twirp.RequiredArgumentError("request.customerId")
	}
	if request.Product == proto.Product_PRODUCT_UNSPECIFIED {
		return nil, twirp.RequiredArgumentError("request.product")
	}

	customerLicenses, err := api.customerLicenseEngine.GetAll(ctx, api.logger, request.CustomerId, models.Product(request.Product))
	if err != nil {
		return nil, err
	}

	customerLicenseProtos := make([]*proto.CustomerLicense, len(customerLicenses))
	for i, cl := range customerLicenses {
		customerLicenseProtos[i] = cl.ToProto()
	}
	return &proto.GetCustomerLicensesResponse{CustomerLicenses: customerLicenseProtos}, nil
}

// UpsertCustomerLicense upserts a customer license.
func (api *CustomerLicenseAPI) UpsertCustomerLicense(ctx context.Context, request *proto.UpsertCustomerLicenseRequest) (*proto.UpsertCustomerLicenseResponse, error) {
	if request == nil {
		return nil, twirp.RequiredArgumentError("request")
	}
	if request.CustomerLicense == nil {
		return nil, twirp.RequiredArgumentError("request.customerLicense")
	}
	if request.CustomerLicense.CustomerId == 0 {
		return nil, twirp.RequiredArgumentError("request.customerLicense.customerId")
	}
	if request.CustomerLicense.Product == proto.Product_PRODUCT_UNSPECIFIED {
		return nil, twirp.RequiredArgumentError("request.customerLicense.product")
	}
	if request.CustomerLicense.LicenseStatus == proto.LicenseStatus_LICENSE_STATUS_UNSPECIFIED {
		return nil, twirp.RequiredArgumentError("request.customerLicense.licenseStatus")
	}
	if request.CustomerLicense.Licensee == nil {
		return nil, twirp.RequiredArgumentError("request.customerLicense.licensee")
	}
	if request.CustomerLicense.Enablements == nil {
		return nil, twirp.RequiredArgumentError("request.customerLicense.enablements")
	}
	for _, e := range request.CustomerLicense.Enablements {
		if e.Type == proto.ProductEnablementType_PRODUCT_ENABLEMENT_TYPE_UNSPECIFIED {
			return nil, twirp.RequiredArgumentError("request.customerLicense.enablements.type")
		}
		if e.Reason == proto.EnablementReason_ENABLEMENT_REASON_UNSPECIFIED {
			return nil, twirp.RequiredArgumentError("request.customerLicense.enablements.reason")
		}
		if e.EnablementIds == nil {
			return nil, twirp.RequiredArgumentError("request.customerLicense.enablements.enablementIds")
		}
	}

	customerLicense := models.NewCustomerLicenseFromProto(request.CustomerLicense)
	err := api.customerLicenseEngine.Upsert(ctx, api.logger, customerLicense, nil)
	if err != nil {
		return nil, err
	}

	// Upsert peer LicenseeLicense for CustomerLicense
	licenseeLicense := models.NewLicenseeLicenseForCustomerLicense(customerLicense)
	err = api.licenseeLicenseEngine.Upsert(ctx, api.logger, licenseeLicense, nil)
	if err != nil {
		return nil, err
	}

	return &proto.UpsertCustomerLicenseResponse{}, nil
}

// GetLicenseeGlobalIds returns the Global IDs of licensees for a product.
//
//nolint:revive // The generated twirp code expects GetLicenseeGlobalIds (lowercase d in Ids)
func (api *CustomerLicenseAPI) GetLicenseeGlobalIds(ctx context.Context, request *proto.GetLicenseeGlobalIdsRequest) (*proto.GetLicenseeGlobalIdsResponse, error) {
	if request == nil {
		return nil, twirp.RequiredArgumentError("request")
	}
	if request.CustomerId == 0 {
		return nil, twirp.RequiredArgumentError("request.customerId")
	}
	if request.Product == proto.Product_PRODUCT_UNSPECIFIED {
		return nil, twirp.RequiredArgumentError("request.product")
	}

	product := models.Product(request.Product)

	var statuses []models.LicenseStatus

	if request.LicenseStatus != proto.LicenseStatus_LICENSE_STATUS_UNSPECIFIED {
		statuses = []models.LicenseStatus{models.LicenseStatus(request.LicenseStatus)}
	}

	licensees, err := api.customerLicenseEngine.GetLicenseesForProduct(ctx, api.logger, request.CustomerId, product, statuses)
	if err != nil {
		return nil, err
	}

	globalIDs := make([]string, len(licensees))
	for i, licensee := range licensees {
		globalIDs[i] = licensee.GlobalID.String()
	}
	return &proto.GetLicenseeGlobalIdsResponse{GlobalIds: globalIDs}, nil
}

// GetLicenseeIds returns the licensee ids for a product and enablement reasons.
// If reasons is empty, it will return all licensees for the product.
//
//nolint:revive // The generated twirp code expects GetLicenseeIds (lowercase d in Ids)
func (api *CustomerLicenseAPI) GetLicenseeIds(ctx context.Context, request *proto.GetLicenseeIdsRequest) (*proto.GetLicenseeIdsResponse, error) {
	if request == nil {
		return nil, twirp.RequiredArgumentError("request")
	}
	if request.CustomerId == 0 {
		return nil, twirp.RequiredArgumentError("request.customerId")
	}
	if request.Product == proto.Product_PRODUCT_UNSPECIFIED {
		return nil, twirp.RequiredArgumentError("request.product")
	}

	product := models.Product(request.Product)

	reasons := make([]models.EnablementReason, len(request.EnablementReasons))
	for i, r := range request.EnablementReasons {
		reasons[i] = models.EnablementReason(r)
	}

	licenseeIDs, err := api.customerLicenseEngine.GetLicenseesForProductAndEnablementReasons(ctx, api.logger, request.CustomerId, product, reasons)
	if err != nil {
		return nil, err
	}

	licenseeIDsAsStrings := make([]string, len(licenseeIDs))
	for i, id := range licenseeIDs {
		licenseeIDsAsStrings[i] = strconv.FormatUint(id, 10)
	}

	return &proto.GetLicenseeIdsResponse{
		LicenseeIdsDeprecated: licenseeIDs,
		LicenseeIds:           licenseeIDsAsStrings,
	}, nil
}

// SyncOrganizationMemberships enqueues an aqueduct job to sync organization memberships for the requested customer/organization.
func (api *CustomerLicenseAPI) SyncOrganizationMemberships(ctx context.Context, request *proto.SyncOrganizationMembershipsRequest) (*proto.SyncOrganizationMembershipsResponse, error) {
	if request == nil {
		return nil, twirp.RequiredArgumentError("request")
	}
	if request.EntityId == 0 {
		return nil, twirp.RequiredArgumentError("request.entityId")
	}
	if request.EntityType == proto.SyncEntityType_SYNC_ENTITY_TYPE_UNSPECIFIED {
		return nil, twirp.RequiredArgumentError("request.entityType")
	}

	syncJob := models.NewSyncJobFromProto(request)
	payload, err := json.Marshal(syncJob)
	if err != nil {
		return nil, twirp.InternalErrorf("failed to marshal sync job: %v", err)
	}

	headers := make(map[string]string)
	headers[jobs.JobNameHeader] = jobs.JobNameSyncOrgMemberships
	// Note: Org syncs from the API (as opposed to syncs originating in event handlers) are considered backfills and sent to a lower priority work queue.
	aqueductJob := aqueduct.Job{
		App:     api.cfg.AqueductApp,
		Queue:   queues.QueueBackfillSyncOrgMemberships,
		Payload: payload,
		Headers: headers,
	}
	jobID, err := api.aqueductClient.Send(ctx, aqueductJob)

	if err != nil {
		return nil, twirp.InternalErrorf("failed to send job to aqueduct: %v", err)
	}
	return &proto.SyncOrganizationMembershipsResponse{JobId: jobID}, nil
}
