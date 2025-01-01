package eventhandlers_test

import (
	"context"
	"net/http"
	"strconv"
	"testing"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/licensify/internal/aqueduct/jobs"
	"github.com/github/licensify/internal/config"
	"github.com/github/licensify/internal/hydro/eventhandlers"
	"github.com/github/licensify/internal/models"
	"github.com/github/licensify/internal/monolith"
	"github.com/github/licensify/testing/mocks"
	"github.com/github/licensify/testing/stubs"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
)

type enterpriseManagedIdentitySuspendedHandlerSuite struct {
	suite.Suite
	mockDB  *mocks.MockDBReadWriter
	handler *eventhandlers.EventHandler
	logger  log.Logger
}

func (s *enterpriseManagedIdentitySuspendedHandlerSuite) SetupTest() {
	cfg, _ := config.Load()
	statter := cfg.StatsClient()
	telem, _ := telemetry.NewFromEnv()
	tracer := telem.Tracer.Tracer

	mockDB := &mocks.MockDBReadWriter{}
	s.mockDB = mockDB
	s.logger = log.NewNullLogger()
	jobby := &jobs.Jobby{Cfg: cfg, AqueductClient: &mocks.MockAqueductClient{}}

	handler, _ := eventhandlers.NewEventHandler(mockDB, jobby, &monolith.Client{}, statter, tracer)
	s.handler = handler
}

func (s *enterpriseManagedIdentitySuspendedHandlerSuite) setupMockDB(customerID uint64, licenseeID string, suspendedAt int64, customerLicensePatchErr, licenseeLicensePatchErr error) {
	wantOps := azcosmos.PatchOperations{}
	wantOps.AppendAdd("/LicenseStatus", models.LicenseStatusSuspended)
	wantOps.AppendAdd("/SuspendedAt", &suspendedAt)

	s.mockDB.On(
		"PatchItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(models.NewCustomerLicensePartitionKey(customerID, models.ProductSDLC)),
		models.NewCustomerLicenseID(models.LicenseeTypeUser, licenseeID),
		wantOps,
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, customerLicensePatchErr).Once()

	s.mockDB.On(
		"PatchItem",
		mock.Anything,
		azcosmos.NewPartitionKeyString(models.NewLicenseeLicensePartitionKey(licenseeID, models.LicenseeTypeUser)),
		models.NewLicenseeLicenseID(models.ProductSDLC, customerID),
		wantOps,
		mock.Anything,
	).Return(azcosmos.ItemResponse{}, licenseeLicensePatchErr).Once()
}

func (s *enterpriseManagedIdentitySuspendedHandlerSuite) TestHandleEnterpriseManagedIdentitySuspended() {
	tests := []struct {
		name                    string
		customerLicensePatchErr error
		licenseeLicensePatchErr error
		expectError             bool
	}{
		{
			name:                    "Success",
			customerLicensePatchErr: nil,
			licenseeLicensePatchErr: nil,
			expectError:             false,
		},
		{
			name:                    "CustomerLicensePatchNotFoundError",
			customerLicensePatchErr: &azcore.ResponseError{StatusCode: http.StatusNotFound},
			licenseeLicensePatchErr: nil,
			expectError:             false,
		},
		{
			name:                    "CustomerLicensePatchOtherError",
			customerLicensePatchErr: &azcore.ResponseError{StatusCode: http.StatusServiceUnavailable},
			licenseeLicensePatchErr: nil,
			expectError:             true,
		},
		{
			name:                    "LicenseeLicensePatchNotFoundError",
			customerLicensePatchErr: nil,
			licenseeLicensePatchErr: &azcore.ResponseError{StatusCode: http.StatusNotFound},
			expectError:             false,
		},
		{
			name:                    "LicenseeLicensePatchOtherError",
			customerLicensePatchErr: nil,
			licenseeLicensePatchErr: &azcore.ResponseError{StatusCode: http.StatusServiceUnavailable},
			expectError:             true,
		},
	}

	for _, tt := range tests {
		s.Run(tt.name, func() {
			ctx := context.Background()
			message := stubs.NewEnterpriseManagedIdentitySuspendedHydroMsg()
			customerID := uint64(message.GetBusiness().GetCustomerId())
			licenseeID := strconv.FormatInt(message.GetUserId(), 10)
			suspendedAt := int64(1728675888)

			s.setupMockDB(customerID, licenseeID, suspendedAt, tt.customerLicensePatchErr, tt.licenseeLicensePatchErr)

			_, err := s.handler.HandleEnterpriseManagedIdentitySuspended(ctx, s.logger, message)
			if tt.expectError {
				s.Require().Error(err.Err)
			} else {
				s.Require().NoError(err.Err)
			}
		})
	}
}

func TestEnterpriseManagedIdentitySuspendedTestSuite(t *testing.T) {
	suite.Run(t, new(enterpriseManagedIdentitySuspendedHandlerSuite))
}
