package cmd

import (
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"os"
	"path"
	"regexp"
	"strings"

	"github.com/pkg/errors"

	"github.com/github/authnd/cmd/authnd-client/shared"
	"github.com/github/go-chatops/v2"
	"github.com/spf13/cobra"
)

const AuthndChatopsRoomId = "#authnd-ops"

type chatopCommand struct {
	environment string
	address     string
	privateKey  string
}

func NewChatopCommand() *cobra.Command {
	var (
		chatop chatopCommand
		cmd    = &cobra.Command{
			Use:   "chatop -- <COMMAND...>",
			Short: "Send a chatop request.",
			Long: `Send a chatop request to the specified instance of authnd.

This command is useful both as a fallback option when Slack is down, and for local development testing.
By default, this command targets your locally-running instance of authnd.

NOTE: It is highly recommended you use '--' to separate the commmand arguments from the chatop itself.
Any arguments after '--' will be left unparsed and passed along to the chatop.
For example: 'authnd-client chatop -- resync --from 1 --to 1000'
Arguments before the '--' may be parsed as arguments to this command rather than part of the chatop.`,
			RunE: chatop.Run,
		}
	)

	chatop.registerFlags(cmd)
	return cmd
}

func (c *chatopCommand) registerFlags(cmd *cobra.Command) {
	cmd.Flags().StringVarP(&c.privateKey, "key", "K", "", "The private key to authenticate with, can be empty in 'development'.")
	cmd.Flags().StringVarP(&c.environment, "environment", "E", "", "An environment name to connect to. Defaults to 'development'.")
	cmd.Flags().StringVarP(&c.address, "address", "a", "", "The URL of the chatops endpoint to call. Overrides the environment default.")
}

func (c *chatopCommand) Run(cmd *cobra.Command, args []string) error {
	envConfig, ok := shared.GetEnvConfig(c.environment)
	if !ok {
		return errors.Errorf("unknown environment '%s'", c.environment)
	}

	if c.address == "" {
		c.address = fmt.Sprintf("%s/_chatops", envConfig.AuthndBaseUrl)
	}

	if c.privateKey == "" {
		if envConfig.Name == "development" {
			c.privateKey = path.Join(os.Getenv("HOME"), ".authnd", "chatops.development.private.pem")
		} else {
			return errors.Errorf("a private key file must be specified using '--key' when connecting to the '%s' environment", c.environment)
		}
	}

	bytes, err := os.ReadFile(c.privateKey)
	if err != nil {
		return errors.Wrapf(err, "error reading private key '%s'", c.privateKey)
	}
	c.privateKey = string(bytes)

	if verbose {
		fmt.Println("Using chatops address:", c.address)
	}

	privPem, _ := pem.Decode([]byte(c.privateKey))
	if privPem.Type != "RSA PRIVATE KEY" {
		return errors.New("private key file does not contain a PEM-encoded private key")
	}

	privateKey, err := x509.ParsePKCS1PrivateKey(privPem.Bytes)
	if err != nil {
		return errors.WithStack(err)
	}

	client := chatops.NewClientWithKey(c.address, privateKey)

	// Fetch the list of chatops, we need it for the regexes.
	list, err := client.List()
	if err != nil {
		return errors.WithStack(err)
	}

	if len(args) == 0 {
		fmt.Println("commands:")
		for k, v := range list.Methods {
			fmt.Printf(" * %s: %s (%s)\n", k, v.Help, v.Regex)
		}
	} else {
		method, params, err := findCommand(args, list.Methods)
		if err != nil {
			return err
		}

		resp, _, err := client.Run(method, os.Getenv("USER"), AuthndChatopsRoomId, params)
		if err != nil {
			return errors.Wrapf(err, "error invoking '%s' chatop", method)
		}
		fmt.Printf("%s\n", resp.Title)
		fmt.Printf("%s\n", resp.Result)
	}

	return nil
}

func findCommand(args []string, methods map[string]*chatops.ListMethod) (string, map[string]string, error) {
	wholeString := strings.Join(args, " ")

	for k, v := range methods {
		// THIS IS A GIGANTOR HACK, but I think it's necessary.
		// Hubot requires named capture groups use `(?<name>expression)` syntax but Go doesn't support that: https://github.com/google/re2/wiki/Syntax
		// It DOES support `(?P<name>expression)` for some reason, so we do a somewhat-gross replacement...
		patchedRegexp := strings.ReplaceAll(v.Regex, "(?<", "(?P<")
		r, err := regexp.Compile(patchedRegexp)
		if err != nil {
			// Just skip this method and warn.
			fmt.Fprintf(os.Stderr, "error compiling regex '%s' for '%s' chatop: %v", v.Regex, k, err)
		} else if matches := r.FindStringSubmatch(wholeString); matches != nil {
			wholeStringArr := strings.Split(wholeString, " ")
			argsString := wholeStringArr[1:]
			params, err := parseChatopArgs(strings.Join(argsString, " "))
			if err != nil {
				return "", nil, err
			}
			return k, params, nil
		}
	}

	return "", nil, errors.Errorf("no chatops matched the input '%s'", wholeString)
}

func parseChatopArgs(argString string) (map[string]string, error) {
	if len(argString) == 0 {
		return map[string]string{}, nil
	}
	parts := strings.Split(argString, " ")
	args := make(map[string]string)
	if len(parts)%2 != 0 {
		return nil, errors.New("could not match every argument name to a value")
	}
	for i := 0; i < len(parts); i += 2 {
		argName := parts[i]
		if !strings.HasPrefix(argName, "--") {
			return nil, errors.New("arg name did not start with '--'")
		}
		argValue := parts[i+1]
		if len(argValue) == 0 {
			return nil, errors.Errorf("coult not parse a value for %s", argName)
		}
		args[argName[2:]] = argValue
	}
	return args, nil
}
