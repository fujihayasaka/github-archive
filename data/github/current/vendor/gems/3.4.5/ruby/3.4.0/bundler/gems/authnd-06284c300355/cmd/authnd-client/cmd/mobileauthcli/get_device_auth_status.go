package mobileauthcli

import (
	"context"
	"fmt"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/cmd/authnd-client/shared"
	"github.com/spf13/cobra"
)

type getDeviceAuthStatusCommand struct {
	shared.ConnectionInfo
	id     int64
	userId int64
}

func NewGetDeviceAuthStatusCommand() *cobra.Command {
	var (
		g   getDeviceAuthStatusCommand
		cmd = &cobra.Command{
			Use:   "status",
			Short: "Gets the status of a device auth record",
			Long: `Submit a request to authnd to retrieve the auth status of an auth request by ID.

	To submit the request, run 'authnd-client mobile-auth status --id <id> --user-id <user_id>'
			`,
			RunE: g.Run,
		}
	)

	g.registerFlags(cmd)
	return cmd
}

func (g *getDeviceAuthStatusCommand) Run(cmd *cobra.Command, args []string) error {
	mdm, err := g.ConnectionInfo.NewMobileDeviceManager()
	if err != nil {
		return err
	}

	req := &pb.GetDeviceAuthStatusRequest{
		Id:     g.id,
		UserId: g.userId,
	}

	resp, err := mdm.GetDeviceAuthStatus(context.Background(), req)
	if err != nil {
		return err
	}

	if resp.Result != pb.GetDeviceAuthStatusResponse_RESULT_SUCCESS {
		fmt.Printf("failed to get device auth status: %s\n", resp.Result)
	} else {
		fmt.Printf("Result: %s\n", resp.Result)
		fmt.Printf("Status: %s\n", resp.Status)
	}

	return nil
}

func (g *getDeviceAuthStatusCommand) registerFlags(cmd *cobra.Command) {
	shared.RegisterConnectionFlags(&g.ConnectionInfo, cmd)

	// id
	cmd.Flags().Int64Var(&g.id, "id", 0, "The ID of the device auth record.")
	err := cmd.MarkFlagRequired("id")
	if err != nil {
		panic(err)
	}

	// user-id
	cmd.Flags().Int64Var(&g.userId, "user-id", 0, "The user ID requesting the status.")
	err = cmd.MarkFlagRequired("user-id")
	if err != nil {
		panic(err)
	}
}
