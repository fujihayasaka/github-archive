package prejobtoken

import (
	"context"
	"encoding/base64"

	errs "github.com/pkg/errors"

	"github.com/github/go-kvp"

	varzpb "github.com/github/kredz/services/protobuf/varz"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/varz"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/types"
)

func GetEnvironmentVariables(ctx context.Context, varzClient varz.Client, ghTwirpClient ghtwirp.Client, envID types.GlobalID, appID string, obs *observability.Observability) (map[string]string, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	envGlobalID, err := ghTwirpClient.GetNextGlobalID(ctx, envID.String())
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	appGlobalID, err := ghTwirpClient.GetNextGlobalID(ctx, appID)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	envOwner := &varzpb.VariableOwner{
		Owner: &varzpb.VariableOwner_Environment{
			Environment: &varzpb.Environment{
				GlobalId: envGlobalID.String(),
			},
		},
	}

	envVariables, err := varzClient.ListVariablesForOwner(ctx, envOwner, appGlobalID)
	if err != nil {
		return nil, errs.Wrap(err, "error retrieving variables")
	}

	variables := make(map[string]string)
	for name, value := range envVariables.Variables {
		decodedVariableValue, err := base64.StdEncoding.DecodeString(value)
		if err == nil {
			variables[name] = string(decodedVariableValue)
		} else {
			obs.Error(ctx, "Error decoding variable value", kvp.Err(err))
		}
	}

	return variables, nil
}
