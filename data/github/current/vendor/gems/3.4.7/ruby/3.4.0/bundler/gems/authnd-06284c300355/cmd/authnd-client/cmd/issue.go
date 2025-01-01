package cmd

import (
	"context"
	"fmt"
	"time"

	"github.com/pkg/errors"
	"github.com/spf13/cobra"
	"google.golang.org/protobuf/types/known/timestamppb"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/cmd/authnd-client/shared"
)

const invalidAttributeErrorMessage = "expected '<id>:[:<type>]=<value>'"

type issueCommand struct {
	shared.ConnectionInfo
	tokenType string
	expiresAt string
	expiresIn string
}

type issueSATCommand struct {
	shared.ConnectionInfo
	userID    uint64
	sessionID uint64
	scope     string
	expiresAt string
	expiresIn string
}

func NewIssueCommands() []*cobra.Command {
	// TODO(chriskirkland): make this an `issue` namespace
	var (
		issue issueCommand
		cmd   = &cobra.Command{
			Use:   "issue",
			Short: "Issue a fine-grained Personal Access Token",
			Long: `Submit a request to issue a token to the service

To issue a token, run 'authnd-client issue <attrs...>'
where '<attrs...>' is a space-delimited list of attributes in the form '<id>[:<type>]=<value>'

Examples:
  actor.id=42
  foo.bar:string=Baz`,
			RunE: issue.Run,
			Args: cobra.MinimumNArgs(1),
		}

		issueSAT issueSATCommand
		satCmd   = &cobra.Command{
			Use:   "issueSAT",
			Short: "Issue a SignedAuthToken",
			Long: `Submit a request to issue a token to the service

To issue a token, run 'authnd-client issueSAT -u <userID> (-s <sessionID>) --scope <scope> [--expiresAt|--expiresIn] <attrs...>'
where '<attrs...>' is a space-delimited list of attributes in the form '<id>[:<type>]=<value>'

The '<type>' can be omitted for well-known attribute IDs, where the type is already known.
Examples:
  actor.id=42
  foo.bar:string=Baz`,
			RunE: issueSAT.Run,
		}
	)

	issue.registerFlags(cmd)
	issueSAT.registerFlags(satCmd)
	return []*cobra.Command{cmd, satCmd}
}

func (i *issueCommand) Run(cmd *cobra.Command, args []string) error {
	attributes := make([]*pb.Attribute, 0)
	for _, arg := range args {
		attr, err := parseAttribute(arg)
		if err != nil {
			return errors.Wrapf(err, "invalid attribute '%s'", arg)
		}
		attributes = append(attributes, attr)
	}

	cm, err := i.ConnectionInfo.NewCredentialManager()
	if err != nil {
		return err
	}

	req := &pb.IssueTokenRequest{
		Attributes: attributes,
	}

	req.Type, err = getKnownTokenType(i.tokenType)
	if err != nil {
		return err
	}

	// Compute expiry
	expiry := time.Time{}
	if i.expiresIn != "" {
		dur, err := time.ParseDuration(i.expiresIn)
		if err != nil {
			return errors.Wrapf(err, "error parsing duration '%s'", i.expiresIn)
		}
		expiry = time.Now().Add(dur)
	} else if i.expiresAt != "" {
		expiry, err = time.Parse(time.RFC3339, i.expiresAt)
		if err != nil {
			return errors.Wrapf(err, "error parsing timestamp '%s'", i.expiresAt)
		}
	}

	if !expiry.IsZero() {
		req.ExpiresAtTime = timestamppb.New(expiry)
	}

	resp, err := cm.IssueToken(context.Background(), req)
	if err != nil {
		return err
	}

	if resp.Result != pb.IssueTokenResponse_RESULT_SUCCESS {
		fmt.Printf("failed to issue token: %s\n", resp.Result)
		fmt.Printf("Error: %s\n", resp.Error)
	} else {
		fmt.Printf("Token: %s\n", resp.Token)
		fmt.Printf("Token ID: %d\n", resp.TokenId)
	}

	return nil
}

func (i *issueCommand) registerFlags(cmd *cobra.Command) {
	shared.RegisterConnectionFlags(&i.ConnectionInfo, cmd)
	cmd.Flags().StringVar(&i.expiresAt, "expires-at", "", "The time (in RFC3339 format) at which the token should expire.")
	cmd.Flags().StringVarP(&i.expiresIn, "expires-in", "e", "", "The length of time (in a string that can be parsed as a time.Duration) that the token should be valid for.")
	cmd.Flags().StringVarP(&i.tokenType, "token-type", "t", "", "The type of the requested token [programmatic_access_token (prat)].")
}

func (i *issueSATCommand) Run(cmd *cobra.Command, args []string) error {
	attributes := make([]*pb.Attribute, 0)
	for _, arg := range args {
		attr, err := parseAttribute(arg)
		if err != nil {
			return errors.Wrapf(err, "invalid attribute '%s'", arg)
		}
		attributes = append(attributes, attr)
	}

	cm, err := i.ConnectionInfo.NewCredentialManager()
	if err != nil {
		return err
	}

	req := &pb.IssueSignedAuthTokenRequest{
		UserId:     uint64(i.userID),
		Scope:      i.scope,
		Attributes: attributes,
	}

	if i.sessionID != 0 {
		req.SessionId = uint64(i.sessionID)
	}

	// Compute expiry
	expiry := time.Time{}
	if i.expiresIn != "" {
		dur, err := time.ParseDuration(i.expiresIn)
		if err != nil {
			return errors.Wrapf(err, "error parsing duration '%s'", i.expiresIn)
		}
		expiry = time.Now().Add(dur)
	} else if i.expiresAt != "" {
		expiry, err = time.Parse(time.RFC3339, i.expiresAt)
		if err != nil {
			return errors.Wrapf(err, "error parsing timestamp '%s'", i.expiresAt)
		}
	}

	if !expiry.IsZero() {
		req.ExpiresAtTime = timestamppb.New(expiry)
	}

	resp, err := cm.IssueSignedAuthToken(context.Background(), req)
	if err != nil {
		return err
	}

	if resp.Error != "" {
		fmt.Printf("Error: %s\n", resp.Error)
	} else {
		fmt.Printf("Token: %s\n", resp.Token)
	}

	return nil
}

func (i *issueSATCommand) registerFlags(cmd *cobra.Command) {
	shared.RegisterConnectionFlags(&i.ConnectionInfo, cmd)
	cmd.Flags().Uint64VarP(&i.userID, "user-id", "u", 0, "The ID of the user to issue the token for.")
	cmd.Flags().Uint64VarP(&i.sessionID, "session-id", "s", 0, "(optional) The ID of the session to issue the token for.")
	cmd.Flags().StringVar(&i.scope, "scope", "", "The scope of the token.")
	cmd.Flags().StringVar(&i.expiresAt, "expires-at", "", "The time (in RFC3339 format) at which the token should expire.")
	cmd.Flags().StringVarP(&i.expiresIn, "expires-in", "e", "", "The length of time (in a string that can be parsed as a time.Duration) that the token should be valid for.")
}
