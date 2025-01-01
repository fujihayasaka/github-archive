package diagnostics

import (
	"context"
	"crypto/sha256"
	"fmt"
	"runtime"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/common/tokens"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
)

// LogDecision logs the result and output attributes of an authentication decision.
func LogDecision(ctx context.Context, creds *pb.Credentials, resp *pb.AuthenticateResponse) {
	fields := make([]kvp.Field, 0, 3+len(resp.Attributes))
	digest := sha256.New()
	digOk := true

	for _, a := range resp.Attributes {
		value, err := a.Value.Unwrap()
		if err != nil {
			value = "???"
		}
		fields = append(fields, kvp.Any(a.Id, value))

		if _, err := digest.Write([]byte(fmt.Sprintf("%s:%v", a.Id, value))); err != nil {
			digOk = false
		}
	}

	if digOk {
		fields = append(fields, kvp.String("digest", fmt.Sprintf("%x", digest.Sum(nil))))
	}

	fields = append(fields, kvp.String("result", resp.Result.String()))
	fields = append(fields, commonFields(creds)...)

	Logger(ctx).Info("authentication request decision", fields...)
}

func LogError(ctx context.Context, creds *pb.Credentials, err error) {
	Logger(ctx).Error("authentication request failed", append(
		commonFields(creds),
		kvp.Err(err),
	)...)
}

func commonFields(creds *pb.Credentials) []kvp.Field {
	credential_type := "unknown"
	credential := "unknown"
	switch creds.GetKind().(type) {
	case *pb.Credentials_LoginPassword:
		credential_type = "login"
		credential = creds.GetLoginPassword().GetLogin()
	case *pb.Credentials_SshPublicKey:
		credential_type = "ssh_public_key"
		credential = creds.GetSshPublicKey().GetKey()
	case *pb.Credentials_AccessToken:
		credential_type = "sha256_hashed_access_token"
		credential = tokens.Hash(creds.GetAccessToken().GetToken())
	}

	fields := make([]kvp.Field, 0, 2)
	if credential != "unknown" {
		fields = append(fields,
			kvp.String("gh.authnd.request.credential.value", credential),
			kvp.String("gh.authnd.request.credential.type", credential_type))
	}
	return fields
}

func StartService(ctx context.Context) {
	Logger(ctx).Info("starting",
		// Add some useful stats to the start message.
		kvp.Int("process.cpus", runtime.NumCPU()),
		kvp.String("build.go_version", runtime.Version()),

		// If the parameter to GOMAXPROCS is 0, it just returns the current value.
		kvp.Int("GOMAXPROCS", runtime.GOMAXPROCS(0)),
	)
	statter := Statter(ctx)
	statter.Run()
	statter.Counter("service.start", nil, 1)
}

// Deprecated logs a warning message and increments the 'deprecated' metric with the 'feature' tag set the the provided value
//
// This is useful for tracking usage of deprecated features.
// Trigger a warning in places in the code where a deprecated feature is used, and monitor the metric to ensure it's at 0 before removing the feature entirely
func Deprecated(ctx context.Context, feature string) {
	Logger(ctx).Info("deprecated feature used", kvp.String("feature", feature))
	Statter(ctx).Counter("deprecated", stats.Tags{"feature": feature}, 1)
}
