package mobileauthcli

import (
	"context"
	"fmt"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/cmd/authnd-client/shared"
	"github.com/spf13/cobra"
)

type requestMobileDeviceAuthCommand struct {
	shared.ConnectionInfo
	userID        int64
	skipChallenge bool
	requestType   string
}

func NewRequestMobileDeviceAuthCommand() *cobra.Command {
	var (
		r   requestMobileDeviceAuthCommand
		cmd = &cobra.Command{
			Use:   "request",
			Short: "Request device auth for a user",
			Long: `Submit a request to authnd to request device auth for a user

	To submit the request, run 'authnd-client mobile-auth request --user-id <user_id>'
			`,
			RunE: r.Run,
		}
	)

	r.registerFlags(cmd)
	return cmd
}

func (r *requestMobileDeviceAuthCommand) Run(cmd *cobra.Command, args []string) error {
	mdm, err := r.ConnectionInfo.NewMobileDeviceManager()
	if err != nil {
		return err
	}

	req := &pb.RequestDeviceAuthRequest{
		UserId:        r.userID,
		SkipChallenge: r.skipChallenge,
		Type:          r.requestType,
	}

	resp, err := mdm.RequestDeviceAuth(context.Background(), req)
	if err != nil {
		return err
	}

	if resp.Result != pb.RequestDeviceAuthResponse_RESULT_SUCCESS {
		fmt.Printf("request device auth failed: %s\n", resp.Result)
	} else {
		fmt.Printf("Result: %s\n", resp.Result)
		fmt.Printf("Id: %d\n", resp.Id)
		fmt.Printf("Challenge: %s\n", resp.Challenge)
		fmt.Printf("Expires at: %s\n", resp.ExpiresAtTime.AsTime())
	}

	return nil
}

func (r *requestMobileDeviceAuthCommand) registerFlags(cmd *cobra.Command) {
	shared.RegisterConnectionFlags(&r.ConnectionInfo, cmd)

	// user-id
	cmd.Flags().Int64Var(&r.userID, "user-id", 0, "The ID of the user making the request.")
	err := cmd.MarkFlagRequired("user-id")
	if err != nil {
		panic(err)
	}

	// skip-challenge
	cmd.Flags().BoolVar(&r.skipChallenge, "skip-challenge", false, "If set to true, the device auth request will not require (or expect) a challenge to be completed for approval.")

	cmd.Flags().StringVar(&r.requestType, "type", "", "Type of request ('2fa_login', 'device_verification', '2fa_password_reset', '2fa_sudo_challenge'). Defaults to '2fa_login'.")
}
