package webhook

import (
	"context"
	"testing"

	"github.com/pkg/errors"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/config/customerlabels"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/slometrics"
	"github.com/github/launch/pkg/rate"
	"github.com/github/launch/pkg/schedulemanager"
	"github.com/github/launch/services/deploy/adminevents"
	"github.com/github/launch/services/deploy/workflowinvoker"
	"github.com/github/launch/types"
)

type extractorSuite struct {
	suite.Suite
	obs       *observability.Observability
	ctx       context.Context
	processor *Processor
	m         mocks
}

func TestExtractData(t *testing.T) {
	suite.Run(t, new(extractorSuite))
}

func (e *extractorSuite) SetupTest() {
	e.ctx = context.Background()
	e.obs = observability.NewNullObservability()

	e.m.invoker = &workflowinvoker.MockInvoker{}
	e.m.wbRepo = &deployer.MockWorkflowBuildsRepository{}
	e.m.scheduleMngr = &schedulemanager.MockManager{}
	e.m.reporter = &adminevents.MockReporter{}
	e.m.hydroEmitter = &slometrics.MockHydroEmitter{}
	e.m.ghTwirp = &ghtwirp.MockClient{}

	sloReporter := slometrics.New(e.m.hydroEmitter)
	labeler := customerlabels.NewNoopCustomerLabeler()
	webhookRateLimiter := &rate.NullRateLimiter{}

	e.processor = New(&Config{}, e.m.invoker, e.m.wbRepo, e.m.scheduleMngr, e.m.ghTwirp, e.m.reporter, sloReporter, labeler, webhookRateLimiter)
}

func (e *extractorSuite) Test_isActionBot_HandlesGlobalIdEquivalency() {
	examples := []struct {
		desc         string
		actor        string
		botGlobalIDs []types.GlobalID
		expected     bool
	}{
		{"old_old_equivalent", "MDM6Qm90NDE4OTgyODI=", []types.GlobalID{"MDM6Qm90NDE4OTgyODI=", "MDM6Qm90NDE5ODk1OTA="}, true},
		{"new_new_equivalent", "BOT_kgDOAn9RKg", []types.GlobalID{"BOT_kgDOAn9RKg", "BOT_kgDOAoC11g"}, true},
		{"old_new_equivalent", "MDM6Qm90NDE5ODk1OTA=", []types.GlobalID{"BOT_kgDOAn9RKg", "BOT_kgDOAoC11g"}, true},
		{"new_old_equivalent", "BOT_kgDOAoC11g", []types.GlobalID{"MDM6Qm90NDE4OTgyODI=", "MDM6Qm90NDE5ODk1OTA="}, true},
		{"old_old_not_equivalent", "O_kgDNA-o", []types.GlobalID{"MDM6Qm90NDE4OTgyODI=", "MDM6Qm90NDE5ODk1OTA="}, false},
		{"new_new_not_equivalent", "U_kgDOADfZAQ", []types.GlobalID{"BOT_kgDOAoC11g", "BOT_kgDOAoC11g"}, false},
	}
	for _, ex := range examples {
		e.Run(ex.desc, func() {
			result := isActionsBot(e.ctx, ex.actor, ex.botGlobalIDs)
			e.Assert().Equal(result, ex.expected)
		})
	}
}

func (e *extractorSuite) Test_extractData_HandlesActorCorrectly() {
	examples := []struct {
		fixture       string
		event         string
		expectedError error
		expected      *actor
	}{
		{"push.json", "push", nil, &actor{NodeID: "BOT_kgDOAoC11g", Login: "fried-oreos-bot", Type: "User", ID: 41989590}},
		{"push_missing_sender.json", "push", nil, nil},
		{"robot_issues_event.json", "issues", nil, &actor{NodeID: testRobotNodeID, Login: "github-actions[bot]", Type: "Bot", ID: 41898282}},
		{"robot_check_suite.json", "", nil, &actor{NodeID: testRobotNodeID, Login: "github-actions[bot]", Type: "Bot", ID: 41898282}},
		{"robot_check_run.json", "", nil, &actor{NodeID: testRobotNodeID, Login: "github-actions[bot]", Type: "Bot", ID: 41898282}},
		{"empty_event.json", "", errors.New("error parsing repository"), nil},
		{"pull_request_missing_sender.json", "", errors.New("error parsing actor"), nil},
	}
	for _, t := range examples {
		e.Run(t.fixture, func() {
			data, err := unmarshalWebhook(fixture(e.T(), t.fixture))
			require.NoError(e.T(), err)
			wh, err := e.processor.extractData(e.ctx, e.obs, data, t.event)
			if err == nil {
				e.NoError(t.expectedError)
			} else {
				e.Assert().EqualError(err, t.expectedError.Error())
			}

			if wh != nil {
				e.Assert().Equal(t.expected.NodeID, wh.ActorGlobalID.String())
				e.Assert().Equal(t.expected.Type, wh.ActorType)
				e.Assert().Equal(t.expected.ID, wh.ActorDatabaseID)
				e.Assert().Equal(t.expected.Login, wh.ActorLogin)
			} else {
				e.Assert().Nil(wh)
			}
		})
	}
}

func (e *extractorSuite) Test_extractData_HandleActionsApps() {
	examples := []struct {
		fixture      string
		isActionsApp bool
	}{
		{"robot_issues_event.json", false},
		{"robot_check_suite.json", true},
		{"robot_check_run.json", true},
	}
	for _, ex := range examples {
		e.Run(ex.fixture, func() {
			data, err := unmarshalWebhook(fixture(e.T(), ex.fixture))
			require.NoError(e.T(), err)
			e.processor.cfg.ActionsAppIDs = []int64{9836}
			wh, err := e.processor.extractData(e.ctx, e.obs, data, "")
			if ex.isActionsApp {
				assert.Nil(e.T(), wh)
				assert.Nil(e.T(), err)
			} else {
				assert.NotNil(e.T(), wh)
				assert.Nil(e.T(), err)
			}
		})
	}
}

func (e *extractorSuite) Test_extractData_HandleActionsBots() {
	examples := []struct {
		fixture      string
		isActionsBot bool
		botGlobalID  types.GlobalID
	}{
		{"robot_issues_event.json", true, testRobotNodeID},
		{"robot_check_suite.json", true, testRobotNodeID},
		{"robot_check_run.json", true, testRobotNodeID},
		{"check_run.json", false, "MDM6Qm90NDE4OTgyODI="},
	}
	for _, ex := range examples {
		e.Run(ex.fixture, func() {
			data, err := unmarshalWebhook(fixture(e.T(), ex.fixture))
			require.NoError(e.T(), err)
			e.processor.cfg.ActionsBotNodeIDs = []types.GlobalID{ex.botGlobalID}
			wh, err := e.processor.extractData(e.ctx, e.obs, data, "")
			if ex.isActionsBot {
				assert.Nil(e.T(), wh)
				assert.Nil(e.T(), err)
			} else {
				assert.NotNil(e.T(), wh)
				assert.Nil(e.T(), err)
			}
		})
	}
}

func (e *extractorSuite) Test_extractData_HandlesRepositoryOwners() {
	examples := []struct {
		fixture            string
		expectedGlobalID   types.GlobalID
		expectedLogin      string
		expectedType       string
		expectedDatabaseID int64
		expectedError      error
	}{
		{"pull_request_missing_repo_owner.json", types.GlobalID(""), "", "", 0, errors.New("error parsing repository owner")},
		{"check_run.json", types.GlobalID("U_kgDOAP3FAg"), "github", "Organization", 16631042, nil},
		{"push.json", types.GlobalID("O_kgDNA-o"), "fried-oreos", "Organization", 1002, nil},
	}
	for _, ex := range examples {
		e.Run(ex.fixture, func() {
			data, err := unmarshalWebhook(fixture(e.T(), ex.fixture))
			e.NoError(err)
			e.processor.cfg.ActionsAppIDs = []int64{9836}
			wh, err := e.processor.extractData(e.ctx, e.obs, data, "")
			if ex.expectedError != nil {
				e.EqualError(err, ex.expectedError.Error())
			} else {
				e.NoError(err)
				e.NotNil(wh)
				e.Equal(ex.expectedGlobalID, wh.RepositoryOwnerGlobalID)
				e.Equal(ex.expectedLogin, wh.RepositoryOwnerLogin)
				e.Equal(ex.expectedDatabaseID, wh.RepositoryOwnerDatabaseID)
				e.Equal(ex.expectedType, wh.RepositoryOwnerType)
			}
		})
	}
}

func (e *extractorSuite) Test_extractData_HandlesRepositories() {
	examples := []struct {
		fixture            string
		expectedID         types.GlobalID
		expectedDatabaseID int64
		expectedError      error
	}{
		{"pull_request_missing_repo.json", types.GlobalID(""), 0, errors.New("error parsing repository")},
		{"empty_event.json", types.GlobalID(""), 0, errors.New("error parsing repository")},
		{"check_run.json", types.GlobalID("R_kgDNA-c"), 526, nil},
	}
	for _, ex := range examples {
		e.Run(ex.fixture, func() {
			data, err := unmarshalWebhook(fixture(e.T(), ex.fixture))
			e.NoError(err)
			e.processor.cfg.ActionsAppIDs = []int64{9836}
			wh, err := e.processor.extractData(e.ctx, e.obs, data, "")
			if ex.expectedError != nil {
				e.EqualError(err, ex.expectedError.Error())
			} else {
				e.NoError(err)
				e.NotNil(wh)
				e.Assert().Equal(ex.expectedID, wh.RepositoryGlobalID)
				e.Assert().Equal(ex.expectedDatabaseID, wh.RepositoryDatabaseID)
			}
		})
	}
}

func (e *extractorSuite) Test_extractData_EvaluateActionsBotEvents() {
	examples := []struct {
		fixture      string
		eventType    string
		eventIgnored bool
	}{
		{"robot_workflow_dispatch.json", "workflow_dispatch", false},
		{"robot_repository_dispatch.json", "repository_dispatch", false},
		{"robot_push_event.json", "push", true},
	}
	for _, ex := range examples {
		e.Run(ex.fixture, func() {
			data, err := unmarshalWebhook(fixture(e.T(), ex.fixture))
			require.NoError(e.T(), err)

			e.processor.cfg.ActionsAppIDs = []int64{9836}
			e.processor.cfg.ActionsBotNodeIDs = []types.GlobalID{"BOT_kgDOAoC11g"}
			wh, err := e.processor.extractData(e.ctx, e.obs, data, ex.eventType)
			e.NoError(err)
			if ex.eventIgnored {
				e.Nil(wh)
			} else {
				e.NotNil(wh)
			}
		})
	}
}
