package mobileauthcli

import (
	"context"
	"fmt"
	"os"

	"github.com/pkg/errors"

	"crypto/ecdsa"
	"crypto/x509"
	"encoding/base64"
	"encoding/pem"
	"strconv"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/cmd/authnd-client/shared"
	"github.com/spf13/cobra"

	"github.com/github/authnd/internal/common/crypto"
	"github.com/github/authnd/internal/common/mobiledeviceauth"
)

const signatureVersion = 1

type completeDeviceAuthCommand struct {
	shared.ConnectionInfo
	authRequestID int64
	userID        int64
	oauthAccessId int64
	approve       bool
	reject        bool
	privateKey    string
	payload       string
	challenge     string
}

func NewCompleteDeviceAuthCommand() *cobra.Command {
	var (
		c   completeDeviceAuthCommand
		cmd = &cobra.Command{
			Use:   "complete",
			Short: "Approves or rejects an active device auth request",
			Long: `Submit a request to authnd to approve or reject an active device auth request for a user.

	To submit the request, run 'authnd-client mobile-auth complete --approve --request-id <request_id> --user-id <user_id> --oauth-access-id <oauth_access_id> --private-key <path_to_key> --payload <payload> --challenge <challenge>'
			`,
			RunE: c.Run,
		}
	)

	c.registerFlags(cmd)
	return cmd
}

func (c *completeDeviceAuthCommand) Run(cmd *cobra.Command, args []string) error {
	if !c.approve && !c.reject {
		return errors.New("must specify --approve or --reject")
	}
	if c.approve && c.reject {
		return errors.New("must specify only one of --approve or --reject")
	}

	mdm, err := c.ConnectionInfo.NewMobileDeviceManager()
	if err != nil {
		return err
	}

	var req *pb.CompleteDeviceAuthRequest
	completeDeviceAuthMessage := &pb.CompleteDeviceAuthMessage{
		AuthRequestId: c.authRequestID,
		UserId:        c.userID,
		OauthAccessId: c.oauthAccessId,
	}

	if c.approve {
		ecdsaPrivateKey, err := parsePrivateKey(c.privateKey)
		if err != nil {
			return err
		}
		base64EncodedSignature, err := createApproveSignature(ecdsaPrivateKey, signatureVersion, c.payload, c.challenge)
		if err != nil {
			return err
		}
		completeDeviceAuthMessage.Signature = base64EncodedSignature
		completeDeviceAuthMessage.SignatureVersion = signatureVersion

		req = &pb.CompleteDeviceAuthRequest{
			Kind: &pb.CompleteDeviceAuthRequest_Approve{
				Approve: completeDeviceAuthMessage,
			},
		}
	} else {
		req = &pb.CompleteDeviceAuthRequest{
			Kind: &pb.CompleteDeviceAuthRequest_Reject{
				Reject: completeDeviceAuthMessage,
			},
		}
	}

	resp, err := mdm.CompleteDeviceAuth(context.Background(), req)
	if err != nil {
		return err
	}

	if resp.Result != pb.CompleteDeviceAuthResponse_RESULT_SUCCESS {
		fmt.Printf("failed to complete device auth request: %s\n", resp.Result)
	} else {
		fmt.Printf("Result: %s\n", resp.Result)
	}

	return nil
}

func (c *completeDeviceAuthCommand) registerFlags(cmd *cobra.Command) {
	shared.RegisterConnectionFlags(&c.ConnectionInfo, cmd)

	// auth-request-id
	cmd.Flags().Int64Var(&c.authRequestID, "auth-request-id", 0, "The device auth request ID that is awaiting approval or rejection.")
	err := cmd.MarkFlagRequired("auth-request-id")
	if err != nil {
		panic(err)
	}

	// user-id
	cmd.Flags().Int64Var(&c.userID, "user-id", 0, "The user ID of the github user approving or rejecting the request.")
	err = cmd.MarkFlagRequired("user-id")
	if err != nil {
		panic(err)
	}

	// oauth-access-id
	cmd.Flags().Int64Var(&c.oauthAccessId, "oauth-access-id", 0, "The oauth access ID for the device performing the action.")
	err = cmd.MarkFlagRequired("oauth-access-id")
	if err != nil {
		panic(err)
	}

	// private-key
	cmd.Flags().StringVar(&c.privateKey, "private-key", "", "Path to a private key PEM file. Used to create the signature for the approve/reject request.")
	err = cmd.MarkFlagRequired("private-key")
	if err != nil {
		panic(err)
	}

	// payload
	cmd.Flags().StringVar(&c.payload, "payload", "", "The base64 encoded payload. Used to create the signature for the approve/reject request.")
	err = cmd.MarkFlagRequired("payload")
	if err != nil {
		panic(err)
	}

	// challenge
	cmd.Flags().StringVar(&c.challenge, "challenge", "", "Challenge number. Used to create the signature for the approve request.")

	// approve / reject
	cmd.Flags().BoolVar(&c.approve, "approve", false, "Approve the device auth request.")
	cmd.Flags().BoolVar(&c.reject, "reject", false, "Reject the device auth request.")
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
