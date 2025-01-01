package cmd

import (
	"context"
	"fmt"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/cmd/authnd-client/shared"
	"github.com/github/authnd/internal/common/tokens/fgpat"
	"github.com/pkg/errors"
	"github.com/spf13/cobra"
)

type verifyCommand struct {
	shared.ConnectionInfo
	tokens []string
}

func NewVerifyCommand() *cobra.Command {
	var (
		verify verifyCommand
		cmd    = &cobra.Command{
			Use:   "verify",
			Short: "Verify credentials",
			Long: `
Submit a request to verify credentials from the service

To verify by Credentials, run 'authnd-client verify' with the corresponding
credential flag(s). Currently, only access tokens are supported.

An example of verifying access tokens looks like:

authnd-client verify --token "access_token_1" --token "access_token_2"
`,
			RunE: verify.Run,
		}
	)

	verify.registerFlags(cmd)
	return cmd
}

func (r *verifyCommand) registerFlags(cmd *cobra.Command) {
	shared.RegisterConnectionFlags(&r.ConnectionInfo, cmd)
	cmd.Flags().StringArrayVarP(&r.tokens, "token", "t", []string{}, "The access token(s) to verify")
}

func (r *verifyCommand) Run(cmd *cobra.Command, args []string) error {
	req := &pb.VerifyRequest{}

	var resultIdentifiers []string
	var err error

	resultIdentifiers, err = r.verify(req, args)
	if err != nil {
		return err
	}

	cm, err := r.ConnectionInfo.NewCredentialManager()
	if err != nil {
		return err
	}

	resp, err := cm.VerifyCredentials(context.Background(), req)
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
			fmt.Printf("Is Verified: %v. Credential ID: %v. Actor ID: %v. %s (%s)\n", response.IsVerified, response.CredentialId, response.ActorId, response.Message, resultIdentifiers[i])
		}
	}

	return nil
}

func (r *verifyCommand) verify(req *pb.VerifyRequest, args []string) ([]string, error) {
	resultIdentifiers := []string{}

	if len(r.tokens) == 0 {
		return resultIdentifiers, errors.New("at least one access token is required")
	}
	candidates := []*pb.Credentials{}

	// collect access token candidates
	for i, t := range r.tokens {
		candidates = append(candidates, pb.NewAccessTokenCredential(t))

		token, err := fgpat.ParseToken(t)
		if err != nil {
			return resultIdentifiers, errors.Wrapf(err, "token %d is invalid", i)
		}
		resultIdentifiers = append(resultIdentifiers, token.GetSuffix())
	}

	req.Candidates = candidates

	return resultIdentifiers, nil
}
