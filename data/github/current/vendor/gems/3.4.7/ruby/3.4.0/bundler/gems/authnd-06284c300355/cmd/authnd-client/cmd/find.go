package cmd

import (
	"context"
	"fmt"

	"github.com/pkg/errors"
	"github.com/spf13/cobra"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/cmd/authnd-client/shared"
)

type findCmd struct {
	shared.ConnectionInfo
	tokenType string
}

func NewFindCommand() *cobra.Command {
	var (
		find findCmd
		cmd  = &cobra.Command{
			Use:   "find",
			Short: "Find token(s)",
			Long: `Submit a request to find credential(s).

To find tokens, run 'authnd-client find <attrs...>'
where '<attrs...>' is a space-delimited list of wellknown attributes in the form '<id>=<value>'

The '<type>' can be omitted for well-known attribute IDs, where the type is already known.
Examples:
  actor.id=42
  actor.type=User
  access.id=123`,
			RunE: find.Run,
			Args: cobra.MinimumNArgs(1),
		}
	)

	find.registerFlags(cmd)
	return cmd
}

func (f *findCmd) Run(cmd *cobra.Command, args []string) error {
	attributes := make([]*pb.Attribute, 0)
	for _, arg := range args {
		attr, err := parseAttribute(arg)
		if err != nil {
			return errors.Wrapf(err, "invalid attribute '%s'", arg)
		}
		attributes = append(attributes, attr)
	}

	cm, err := f.ConnectionInfo.NewCredentialManager()
	if err != nil {
		return err
	}

	req := &pb.FindCredentialsRequest{
		Attributes: attributes,
	}

	switch f.tokenType {
	case "programmatic_access_token", "prat":
		req.Type = pb.ProgrammaticAccessTokenType
	default:
		return errors.Errorf("invalid token type: %s. expected 'programmatic_access_token' or 'prat'.", f.tokenType)
	}

	resp, err := cm.FindCredentials(context.Background(), req)
	if err != nil {
		fmt.Println(err.Error())

		if isDNSError(err) {
			printDNSWarning()
		}

		// intentionally return nil here to prevent cobra from printing command help
		return nil
	}

	if resp == nil {
		fmt.Println("No credentials found.")
		return nil
	}

	if resp.Error != "" {
		fmt.Println(resp.Error)
		return nil
	}

	for _, credential := range resp.Credentials {
		shared.PrintAttributes(credential.Attributes...)
	}

	return nil
}

func (f *findCmd) registerFlags(cmd *cobra.Command) {
	shared.RegisterConnectionFlags(&f.ConnectionInfo, cmd)
	cmd.Flags().StringVarP(&f.tokenType, "token-type", "t", "", "The type of the requested token [programmatic_access_token (prat)].")
}
