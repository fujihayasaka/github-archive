package mobileauthcli

import (
	"context"
	"crypto/ecdsa"
	"fmt"
	"strings"
	"time"

	"github.com/IBM/sarama"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/cmd/authnd-client/shared"
	notifydProto "github.com/github/authnd/internal/common/publisher/hydro/schemas/notifyd/v0"
	pbhydro "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/golang/protobuf/proto" //nolint: staticcheck
	"github.com/google/uuid"
	"github.com/pkg/errors"
	"github.com/spf13/cobra"
)

const (
	kafkaBroker        = "127.0.0.1:9092"
	notificationsTopic = "notifyd.v1.Notify"
)

type devListenerCommand struct {
	shared.ConnectionInfo
	userID         int64
	oauthAccessId  int64
	privateKeyPath string
	privateKey     *ecdsa.PrivateKey
}

func NewDevListenerCommand() *cobra.Command {
	var (
		d   devListenerCommand
		cmd = &cobra.Command{
			Use:   "dev-listener",
			Short: "Start up a listener of GitHub Mobile auth requests for dotcom local testing.",
			Long: `Helper for approving and rejecting device auth requests. Uses default params, but can be overridden.

	To use, run 'authnd-client mobile-auth dev-listener --user-id <user_id> --oauth-access-id <oauth_access_id> --private-key <private_key_path>'
			`,
			RunE: d.Run,
		}
	)

	d.registerFlags(cmd)
	return cmd
}

func (d *devListenerCommand) Run(cmd *cobra.Command, args []string) error {
	ecdsaPrivateKey, err := parsePrivateKey(d.privateKeyPath)
	if err != nil {
		panic(err)
	}
	d.privateKey = ecdsaPrivateKey

	fmt.Println("Listening for requests...")
	// check for an existing request when the command starts up (similar to when the app is brought to foreground on a real device)
	resp, err := d.findRequest()
	if err != nil {
		return err
	}
	if resp != nil && resp.Result == pb.FindActiveDeviceAuthResponse_RESULT_SUCCESS {
		go d.authRequestPrompt()
	}

	groupID := fmt.Sprintf("authnd-client-consume-%s", uuid.New().String())
	options := []hydro.KafkaConfigOption{
		hydro.WithSaramaConfig(func(c *sarama.Config) {
			c.Consumer.Offsets.Initial = sarama.OffsetNewest
		}),
		hydro.WithKafkaVersion("1.1.1"),
	}
	kafka, err := hydro.NewKafkaConfig([]string{kafkaBroker}, options...)
	if err != nil {
		return errors.WithStack(err)
	}

	source, err := hydro.NewKafkaSource(*kafka, groupID, []string{notificationsTopic})
	if err != nil {
		return errors.WithStack(err)
	}

	return source.Consume(context.Background(), func(ctx context.Context, m hydro.Message) error {
		var envelope pbhydro.Envelope
		if err := proto.Unmarshal(m.Value, &envelope); err != nil {
			wrappedErr := errors.Wrapf(err, "error processing message in partition %d, offset %d", m.Partition, m.Offset)
			fmt.Println(wrappedErr)
			return wrappedErr
		}
		var message notifydProto.Notify
		if err := proto.Unmarshal(envelope.Message, &message); err != nil {
			wrappedErr := errors.Wrapf(err, "error processing message in partition %d, offset %d", m.Partition, m.Offset)
			fmt.Println(wrappedErr)
			return wrappedErr
		}

		if message.ExplicitRecipients != nil {
			for _, r := range message.ExplicitRecipients {
				if r.Reason == "mobile_auth_request" {
					for _, userID := range r.UserIds {
						if int64(userID) == d.userID {
							go d.authRequestPrompt()
						}
					}
				}
			}
		}

		return nil
	})
}

func (d *devListenerCommand) authRequestPrompt() {
	fmt.Println("New request: approve or reject? [a/r]")
	ch := make(chan int)
	var s string
	go func() {
		_, err := fmt.Scan(&s)
		if err != nil {
			panic("Failed to scan auth prompt")
		}
		ch <- 1
	}()
	select {
	case <-ch:
		s = strings.TrimSpace(s)
		s = strings.ToLower(s)
		if s == "a" || s == "approve" {
			err := d.findAndCompleteRequest(true)
			if err != nil {
				fmt.Printf("Error approving request: %v\n\n", err)
			} else {
				fmt.Print("Request approved.\n\n")
			}
		} else {
			err := d.findAndCompleteRequest(false)
			if err != nil {
				fmt.Printf("Error rejecting request: %v\n\n", err)
			} else {
				fmt.Print("Request rejected.\n\n")
			}
		}
	case <-time.After(60 * time.Second):
		fmt.Println("Request timed out.")
	}
}

func (d *devListenerCommand) challengeNumberPrompt() string {
	fmt.Println("Enter the challenge number seen on dotcom: ")
	ch := make(chan int)
	var s string
	go func() {
		_, err := fmt.Scan(&s)
		if err != nil {
			panic("Failed to scan challenge number")
		}
		ch <- 1
	}()
	select {
	case <-ch:
		s = strings.TrimSpace(s)
		s = strings.ToLower(s)
		return s
	case <-time.After(60 * time.Second):
		fmt.Println("Request timed out.")
		return ""
	}
}

func (d *devListenerCommand) findRequest() (*pb.FindActiveDeviceAuthResponse, error) {
	mdm, err := d.ConnectionInfo.NewMobileDeviceManager()
	if err != nil {
		return nil, err
	}

	findReq := &pb.FindActiveDeviceAuthRequest{
		UserId:        d.userID,
		OauthAccessId: d.oauthAccessId,
	}
	resp, err := mdm.FindActiveDeviceAuth(context.Background(), findReq)
	if err != nil {
		return nil, err
	}
	if resp.Result != pb.FindActiveDeviceAuthResponse_RESULT_SUCCESS && resp.Result != pb.FindActiveDeviceAuthResponse_RESULT_NOT_FOUND {
		return nil, errors.New(fmt.Sprintf("failed to get device auth status: %s\n", resp.Result))
	}

	return resp, nil
}

func (d *devListenerCommand) findAndCompleteRequest(approve bool) error {
	mdm, err := d.ConnectionInfo.NewMobileDeviceManager()
	if err != nil {
		return err
	}
	resp, err := d.findRequest()
	if err != nil {
		return err
	}

	var completeReq *pb.CompleteDeviceAuthRequest
	completeDeviceAuthMessage := &pb.CompleteDeviceAuthMessage{
		AuthRequestId: resp.Id,
		UserId:        d.userID,
		OauthAccessId: d.oauthAccessId,
	}

	if approve {
		challenge := ""
		if resp.ChallengeRequired {
			challenge = d.challengeNumberPrompt()
		}
		base64EncodedSignature, err := createApproveSignature(d.privateKey, signatureVersion, resp.Payload, challenge)
		if err != nil {
			return err
		}
		completeDeviceAuthMessage.Signature = base64EncodedSignature
		completeDeviceAuthMessage.SignatureVersion = signatureVersion

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
	if err != nil {
		return err
	}
	if completeResp.Result != pb.CompleteDeviceAuthResponse_RESULT_SUCCESS {
		return errors.New(fmt.Sprint(completeResp.Result))
	}

	return nil
}

func (d *devListenerCommand) registerFlags(cmd *cobra.Command) {
	shared.RegisterConnectionFlags(&d.ConnectionInfo, cmd)

	// user-id (default is for monalisa in development)
	cmd.Flags().Int64Var(&d.userID, "user-id", 2, "The ID of the user making the request.")
	// oauth-access-id (default is for monalisa in development)
	cmd.Flags().Int64Var(&d.oauthAccessId, "oauth-access-id", 2, "The ID of the oauth access id making the request.")
	// private-key (defaults to the default private key path created by script/gen-ecdsa-p256-keypair)
	cmd.Flags().StringVar(&d.privateKeyPath, "private-key", "dev/gh-mobile-dev.pem", "Path to a private key PEM file. Used to create the signature for the approve/reject request.")
}
