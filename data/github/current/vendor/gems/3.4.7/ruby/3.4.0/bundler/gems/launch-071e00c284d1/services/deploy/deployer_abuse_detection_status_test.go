package deploy

import (
	"context"
	"encoding/base64"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/launch/auth"
	"github.com/github/launch/auth/hmac"
	"github.com/github/launch/clients/ghinternal"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/hydro/events"
	hydroV0 "github.com/github/launch/hydro/schemas/github/actions/v0"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/azp"
	pb "github.com/github/launch/services/pb/deploy"
	"github.com/github/launch/types"
	azpconf "github.com/github/launch/workflowbuild/azp/config"
)

func TestAbuseDetectionStatus(t *testing.T) {
	suite.Run(t, new(abuseDetectionStatusTestSuite))
}

type abuseDetectionStatusTestSuite struct {
	suite.Suite
	svc *service

	ghFactory             *github.MockFactory
	ghClient              *github.MockClient
	hydro                 *events.MockHydro
	internalClient        *ghinternal.MockClient
	internalClientFactory *ghinternal.MockFactory
	azpResources          deployer.MockAzpResourcesRepository
	verifier              *auth.MockVerifier
	keyVaultClient        *azp.MockKeyVaultClient
}

func (s *abuseDetectionStatusTestSuite) SetupTest() {
	log := logger.TestLogger()
	statter := statter.NullStatter()

	s.hydro = &events.MockHydro{}

	s.ghClient = &github.MockClient{}
	s.ghFactory = &github.MockFactory{}

	s.internalClient = &ghinternal.MockClient{}
	s.internalClientFactory = &ghinternal.MockFactory{}
	s.internalClientFactory.On("Create").Return(s.internalClient, nil)

	s.azpResources = deployer.MockAzpResourcesRepository{}

	s.verifier = &auth.MockVerifier{}

	s.keyVaultClient = &azp.MockKeyVaultClient{}

	s.keyVaultClient.On(
		"GetSecret", mock.Anything, authVaultName, primaryHMACKeyName,
	).Return(makeKeyVaultSecret(primaryHMACKey), nil).Once()
	s.keyVaultClient.On(
		"GetSecret", mock.Anything, authVaultName, secondaryHMACKeyName,
	).Return(makeKeyVaultSecret(secondaryHMACKey), nil).Once()

	s.svc = &service{
		cfg: config{
			Log:                   log,
			Stats:                 statter,
			Hydro:                 s.hydro,
			ClientFactory:         s.ghFactory,
			AZPResources:          &s.azpResources,
			InternalClientFactory: s.internalClientFactory,
			Verifier:              s.verifier,
			KeyVaultClient:        s.keyVaultClient,
			AzureProviderConfig: azpconf.AzureProviderConfig{
				AuthVaultName: authVaultName,
			},
		},
	}

}

func (s *abuseDetectionStatusTestSuite) TestVerification() {
	// OUTPUT from a test run:
	// Server: Key: K3YFqxD6j80gF18tJXEIy/qBlCZFU+jQnRkH2ZiZWwbFjOk4DJdnIASeaQMk/6RMeRTJjwdnv2BNU/fTuAj+Gg==

	// Client: URL: https://some.url/build/1234/job/2345?timestamp=2019-07-01T10%3A57%3A02Z
	// Client: Message: {"some":"json"}
	// Client: Signature: gPYSfeqer9ZEhu9WkPT0gFC34hR/+zawsdVWMF//nFzn4e5MmMEkdDQGNiwlsgmvCnAhk/PXLuJfROq68EM23A==
	// Client: Authorization Header: HMAC-SHA512 Signature=gPYSfeqer9ZEhu9WkPT0gFC34hR/+zawsdVWMF//nFzn4e5MmMEkdDQGNiwlsgmvCnAhk/PXLuJfROq68EM23A==

	// Server: Rebuilt Signature: gPYSfeqer9ZEhu9WkPT0gFC34hR/+zawsdVWMF//nFzn4e5MmMEkdDQGNiwlsgmvCnAhk/PXLuJfROq68EM23A==

	// Message is valid!

	primaryKey, _ := base64.StdEncoding.DecodeString("K3YFqxD6j80gF18tJXEIy/qBlCZFU+jQnRkH2ZiZWwbFjOk4DJdnIASeaQMk/6RMeRTJjwdnv2BNU/fTuAj+Gg==")

	keyVaultClient := &azp.MockKeyVaultClient{}
	keyVaultClient.On(
		"GetSecret", mock.Anything, authVaultName, primaryHMACKeyName, mock.Anything,
	).Return(makeKeyVaultSecret(primaryKey), nil).Once()
	keyVaultClient.On(
		"GetSecret", mock.Anything, authVaultName, secondaryHMACKeyName, mock.Anything,
	).Return(makeKeyVaultSecret([]byte("foo")), nil).Once()

	log := logger.TestLogger()
	statter := statter.NullStatter()
	svc := &service{
		cfg: config{
			Log:                   log,
			Stats:                 statter,
			Hydro:                 s.hydro,
			ClientFactory:         s.ghFactory,
			AZPResources:          &s.azpResources,
			InternalClientFactory: s.internalClientFactory,
			Verifier:              hmac.NewVerifier(hmac.NewSigner()),
			KeyVaultClient:        keyVaultClient,
			AzureProviderConfig: azpconf.AzureProviderConfig{
				AuthVaultName: authVaultName,
			},
		},
	}
	ctx := context.Background()
	signature, _ := base64.StdEncoding.DecodeString("gPYSfeqer9ZEhu9WkPT0gFC34hR/+zawsdVWMF//nFzn4e5MmMEkdDQGNiwlsgmvCnAhk/PXLuJfROq68EM23A==")
	res, err := svc.verifySignature(ctx, &pb.AbuseStatusRequest{
		Status:     []byte(`{"some":"json"}`),
		RequestURI: "https://some.url/build/1234/job/2345?timestamp=2019-07-01T10%3A57%3A02Z",
		Signature:  signature,
	})
	s.NoError(err)
	s.True(res)
}

func (s *abuseDetectionStatusTestSuite) TestInvalidPayloadsAreRejected() {
	s.setRequestVerificationResult(false)

	ctx := context.Background()
	res, err := s.svc.AbuseDetectionStatus(ctx, &pb.AbuseStatusRequest{})
	s.NoError(err)
	s.False(res.ValidSignature)
}

func (s *abuseDetectionStatusTestSuite) TestHandlesEmptyUpdate() {
	s.setRequestVerificationResult(true)

	ctx := context.Background()
	res, err := s.svc.AbuseDetectionStatus(ctx, &pb.AbuseStatusRequest{
		Status: []byte(`{"abuseMetrics":[]}`),
	})
	s.NoError(err)
	s.True(res.ValidSignature)
}

func (s *abuseDetectionStatusTestSuite) TestAbuseMetricsMessageIsPublished() {
	ctx := context.Background()

	s.setRequestVerificationResult(true)

	s.internalClient.On("GetAbuseDataForHydro", mock.Anything, mock.Anything).Return(&ghinternal.AbuseDataForHydro{
		OwnersByEntityID: map[types.GlobalID]*hydroV0.BillingPlanOwner{
			alphaEntityID: {
				GlobalId: alphaBillingID,
				Name:     "alpha-owner",
				PlanSku:  hydroV0.BillingPlanOwner_SKU_FREE,
				Type:     hydroV0.BillingPlanOwner_TYPE_BUSINESS,
				// this is not set by dotcom
				TenantName: "",
			},
		},
	}, nil)

	abuseData := make(map[types.GlobalID]string)
	abuseData[alphaEntityID] = alphaTenantName
	s.azpResources.On("GetDataForAbuseHydro", mock.Anything, []string{alphaTenantName}).Return(&deployer.AbuseHydroDBData{
		EntityIDsToTenantIDs: abuseData,
	}, nil)

	s.hydro.On("Emit", mock.MatchedBy(func(event events.Event) bool {
		rep, ok := event.(abuseDetectionEventChange)
		if !ok {
			return false
		}

		s.Len(rep.changes, 1)
		change := rep.changes[0]
		fd := timestamppb.New(time.Date(2019, 8, 25, 21, 46, 47, 0, time.UTC))

		s.Equal(change.BillingPlanOwner, &hydroV0.BillingPlanOwner{
			GlobalId:   alphaBillingID,
			Name:       "alpha-owner",
			PlanSku:    hydroV0.BillingPlanOwner_SKU_FREE,
			Type:       hydroV0.BillingPlanOwner_TYPE_BUSINESS,
			TenantName: alphaTenantName,
			// TODO not sure if required
			OrganizationTenantName: "",
		})
		// zero out to compare single struct
		change.BillingPlanOwner = nil
		s.Equal(&hydroV0.AbuseDetectionEvent{
			ReputationScore:                   25,
			MaxParallelism:                    11,
			FirstBuildDate:                    fd,
			TotalJobs:                         12,
			InProgressJobs:                    6,
			NumberOfLongRunningRequests:       2,
			AccountLifetimeInMinutes:          100,
			TotalJobRuntime:                   60,
			InProgressJobRuntime:              20,
			HasMaxConcurrentLongRunningBuilds: false,
		}, change)

		return true
	}), mock.Anything)

	res, err := s.svc.AbuseDetectionStatus(ctx, &pb.AbuseStatusRequest{
		Status: abuseDetectionStatusPayload(
			abuseDetectionJSONItem(alphaTenantName),
		),
	})
	s.NoError(err)
	s.True(res.ValidSignature)
}

func (s *abuseDetectionStatusTestSuite) setRequestVerificationResult(valid bool) {
	s.verifier.On("Verify",
		mock.Anything,
		mock.Anything,
		auth.NewKey(primaryHMACKey),
		auth.NewKey(secondaryHMACKey),
	).Return(valid)
}

func abuseDetectionStatusPayload(items ...string) []byte {
	return []byte(fmt.Sprintf(`{"abuseMetrics":[%s]}`, strings.Join(items, ",")))
}

func abuseDetectionJSONItem(tenantName string) string {
	return fmt.Sprintf(`{
		"tenantName": %q,
		"score": 25,
		"maxParallelism": 11,
		"firstBuildDate": "2019-08-25T21:46:47Z",
		"totalJobs": 12,
		"inProgressJobs": 6,
		"numberOfLongRunningRequests": 2,
		"accountLifetimeInMinutes": 100,
		"totalJobRuntime": 60,
		"inProgressJobRuntime": 20,
		"hasMaxConcurrentLongRunningBuilds": false
	}`, tenantName)
}
