package mobiledevicecli

import "github.com/spf13/cobra"

func NewMobileDeviceRootCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "mobile-device",
		Short: "Parent command for mobile device APIs.",
	}

	cmd.AddCommand(NewRegisterKeyCommand())
	cmd.AddCommand(NewRevokeMobileDeviceAuthKeyCommand())
	cmd.AddCommand(NewFindRegistrationsCommand())
	cmd.AddCommand(NewRevokeMobileDeviceKeysCommand())

	return cmd
}
