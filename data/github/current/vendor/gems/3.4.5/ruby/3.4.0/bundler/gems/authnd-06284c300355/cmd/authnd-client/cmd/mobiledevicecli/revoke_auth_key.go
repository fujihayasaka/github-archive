package mobiledevicecli

import (
	"context"
	"fmt"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/cmd/authnd-client/shared"
	"github.com/spf13/cobra"
)

type revokeMobileDeviceAuthKeyCommand struct {
	shared.ConnectionInfo
	oauthAccessId int64
}

func NewRevokeMobileDeviceAuthKeyCommand() *cobra.Command {
	var (
		r   revokeMobileDeviceAuthKeyCommand
		cmd = &cobra.Command{
			Use:   "revoke-auth-key",
			Short: "Revokes a mobile device auth key",
			Long: `Submit a request to authnd to revoke a mobile device auth key

	To submit the request, run 'authnd-client mobile-device revoke-auth-key <flags>'
			`,
			RunE: r.Run,
		}
	)

	r.registerFlags(cmd)
	return cmd
}

func (r *revokeMobileDeviceAuthKeyCommand) Run(cmd *cobra.Command, args []string) error {
	mdm, err := r.ConnectionInfo.NewMobileDeviceManager()
	if err != nil {
		return err
	}

	req := &pb.RevokeDeviceKeyRequest{
		Kind: &pb.RevokeDeviceKeyRequest_RevokeAuthKeyRequest{
			RevokeAuthKeyRequest: &pb.RevokeDeviceAuthKeyRequest{
				OauthAccessId: r.oauthAccessId,
			},
		},
	}
	resp, err := mdm.RevokeDeviceKey(context.Background(), req)
	if err != nil {
		return err
	}

	if resp.Result != pb.RevokeDeviceKeyResponse_RESULT_SUCCESS {
		fmt.Printf("failed to revoke device auth key: %s\n", resp.Result)
	} else {
		fmt.Printf("Result: %s\n", resp.Result)
	}

	return nil
}

func (r *revokeMobileDeviceAuthKeyCommand) registerFlags(cmd *cobra.Command) {
	shared.RegisterConnectionFlags(&r.ConnectionInfo, cmd)

	// oauth-access-id
	cmd.Flags().Int64Var(&r.oauthAccessId, "oauth-access-id", 0, "The oauth access ID the mobile device key belongs to.")
	err := cmd.MarkFlagRequired("oauth-access-id")
	if err != nil {
		panic(err)
	}
}
