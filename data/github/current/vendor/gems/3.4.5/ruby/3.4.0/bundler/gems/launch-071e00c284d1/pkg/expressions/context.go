package expressions

import (
	"context"
	"fmt"
	"strconv"
	"strings"

	"github.com/github/actions-expressions/go/data"

	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/observability"
	"github.com/github/launch/workflowbuild/build"
	"github.com/github/launch/workflowparser"
)

// NewContext constructs the "github", "inputs" and "vars" contexts for expression evaluation, and to be sent to Run Service
func NewContext(ctx context.Context, obs *observability.Observability, parsedWorkflow *workflowparser.Workflow, wfb *build.WorkflowBuild, secretSource string, variables map[string]string) (*data.Dictionary, error) {

	github, err := NewGitHubContext(ctx, obs, wfb, secretSource)
	if err != nil {
		return nil, fmt.Errorf("error decoding event for use in build payload: %w", err)
	}

	inputs := newInputsContextFromOnEvent(parsedWorkflow, wfb, github)

	vars := newVarsContext(variables)

	result := data.NewDictionary(
		data.Pair{Key: "github", Value: github},
		data.Pair{Key: "inputs", Value: inputs},
		data.Pair{Key: "vars", Value: vars},
	)
	return result, nil
}

func NewGitHubContext(ctx context.Context, obs *observability.Observability, wfb *build.WorkflowBuild, secretSource string) (*data.Dictionary, error) {

	event, err := flowevents.WorkflowEventContext(ctx, obs, wfb.Event, wfb.EventPayload)
	if err != nil {
		return nil, err
	}

	refType := "branch"
	if wfb.CheckoutRef.IsTagRef() {
		refType = "tag"
	}

	// Keep in sync w/ https://github.com/github/actions-dotnet/blob/abbe3e50446fee6dcda0296b089f6a8ffcb4b1d6/Actions/Service/Server/ActionsService.cs#L518-L551
	github := data.NewDictionary(
		data.Pair{Key: "ref", Value: data.NewString(wfb.CheckoutRef.String())},
		data.Pair{Key: "sha", Value: data.NewString(wfb.CheckoutSHA.String())},
		data.Pair{Key: "repository", Value: data.NewString(wfb.RunEnvironment.Repository.String())},
		data.Pair{Key: "repository_owner", Value: data.NewString(wfb.RunEnvironment.Repository.Owner)},
		data.Pair{Key: "repository_owner_id", Value: data.NewString(strconv.FormatInt(wfb.RunEnvironment.OwnerDatabaseID, 10))},
		data.Pair{Key: "repositoryUrl", Value: data.NewString(wfb.RunEnvironment.GitURL)},
		data.Pair{Key: "run_id", Value: data.NewString(strconv.FormatInt(wfb.RunEnvironment.WorkflowRunID, 10))},
		data.Pair{Key: "run_number", Value: data.NewString(strconv.FormatInt(wfb.RunEnvironment.WorkflowRunNumber, 10))},
		data.Pair{Key: "retention_days", Value: data.NewString(strconv.FormatInt(wfb.RunEnvironment.RetentionDays, 10))},
		data.Pair{Key: "run_attempt", Value: data.NewString(strconv.FormatInt(wfb.RunEnvironment.WorkflowRunAttempt, 10))},
		data.Pair{Key: "artifact_cache_size_limit", Value: data.NewString(strconv.FormatUint(wfb.RunEnvironment.ActionsCacheSizeLimit, 10))},
		data.Pair{Key: "repository_visibility", Value: data.NewString(strings.ToLower(wfb.RunEnvironment.RepositoryVisibility))},
		data.Pair{Key: "actor_id", Value: data.NewString(strconv.FormatInt(wfb.RunEnvironment.ExecutingActorDatabaseID, 10))},
		data.Pair{Key: "actor", Value: data.NewString(wfb.RunEnvironment.ExecutingActor)},
		data.Pair{Key: "workflow", Value: data.NewString(wfb.RunEnvironment.Workflow)},
		data.Pair{Key: "head_ref", Value: data.NewString(wfb.RunEnvironment.HeadRef.String())},
		data.Pair{Key: "base_ref", Value: data.NewString(wfb.RunEnvironment.BaseRef.String())},
		data.Pair{Key: "event_name", Value: data.NewString(wfb.RunEnvironment.Event)},
		data.Pair{Key: "server_url", Value: data.NewString(strings.TrimSuffix(wfb.RunEnvironment.ServerURL, "/"))},
		data.Pair{Key: "api_url", Value: data.NewString(strings.TrimSuffix(wfb.RunEnvironment.APIURL, "/"))},
		data.Pair{Key: "graphql_url", Value: data.NewString(strings.TrimSuffix(wfb.RunEnvironment.GraphQLURL, "/"))},
		data.Pair{Key: "ref_name", Value: data.NewString(wfb.CheckoutRef.TrimRefPrefix())},
		data.Pair{Key: "ref_protected", Value: data.NewBoolean(wfb.CheckoutRefProtected)},
		data.Pair{Key: "ref_type", Value: data.NewString(refType)},
		data.Pair{Key: "secret_source", Value: data.NewString(secretSource)},
		data.Pair{Key: "event", Value: event},
		data.Pair{Key: "workflow_ref", Value: data.NewString(wfb.RunEnvironment.WorkflowRef)},
		data.Pair{Key: "workflow_sha", Value: data.NewString(wfb.RunEnvironment.WorkflowSha.String())},
	)

	if wfb.RunEnvironment.RepositoryDatabaseID > -1 {
		github.Add("repository_id", data.NewString(strconv.FormatInt(wfb.RunEnvironment.RepositoryDatabaseID, 10)))
	}

	if wfb.RunEnvironment.TriggeringActor != "" {
		github.Add("triggering_actor", data.NewString(wfb.RunEnvironment.TriggeringActor))
	}

	return github, nil
}

func newInputsContextFromOnEvent(parsedWorkflow *workflowparser.Workflow, wfb *build.WorkflowBuild, github *data.Dictionary) *data.Dictionary {
	// Load workflow_dispatch input types
	inputTypes := make(map[string]string)
	if ec, ok := parsedWorkflow.OnForEvent(flowevents.WorkflowDispatch); ok && ec.Inputs != nil && wfb.Event == flowevents.WorkflowDispatch {

		for inputName, inputDef := range *ec.Inputs {
			inputTypes[inputName] = strings.ToLower(inputDef.Type)
		}
	}

	// passing false for allowDynamic at this time to not change production behaviour when this is called during run-name calculation
	return NewInputsContext(inputTypes, wfb, github, false)
}

// NewInputsContext takes a set of desired inputs and extracts them from the workflow_dispatch or dynamic event payload as a dictionary.
// If allowDynamic is false, it will only extract from workflow_dispatch events.
func NewInputsContext(inputTypes map[string]string, wfb *build.WorkflowBuild, github *data.Dictionary, allowDynamic bool) *data.Dictionary {
	result := data.NewDictionary()

	if wfb.Event != flowevents.WorkflowDispatch && wfb.Event != flowevents.Dynamic {
		return result
	}

	isDynamicAllowed := allowDynamic && wfb.Event == flowevents.Dynamic

	// Load workflow_dispatch or dynamic input values
	if event, ok := github.Get("event"); ok {
		if eventDict, ok := event.(*data.Dictionary); ok {
			if inputs, ok := eventDict.Get("inputs"); ok {
				if inputsDict, ok := inputs.(*data.Dictionary); ok {
					for _, pair := range inputsDict.Pairs() {
						inputType, exists := inputTypes[pair.Key]
						if exists || isDynamicAllowed { // Dynamic workflows don't define their inputTypes like a workflow dispatch does
							switch strings.ToLower(inputType) {
							case "boolean":
								result.Add(pair.Key, data.NewBoolean(strings.ToLower(pair.Value.CoerceString()) == "true"))
							default:
								result.Add(pair.Key, pair.Value)
							}
						}
					}
				}
			}
		}
	}

	return result
}

func newVarsContext(variables map[string]string) *data.Dictionary {

	result := data.NewDictionary()

	if variables == nil {
		return result
	}

	for k, v := range variables {
		result.Add(k, data.NewString(v))
	}
	return result
}
