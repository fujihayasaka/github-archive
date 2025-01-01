package checks

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/services/pbtypes"
	"github.com/github/launch/workflowbuild/azp/azptypes"
)

var (
	defaultTime = time.Date(2000, 1, 1, 10, 0, 0, 1, time.UTC)
)

type TestRequest struct {
	Description   string
	Request       *SummaryExchangeURLRequest
	Response      *SummaryExchangeURLResponse
	ErrorExpected bool
}

func TestExchangeURL(t *testing.T) {
	defaultTimeProto := timestamppb.New(defaultTime)

	repoID := &pbtypes.Identity{
		GlobalId: "46704D16-FDBA-45DC-8387-CFDC8B36D120",
	}

	tests := []TestRequest{
		{
			Description: "returns an authenticated url for a valid request",
			Request: &SummaryExchangeURLRequest{
				UnauthenticatedJobSummariesUrl: "https://test-url.com",
				RepositoryId:                   repoID,
			},
			Response: &SummaryExchangeURLResponse{
				AuthenticatedUrl: "https://test-authenticated-url.com",
				ExpiresAt:        defaultTimeProto,
			},
			ErrorExpected: false,
		},
		{
			Description:   "returns an error when request is missing",
			Request:       nil,
			Response:      nil,
			ErrorExpected: true,
		},
		{
			Description: "returns an error when a blank url is provided",
			Request: &SummaryExchangeURLRequest{
				UnauthenticatedJobSummariesUrl: "",
				RepositoryId:                   repoID,
			},
			Response:      nil,
			ErrorExpected: true,
		},
		{
			Description: "returns an error when repository id is missing",
			Request: &SummaryExchangeURLRequest{
				UnauthenticatedJobSummariesUrl: "https://test-url.com",
				RepositoryId:                   nil,
			},
			Response:      nil,
			ErrorExpected: true,
		},
	}

	for _, test := range tests {
		t.Run(test.Description, func(t *testing.T) {
			rcf := &azp.MockRepositoryClientFactory{}
			arr := &deployer.MockAzpResourcesRepository{}
			rrc := &azp.MockRepositoryClient{}
			svc := &service{
				log:                  logger.TestLogger(),
				stats:                statter.NullStatter(),
				azpRepoClientFactory: rcf,
				azpResourceRepo:      arr,
			}
			arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
			rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(rrc)

			if test.Request != nil {
				rrc.On("GetAuthenticatedURL", mock.Anything, test.Request.UnauthenticatedJobSummariesUrl).Return(&azp.GetAuthenticatedURLResponse{
					SignedContent: &azp.SignedContent{
						URL:              "https://test-authenticated-url.com",
						SignatureExpires: defaultTime,
					},
				}, nil)
			}

			got, err := svc.GetSummaryExchangeURL(context.Background(), test.Request)
			if test.ErrorExpected {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
			}

			require.Equal(t, test.Response, got, "response should match expected value")
		})
	}
}
