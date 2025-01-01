package status

import (
	"context"
	"testing"

	mock "github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/clients/aqueduct"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/types"
)

func TestResultsSyncClient(t *testing.T) {
	suite.Run(t, new(resultsSyncServiceSuite))
}

type resultsSyncServiceSuite struct {
	suite.Suite
	clientProvider func(aqueductClient aqueduct.Client, log logs, twirpClient ghtwirp.Client) *resultsSyncClient
}

func (suite *resultsSyncServiceSuite) SetupTest() {
	suite.clientProvider = newResultsSyncClient
}

func (suite *resultsSyncServiceSuite) Test_CreateCheckRun_ReturnsNil() {
	aqueductClient := aqueduct.NewMockClient(suite.T())
	ghTwirpClient := &ghtwirp.MockClient{}
	resultsSyncClient := suite.clientProvider(aqueductClient, logger.TestLogger(), ghTwirpClient)
	aqueductClient.On("Send", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return("jobID", nil)
	workflowRunBackendID := "test-id-1"
	workflowJobRunBackendID := "test-id-2"
	fakeDotcomID := "fake-dotcom-id"
	fakeCheckRunDatabaseId := int64(1234)
	ctx := context.Background()

	checkRunCreatedRequestResult := resultsSyncClient.CreateCheckRun(ctx, workflowRunBackendID, workflowJobRunBackendID, types.GlobalID(fakeDotcomID), "job", fakeCheckRunDatabaseId)

	suite.Nil(checkRunCreatedRequestResult)
}
