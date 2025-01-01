package tester

import (
	"context"
	"fmt"
	"time"

	"github.com/github/authnd/client"
	"github.com/github/authnd/internal/common"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/pkg/errors"

	pb "github.com/github/authnd/client/proto/authentication/v0"
)

const (
	// ID for the 'authnd-tester' user in dotcom production DB. Use this ID to avoid issuing
	// mint tokens for a "real" user in dotcom.
	testActorID   = 87713447
	testActorType = "Bot"
	testAccessID  = 1
)

// Only one instance of each test object should ever be created in the lifetime of the tester. However,
// set this up as a singleton so no two test instances can run simultaneously even if they are created.
var pratRunTracker runTracker

func init() {
	pratRunTracker = new(singleRunTracker)
}

func NewProgrammaticAccessTokenTest(cfg *Config) Runnable {
	return &programmaticAccessTokenTest{
		cfg:        cfg,
		runTracker: pratRunTracker,
		authenticatorFunc: func() (client.Authenticator, error) {
			return client.NewAuthenticator(
				cfg.AuthndTwirpURL,
				cfg.ServiceName,
				client.WithHMACKey(cfg.GetHMACKey()),
			)
		},
		credManagerFunc: func() (client.CredentialManager, error) {
			return client.NewCredentialManager(
				cfg.AuthndTwirpURL,
				cfg.ServiceName,
				client.WithHMACKey(cfg.GetHMACKey()),
			)
		},
	}
}

type programmaticAccessTokenTest struct {
	cfg *Config
	runTracker
	authenticatorFunc func() (client.Authenticator, error)
	credManagerFunc   func() (client.CredentialManager, error)
}

func (pkt *programmaticAccessTokenTest) Name() string {
	return "programmatic_access_token"
}

func (pkt *programmaticAccessTokenTest) Frequency() time.Duration {
	return 1 * time.Hour
}

func (pkt *programmaticAccessTokenTest) Timeout() time.Duration {
	return 1 * time.Minute
}

// verifies the end-to-end flow of issuing, authenticating, and revoking programmatic
// access tokens.
//
// 1. initialize authnd clients
// 2. create new programmatic access token
// 3. authenticate programmatic access token and verify attributes
// 4. revoke programmatic access token
// 5. ensure the programmatic access token is rejected by the server
func (pratt *programmaticAccessTokenTest) Run(ctx context.Context) (testErr error) {
	pratt.runTracker.Start()
	defer pratt.runTracker.Stop()

	logger := diagnostics.Logger(ctx)
	statter := diagnostics.Statter(ctx)

	// 1. initialize authnd clients
	authenticator, err := pratt.authenticatorFunc()
	if err != nil {
		return errors.Wrap(err, "failed to create authenticator client")
	}

	credentialManager, err := pratt.credManagerFunc()
	if err != nil {
		return errors.Wrap(err, "failed to create credential manager client")
	}

	currentOperation := "issue_token"
	defer func() {
		if testErr != nil {
			statter.Counter("prat_e2e_test_failure", stats.Tags{"operation": currentOperation}, 1)
		}
	}()

	// 2. create new programmatic access token. retries are not provided by the client, so we instrument them here.
	logger.Info("issuing programmatic access token")
	start := time.Now()
	var issueResp *pb.IssueTokenResponse
	err = common.WithRetries(ctx, "e2e_test_issue_token", func(ctx context.Context) error {
		var issueErr error
		issueResp, issueErr = credentialManager.IssueToken(ctx, &pb.IssueTokenRequest{
			Attributes: []*pb.Attribute{
				pb.NewInt64Attribute(client.ActorIDAttribute, testActorID),
				pb.NewStringAttribute(client.ActorTypeAttribute, "Bot"),
				pb.NewInt64Attribute(client.ProgrammaticAccessIDAttribute, testAccessID),
			},
			Type: pb.ProgrammaticAccessTokenType,
		})
		return issueErr
	}, 3)
	if err != nil {
		return errors.Wrap(err, "error in issue prat request")
	}
	if issueResp.Result != pb.IssueTokenResponse_RESULT_SUCCESS {
		return errors.Errorf("issue request should have succeeded but returned '%s'", issueResp.Result)
	}
	duration := time.Since(start)
	token, tokenID := issueResp.Token, issueResp.TokenId
	if err != nil {
		return errors.Errorf("token ID is not an integer: %d", issueResp.TokenId)
	}
	logger = logger.WithFields(kvp.Int64("id", tokenID))
	logger.Info("successfully issued programmatic access token", kvp.Duration("gh.authnd.tester.request.duration", duration))
	statter.DistributionMs("e2e.programmatic_access_token.issue", nil, duration)

	// 3. authenticate programmatic access token and verify attributes
	var req *client.AuthenticateRequest
	var authenticateResp *client.AuthenticateResponse
	logger.Info("authenticating programmatic access token")
	start = time.Now()
	for try := 0; ; try++ {
		// check for test timeout before trying
		if err := ctx.Err(); err != nil {
			logger.Info("test timeout exceeded while attempting to authenticate a new prat token")
			return errorTestTimeout
		}

		if try+1 == authndMaxTries {
			logger.Info("max tries exhausted for authnd authenticate request")
			return authndTriesExhausted
		}

		aCtx, cancel := context.WithTimeout(ctx, 1*time.Second)
		defer cancel()

		req = client.NewAuthenticateRequest(
			client.NewAccessTokenCredentials(token),
		)
		authenticateResp, err = authenticator.Authenticate(aCtx, req)
		if err != nil {
			logger.WithError(err).Info("error authenticating programmatic access token with authnd")
			time.Sleep(requestRetryTime)
			continue
		}
		if authenticateResp.Result == pb.AuthenticateResponse_RESULT_SUCCESS {
			// success
			break
		}
		logger.Info(fmt.Sprintf("expected successful programmatic access token authentication response but recieved '%s'", authenticateResp.Result), kvp.String("gh.authnd.tester.request.result", authenticateResp.Result.String()))
		time.Sleep(requestRetryTime)
	}

	duration = time.Since(start)
	logger.Info("successfully authenticated programmatic access token", kvp.Duration("gh.authnd.tester.request.duration", duration))
	statter.DistributionMs("e2e.programmatic_access_token.authenticate", nil, duration)

	// verify 'actor.id' attribute
	actorID, err := authenticateResp.GetIntAttribute(client.ActorIDAttribute)
	if err != nil {
		return errors.Wrapf(err, "error getting '%s' attribute in authenticate response", client.ActorIDAttribute)
	} else if actorID != testActorID {
		return errors.Errorf("mismatch in '%s' attribute. got %d but expected %d.", client.ActorIDAttribute, actorID, testActorID)
	}
	// verify 'actor.type' attribute
	actorType, err := authenticateResp.GetStringAttribute(client.ActorTypeAttribute)
	if err != nil {
		return errors.Wrapf(err, "error getting '%s' attribute in authenticate response", client.ActorTypeAttribute)
	} else if actorType != testActorType {
		return errors.Errorf("mismatch in '%s' attribute. got %s but expected %s.", client.ActorTypeAttribute, actorType, testActorType)
	}
	// verify 'access.id' attribute
	accessID, err := authenticateResp.GetIntAttribute(client.ProgrammaticAccessIDAttribute)
	if err != nil {
		return errors.Wrapf(err, "error getting '%s' attribute in authenticate response", client.ProgrammaticAccessIDAttribute)
	} else if accessID != testAccessID {
		return errors.Errorf("mismatch in '%s' attribute. got %d but expected %d.", client.ProgrammaticAccessIDAttribute, accessID, testAccessID)
	}
	// verify 'credential.type' attribute
	credentialType, err := authenticateResp.GetStringAttribute(client.CredentialTypeAttribute)
	if err != nil {
		return errors.Wrapf(err, "error getting '%s' attribute in authenticate response", client.CredentialTypeAttribute)
	} else if credentialType != pb.ProgrammaticAccessTokenType {
		return errors.Errorf("mismatch in '%s' attribute. got %s but expected %s.", client.CredentialTypeAttribute, credentialType, pb.ProgrammaticAccessTokenType)
	}
	// verify 'credential.id' attribute
	credentialID, err := authenticateResp.GetIntAttribute(client.CredentialIDAttribute)
	if err != nil {
		return errors.Wrapf(err, "error getting '%s' attribute in authenticate response", client.CredentialIDAttribute)
	} else if credentialID != int64(tokenID) {
		return errors.Errorf("mismatch in '%s' attribute. got %d but expected %d.", client.CredentialIDAttribute, credentialID, tokenID)
	}

	// 4. revoke programmatic access token. retries are not provided by the client, so we instrument them here.
	logger.Info("revoking programmatic access token")
	start = time.Now()
	var revokeResp *pb.BatchRevokeResponse
	err = common.WithRetries(ctx, "e2e_test_revoke_token", func(ctx context.Context) error {
		var revokeErr error
		revokeResp, revokeErr = credentialManager.RevokeCredentials(ctx, &pb.RevokeRequest{
			Reason: "e2e test",
			Kind: &pb.RevokeRequest_ByCredential{
				ByCredential: &pb.RevokeByCredential{
					Credentials: []*pb.Credentials{
						pb.NewAccessTokenCredential(token),
					},
				},
			},
		})
		return revokeErr
	}, 3)
	if err != nil {
		return errors.Wrap(err, "error in revoke prat request")
	}
	if len(revokeResp.Responses) != 1 {
		return errors.Errorf("incorrect number of revoke responses. expected 1 but found %d", len(revokeResp.Responses))
	}
	tokenRevokeResponse := revokeResp.Responses[0]
	if tokenRevokeResponse.Result != pb.RevokeResponse_RESULT_SUCCESS {
		return errors.Errorf("revoke request should have succeeded but returned '%s'", tokenRevokeResponse.Result)
	}
	duration = time.Since(start)
	logger.Info("successfully revoked programmatic access token", kvp.Duration("gh.authnd.tester.request.duration", duration))
	statter.DistributionMs("e2e.programmatic_access_token.revoke", nil, duration)

	// 5. ensure the programmatic access token is rejected by the server
	logger.Info("verifying server rejects revoked programmatic access token")
	start = time.Now()
	for try := 0; ; try++ {
		// check for test timeout before trying
		if err := ctx.Err(); err != nil {
			logger.Info("test timeout exceeded while attempting to authenticate a revoked prat token")
			return errorTestTimeout
		}

		if try+1 == authndMaxTries {
			logger.Info("max tries exhausted for authnd authenticate request")
			return authndTriesExhausted
		}

		aCtx, cancel := context.WithTimeout(ctx, 1*time.Second)
		defer cancel()

		authenticateResp, err = authenticator.Authenticate(aCtx, req)
		if err != nil {
			logger.WithError(err).Info("error authenticating programmatic access token with authnd")
			time.Sleep(requestRetryTime)
			continue
		}
		if authenticateResp.Result == pb.AuthenticateResponse_RESULT_FAILED_CREDENTIAL_REVOKED {
			// success
			break
		}
		logger.Info(fmt.Sprintf("expected failed authentication response due to revocation but recieved  '%s'", authenticateResp.Result), kvp.String("gh.authnd.tester.request.result", authenticateResp.Result.String()))
		time.Sleep(requestRetryTime)
	}

	duration = time.Since(start)
	logger.Info("successfully rejected revoked programmatic access token", kvp.Duration("gh.authnd.tester.request.duration", duration))
	statter.DistributionMs("e2e.programmatic_access_token.reject_after_revoke", nil, duration)

	return nil
}
