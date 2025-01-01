package tester

import (
	"context"
	crand "crypto/rand"
	"crypto/rsa"
	"fmt"
	"math/rand" //nolint:depguard
	"time"

	"github.com/github/authnd/client"
	v0 "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/google/go-github/github"
	"github.com/pkg/errors"
	"golang.org/x/crypto/ssh"
	"golang.org/x/oauth2"
)

// Only one instance of each test object should ever be created in the lifetime of the tester. However,
// set this up as a singleton so no two test instances can run simultaneously even if they are created.
var publicKeysRunTracker runTracker

func init() {
	publicKeysRunTracker = new(singleRunTracker)

	// seed the random number generate to get unique key names
	rand.New(rand.NewSource(time.Now().UnixNano()))
}

func NewPublicKeysTest(cfg *Config) Runnable {
	return &publicKeysTest{
		cfg:        cfg,
		runTracker: publicKeysRunTracker,
		authenticatorFunc: func() (client.Authenticator, error) {
			return client.NewAuthenticator(
				cfg.AuthndTwirpURL,
				cfg.ServiceName,
				client.WithHMACKey(cfg.GetHMACKey()),
			)
		},
		githubCreateFunc: func(ctx context.Context, key *github.Key) (*github.Key, *github.Response, error) {
			ts := oauth2.StaticTokenSource(&oauth2.Token{AccessToken: cfg.TestUserToken})
			tc := oauth2.NewClient(ctx, ts)
			ghClient := github.NewClient(tc)
			return ghClient.Users.CreateKey(ctx, key)
		},
		githubDeleteFunc: func(ctx context.Context, id int64) (*github.Response, error) {
			ts := oauth2.StaticTokenSource(&oauth2.Token{AccessToken: cfg.TestUserToken})
			tc := oauth2.NewClient(ctx, ts)
			ghClient := github.NewClient(tc)
			return ghClient.Users.DeleteKey(ctx, id)
		},
	}
}

type publicKeysTest struct {
	cfg *Config
	runTracker
	authenticatorFunc func() (client.Authenticator, error)
	githubCreateFunc  func(ctx context.Context, key *github.Key) (*github.Key, *github.Response, error)
	githubDeleteFunc  func(ctx context.Context, id int64) (*github.Response, error)
}

func (pkt *publicKeysTest) Name() string {
	return "public_keys"
}

func (pkt *publicKeysTest) Frequency() time.Duration {
	return 1 * time.Hour
}

func (pkt *publicKeysTest) Timeout() time.Duration {
	return 1 * time.Minute
}

// verifies that replication flow from dotcom to authnd for public keys and that
// authnd appropriately validates/rejects public keys based on their status in dotcom
//
// 1. initialize github and authnd clients
// 2. generate SSH public/private keypair
// 3. import SSH public key into github user settings using REST API
// 4. poll authnd until public key is accepted
// 5. delete public key using dotcom REST API
// 6. poll authnd until public key is rejected
func (pkt *publicKeysTest) Run(ctx context.Context) error {
	pkt.runTracker.Start()
	defer pkt.runTracker.Stop()

	logger := diagnostics.Logger(ctx)
	statter := diagnostics.Statter(ctx)

	// 1. initialize authnd client
	authenticator, err := pkt.authenticatorFunc()
	if err != nil {
		return errors.Wrap(err, "failed to create authnd client")
	}

	// 2. generate SSH public/private keypair
	logger.Info("generating ssh keypair")
	privateKey, err := rsa.GenerateKey(crand.Reader, 4096)
	if err != nil {
		return errors.Wrap(err, "failed to generate private key")
	}
	publicRSAKey, err := ssh.NewPublicKey(&privateKey.PublicKey)
	if err != nil {
		return errors.Wrap(err, "failed to generate public rsa key")
	}
	pubKeyBytes := ssh.MarshalAuthorizedKey(publicRSAKey)
	pubKey := string(pubKeyBytes)

	// 3. import SSH public key into github user settings using REST API
	logger.Info("importing ssh public key to dotcom")
	start := time.Now()
	var keyName string
	var keyID int64
	for try := 0; ; try++ {
		// check for test timeout before trying
		if err := ctx.Err(); err != nil {
			logger.Info("test timeout exceeded")
			return errorTestTimeout
		}

		if try+1 == dotcomMaxTries {
			logger.Info("max tries exhausted attempt to import public key to dotcom")
			return dotcomTriesExhausted
		}

		keyName = fmt.Sprintf("authnd-e2e-test-%d", rand.Int())
		key, resp, err := pkt.githubCreateFunc(ctx, &github.Key{
			Key:   &pubKey,
			Title: &keyName,
		})
		if err != nil {
			logger.WithError(err).Info("error importing public key")
			time.Sleep(requestRetryTime)
			continue
		}
		if resp.StatusCode < 300 {
			// success
			keyID = *key.ID
			break
		}

		logger.Info("failed to import public key", kvp.Int("gh.authnd.tester.response.status_code", resp.StatusCode))
		time.Sleep(requestRetryTime)
	}
	duration := time.Since(start)
	statter.DistributionMs("e2e.public_keys.create", nil, duration)
	logger.Info("successfully added key for user", kvp.Int64("gh.authnd.tester.credential.id", keyID), kvp.String("gh.authnd.tester.credential.name", keyName), kvp.Duration("gh.authnd.tester.request.duration", duration))

	// 4. poll authnd until public key is accepted
	logger.Info("checking that the public key is accepted by authnd")
	start = time.Now()
	for try := 0; ; try++ {
		// check for test timeout before trying
		if err := ctx.Err(); err != nil {
			logger.Info("test timeout exceeded")
			return errorTestTimeout
		}

		if try+1 == authndMaxTries {
			logger.Info("max tries exhausted for authnd authenticate request")
			return authndTriesExhausted
		}

		aCtx, cancel := context.WithTimeout(ctx, 1*time.Second)
		defer cancel()

		aResp, err := authenticator.Authenticate(aCtx, client.NewAuthenticateRequest(client.NewSSHKeyCredentials(pubKey)))
		if err != nil {
			logger.WithError(err).Info("error validating public key with authnd")
			time.Sleep(requestRetryTime)
			continue
		}
		if aResp.Result == v0.AuthenticateResponse_RESULT_SUCCESS {
			// success
			break
		}
		logger.Info("public key rejected by authnd", kvp.String("gh.authnd.tester.request.result", aResp.Result.String()))

		time.Sleep(requestRetryTime)
	}
	duration = time.Since(start)
	logger.Info("public key successfully authenticated by authnd", kvp.Duration("gh.authnd.tester.request.duration", time.Since(start)))
	statter.DistributionMs("e2e.public_keys.validate_after_create", nil, duration)

	// 5. delete public key using dotcom REST API
	logger.Info("deleting public key from dotcom")
	start = time.Now()
	for try := 0; ; try++ {
		// check for test timeout before trying again
		if cErr := ctx.Err(); cErr != nil {
			logger.Info("test timeout exceeded")
			return errorTestTimeout
		}

		if try+1 == dotcomMaxTries {
			logger.Info("max tries exhausted attempt to delete public key from dotcom")
			return dotcomTriesExhausted
		}

		gCtx, cancel := context.WithTimeout(ctx, 1*time.Second)
		defer cancel()

		resp, err := pkt.githubDeleteFunc(gCtx, keyID)
		if err != nil {
			logger.WithError(err).Info("error deleting public key")
			time.Sleep(requestRetryTime)
			continue
		}
		if resp.StatusCode < 300 {
			// success
			break
		}

		logger.Info("failed to delete public key from authnd", kvp.Int("gh.authnd.tester.response.status_code", resp.StatusCode))
		time.Sleep(requestRetryTime)
	}
	duration = time.Since(start)
	statter.DistributionMs("e2e.public_keys.delete", nil, duration)
	logger.Info("successfully deleted key for user", kvp.Int64("gh.authnd.tester.credential.id", keyID), kvp.Duration("gh.authnd.tester.request.duration", duration))

	// 6. poll authnd until public key is rejected
	logger.Info("checking that the public key is rejected by authnd")
	start = time.Now()
	for try := 0; ; try++ {
		// check for test timeout before trying
		if err := ctx.Err(); err != nil {
			logger.Info("test timeout exceeded")
			return errorTestTimeout
		}

		if try+1 == authndMaxTries {
			logger.Info("max tries exhausted for authnd authenticate request")
			return authndTriesExhausted
		}

		aCtx, cancel := context.WithTimeout(ctx, 1*time.Second)
		defer cancel()

		aResp, err := authenticator.Authenticate(aCtx, client.NewAuthenticateRequest(
			client.NewSSHKeyCredentials(pubKey),
		))
		if err != nil {
			logger.WithError(err).Info("error validating public key with authnd")
			time.Sleep(requestRetryTime)
			continue
		}
		if aResp.Result == v0.AuthenticateResponse_RESULT_FAILED_PUBLIC_KEY_NOT_FOUND {
			logger.Info("public key appropriately rejected by authnd", kvp.Duration("gh.authnd.tester.request.duration", time.Since(start)))
			break
		} else if aResp.Result == v0.AuthenticateResponse_RESULT_SUCCESS {
			logger.Info("public key accepted by authnd", kvp.String("gh.authnd.tester.request.result", aResp.Result.String()))
		} else {
			logger.Info("public key rejected by authnd for an unexpected reason", kvp.String("gh.authnd.tester.request.result", aResp.Result.String()))
		}

		time.Sleep(requestRetryTime)
	}
	duration = time.Since(start)
	statter.DistributionMs("e2e.public_keys.reject_after_delete", nil, duration)

	return nil
}
