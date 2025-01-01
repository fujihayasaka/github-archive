package mobiledevicecli

import (
	"context"
	"crypto/sha256"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"math/rand" //nolint:depguard
	"os"
	"time"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/common/crypto"
	"github.com/pkg/errors"

	"github.com/github/authnd/cmd/authnd-client/shared"
	"github.com/spf13/cobra"
)

type keyRegistration struct {
	PublicKey             string
	VerificationMessage   string
	VerificationSignature string
}

type registerKeyCommand struct {
	shared.ConnectionInfo
	userId              int64
	oauthAccessId       int64
	deviceName          string
	deviceModel         string
	deviceOs            string
	isHardwareBacked    bool
	privateKey          string
	registerRecoveryKey bool
}

func NewRegisterKeyCommand() *cobra.Command {
	var (
		r   registerKeyCommand
		cmd = &cobra.Command{
			Use:   "register-key",
			Short: "Register a mobile device key",
			Long: `Submit a request to register a mobile device key to the service

	To register a mobile device key, run 'authnd-client mobile-device register-key <flags>'
			`,
			RunE: r.Run,
		}
	)

	r.registerFlags(cmd)
	return cmd
}

func (r *registerKeyCommand) Run(cmd *cobra.Command, args []string) error {
	publicKeyRegistration, err := createPublicKeyRegistrationForPrivateKey(r.privateKey)
	if err != nil {
		return err
	}

	mdm, err := r.ConnectionInfo.NewMobileDeviceManager()
	if err != nil {
		return err
	}

	deviceKeyRequest := &pb.DeviceKeyRequest{
		UserId:                         r.userId,
		OauthAccessId:                  r.oauthAccessId,
		DeviceName:                     r.deviceName,
		DeviceModel:                    r.deviceModel,
		DeviceOs:                       r.deviceOs,
		IsHardwareBacked:               r.isHardwareBacked,
		PublicKey:                      publicKeyRegistration.PublicKey,
		PublicKeyVerificationSignature: publicKeyRegistration.VerificationSignature,
		PublicKeyVerificationMessage:   publicKeyRegistration.VerificationMessage,
	}
	var req *pb.RegisterDeviceKeyRequest
	if r.registerRecoveryKey {
		req = &pb.RegisterDeviceKeyRequest{
			Kind: &pb.RegisterDeviceKeyRequest_RecoveryKeyRequest{
				RecoveryKeyRequest: deviceKeyRequest,
			},
		}
	} else {
		req = &pb.RegisterDeviceKeyRequest{
			Kind: &pb.RegisterDeviceKeyRequest_AuthKeyRequest{
				AuthKeyRequest: deviceKeyRequest,
			},
		}
	}

	resp, err := mdm.RegisterDeviceKey(context.Background(), req)
	if err != nil {
		return err
	}

	if resp.Result != pb.RegisterDeviceKeyResponse_RESULT_SUCCESS {
		fmt.Printf("failed to register device key: %s\n", resp.Result)
	} else {
		fmt.Printf("Result: %s\n", resp.Result)
		fmt.Printf("ID: %d\n", resp.Id)
		fmt.Printf("ExpiresAt: %s\n", resp.ExpiresAtTime.AsTime())
	}

	return nil
}

func (r *registerKeyCommand) registerFlags(cmd *cobra.Command) {
	shared.RegisterConnectionFlags(&r.ConnectionInfo, cmd)

	// user-id
	cmd.Flags().Int64Var(&r.userId, "user-id", 0, "The user ID of the user that the mobile device key belongs to.")
	err := cmd.MarkFlagRequired("user-id")
	if err != nil {
		panic(err)
	}

	// oauth-access-id
	cmd.Flags().Int64Var(&r.oauthAccessId, "oauth-access-id", 0, "The oauth access ID the mobile device key will belong to.")
	err = cmd.MarkFlagRequired("oauth-access-id")
	if err != nil {
		panic(err)
	}

	// device-name
	cmd.Flags().StringVar(&r.deviceName, "device-name", "", "The name of the device.")
	err = cmd.MarkFlagRequired("device-name")
	if err != nil {
		panic(err)
	}

	// device-model
	cmd.Flags().StringVar(&r.deviceModel, "device-model", "", "The device model information.")
	err = cmd.MarkFlagRequired("device-model")
	if err != nil {
		panic(err)
	}

	// device-os
	cmd.Flags().StringVar(&r.deviceOs, "device-os", "", "The device operating system (e.g. iOS/Android).")
	err = cmd.MarkFlagRequired("device-os")
	if err != nil {
		panic(err)
	}

	// private-key (defaults to the default private key path created by script/gen-ecdsa-p256-keypair)
	cmd.Flags().StringVar(&r.privateKey, "private-key", "dev/gh-mobile-dev.pem", "Path to a private key PEM file. The public key is extracted and sent to the server.")

	// recovery-key
	cmd.Flags().BoolVar(&r.registerRecoveryKey, "recovery-key", false, "Whether the key will be registered to be used for account recovery. Default to auth key.")

	// is-hardware-backed
	cmd.Flags().BoolVar(&r.isHardwareBacked, "is-hardware-backed", false, "Whether the device is hardware backed.")
}

func createPublicKeyRegistrationForPrivateKey(privateKeyPath string) (*keyRegistration, error) {
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
	base64EncodedPublicKeyPem, err := crypto.GetBase64EncodedPublicKey(ecdsaPrivateKey)
	if err != nil {
		return nil, err
	}

	rand.New(rand.NewSource(time.Now().UTC().UnixNano()))
	message := randomString(12)
	messageHash := sha256.Sum256([]byte(message))
	base64EncodedSignature, err := crypto.SignMessageHash(ecdsaPrivateKey, messageHash[:])
	if err != nil {
		return nil, err
	}

	return &keyRegistration{
		PublicKey:             base64EncodedPublicKeyPem,
		VerificationMessage:   message,
		VerificationSignature: base64EncodedSignature,
	}, nil
}

func randomString(len int) string {
	bytes := make([]byte, len)
	for i := 0; i < len; i++ {
		bytes[i] = byte(randInt(97, 122))
	}
	return string(bytes)
}

func randInt(min int, max int) int {
	return min + rand.Intn(max-min)
}
