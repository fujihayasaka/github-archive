package fromctx

import (
	"context"
	"encoding/json"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/github/turboghas/internal/lag"
	"github.com/pkg/errors"
	"github.com/simon-engledew/ctxkey"
)

type lagKey struct {
	ctxkey.ContextKey[lag.Client]
}

var Lag = lagKey{
	ctxkey.New[lag.Client](lag.NullClient),
}

func (k *lagKey) Wait(ctx context.Context, msg hydro.Message) error {
	delay, delayErr := k.Delay(ctx, msg)
	if delayErr != nil {
		return errors.Wrap(delayErr, "could not fetch current replication lag")
	}
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-time.After(delay):
		return nil
	}
}

const replicationStateHeader = "replication_state"

// Delay returns the duration we should wait to ensure that the replicas referenced by a hydro message
// have caught up.
func (k *lagKey) Delay(ctx context.Context, msg hydro.Message) (time.Duration, error) {
	var delay time.Duration

	client := k.Value(ctx)

	statter := Statter.Value(ctx)
	logger := Logger.Value(ctx)

	header, ok := msg.Headers[replicationStateHeader]
	if !ok {
		return 0, nil
	}

	var clusters map[string]struct {
		GTID string `json:"gtid"`
		Time int64
	}
	if err := json.Unmarshal([]byte(header), &clusters); err != nil {
		return delay, errors.Wrap(err, "could not decode cluster information")
	}

	for name, info := range clusters {
		cluster := name

		// Find the correct cluster names by searching with https://professorx.githubapp.com/mysql
		switch name {
		case "memex":
			cluster = "blanket"
		case "github_models", "signup_flow":
			cluster = "ballast"
		case "notifications_summaries":
			cluster = "notification-summaries"
		case "iam":
			cluster = "iam_abilities"
		}

		v, err := client.Value(ctx, cluster)
		if err != nil {
			logger.Info("could not fetch lag for cluster", kvp.String("header", name), kvp.String("cluster", cluster), kvp.Err(err))
		}

		then := time.UnixMilli(info.Time)

		d := max(0, time.Until(then.Add(v)))

		statter.DistributionMs("replication_lag", stats.Tags{"cluster": name}, d)

		delay = max(delay, d)
	}

	statter.DistributionMs("replication_delay", nil, delay)

	return delay, nil
}
