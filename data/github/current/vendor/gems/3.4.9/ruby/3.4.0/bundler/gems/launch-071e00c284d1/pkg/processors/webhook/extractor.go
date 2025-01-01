package webhook

import (
	"context"
	"encoding/json"
	"strings"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"

	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/flow/flowevents/eventactions"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/types"
)

type webhookData struct {
	RepositoryGlobalID   types.GlobalID
	RepositoryDatabaseID int64

	ActorGlobalID   types.GlobalID
	ActorDatabaseID int64
	ActorLogin      string
	ActorType       string

	RepositoryOwnerGlobalID   types.GlobalID
	RepositoryOwnerDatabaseID int64
	RepositoryOwnerLogin      string
	RepositoryOwnerType       string

	EventAction string
}

// ExtractData builds up the webhookData needed for invocation
func (p *Processor) extractData(ctx context.Context, obs *observability.Observability, data *webhookJSON, eventName string) (*webhookData, error) {
	if data.Repository == nil || data.Repository.ID == 0 || data.Repository.NodeID == "" {
		return nil, errors.New("error parsing repository")
	}

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.repo.global_id", data.Repository.NodeID), kvp.Int64("gh.repo.id", data.Repository.ID))
	obs.Debug(ctx, "extracted repository")

	if data.Repository.Owner == nil || data.Repository.Owner.ID == 0 || data.Repository.Owner.NodeID == "" || data.Repository.Owner.Type == "" || data.Repository.Owner.Login == "" {
		return nil, errors.New("error parsing repository owner")
	}

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.repo.owner.global_id", data.Repository.Owner.NodeID), kvp.Int64("gh.repo.owner.id", data.Repository.Owner.ID))
	obs.Debug(ctx, "extracted repository owner")

	if data.Actor == nil || data.Actor.ID == 0 || data.Actor.NodeID == "" {
		if eventName == flowevents.Push {
			// The actor has been deleted, this event is a noop. See https://github.com/github/c2c-actions-experience/issues/5184
			obs.Debug(ctx, "skipping push event with missing sender")
			return nil, nil
		}
		return nil, errors.New("error parsing actor")
	}

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.actor.global_id", data.Actor.NodeID), kvp.String("gh.actor.login", data.Actor.Login))
	obs.Debug(ctx, "extracted actor")

	if data.EventAction != "" {
		ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.event.type", data.EventAction))
		obs.Debug(ctx, "extracted action")
	}

	app, appFound := extractApp(data)
	if appFound {
		ctx = ctxstash.WithFields(ctx, kvp.Any("gh.launch.github_app.id", app.ID), kvp.Any("gh.launch.github_app.name", app.Name))
		obs.Debug(ctx, "extracted event actor/app")
	}

	// Not all events have an "app" block.  We really only care about it for
	// check_run and check_status events, because their "sender" block
	// doesn't identify the event as bot-sent.  For any other event, we can
	// ignore the lack of an "app" block. For rerequested Actions from our own app
	// though, we want to process them.
	if appFound && isActionsApp(app.ID, p.cfg.ActionsAppIDs) && !(isRerequestAction(data.EventAction) || isWorkflowRunEvent(eventName)) {
		obs.Counter(ctx, "queue.webhook.triggered_by_actions_app", statter.Tags{"event_type": eventName}, 1)
		obs.Log(ctx, "skipping event from our own robot app")
		return nil, nil
	}

	// Return without opening a check suite or running any user actions if
	// this event's sender was our own robot.
	if isActionsBot(ctx, data.Actor.NodeID, p.cfg.ActionsBotNodeIDs) && ignoreActionsBotEvent(data.EventAction, eventName) {
		obs.Counter(ctx, "queue.webhook.triggered_by_actions_app", statter.Tags{"event_type": eventName}, 1)
		obs.Log(ctx, "skipping event from our own robot user")
		return nil, nil
	}

	return &webhookData{
		RepositoryGlobalID:        types.NewGlobalID(ctx, data.Repository.NodeID),
		RepositoryDatabaseID:      data.Repository.ID,
		ActorGlobalID:             types.NewGlobalID(ctx, data.Actor.NodeID),
		ActorDatabaseID:           data.Actor.ID,
		ActorLogin:                data.Actor.Login,
		ActorType:                 data.Actor.Type,
		RepositoryOwnerGlobalID:   types.NewGlobalID(ctx, data.Repository.Owner.NodeID),
		RepositoryOwnerLogin:      data.Repository.Owner.Login,
		RepositoryOwnerDatabaseID: data.Repository.Owner.ID,
		RepositoryOwnerType:       data.Repository.Owner.Type,
		EventAction:               data.EventAction,
	}, nil
}

type webhookJSON struct {
	Repository  *repository `json:"repository"`
	Actor       *actor      `json:"sender"`
	CheckRun    *checkRun   `json:"check_run"`
	CheckSuite  *checkSuite `json:"check_suite"`
	EventAction string      `json:"action"`
}

type repository struct {
	Owner  *actor `json:"owner"`
	NodeID string `json:"node_id"`
	ID     int64  `json:"id"`
}

type actor struct {
	NodeID string `json:"node_id"`
	Login  string `json:"login"`
	ID     int64  `json:"id"`
	Type   string `json:"type"`
}

type checkRun struct {
	App *app `json:"app"`
}

type checkSuite struct {
	App *app `json:"app"`
}

type app struct {
	ID   int64  `json:"id"`
	Name string `json:"name"`
}

// Unmarshal webhook payload into a struct that contains all the fields we might
// need. Some fields will be set to their default values, if they are missing.
func unmarshalWebhook(rawData []byte) (*webhookJSON, error) {
	wh := webhookJSON{}
	if err := json.Unmarshal(rawData, &wh); err != nil {
		return nil, errors.Wrap(err, "skipping malformed json payload")
	}
	return &wh, nil
}

func isActionsApp(appID int64, appIDs []int64) bool {
	for _, id := range appIDs {
		if appID == id {
			return true
		}
	}
	return false
}

func isActionsBot(ctx context.Context, actor string, botNodeIDs []types.GlobalID) bool {
	actorID := types.NewGlobalID(ctx, actor)
	for _, id := range botNodeIDs {
		if actorID.IsEquivalent(id) {
			return true
		}
	}
	return false
}

// Take in a webhook event type and determine if whether or not the actions bot should trigger a run or return without processing the event
func ignoreActionsBotEvent(eventAction, eventName string) bool {
	if isRerequestAction(eventAction) || isWorkflowRunEvent(eventName) || isWorkflowDispatchEvent(eventName) || isRepositoryDispatchEvent(eventName) {
		return false
	}

	return true
}

func isRerequestAction(eventAction string) bool {
	return eventAction == eventactions.Rerequested
}

func isWorkflowRunEvent(eventName string) bool {
	return eventName == flowevents.WorkflowRun
}

func isRepositoryDispatchEvent(eventName string) bool {
	return eventName == flowevents.RepositoryDispatch
}

func isWorkflowDispatchEvent(eventName string) bool {
	return eventName == flowevents.WorkflowDispatch
}

func getSyntheticEvent(eventName string) (string, bool) {
	n := strings.ToLower(eventName)
	synthetic, ok := syntheticEvents[n]
	return synthetic, ok
}

func extractApp(wh *webhookJSON) (*app, bool) {
	if wh.CheckRun != nil && wh.CheckRun.App != nil && wh.CheckRun.App.ID != 0 && wh.CheckRun.App.Name != "" {
		return wh.CheckRun.App, true
	}

	if wh.CheckSuite != nil && wh.CheckSuite.App != nil && wh.CheckSuite.App.ID != 0 && wh.CheckSuite.App.Name != "" {
		return wh.CheckSuite.App, true
	}

	return nil, false
}

var syntheticEvents = map[string]string{
	flowevents.PullRequest: flowevents.PullRequestTarget,
}
