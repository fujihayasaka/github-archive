package deploy

import (
	"context"
	"encoding/base64"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
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

func TestAbuseStatus(t *testing.T) {
	suite.Run(t, new(abuseStatusTestSuite))
}

type abuseStatusTestSuite struct {
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

func (s *abuseStatusTestSuite) SetupSuite() {
	s.azpResources = deployer.MockAzpResourcesRepository{}
}

func (s *abuseStatusTestSuite) TearDownSuite() {
	s.azpResources.AssertExpectations(s.T())
}

func (s *abuseStatusTestSuite) SetupTest() {
	log := logger.TestLogger()
	statter := statter.NullStatter()

	s.hydro = &events.MockHydro{}

	s.ghClient = &github.MockClient{}
	s.ghFactory = &github.MockFactory{}

	s.internalClient = &ghinternal.MockClient{}
	s.internalClientFactory = &ghinternal.MockFactory{}
	s.internalClientFactory.On("Create").Return(s.internalClient, nil)

	s.verifier = &auth.MockVerifier{}

	s.keyVaultClient = &azp.MockKeyVaultClient{}

	s.keyVaultClient.
		On("GetSecret", mock.Anything, authVaultName, primaryHMACKeyName).
		Return(makeKeyVaultSecret(primaryHMACKey), nil).
		Once()
	s.keyVaultClient.
		On("GetSecret", mock.Anything, authVaultName, secondaryHMACKeyName).
		Return(makeKeyVaultSecret(secondaryHMACKey), nil).
		Once()

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

var (
	alphaTenantName  = "alpha-abuse-tenant"
	alphaEntityID    = types.GlobalID("alpha-abuse-tenant")
	alphaBillingID   = "alpha-billing-id"
	authVaultName    = "some vault name"
	primaryHMACKey   = []byte("primary secret key")
	secondaryHMACKey = []byte("secondary secret key")
)

func makeKeyVaultSecret(pwd []byte) *azp.KeyVaultSecret {
	val := fmt.Sprintf(`{"Password":"%s"}`, base64.StdEncoding.EncodeToString(pwd))
	return &azp.KeyVaultSecret{
		Value: val,
	}
}

func (s *abuseStatusTestSuite) TestVerification() {
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
	keyVaultClient.
		On("GetSecret", mock.Anything, authVaultName, primaryHMACKeyName).
		Return(makeKeyVaultSecret(primaryKey), nil).
		Once()
	keyVaultClient.
		On("GetSecret", mock.Anything, authVaultName, secondaryHMACKeyName).
		Return(makeKeyVaultSecret([]byte("foo")), nil).
		Once()

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

func (s *abuseStatusTestSuite) TestInvalidPayloadsAreRejected() {
	s.setRequestVerificationResult(false)

	ctx := context.Background()
	res, err := s.svc.AbuseStatus(ctx, &pb.AbuseStatusRequest{})
	s.NoError(err)
	s.False(res.ValidSignature)
}

func (s *abuseStatusTestSuite) TestHandlesEmptyUpdate() {
	s.setRequestVerificationResult(true)

	ctx := context.Background()
	res, err := s.svc.AbuseStatus(ctx, &pb.AbuseStatusRequest{
		Status: []byte(`{"reputations":[]}`),
	})
	s.NoError(err)
	s.True(res.ValidSignature)
}

func (s *abuseStatusTestSuite) TestMessageIsPublished() {
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
	s.azpResources.On("GetDataForAbuseHydro", mock.Anything, []string{alphaEntityID.String()}).Return(&deployer.AbuseHydroDBData{
		EntityIDsToTenantIDs: abuseData,
	}, nil)

	s.hydro.On("Emit", mock.MatchedBy(func(event events.Event) bool {
		rep, ok := event.(reputationScoreEvent)
		if !ok {
			return false
		}

		s.Len(rep.changes, 1)
		change := rep.changes[0]
		fd := timestamppb.New(time.Date(2019, 8, 25, 21, 46, 47, 0, time.UTC))
		ed := timestamppb.New(time.Date(2019, 8, 28, 21, 46, 47, 0, time.UTC))

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
		s.Equal(&hydroV0.ReputationScoreChange{
			ReputationScore:         25,
			IsConstant:              false,
			FirstDate:               fd,
			EvaluationDate:          ed,
			HasPrivateProject:       true,
			MaxParallelism:          11,
			RunCount:                238,
			RunAverage:              8,
			RunDeviation:            1,
			RunDensity:              85,
			MaliciousProcessDensity: 12,
			AlteredHostsFileDensity: 123,
			SuspiciousSourceDensity: 1234,
		}, change)

		return true
	}), mock.Anything)

	res, err := s.svc.AbuseStatus(ctx, &pb.AbuseStatusRequest{
		Status: abuseStatusPayload(
			abuseJSONItem(alphaTenantName),
		),
	})
	s.NoError(err)
	s.True(res.ValidSignature)
}
func TestSumByEntityTypes(t *testing.T) {
	ids := []types.GlobalID{
		"MDEwOlJlcG9zaXRvcnk3MzM2ODg0MQ==",
		"MDEwOlJlcG9zaXRvcnk3MzM2ODg0MQ==",
		"MDg6Q2hlY2tSdW4yNjM5ODIxMjg=",
	}

	assert.Equal(t, map[string]int64{
		"Repository": 2,
		"CheckRun":   1,
	}, sumByEntityType(ids))
}

func TestValidatesUpdates(t *testing.T) {
	_, err := updateToHydro(update{
		FirstDate:      time.Time{},
		EvaluationDate: time.Time{},
	})
	assert.EqualError(t, err, "FirstDate must be non-zero value")
}

func (s *abuseStatusTestSuite) setRequestVerificationResult(valid bool) {
	s.verifier.On("Verify",
		mock.Anything,
		mock.Anything,
		auth.NewKey(primaryHMACKey),
		auth.NewKey(secondaryHMACKey),
	).Return(valid)
}

func abuseStatusPayload(items ...string) []byte {
	return []byte(fmt.Sprintf(`{"reputations":[%s]}`, strings.Join(items, ",")))
}

func abuseJSONItem(tenantName string) string {
	return fmt.Sprintf(`{
		"tenantName": %q,
		"score": 25,
		"isConstant": false,
		"firstDate": "2019-08-25T21:46:47Z",
		"evaluationDate": "2019-08-28T21:46:47Z",
		"hasPrivateProject": true,
		"maxParallelism": 11,
		"runCount":238,
		"runAverage":8,
		"runDeviation":1,
		"runDensity":85,
		"maliciousProcessDensity":12,
		"alteredHostsFileDensity":123,
		"suspiciousSourceDensity":1234
	}`, tenantName)
}
