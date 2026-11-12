// Description: This is the main entry point for the twirp-test command line tool.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"

	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-auth/hmac"
	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/command"
	"github.com/github/osslicensecompliance/internal/config"
	"github.com/github/osslicensecompliance/internal/dependencies"
	proto "github.com/github/osslicensecompliance/pkg/proto/v0"
)

func main() {
	if err := run(); err != nil {
		log.Fatalf("failed to run service: %v", err)
	}
}

const minimumArgs = 2

func run() error {
	if len(os.Args) < minimumArgs {
		return errors.New("usage: twirp-test <command> [additional options]\n" + command.ListCommands(allCommands))
	}

	return command.DispatchCommand(os.Args[1], allCommands)
}

func newServiceURLFlag(f *flag.FlagSet) *string {
	return f.String("url", os.Getenv("TWIRP_URL"), "The url of the Twirp server")
}

// createHMACClient creates an HTTP client that adds HMAC headers to requests
func createHMACClient() *http.Client {
	hmacSecret := os.Getenv("HMAC_SECRET")
	if hmacSecret == "" {
		log.Println("Warning: HMAC_SECRET environment variable not set, requests may fail")
		return &http.Client{}
	}

	return &http.Client{
		Transport: &hmacTransport{
			secret:    hmacSecret,
			transport: http.DefaultTransport,
		},
	}
}

// hmacTransport wraps an http.RoundTripper to add HMAC headers
type hmacTransport struct {
	secret    string
	transport http.RoundTripper
}

func (t *hmacTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	// Create HMAC token
	hmacToken := hmac.NewRequestHMAC(t.secret)

	// Add the Request-HMAC header
	req.Header.Set(hmac.RequestHeader, hmacToken.String())

	return t.transport.RoundTrip(req)
}

var allCommands = []command.Command{
	{Name: "create_org_policy", Desc: "Creates an organization Policy", Execute: createOrgPolicy},
	{Name: "get_org_policy", Desc: "Gets an organization Policy by ID", Execute: getOrgPolicy},
	{Name: "check", Desc: "Get the result of a PR check", Execute: checkRepository},
	{Name: "depdiff", Desc: "Get the diff of dependencies for a repo and SHA combo", Execute: getDependenciesDiff},
}

const sampleOrgID = 100

func isProductionURL(serviceURL string) bool {
	return strings.Contains(strings.ToLower(serviceURL), "production")
}

func createOrgPolicy(c *command.Command) error {
	flagSet := flag.NewFlagSet("create_org_policy", flag.ExitOnError)
	serviceURLFlag := newServiceURLFlag(flagSet)

	// Parse the flags to populate the values
	if err := flagSet.Parse(os.Args[2:]); err != nil {
		return err
	}

	// Production protection: prevent create operations against production URLs
	if isProductionURL(*serviceURLFlag) {
		return fmt.Errorf("cannot create organization policy against production URL: %s - this is a safety protection to prevent accidental modifications to production data", *serviceURLFlag)
	}

	service := proto.NewLicenseComplianceProtobufClient(*serviceURLFlag, createHMACClient())

	request := &proto.CreateOrganizationPolicyRequest{
		OrganizationId: sampleOrgID,
		Licenses: &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{
				{
					SpdxId:   "MIT",
					Contexts: []string{"distributed"},
				},
			},
		},
		Packages: []*proto.PackagePolicy{
			{
				PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
				Name:           "lodash",
				Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
				Reason:         "reason",
			},
		},
	}

	response, err := service.CreateOrganizationPolicy(context.Background(), request)
	if err != nil {
		return err
	}

	fmt.Printf("Received response from server: %s\n", response.GetPolicy())

	return nil
}

func getOrgPolicy(c *command.Command) error {
	flagSet := flag.NewFlagSet("get_org_policy", flag.ExitOnError)
	serviceURLFlag := newServiceURLFlag(flagSet)

	// Parse the flags to populate the values
	if err := flagSet.Parse(os.Args[2:]); err != nil {
		return err
	}

	// Get remaining arguments after flags
	args := flagSet.Args()
	if len(args) == 0 {
		return command.NewUsageError("organization ID is required", flagSet)
	}

	orgID, err := strconv.ParseUint(args[0], 10, 64)
	if err != nil {
		return err
	}
	service := proto.NewLicenseComplianceProtobufClient(*serviceURLFlag, createHMACClient())

	request := &proto.GetOrganizationPolicyRequest{
		OrganizationId: orgID,
	}
	response, err := service.GetOrganizationPolicy(context.Background(), request)
	if err != nil {
		return err
	}
	fmt.Printf("Received response from server: %s\n", response.GetPolicy())
	return nil
}

func checkRepository(c *command.Command) error {
	flagSet := flag.NewFlagSet("check_repository", flag.ExitOnError)
	serviceURLFlag := newServiceURLFlag(flagSet)
	repoID := flagSet.Uint64("repo", 0, "Repository ID")
	enterpriseID := flagSet.Uint64("enterprise", 0, "Enterprise ID")
	organizationID := flagSet.Uint64("organization", 0, "Organization ID")
	commitSHA := flagSet.String("sha", "", "Commit SHA")
	baseSHA := flagSet.String("base", "", "Base SHA")
	repoContext := flagSet.String("context", "", "Distribution context for the repo (optional)")

	// Parse the flags to populate the values
	if err := flagSet.Parse(os.Args[2:]); err != nil {
		return err
	}

	// repoID, organizationID, commitSHA, baseSHA are all required
	if *repoID == 0 || *organizationID == 0 || *commitSHA == "" || *baseSHA == "" {
		return command.NewUsageError("repo ID, organization ID, commit SHA, and base SHA are all required", flagSet)
	}

	service := proto.NewLicenseComplianceProtobufClient(*serviceURLFlag, createHMACClient())

	request := &proto.CheckRepositoryRequest{
		OrganizationId: *organizationID,
		EnterpriseId:   *enterpriseID,
		RepositoryId:   *repoID,
		CommitSha:      *commitSHA,
		BaseSha:        *baseSHA,
		Context:        *repoContext,
	}
	response, err := service.CheckRepository(context.Background(), request)
	if err != nil {
		return err
	}
	status := response.GetStatus().String()
	message := response.GetMessage()
	fmt.Printf("Received response from server:\nStatus: %s\nMessage: %s\n", status, message)
	return nil
}

func getDependenciesDiff(c *command.Command) error {
	flagSet := flag.NewFlagSet("depdiff", flag.ExitOnError)
	repoID := flagSet.Uint64("repo", 0, "Repository ID")
	commitSHA := flagSet.String("sha", "", "Commit SHA")
	baseSHA := flagSet.String("base", "", "Base SHA")

	// Parse the flags to populate the values
	if err := flagSet.Parse(os.Args[2:]); err != nil {
		return err
	}

	cfg, err := config.Load()
	if err != nil {
		return err
	}

	telemetryProvider, err := telemetry.NewFromEnv()
	if err != nil {
		return err
	}

	// Create and start stats client
	statsClient, err := cfg.NewStatsClient()
	if err != nil {
		return err
	}
	statsClient.Run()
	defer statsClient.Stop()

	logger := telemetryProvider.Logger.Named("twirp-test")

	// Use the null here so that we can avoid having to set up all of the Azure stuff
	app, err := application.NewNullApplication(&application.NullConfig{}, logger)
	if err != nil {
		return err
	}

	// Replace the null dependency getter with a real one
	app.Subsystems.DependencyGetter, err = dependencies.New(cfg, logger, statsClient)
	if err != nil {
		return err
	}

	result, err := app.Subsystems.DependencyGetter.GetDiffDependenciesForRepo(context.Background(), *repoID, *commitSHA, *baseSHA)
	if err != nil {
		return err
	}

	depsJSONBytes, err := json.Marshal(result)
	if err != nil {
		return err
	}

	fmt.Println(string(depsJSONBytes))

	return nil
}
