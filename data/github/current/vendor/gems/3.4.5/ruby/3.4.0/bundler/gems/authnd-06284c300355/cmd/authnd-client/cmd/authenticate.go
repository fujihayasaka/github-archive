package cmd

import (
	"context"
	"fmt"
	"os"
	"reflect"

	"github.com/pkg/errors"
	"github.com/spf13/cobra"
	"golang.org/x/term"

	"github.com/github/authnd/client"
	"github.com/github/authnd/cmd/authnd-client/shared"
)

type authenticateCommand struct {
	shared.ConnectionInfo
	login        string
	password     string
	keyFile      string
	ip           string
	token        string
	sat          string
	satScope     string
	readToken    bool
	readPassword bool
}

func NewAuthenticateCommand() *cobra.Command {
	var (
		authenticate authenticateCommand
		cmd          = &cobra.Command{
			Use:   "authenticate",
			Short: "Request authentication",
			Long:  `Submit an authentication request to the service.`,
			RunE:  authenticate.Run,
		}
	)

	authenticate.registerFlags(cmd)
	return cmd
}

func (a *authenticateCommand) Run(cmd *cobra.Command, args []string) error {
	authenticator, err := a.ConnectionInfo.NewAuthenticator()
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

	req := client.NewAuthenticateRequest(creds)

	resp, err := authenticator.Authenticate(context.Background(), req)
	if err != nil {
		fmt.Println(err.Error())

		if isDNSError(err) {
			printDNSWarning()
		}

		return nil
	}

	if !resp.Succeeded() {
		fmt.Printf("authentication failed: %v\n", resp.Result)
		return nil
	}

	for id, val := range resp.Attributes {
		if val == nil {
			fmt.Printf("%v = [nil]\n", id)
		} else {
			typ := reflect.TypeOf(val)
			fmt.Printf("%v = [%s] %v\n", id, typ.Name(), val)
		}
	}

	return nil
}

func (a *authenticateCommand) registerFlags(cmd *cobra.Command) {
	shared.RegisterConnectionFlags(&a.ConnectionInfo, cmd)
	cmd.Flags().StringVarP(&a.login, "login", "l", "", "A username to authenticate with. The '--password' option must also be provided.")
	cmd.Flags().StringVarP(&a.password, "password", "p", "", "A password to authenticate with. The '--login' option must also be provided.")
	cmd.Flags().BoolVarP(&a.readPassword, "read-password", "P", false, "If set, authnd-client will prompt for the password.")
	cmd.Flags().StringVarP(&a.keyFile, "ssh-key", "k", "", "An SSH key file to authenticate with.")
	cmd.Flags().StringVarP(&a.token, "token", "t", "", "An OAuth/Personal Access Token to authenticate with.")
	cmd.Flags().BoolVarP(&a.readToken, "read-token", "T", false, "If set, authnd-client will prompt for the token.")
	cmd.Flags().StringVar(&a.sat, "sat", "", "A SignedAuthToken to authenticate with. If this is specified, '--sat-scope' must also be specified.")
	cmd.Flags().StringVar(&a.satScope, "sat-scope", "", "The scope of the SignedAuthToken to authenticate. Ignored unless '--sat' is also specified.")
	cmd.Flags().StringVar(&a.ip, "ip", "127.0.0.1", "An IP address to include in the request.")
}

func (a *authenticateCommand) generateCreds() (*client.Credentials, error) {
	var err error

	switch {
	case a.keyFile != "":
		contents, err := os.ReadFile(a.keyFile)
		if err != nil {
			return nil, err
		}
		return client.NewSSHKeyCredentials(string(contents)), nil
	case a.readPassword:
		a.password, err = promptSecure("Enter Password:")
		if err != nil {
			return nil, err
		}
		fallthrough
	case a.login != "":
		if a.password == "" {
			return nil, errors.New("both '--login' and '--password' must be specified")
		}
		return client.NewLoginPasswordCredentials(a.login, a.password), nil
	case a.readToken:
		a.token, err = promptSecure("Enter Token:")
		if err != nil {
			return nil, err
		}
		fallthrough
	case a.token != "":
		return client.NewAccessTokenCredentials(a.token), nil
	case a.sat != "":
		if a.satScope == "" {
			return nil, errors.New("both '--sat' and '--sat-scope' must be specified")
		}
		return client.NewSignedAuthTokenCredentials(a.sat, a.satScope), nil
	default:
		// No creds? Ok, we'll just return nil and you'll get a twirp error.
		return nil, nil
	}
}

// promptSecure writes the provided message (without a newline) then reads user input without echoing it
// back until a newline
func promptSecure(message string) (string, error) {
	fmt.Print(message)
	tokenBytes, err := term.ReadPassword(int(os.Stdin.Fd()))
	if err != nil {
		return "", err
	}
	return string(tokenBytes), nil
}
