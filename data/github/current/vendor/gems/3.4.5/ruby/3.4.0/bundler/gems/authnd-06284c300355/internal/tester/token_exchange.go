package tester

import (
	"context"
	"crypto/rsa"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/github/authnd/client"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	jwt "github.com/golang-jwt/jwt/v5"
	"github.com/pkg/errors"

	pb "github.com/github/authnd/client/proto/authentication/v0"
)

const (
	// 'authnd-tester-github-app' owned by the authnd-tester functional account
	// https://github.com/settings/apps/authnd-tester-github-app
	AppID    = int64(1083736)
	ClientID = "Iv23lifgF0XXnew0jYx0"

	// the owner of the app is the authnd-tester functional account
	AppOwnerID     = int64(testActorID)
	AppOwnerType   = "User"
	InstallationID = int64(58462832)
	// the app is installed on the authnd-tester functional account
	InstallationTargetID   = int64(testActorID)
	InstallationTargetType = "User"
)

type tokenVerifier interface {
	VerifyToken(token string) ([]*pb.Attribute, error)
}

type tokenExchangeTest struct {
	cfg *Config
	runTracker
	createTokenFunc           func() (string, error)
	authenticatorFunc         func(stats.Client) (client.Authenticator, error)
	exchangeTokenFunc         func(stats.Client) (client.TokenExchanger, error)
	exchangeTokenVerifierFunc func(stats.Client) (tokenVerifier, error)
}

var tokenExchangeTracker runTracker

func init() {
	tokenExchangeTracker = new(singleRunTracker)
}

func createAuthJWT(privateKey *rsa.PrivateKey) (string, error) {
	claims := jwt.MapClaims{
		"iat": time.Now().Unix(),
		"exp": time.Now().Add(10 * time.Minute).Unix(),
		"iss": AppID,
	}

	token := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)

	signedToken, err := token.SignedString(privateKey)
	if err != nil {
		return "", err
	}

	return signedToken, nil
}

func getServerToServerToken(jwt string) (string, error) {
	client := &http.Client{}

	apiURL := fmt.Sprintf("https://api.github.com/app/installations/%d/access_tokens", InstallationID)
	req, err := http.NewRequest(http.MethodPost, apiURL, nil)
	if err != nil {
		return "", err
	}

	req.Header.Add("Accept", "application/vnd.github+json")
	req.Header.Add("X-GitHub-Api-Version", "2022-11-28")
	req.Header.Add("Authorization", "Bearer "+jwt)

	res, err := client.Do(req)
	if err != nil {
		return "", err
	}
	if res.StatusCode != http.StatusCreated {
		return "", fmt.Errorf("unexpected status code: %d", res.StatusCode)
	}
	defer res.Body.Close()

	var resp struct {
		Token string `json:"token"`
	}
	decoder := json.NewDecoder(res.Body)
	err = decoder.Decode(&resp)
	if err != nil {
		return "", err
	}
	if resp.Token == "" {
		return "", errors.New("empty token in response")
	}

	return resp.Token, nil
}

func NewTokenExchangeTest(cfg *Config) Runnable {
	return &tokenExchangeTest{
		cfg:        cfg,
		runTracker: tokenExchangeTracker,
		createTokenFunc: func() (string, error) {
			privateKey, err := jwt.ParseRSAPrivateKeyFromPEM([]byte(cfg.GitHubAppPrivateKey))
			if err != nil {
				return "", errors.Wrap(err, "failed to parse GitHub app private key")
			}

			jwt, err := createAuthJWT(privateKey)
			if err != nil {
				return "", errors.Wrap(err, "error creating auth jwt")
			}

			token, err := getServerToServerToken(jwt)
			if err != nil {
				return "", errors.Wrap(err, "error getting server to server token")
			}
			return token, nil
		},
		authenticatorFunc: func(statter stats.Client) (client.Authenticator, error) {
			return client.NewAuthenticator(
				cfg.AuthndTwirpURL,
				cfg.ServiceName,
				client.WithHMACKey(cfg.GetHMACKey()),
				client.WithStatter(statter),
			)
		},
		exchangeTokenFunc: func(statter stats.Client) (client.TokenExchanger, error) {
			return client.NewTokenExchanger(
				cfg.AuthndTwirpURL,
				cfg.ServiceName,
				client.WithHMACKey(cfg.GetHMACKey()),
				client.WithStatter(statter),
			)
		},
		exchangeTokenVerifierFunc: func(statter stats.Client) (tokenVerifier, error) {
			return client.NewExchangeTokenVerifier(
				client.WithStatter(statter),
			)
		},
	}
}

func (t *tokenExchangeTest) Name() string {
	return "server_to_server_token"
}

func (t *tokenExchangeTest) Frequency() time.Duration {
	return 1 * time.Minute
}

func (t *tokenExchangeTest) Timeout() time.Duration {
	return 1 * time.Minute
}

// 1. Initialize authnd clients
// 2. Create new server to server token
// 3. Authenticate token
// 4. Verify authentication attributes
// 5. Exchange token for a stateless token (JWT)
// 6. Verify token
// 7. Compare JWT claims and attributes
func (t *tokenExchangeTest) Run(ctx context.Context) (testErr error) {
	t.runTracker.Start()
	defer t.runTracker.Stop()

	logger := diagnostics.Logger(ctx)
	statter := diagnostics.Statter(ctx)

	// 1. Initialize authnd clients
	logger.Info("initializing clients")
	authenticator, err := t.authenticatorFunc(statter)
	if err != nil {
		return errors.Wrap(err, "failed to create authenticator client")
	}

	tokenExchanger, err := t.exchangeTokenFunc(statter)
	if err != nil {
		return errors.Wrap(err, "failed to create token exchanger client")
	}

	tokenExchangeVerifier, err := t.exchangeTokenVerifierFunc(statter)
	if err != nil {
		return errors.Wrap(err, "failed to create token exchange verifier client")
	}

	currentOperation := "issue_token"
	defer func() {
		if testErr != nil {
			statter.Counter("e2e.token_exchange_failure", stats.Tags{"operation": currentOperation}, 1)
		}
	}()

	// 2. Create new server to server token
	logger.Info("issuing server-to-server token")
	s2sToken, err := t.createTokenFunc()
	if err != nil {
		return errors.Wrap(err, "error getting server to server token")
	}

	// 3. Authenticate token
	currentOperation = "authenticate"
	logger.Info("authenticating server-to-server token")
	var authReq *client.AuthenticateRequest
	var authenticateResp *client.AuthenticateResponse
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

		authReq = client.NewAuthenticateRequest(client.NewAccessTokenCredentials(s2sToken))
		authenticateResp, err = authenticator.Authenticate(aCtx, authReq)
		if err != nil {
			logger.WithError(err).Info("error authenticating s2s token with authnd")
			time.Sleep(requestRetryTime)
			continue
		}
		if authenticateResp.Result == pb.AuthenticateResponse_RESULT_SUCCESS {
			// success
			break
		}
		logger.Info("authenticate request was unsuccessful",
			kvp.Stringer("result", authenticateResp.Result),
			kvp.String("gh.authnd.tester.request.result", authenticateResp.Result.String()),
		)
		time.Sleep(requestRetryTime)
	}

	// 4. Verify authentication attributes
	logger.Info("verifying authenticate attributes")
	actorID, err := authenticateResp.GetIntAttribute(client.ActorIDAttribute)
	if err != nil {
		return errors.Wrapf(err, "error getting '%s' attribute in authenticate response", client.ActorIDAttribute)
	}

	actorType, err := authenticateResp.GetStringAttribute(client.ActorTypeAttribute)
	if err != nil {
		return errors.Wrapf(err, "error getting '%s' attribute in authenticate response", client.ActorTypeAttribute)
	}

	clientID, err := authenticateResp.GetStringAttribute(client.ApplicationClientIDAttribute)
	if err != nil {
		return errors.Wrapf(err, "error getting '%s' attribute in authenticate response", client.ApplicationClientIDAttribute)
	}
	if clientID != ClientID {
		return errors.Errorf("mismatch in '%s' attribute. got %s but expected %s.", client.ApplicationClientIDAttribute, clientID, ClientID)
	}

	applicationID, err := authenticateResp.GetIntAttribute(client.ApplicationIDAttribute)
	if err != nil {
		return errors.Wrapf(err, "error getting '%s' attribute in authenticate response", client.ApplicationIDAttribute)
	}
	if applicationID != AppID {
		return errors.Errorf("mismatch in '%s' attribute. got %d but expected %d.", client.ApplicationIDAttribute, applicationID, AppID)
	}

	applicationType, err := authenticateResp.GetStringAttribute(client.ApplicationTypeAttribute)
	if err != nil {
		return errors.Wrapf(err, "error getting '%s' attribute in authenticate response", client.ApplicationTypeAttribute)
	}
	if applicationType != "Integration" {
		return errors.Errorf("mismatch in '%s' attribute. got %s but expected Integration.", client.ApplicationTypeAttribute, applicationType)
	}

	applicationOwnerID, err := authenticateResp.GetIntAttribute(client.ApplicationOwnerIDAttribute)
	if err != nil {
		return errors.Wrapf(err, "error getting '%s' attribute in authenticate response", client.ApplicationOwnerIDAttribute)
	}
	if applicationOwnerID != AppOwnerID {
		return errors.Errorf("mismatch in '%s' attribute. got %d but expected %d.", client.ApplicationOwnerIDAttribute, applicationOwnerID, AppOwnerID)
	}

	applicationOwnerType, err := authenticateResp.GetStringAttribute(client.ApplicationOwnerTypeAttribute)
	if err != nil {
		return errors.Wrapf(err, "error getting '%s' attribute in authenticate response", client.ApplicationOwnerTypeAttribute)
	}
	if applicationOwnerType != AppOwnerType {
		return errors.Errorf("mismatch in '%s' attribute. got %s but expected User.", client.ApplicationOwnerTypeAttribute, applicationOwnerType)
	}

	installationID, err := authenticateResp.GetIntAttribute(client.InstallationIDAttribute)
	if err != nil {
		return errors.Wrapf(err, "error getting '%s' attribute in authenticate response", client.InstallationIDAttribute)
	}
	if installationID != InstallationID {
		return errors.Errorf("mismatch in '%s' attribute. got %d but expected %d.", client.InstallationIDAttribute, installationID, InstallationID)
	}

	installationTargetID, err := authenticateResp.GetIntAttribute(client.InstallationTargetIDAttribute)
	if err != nil {
		return errors.Wrapf(err, "error getting '%s' attribute in authenticate response", client.InstallationTargetIDAttribute)
	}
	if installationTargetID != InstallationTargetID {
		return errors.Errorf("mismatch in '%s' attribute. got %d but expected %d.", client.InstallationTargetIDAttribute, installationTargetID, InstallationTargetID)
	}

	installationTargetType, err := authenticateResp.GetStringAttribute(client.InstallationTargetTypeAttribute)
	if err != nil {
		return errors.Wrapf(err, "error getting '%s' attribute in authenticate response", client.InstallationTargetTypeAttribute)
	}
	if installationTargetType != InstallationTargetType {
		return errors.Errorf("mismatch in '%s' attribute. got %s but expected User.", client.InstallationTargetTypeAttribute, installationTargetType)
	}

	credentialType, err := authenticateResp.GetStringAttribute(client.CredentialTypeAttribute)
	if err != nil {
		return errors.Wrapf(err, "error getting '%s' attribute in authenticate response", client.CredentialTypeAttribute)
	}
	if credentialType != string(client.CredentialTypeServerToServerToken) {
		return errors.Errorf("mismatch in '%s' attribute. got %s but expected %s.", client.CredentialTypeAttribute, credentialType, client.CredentialTypeServerToServerToken)
	}

	credentialID, err := authenticateResp.GetIntAttribute(client.CredentialIDAttribute)
	if err != nil {
		return errors.Wrapf(err, "error getting '%s' attribute in authenticate response", client.CredentialIDAttribute)
	}

	// 5. Exchange token for a stateless token (JWT)
	currentOperation = "exchange_token"
	logger.Info("exchanging server-to-server token")
	exchangeRes, err := tokenExchanger.ExchangeToken(ctx, client.NewExchangeTokenRequest(client.NewAccessTokenCredentials(s2sToken)))
	if err != nil {
		return errors.Wrap(err, "failed to exchange token")
	}
	if exchangeRes.Result != pb.AuthenticateResponse_RESULT_SUCCESS {
		return fmt.Errorf("exchange token request failed with result %s", exchangeRes.Result.String())
	}

	// 6. Verify token
	currentOperation = "verify_exchange_token"
	logger.Info("verifying exchange token")
	verifyRes, err := tokenExchangeVerifier.VerifyToken(exchangeRes.Token)
	if err != nil {
		return errors.Wrap(err, "failed to verify token")
	}

	// 7. Compare JWT claims and attributes
	currentOperation = "compare_exchange_token"
	logger.Info("comparing exchange token attributes")
	//TODO(chriskirkland): migrate this to using the new Actor model from client/exp/
	attrs := make(map[string]*pb.Value)
	fields := []kvp.Field{}
	for _, a := range verifyRes {
		attrs[a.GetId()] = a.GetValue()
		fields = append(fields, kvp.Any(a.GetId(), a.GetValue()))
	}

	logger.Info("extracted attributes", fields...)
	if actorID != attrs["actor.id"].GetIntegerValue() {
		return fmt.Errorf("actor.id attribute mismatch, got %d but expected %d", actorID, attrs["actor.id"].GetIntegerValue())
	}

	if actorType != attrs["actor.type"].GetStringValue() {
		return fmt.Errorf("actor.type attribute mismatch, got %s but expected %s", actorType, attrs["actor.type"].GetStringValue())
	}

	if clientID != attrs["application.client_id"].GetStringValue() {
		return fmt.Errorf("application.client_id attribute mismatch, got %s but expected %s", clientID, attrs["application.client_id"].GetStringValue())
	}

	if applicationID != attrs["application.id"].GetIntegerValue() {
		return fmt.Errorf("application.id attribute mismatch, got %d but expected %d", applicationID, attrs["application.id"].GetIntegerValue())
	}

	if applicationType != attrs["application.type"].GetStringValue() {
		return fmt.Errorf("application.type attribute mismatch, got %s but expected %s", applicationType, attrs["application.type"].GetStringValue())
	}

	if applicationOwnerID != attrs["application.owner.id"].GetIntegerValue() {
		return fmt.Errorf("application.owner.id attribute mismatch, got %d but expected %d", applicationOwnerID, attrs["application.owner.id"].GetIntegerValue())
	}

	if applicationOwnerType != attrs["application.owner.type"].GetStringValue() {
		return fmt.Errorf("application.owner.type attribute mismatch, got %s but expected %s", applicationOwnerType, attrs["application.owner.type"].GetStringValue())
	}

	if credentialID != attrs["credential.id"].GetIntegerValue() {
		return fmt.Errorf("credential.id attribute mismatch, got %d but expected %d", credentialID, attrs["credential.id"].GetIntegerValue())
	}

	if credentialType != attrs["credential.type"].GetStringValue() {
		return fmt.Errorf("credential.type attribute mismatch, got %s but expected %s", credentialType, attrs["credential.type"].GetStringValue())
	}

	if installationID != attrs["installation.id"].GetIntegerValue() {
		return fmt.Errorf("installation.id attribute mismatch, got %d but expected %d", installationID, attrs["installation.id"].GetIntegerValue())
	}

	if installationTargetID != attrs["installation.target.id"].GetIntegerValue() {
		return fmt.Errorf("installation.target.id attribute mismatch, got %d but expected %d", installationTargetID, attrs["installation.target.id"].GetIntegerValue())
	}

	if installationTargetType != attrs["installation.target.type"].GetStringValue() {
		return fmt.Errorf("installation.target.type attribute mismatch, got %s but expected %s", installationTargetType, attrs["installation.target.type"].GetStringValue())
	}

	logger.Info("test completed successfully")
	return nil
}
