package mobileauthcli

import "github.com/spf13/cobra"

func NewMobileAuthRootCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "mobile-auth",
		Short: "Parent command for mobile auth APIs.",
	}

	cmd.AddCommand(NewRequestMobileDeviceAuthCommand())
	cmd.AddCommand(NewGetDeviceAuthStatusCommand())
	cmd.AddCommand(NewFindActiveDeviceAuthCommand())
	cmd.AddCommand(NewCompleteDeviceAuthCommand())
	cmd.AddCommand(NewDevListenerCommand())

	return cmd
}
