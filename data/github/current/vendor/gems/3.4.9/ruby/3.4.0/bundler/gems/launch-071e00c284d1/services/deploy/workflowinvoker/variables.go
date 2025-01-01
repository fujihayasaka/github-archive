package workflowinvoker

import (
	"context"
	"encoding/base64"

	"github.com/github/go-kvp"
	"github.com/github/kredz/utils/varzconstants"
	"github.com/pkg/errors"
	"golang.org/x/sync/errgroup"

	varzpb "github.com/github/kredz/services/protobuf/varz"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/varz"
	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/types"
)

const (
	batchSize           = int64(100)
	totalSizeBudget     = int64(256 * 1024)       // 256 KB
	totalSizeBudgetGHES = int64(10 * 1024 * 1024) // 10 MB. For more info see https://github.com/github/c2c-actions-ace/issues/321
)

type chunkedVarzResponse struct {
	ChunkSerial  int64
	Chunk        []string
	VarzResponse *varz.ListVariablesResponse
}

type EntityType int

const (
	Repository   EntityType = iota + 1 // EnumIndex = 1
	Organization                       // EnumIndex = 2
)

var ErrVariableSizeExceeded = errors.New("size exceeded while populating variables")

func (i *buildInvoker) getVariables(ctx context.Context, varzClient varz.Client, ghTwirpClient ghtwirp.Client, data *types.WorkflowInvocationData, repoID types.GlobalID) (map[string]string, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	repoGlobalID, err := ghTwirpClient.GetNextGlobalID(ctx, repoID.String())
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	orgGlobalID, err := ghTwirpClient.GetNextGlobalID(ctx, i.data.Owner.GlobalID.String())
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	actionsAppGlobalID, err := ghTwirpClient.GetNextGlobalID(ctx, i.actionsAppGlobalID)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	variables, err := varzClient.ListVariablesForRepository(ctx, data.Owner, orgGlobalID, repoGlobalID, data.RepoIsPrivate, actionsAppGlobalID, false)
	if err != nil {
		return nil, errors.Wrap(err, "could not list variables for repository")
	}

	variablesMap := make(map[string]string, len(variables.RepositoryVariables))
	for name, value := range variables.RepositoryVariables {
		decodedVariableValue, err := base64.StdEncoding.DecodeString(value)
		if err == nil {
			variablesMap[name] = string(decodedVariableValue)
		} else {
			i.obs.Error(ctx, "Error decoding variable value", kvp.Err(err))
		}
	}

	if canUseOrgVariables(data) {
		for name, value := range variables.OrganizationVariables {
			// take org variable only if there is no repo variable with the same name
			if _, ok := variablesMap[name]; !ok {
				decodedVariableValue, err := base64.StdEncoding.DecodeString(value)
				if err == nil {
					variablesMap[name] = string(decodedVariableValue)
				} else {
					i.obs.Error(ctx, "Error decoding variable value", kvp.Err(err))
				}
			}
		}
	}

	return variablesMap, nil
}

// Gets variables and tries to fit them in the 256KB threshold, First tries to fit repo vars and if space remains tries to fit org vars
// this should allow us to send more variables to Actions-Service as compared to getVariables which send 100 repo vars and 100 org vars
func (i *buildInvoker) getVariablesIncreasedCount(ctx context.Context, varzClient varz.Client, ghTwirpClient ghtwirp.Client, data *types.WorkflowInvocationData, repoID types.GlobalID) (map[string]string, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	orgGlobalID := data.Owner.GlobalID

	actionsAppGlobalID, err := ghTwirpClient.GetNextGlobalID(ctx, i.actionsAppGlobalID)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	// init empty payload
	variablesMap := make(map[string]string)

	// Get initial batch,
	variablesResponse, err := varzClient.ListVariablesForRepository(ctx, data.Owner, orgGlobalID, repoID, data.RepoIsPrivate, actionsAppGlobalID, true)
	if err != nil {
		i.obs.Error(ctx, "error while fetching repo variables using ListVariablesForRepository", kvp.Err(err))
		return nil, err
	}
	totalVariables := len(variablesResponse.RepositoryVariables) + len(variablesResponse.OrganizationVariables) + len(variablesResponse.RemainingRepositoryVariablesNames) + len(variablesResponse.RemainingOrganizationVariablesNames)
	useOrgVars := canUseOrgVariables(data)

	sizeBudget := totalSizeBudget
	if i.isEnterprise {
		sizeBudget = totalSizeBudgetGHES
	}
	i.obs.Statter.Distribution(ctx, "variables.count", statter.Tags{"type": "requested"}, float64(totalVariables))

	// Populate first fetch repository variables to map
	sizeBudget = i.mergeVariablesToMapAndReturnRemainingSizeBudget(ctx, variablesResponse.RepositoryVariables, variablesMap, sizeBudget)

	// If there are more repo variables fetch in batches and add to response map
	if sizeBudget > 0 && len(variablesResponse.RemainingRepositoryVariablesNames) > 0 {
		var err error
		// We shouldn't be requesting already fetched vars
		unfetchedVariableNames := getUnfetchedVariableNames(variablesResponse.RemainingRepositoryVariablesNames, variablesMap)
		sizeBudget, err = i.fetchAndMergeRemainingVariables(ctx, varzClient, orgGlobalID, data.Owner.Type, repoID, data.RepoIsPrivate, actionsAppGlobalID, unfetchedVariableNames, variablesMap, sizeBudget, Repository)
		if err != nil {
			i.obs.Error(ctx, "error while fetching remaining repo variables")
			return nil, err
		}
	}
	if sizeBudget < 0 {
		i.obs.Log(ctx, "threshold exceeded while populating repo variables", kvp.Int("gh.launch.total_requested_variables", totalVariables), kvp.Int("gh.launch.populated_variables", len(variablesMap)))
		i.obs.Statter.Counter(ctx, "variables.metrics", statter.Tags{"type": "throttled", "stage": "repository_variables"}, 1)
		return variablesMap, ErrVariableSizeExceeded
	}

	if sizeBudget > 0 && useOrgVars {

		sizeBudget = i.mergeVariablesToMapAndReturnRemainingSizeBudget(ctx, variablesResponse.OrganizationVariables, variablesMap, sizeBudget)

		// If there are more organization variables fetch in batches and add to response map
		if sizeBudget > 0 && len(variablesResponse.RemainingOrganizationVariablesNames) > 0 {
			var err error

			// We shouldn't be requesting already fetched vars
			unfetchedVariableNames := getUnfetchedVariableNames(variablesResponse.RemainingOrganizationVariablesNames, variablesMap)
			sizeBudget, err = i.fetchAndMergeRemainingVariables(ctx, varzClient, orgGlobalID, data.Owner.Type, repoID, data.RepoIsPrivate, actionsAppGlobalID, unfetchedVariableNames, variablesMap, sizeBudget, Organization)
			if err != nil {
				i.obs.Error(ctx, "error while fetching remaining org variables")
				return nil, err
			}
		}
	}
	if sizeBudget < 0 {
		i.obs.Log(ctx, "threshold exceeded while populating organization variables ", kvp.Int("gh.launch.total_requested_variables", totalVariables), kvp.Int("gh.launch.populated_variables", len(variablesMap)))
		i.obs.Statter.Counter(ctx, "variables.metrics", statter.Tags{"type": "throttled", "stage": "organization_variables"}, 1)
		return variablesMap, ErrVariableSizeExceeded
	}

	return variablesMap, nil
}
func canUseOrgVariables(data *types.WorkflowInvocationData) bool {
	if data.Owner.Type != ownerTypeOrganisation {
		return false
	}

	if data.PlanOwner.PlanName == planTypeFreeOrg {
		// Only public repos on free org plans can use org variables
		return !data.RepoIsPrivate
	}

	return true
}

func ShouldSendVariables(eventType string, event flowevents.GitHubEvent, forkPolicy types.ForkPRWorkflowsPolicy, publicForkPolicy types.PublicForkPRWorkflowsPolicy) bool {
	// Variables use same configuration as that of secrets for private fork PRs
	if flowevents.IsRestrictedForkPREvent(eventType, event) && !forkPolicy.ShouldSendSecrets() && !publicForkPolicy.ShouldSendVariables() {
		return false
	}

	return true
}

func (i *buildInvoker) fetchAndMergeRemainingVariables(ctx context.Context, varzClient varz.Client, ownerGlobalID types.GlobalID, ownerType string, repoID types.GlobalID, isPrivateRepo bool, appID types.GlobalID, variableNames []string, variablesMap map[string]string, sizeBudget int64, entityType EntityType) (int64, error) {

	wg, ctx := errgroup.WithContext(ctx)
	chunkSize := int(varzconstants.MaxNamedVariablesInputCount)
	channelSize := (len(variableNames) / chunkSize) + 1
	fetchVarsCh := make(chan chunkedVarzResponse, channelSize)

	for i := 0; i < len(variableNames); i += chunkSize {
		end := i + int(batchSize)

		if end > len(variableNames) {
			end = len(variableNames)
		}

		chunk := variableNames[i:end]
		chunkSerial := i / chunkSize // for closure

		wg.Go(func() error {
			var varzResp *varz.ListVariablesResponse
			var err error

			switch entityType {
			case Repository:
				owner := &varzpb.VariableOwner{
					Owner: &varzpb.VariableOwner_Repository{
						Repository: &varzpb.Repository{
							GlobalId: repoID.String(),
						},
					},
				}
				varzResp, err = varzClient.ListVariablesByNamesForOwner(ctx, owner, appID, chunk)
			case Organization:
				varzResp, err = varzClient.ListOrganizationVariablesForRepositoryByNames(ctx, ownerGlobalID, ownerType, repoID, isPrivateRepo, appID, chunk)
			}

			if err != nil {
				err := errors.Wrap(err, "error retrieving variables")
				return err
			}
			fetchVarsCh <- chunkedVarzResponse{ChunkSerial: int64(chunkSerial), Chunk: chunk, VarzResponse: varzResp}
			return nil
		})
	}
	if err := wg.Wait(); err != nil {
		i.obs.Error(ctx, "error while fetching remaining variables in method fetchAndMergeRemainingVariables", kvp.Err(err))
		return -1, err
	}
	close(fetchVarsCh)

	orderedVarzResp := make([]chunkedVarzResponse, len(fetchVarsCh))
	for fetchedVarzResp := range fetchVarsCh {
		orderedVarzResp[fetchedVarzResp.ChunkSerial] = fetchedVarzResp
	}

	for _, orderedResponseChunk := range orderedVarzResp {
		if sizeBudget < 0 {
			return sizeBudget, nil
		}
		sizeBudget = i.mergeChunkResponseToMapAndReturnRemainingSizeBudget(ctx, orderedResponseChunk, variablesMap, sizeBudget)
	}
	return sizeBudget, nil
}

// Adds variable to map in the order which they are received order is maintained
// Note : We are not checking if variable present in map as we already filter out those before requesting for vars
func (i *buildInvoker) mergeChunkResponseToMapAndReturnRemainingSizeBudget(ctx context.Context, variablesResp chunkedVarzResponse, variablesMap map[string]string, sizeBudget int64) int64 {
	if variablesResp.VarzResponse.Variables == nil {
		return sizeBudget
	}

	for _, varName := range variablesResp.Chunk {

		if value, ok := variablesResp.VarzResponse.Variables[varName]; ok { // name should be present in chunk

			decodedVariableValue, err := base64.StdEncoding.DecodeString(value)
			if err != nil {
				i.obs.Error(ctx, "error decoding variable value", kvp.Err(err))
				continue
			}

			sizeBudget = sizeBudget - int64(len(decodedVariableValue))
			if sizeBudget < 0 {
				return sizeBudget
			}
			variablesMap[varName] = string(decodedVariableValue)
		}
	}
	return sizeBudget
}

// Adds variable to map, order not maintained
func (i *buildInvoker) mergeVariablesToMapAndReturnRemainingSizeBudget(ctx context.Context, variablesResp, variablesPayload map[string]string, sizeBudget int64) int64 {
	if variablesResp == nil {
		return sizeBudget
	}

	for name, value := range variablesResp {
		if _, ok := variablesPayload[name]; !ok {
			decodedVariableValue, err := base64.StdEncoding.DecodeString(value)
			if err != nil {
				i.obs.Error(ctx, "error decoding variable value", kvp.Err(err))
				continue
			}

			sizeBudget = sizeBudget - int64(len(decodedVariableValue))
			if sizeBudget < 0 {
				return sizeBudget
			}
			variablesPayload[name] = string(decodedVariableValue)
		}
	}
	return sizeBudget
}

func getUnfetchedVariableNames(variableNames []string, variablesMap map[string]string) []string {
	filteredVariableNames := make([]string, 0, len(variableNames))
	for _, varName := range variableNames {
		if _, ok := variablesMap[varName]; !ok {
			filteredVariableNames = append(filteredVariableNames, varName)
		}
	}
	return filteredVariableNames
}
