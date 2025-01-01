package mobiledevicecli

import (
	"context"
	"fmt"
	"os"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/cmd/authnd-client/shared"
	"github.com/olekukonko/tablewriter"
	"github.com/spf13/cobra"
)

type findRegistrationsCommand struct {
	shared.ConnectionInfo
	userId        int64
	oauthAccessId int64
	findAuthKeys  bool
}

func NewFindRegistrationsCommand() *cobra.Command {
	var (
		f   findRegistrationsCommand
		cmd = &cobra.Command{
			Use:   "find",
			Short: "Finds device key registrations for a user",
			Long: `Submit a request to authnd to find valid device key registrations for a user

	To submit the request, run 'authnd-client mobile-device find <flags>'
			`,
			RunE: f.Run,
		}
	)

	f.registerFlags(cmd)
	return cmd
}

func (f *findRegistrationsCommand) Run(cmd *cobra.Command, args []string) error {
	if !f.findAuthKeys {
		fmt.Println("You must provide the --auth flag. Authnd currently only supports retrieving device auth keys.")
		return nil
	}

	mdm, err := f.ConnectionInfo.NewMobileDeviceManager()
	if err != nil {
		return err
	}

	var registrations []*pb.DeviceKeyRegistration
	if f.oauthAccessId != 0 {
		registrations, err = f.findRegistrationsForDevice(mdm)
	} else {
		registrations, err = f.findRegistrationsForUser(mdm)
	}

	if err != nil {
		return err
	}

	fmt.Printf("Found %d device key registrations:\n", len(registrations))

	table := tablewriter.NewWriter(os.Stdout)
	table.SetHeader([]string{"id", "name", "model", "os", "created_at", "expires_at", "last_used_at", "oauth_access_id"})

	for _, r := range registrations {
		values := []string{fmt.Sprint(r.Id), r.DeviceName, r.DeviceModel, r.DeviceOs, r.CreatedAtTime.AsTime().String(), r.ExpiresAtTime.AsTime().String(), r.LastUsedAtTime.AsTime().String(), fmt.Sprint(r.OauthAccessId)}
		if r.LastUsedAtTime.IsValid() {
			values = append(values, r.LastUsedAtTime.AsTime().String())
		}
		table.Append(values)
	}

	table.Render()
	return nil
}

func (f *findRegistrationsCommand) findRegistrationsForUser(mdm client.MobileDeviceManager) ([]*pb.DeviceKeyRegistration, error) {
	req := &pb.FindDeviceKeyRegistrationsRequest{
		Kind: &pb.FindDeviceKeyRegistrationsRequest_AuthRegistrationsRequest{
			AuthRegistrationsRequest: &pb.RegistrationsRequest{
				UserId: f.userId,
			},
		},
	}

	resp, err := mdm.FindDeviceKeyRegistrations(context.Background(), req)
	if err != nil {
		return nil, err
	}

	if resp.Result != pb.FindDeviceKeyRegistrationsResponse_RESULT_SUCCESS {
		fmt.Printf("failed to find device key registrations: %s\n", resp.Result)
	} else {
		fmt.Printf("Result: %s\n", resp.Result)
	}
	return resp.Registrations, nil
}

func (f *findRegistrationsCommand) findRegistrationsForDevice(mdm client.MobileDeviceManager) ([]*pb.DeviceKeyRegistration, error) {
	req := &pb.FindDeviceKeyRegistrationRequest{
		Kind: &pb.FindDeviceKeyRegistrationRequest_AuthRegistrationRequest{
			AuthRegistrationRequest: &pb.RegistrationRequest{
				UserId:        f.userId,
				OauthAccessId: f.oauthAccessId,
			},
		},
	}

	resp, err := mdm.FindDeviceKeyRegistration(context.Background(), req)
	if err != nil {
		return nil, err
	}
	if resp.Result != pb.FindDeviceKeyRegistrationResponse_RESULT_SUCCESS {
		fmt.Printf("failed to find device key registrations: %s\n", resp.Result)
	}
	fmt.Printf("Result: %s\n", resp.Result)
	if resp.Registration != nil {
		return []*pb.DeviceKeyRegistration{resp.Registration}, nil
	}
	return nil, nil
}

func (f *findRegistrationsCommand) registerFlags(cmd *cobra.Command) {
	shared.RegisterConnectionFlags(&f.ConnectionInfo, cmd)

	// user-id
	cmd.Flags().Int64Var(&f.userId, "user-id", 0, "The user ID of the user that the mobile device keys belong to.")
	err := cmd.MarkFlagRequired("user-id")
	if err != nil {
		panic(err)
	}

	// oauth-access-id
	cmd.Flags().Int64Var(&f.oauthAccessId, "oauth-access-id", 0, "The optional oauth access ID of the device that the mobile device key belongs to.")

	// auth
	cmd.Flags().BoolVar(&f.findAuthKeys, "auth", true, "Find mobile device auth keys for the user.")
}
