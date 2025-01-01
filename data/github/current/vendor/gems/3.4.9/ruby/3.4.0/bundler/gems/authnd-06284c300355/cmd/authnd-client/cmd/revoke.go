package cmd

import (
	"context"
	"fmt"
	"strconv"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/cmd/authnd-client/shared"
	"github.com/github/authnd/internal/common/tokens/fgpat"
	"github.com/pkg/errors"
	"github.com/spf13/cobra"
)

type revokeCommand struct {
	shared.ConnectionInfo
	reason         string
	tokens         []string
	credentialType string
}

func NewRevokeCommand() *cobra.Command {
	var (
		revoke revokeCommand
		cmd    = &cobra.Command{
			Use:   "revoke",
			Short: "Revoke credentials",
			Long: `
Submit a request to revoke credentials from the service

There are two ways to revoke credentials, by ID and by the Credentials themselves.

To revoke by Credentials, run 'authnd-client revoke' with the corresponding
credential flag(s) and a reason. Currently, only access tokens are supported.

An example of revoking access tokens looks like:

authnd-client revoke --reason "Good Reason" --token "access_token_1" --token "access_token_2"

To revoke by IDs, run 'authnd-client revoke' with the '--type' flag and specify the IDs as arguments.
The '--type' flag cannot be used along with the other credential flag(s) (like '--token').

An example of revoking access tokens by ID looks like:

 authnd-client revoke --reason "Good Reason" --type "programmatic_access_token" 1234 5678
			`,
			RunE: revoke.Run,
		}
	)

	revoke.registerFlags(cmd)
	return cmd
}

func (r *revokeCommand) registerFlags(cmd *cobra.Command) {
	shared.RegisterConnectionFlags(&r.ConnectionInfo, cmd)
	cmd.Flags().StringVarP(&r.reason, "reason", "r", "", "The reason for revoking the credentials")
	cmd.Flags().StringArrayVarP(&r.tokens, "token", "t", []string{}, "The access token(s) to revoke")
	cmd.Flags().StringVarP(&r.credentialType, "type", "T", "", "The type of credential to revoke (used for revoking by id)")
	err := cmd.MarkFlagRequired("reason")
	if err != nil {
		panic(err)
	}
}

func (r *revokeCommand) Run(cmd *cobra.Command, args []string) error {
	req := &pb.RevokeRequest{
		Reason: r.reason,
	}

	var resultIdentifiers []string
	var err error

	// Revoking by ID
	if r.credentialType != "" {
		resultIdentifiers, err = r.revokeById(req, args)
		if err != nil {
			return err
		}
	} else {
		resultIdentifiers, err = r.revokeByCredential(req, args)
		if err != nil {
			return err
		}
	}

	cm, err := r.ConnectionInfo.NewCredentialManager()
	if err != nil {
		return err
	}

	resp, err := cm.RevokeCredentials(context.Background(), req)
	if err != nil {
		fmt.Println(err.Error())

		if isDNSError(err) {
			printDNSWarning()
		}

		// intentionally return nil here to prevent cobra from printing command help
		return nil
	}

	if resp != nil {
		for i, response := range resp.Responses {
			fmt.Printf("Revoke Result: %s. %s (%s)\n", response.Result, response.Message, resultIdentifiers[i])
		}
	}

	return nil
}

func (r *revokeCommand) revokeByCredential(req *pb.RevokeRequest, args []string) ([]string, error) {
	resultIdentifiers := make([]string, 0)

	if len(r.tokens) == 0 {
		return resultIdentifiers, errors.New("at least one access token is required")
	}
	credentials := make([]*pb.Credentials, 0)

	// collect access token credentials
	for i, t := range r.tokens {
		credentials = append(credentials, pb.NewAccessTokenCredential(t))

		token, err := fgpat.ParseToken(t)
		if err != nil {
			return resultIdentifiers, errors.Wrapf(err, "token %d is invalid", i)
		}
		resultIdentifiers = append(resultIdentifiers, token.GetSuffix())
	}

	req.Kind = &pb.RevokeRequest_ByCredential{
		ByCredential: &pb.RevokeByCredential{
			Credentials: credentials,
		},
	}
	return resultIdentifiers, nil
}

func (r *revokeCommand) revokeById(req *pb.RevokeRequest, args []string) ([]string, error) {
	resultIdentifiers := make([]string, 0)

	credType, err := getKnownTokenType(r.credentialType)
	if err != nil {
		return resultIdentifiers, err
	}

	if len(r.tokens) > 0 {
		return resultIdentifiers, errors.New("cannot use --token with --type")
	}

	if len(args) == 0 {
		return resultIdentifiers, errors.New("at least one ID is required")
	}

	ids := make([]int64, 0)
	for _, arg := range args {
		parsedID, err := strconv.ParseInt(arg, 10, 64)
		if err != nil {
			return resultIdentifiers, errors.Errorf("invalid ID '%s'", arg)
		}
		ids = append(ids, parsedID)
		resultIdentifiers = append(resultIdentifiers, arg)
	}

	req.Kind = &pb.RevokeRequest_ById{
		ById: &pb.RevokeById{
			CredentialType: credType,
			CredentialIds:  ids,
		},
	}

	return resultIdentifiers, nil
}
