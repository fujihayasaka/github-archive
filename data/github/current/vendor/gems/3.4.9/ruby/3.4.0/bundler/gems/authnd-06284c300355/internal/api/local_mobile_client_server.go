package api

import (
	"context"
	"crypto/ecdsa"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"net"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	apiConfig "github.com/github/authnd/internal/api/config"
	"github.com/github/authnd/internal/api/mux"
	"github.com/github/authnd/internal/common/crypto"
	"github.com/github/authnd/internal/common/mobiledeviceauth"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-ctxutil"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
)

const (
	SIGNATURE_VERSION = 1
	USER_ID           = 2
	USER_EMAIL        = "octocat@github.com"
	OAUTH_ACCESS_ID   = 3
	// private-key (defaults to the default private key path created by script/gen-ecdsa-p256-keypair)
	DEFAULT_PRIVATE_KEY_PATH = "dev/gh-mobile-dev.pem"
)

type promptInfo struct {
	RequestID         int64  `json:"requestId"`
	ChallengeRequired bool   `json:"challengeRequired"`
	Payload           string `json:"payload"`
	Email             string `json:"email"`
	DeviceDisplayName string `json:"deviceDisplayName"`
	DeviceIP          string `json:"deviceIp"`
	CreatedAt         string `json:"createdAt"`
}

type completeRequestBody struct {
	promptInfo
	Approval  bool   `json:"approval"`
	Challenge string `json:"challenge"`
}

type completeResponse struct {
	Success bool `json:"success"`
}

type pollRespObj struct {
	ShowPrompt bool       `json:"showPrompt"`
	PromptInfo promptInfo `json:"promptInfo"`
}

// Creates an http server that _only_ runs in development
// which serves up a set of APIs specifically to run the local "mobile client" in the browser
// to simulate the GH mobile app authenticating with the authnd service using github mobile auth
func NewLocalMobileClientServer(ctx context.Context, cfg *apiConfig.Config, logger log.Logger, statter stats.Client) *http.Server {
	if !cfg.IsDevelopment() || cfg.DisableLocalMobileClient {
		return nil
	}

	ecdsaPrivateKey, err := parsePrivateKey(DEFAULT_PRIVATE_KEY_PATH)
	if err != nil {
		panic(err)
	}

	mdm, err := client.NewMobileDeviceManager(fmt.Sprintf("http://%s:%d", "0.0.0.0", cfg.Port), "mock-client", client.WithHMACKey(cfg.GetHMACKeys()[0]))
	if err != nil {
		return nil
	}

	localMobileClientServerPrefixHandlers := []mux.PrefixHandler{
		mux.HandlePrefix("/", http.FileServer(http.Dir("./static"))),
		mux.HandlePrefix("/find_active_device_auth", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			resp, err := mdm.FindActiveDeviceAuth(context.Background(), &pb.FindActiveDeviceAuthRequest{
				UserId:        USER_ID,
				OauthAccessId: OAUTH_ACCESS_ID,
			})
			if err != nil {
				logger.WithError(err).Error("failed to get device auth status")
				return
			}
			if resp.Result != pb.FindActiveDeviceAuthResponse_RESULT_SUCCESS && resp.Result != pb.FindActiveDeviceAuthResponse_RESULT_NOT_FOUND {
				logger.Error("failed to get device auth status", kvp.String("result", resp.Result.String()))
				return
			}

			showPrompt := false
			promptInfo := promptInfo{}
			if err != nil {
				fmt.Printf("Error getting request: %v\n\n", err)
			} else if resp != nil && resp.Result == pb.FindActiveDeviceAuthResponse_RESULT_SUCCESS {
				showPrompt = true
				promptInfo.RequestID = resp.Id
				promptInfo.ChallengeRequired = resp.ChallengeRequired
				promptInfo.Payload = resp.Payload
				promptInfo.Email = USER_EMAIL
				promptInfo.DeviceDisplayName = resp.DeviceDisplayName
				promptInfo.DeviceIP = resp.IpAddress
				promptInfo.CreatedAt = resp.CreatedAtUtc.AsTime().Format(time.RFC3339)
			}

			w.Header().Set("Content-Type", "application/json")
			bytes, err := json.Marshal(pollRespObj{
				ShowPrompt: showPrompt,
				PromptInfo: promptInfo,
			})
			if err != nil {
				panic(err)
			}
			_, err = w.Write(bytes)
			if err != nil {
				logger.WithError(err).Error("error writing response")
			}
		})),
		mux.HandlePrefix("/complete_device_auth", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			var completeRequestBody *completeRequestBody
			err := json.NewDecoder(r.Body).Decode(&completeRequestBody)
			if err != nil {
				logger.WithError(err).Error("error decoding request body")
				writeFailureResponse(w, logger)
				return
			}

			var completeReq *pb.CompleteDeviceAuthRequest
			completeDeviceAuthMessage := &pb.CompleteDeviceAuthMessage{
				AuthRequestId: completeRequestBody.RequestID,
				UserId:        USER_ID,
				OauthAccessId: OAUTH_ACCESS_ID,
			}

			if completeRequestBody.Approval {
				challenge := ""
				if completeRequestBody.ChallengeRequired {
					challenge = completeRequestBody.Challenge
				}
				base64EncodedSignature, err := createApproveSignature(ecdsaPrivateKey, SIGNATURE_VERSION, completeRequestBody.Payload, challenge)
				if err != nil {
					logger.WithError(err).Error("error creating approve signature")
					writeFailureResponse(w, logger)
					return
				}
				completeDeviceAuthMessage.Signature = base64EncodedSignature
				completeDeviceAuthMessage.SignatureVersion = SIGNATURE_VERSION

				completeReq = &pb.CompleteDeviceAuthRequest{
					Kind: &pb.CompleteDeviceAuthRequest_Approve{
						Approve: completeDeviceAuthMessage,
					},
				}
			} else {
				completeReq = &pb.CompleteDeviceAuthRequest{
					Kind: &pb.CompleteDeviceAuthRequest_Reject{
						Reject: completeDeviceAuthMessage,
					},
				}
			}

			completeResp, err := mdm.CompleteDeviceAuth(context.Background(), completeReq)
			if err != nil || completeResp.Result != pb.CompleteDeviceAuthResponse_RESULT_SUCCESS {
				logger.WithError(err).Error("error completing device auth", kvp.String("result", completeResp.Result.String()))
				writeFailureResponse(w, logger)
				return
			}

			w.Header().Set("Content-Type", "application/json")
			bytes, err := json.Marshal(completeResponse{
				Success: true,
			})
			if err != nil {
				logger.WithError(err).Error("error marshalling response")
				return
			}
			_, err = w.Write(bytes)
			if err != nil {
				logger.WithError(err).Error("error writing response")
			}
		})),
	}
	localMobileClientServerHandler := mux.NewMux(logger, statter, false, nil, localMobileClientServerPrefixHandlers...)
	return &http.Server{
		Addr:         cfg.LocalMobileServerClientBindAddress(),
		Handler:      localMobileClientServerHandler,
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  120 * time.Second,
		BaseContext: func(l net.Listener) context.Context {
			// We _don't_ want cancellation of the parent context to cause cancellation of a request.
			// Requests need to complete even when the parent context is cancelled.
			// ctxutil.DetatchedCancel returns a new context that carries Values (like loggers/statters) through, but does not carry cancellation signals from the parent.
			return ctxutil.DetachedCancel(ctx)
		},
	}
}

func writeFailureResponse(w http.ResponseWriter, logger log.Logger) {
	w.Header().Set("Content-Type", "application/json")
	bytes, err := json.Marshal(completeResponse{
		Success: false,
	})
	if err != nil {
		logger.WithError(err).Error("error marshalling response")
	}
	_, err = w.Write(bytes)
	if err != nil {
		logger.WithError(err).Error("error writing response")
	}
}

func createApproveSignature(ecdsaPrivateKey *ecdsa.PrivateKey, version int, base64EncodedPayload string, challenge string) (string, error) {
	payload, err := base64.StdEncoding.DecodeString(base64EncodedPayload)
	if err != nil {
		return "", errors.WithStack(err)
	}

	var messageHash []byte
	if challenge != "" {
		challengeNum, err := strconv.Atoi(challenge)
		if err != nil {
			return "", errors.New("challenge must be a number")
		}
		messageHash = mobiledeviceauth.CreateExpectedApproveMessageHash(uint64(version), payload, int64(challengeNum))
	} else {
		messageHash = mobiledeviceauth.CreateExpectedApproveMessageWithoutChallengeHash(uint64(version), payload)
	}
	base64EncodedSignature, err := crypto.SignMessageHash(ecdsaPrivateKey, messageHash)
	if err != nil {
		return "", err
	}

	return base64EncodedSignature, nil
}

func parsePrivateKey(privateKeyPath string) (*ecdsa.PrivateKey, error) {
	privKey, err := os.ReadFile(privateKeyPath)
	if err != nil {
		return nil, errors.WithStack(err)
	}
	block, _ := pem.Decode(privKey)
	if block == nil {
		return nil, errors.New("failed to parse PEM block containing the private key")
	}
	ecdsaPrivateKey, err := x509.ParseECPrivateKey(block.Bytes)
	if err != nil {
		return nil, errors.WithStack(err)
	}
	return ecdsaPrivateKey, nil
}
