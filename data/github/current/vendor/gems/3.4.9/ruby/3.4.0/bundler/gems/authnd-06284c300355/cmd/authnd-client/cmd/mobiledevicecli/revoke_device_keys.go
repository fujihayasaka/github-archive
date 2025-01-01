package mobiledevicecli

import (
	"context"
	"fmt"
	"os"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/cmd/authnd-client/shared"
	"github.com/olekukonko/tablewriter"
	"github.com/spf13/cobra"
)

type revokeMobileDeviceKeysCommand struct {
	shared.ConnectionInfo
	userId int64
}

func NewRevokeMobileDeviceKeysCommand() *cobra.Command {
	var (
		r   revokeMobileDeviceKeysCommand
		cmd = &cobra.Command{
			Use:   "revoke-device-keys",
			Short: "Revokes all mobile device keys for a user",
			Long: `Submit a request to authnd to revoke all mobile device keys for a user

	To submit the request, run 'authnd-client mobile-device revoke-device-keys <flags>'
			`,
			RunE: r.Run,
		}
	)

	r.registerFlags(cmd)
	return cmd
}

func (r *revokeMobileDeviceKeysCommand) Run(cmd *cobra.Command, args []string) error {
	mdm, err := r.ConnectionInfo.NewMobileDeviceManager()
	if err != nil {
		return err
	}

	req := &pb.RevokeDeviceKeysRequest{
		Kind: &pb.RevokeDeviceKeysRequest_RevokeAuthKeysRequest{
			RevokeAuthKeysRequest: &pb.RevokeDeviceAuthKeysRequest{
				UserId: r.userId,
			},
		},
	}

	resp, err := mdm.RevokeDeviceKeys(context.Background(), req)
	if err != nil {
		return err
	}

	if resp.Result != pb.RevokeDeviceKeysResponse_RESULT_SUCCESS {
		fmt.Printf("failed to revoke device keys: %s\n", resp.Result)
	} else {
		fmt.Printf("Result: %s\n", resp.Result)
		table := tablewriter.NewWriter(os.Stdout)
		table.SetHeader([]string{"oauth_ids"})

		for _, r := range resp.OauthAccessIds {
			values := []string{fmt.Sprint(r)}
			table.Append(values)
		}

		table.Render()
	}

	return nil
}

func (r *revokeMobileDeviceKeysCommand) registerFlags(cmd *cobra.Command) {
	shared.RegisterConnectionFlags(&r.ConnectionInfo, cmd)

	// user-id
	cmd.Flags().Int64Var(&r.userId, "user-id", 0, "The user ID of the user you want to revoke mobile device keys for.")
	err := cmd.MarkFlagRequired("user-id")
	if err != nil {
		panic(err)
	}
}
