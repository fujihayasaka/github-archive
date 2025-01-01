package cmd

import (
	"context"
	"fmt"

	"github.com/pkg/errors"
	"github.com/spf13/cobra"

	"github.com/github/authnd/client"
	"github.com/github/authnd/cmd/authnd-client/shared"
)

type exchangeCommand struct {
	shared.ConnectionInfo
	token string
}

func NewExchangeCommand() *cobra.Command {
	var (
		exchange exchangeCommand
		cmd      = &cobra.Command{
			Use:  "exchange",
			RunE: exchange.Run,
		}
	)

	exchange.registerFlags(cmd)
	return cmd
}

func (a *exchangeCommand) Run(cmd *cobra.Command, args []string) error {
	exchanger, err := a.ConnectionInfo.NewExchanger()
	if err != nil {
		return err
	}

	creds, err := a.generateCreds()
	if err != nil {
		return err
	}
	if creds == nil {
		return errors.New("no credentials specified")
	}

	req := client.NewExchangeTokenRequest(creds)

	resp, err := exchanger.ExchangeToken(context.Background(), req)
	if err != nil {
		fmt.Println(err.Error())

		if isDNSError(err) {
			printDNSWarning()
		}

		return nil
	}

	if !resp.Succeeded() {
		fmt.Printf("token exchange failed: %v\n", resp.Result)
		return nil
	}
	fmt.Printf("token: %v\n", resp.Token)

	return nil
}

func (a *exchangeCommand) registerFlags(cmd *cobra.Command) {
	shared.RegisterConnectionFlags(&a.ConnectionInfo, cmd)
	cmd.Flags().StringVarP(&a.token, "token", "t", "", "An OAuth/Personal Access Token to authenticate with.")
}

func (a *exchangeCommand) generateCreds() (*client.Credentials, error) {
	switch {
	case a.token != "":
		return client.NewAccessTokenCredentials(a.token), nil
	default:
		// No creds? Ok, we'll just return nil and you'll get a twirp error.
		return nil, nil
	}
}
