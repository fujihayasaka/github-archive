package mobileauthcli

import (
	"context"
	"fmt"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/cmd/authnd-client/shared"
	"github.com/spf13/cobra"
)

type findActiveDeviceAuthCommand struct {
	shared.ConnectionInfo
	userID        int64
	oauthAccessId int64
}

func NewFindActiveDeviceAuthCommand() *cobra.Command {
	var (
		f   findActiveDeviceAuthCommand
		cmd = &cobra.Command{
			Use:   "find",
			Short: "Finds an active device auth record for a user",
			Long: `Submit a request to authnd to retrieve an active device auth request for a user.

	To submit the request, run 'authnd-client mobile-auth find --user-id <user_id> --oauth-access-id <oauth_access_id>'
			`,
			RunE: f.Run,
		}
	)

	f.registerFlags(cmd)
	return cmd
}

func (d *findActiveDeviceAuthCommand) Run(cmd *cobra.Command, args []string) error {
	mdm, err := d.ConnectionInfo.NewMobileDeviceManager()
	if err != nil {
		return err
	}

	req := &pb.FindActiveDeviceAuthRequest{
		UserId:        d.userID,
		OauthAccessId: d.oauthAccessId,
	}

	resp, err := mdm.FindActiveDeviceAuth(context.Background(), req)
	if err != nil {
		return err
	}

	if resp.Result != pb.FindActiveDeviceAuthResponse_RESULT_SUCCESS {
		fmt.Printf("failed to get device auth status: %s\n", resp.Result)
	} else {
		fmt.Printf("Result: %s\n", resp.Result)
		fmt.Printf("Request ID: %d\n", resp.Id)
		fmt.Printf("Payload: %s\n", resp.Payload)
		fmt.Printf("ChallengeRequired: %v\n", resp.ChallengeRequired)
		fmt.Printf("HasValidDeviceKey: %v\n", resp.HasValidDeviceKey)
		fmt.Printf("RequestType: %s\n", resp.Type)
	}

	return nil
}

func (f *findActiveDeviceAuthCommand) registerFlags(cmd *cobra.Command) {
	shared.RegisterConnectionFlags(&f.ConnectionInfo, cmd)

	// user-id
	cmd.Flags().Int64Var(&f.userID, "user-id", 0, "The user ID used to look up the active device auth request.")
	err := cmd.MarkFlagRequired("user-id")
	if err != nil {
		panic(err)
	}

	// oauth-access-id
	cmd.Flags().Int64Var(&f.oauthAccessId, "oauth-access-id", 0, "The oauth access ID for the device performing the action.")
	err = cmd.MarkFlagRequired("oauth-access-id")
	if err != nil {
		panic(err)
	}
}
