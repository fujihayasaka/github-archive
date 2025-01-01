package tester

import (
	"context"
	"time"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/common"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
	"google.golang.org/protobuf/types/known/timestamppb"
)

var ssatRunTracker runTracker

func init() {
	ssatRunTracker = new(singleRunTracker)
}

type signedAuthTokenTest struct {
	cfg *Config
	runTracker
	credManagerFunc func() (client.CredentialManager, error)
}

// Frequency implements Runnable
func (*signedAuthTokenTest) Frequency() time.Duration {
	return 1 * time.Hour
}

// Name implements Runnable
func (*signedAuthTokenTest) Name() string {
	return "signed_auth_token"
}

// Run implements Runnable
func (satt *signedAuthTokenTest) Run(ctx context.Context) (testErr error) {
	satt.runTracker.Start()
	defer satt.runTracker.Stop()

	logger := diagnostics.Logger(ctx)
	statter := diagnostics.Statter(ctx)

	credentialManager, err := satt.credManagerFunc()
	if err != nil {
		return errors.Wrap(err, "failed to create credential manager client")
	}

	currentOperation := "issue_signed_auth_token"
	defer func() {
		if testErr != nil {
			statter.Counter("ssat_e2e_test_failure", stats.Tags{"operation": currentOperation}, 1)
		}
	}()

	logger.Info("issuing signed auth token")
	start := time.Now()
	var signedAuthTokenResp *pb.IssueSignedAuthTokenResponse
	err = common.WithRetries(ctx, "e2e_test_issue_signed_auth_token", func(ctx context.Context) error {
		var issueErr error
		signedAuthTokenResp, issueErr = credentialManager.IssueSignedAuthToken(ctx, &pb.IssueSignedAuthTokenRequest{
			UserId:        testActorID,
			SessionId:     0,
			Scope:         "test:scope",
			ExpiresAtTime: timestamppb.New(time.Now().Add(10 * time.Minute)),
		})
		return issueErr
	}, 3)
	if err != nil {
		return errors.Wrap(err, "failed to issue signed auth token")
	}
	if signedAuthTokenResp.Error != "" {
		return errors.Errorf("failed to issue signed auth token: %s", signedAuthTokenResp.Error)
	}
	if signedAuthTokenResp.GetToken() == "" {
		return errors.New("Got an empty token but there was no error")
	}
	logger.Info("successfully issued SAT", kvp.Duration("gh.authnd.tester.request.duration", time.Since(start)))
	return nil
}

// Timeout implements Runnable
func (*signedAuthTokenTest) Timeout() time.Duration {
	return 1 * time.Minute
}

func NewSignedAuthTokenTest(cfg *Config) Runnable {
	return &signedAuthTokenTest{
		cfg:        cfg,
		runTracker: ssatRunTracker,
		credManagerFunc: func() (client.CredentialManager, error) {
			return client.NewCredentialManager(
				cfg.AuthndTwirpURL,
				cfg.ServiceName,
				client.WithHMACKey(cfg.GetHMACKey()),
			)
		},
	}
}
