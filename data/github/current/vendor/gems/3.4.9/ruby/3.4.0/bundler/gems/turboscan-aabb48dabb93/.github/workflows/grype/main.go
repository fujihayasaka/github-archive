package main

import (
	"bytes"
	"context"
	"embed"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"sort"
	"strings"
	"text/template"
	"time"

	"github.com/github/turboscan/.github/workflows/grype/types"
	"github.com/pkg/errors"
	"golang.org/x/oauth2"

	"github.com/google/go-github/v45/github"
	"github.com/hashicorp/go-version"
	log "github.com/sirupsen/logrus"
)

const scannedRepositoryOwner, scannedRepositoryName = "github", "turboscan"
const scannedImage = "containers.pkg.github.com/github/turboscan/turboscan"
const issueRepositoryOwner, issueRepositoryName = "github", "code-scanning"
const issueLabel = "dependency-vulnerability"
const enterpriseReleasesRepositoryOwner, enterpriseReleasesRepositoryName = "github", "enterprise-releases"
const enterpriseReleasesPath = "releases.json"

var supportedEnterpriseReleaseLabel = regexp.MustCompile(`^enterprise-(\d+.\d+)-backport$`)
var issueTitle = regexp.MustCompile(`^.*\[([^\]]+)\]$`)

type argumentsType struct {
	verbose   bool
	dryRun    bool
	debugPath string
}

//go:embed templates
var issueTemplates embed.FS

func parseArguments() argumentsType {
	arguments := argumentsType{}
	flag.BoolVar(&arguments.verbose, "verbose", false, "Enable verbose output.")
	flag.BoolVar(&arguments.dryRun, "dry-run", false, "Enable dry run.")
	flag.StringVar(&arguments.debugPath, "debug-path", "", "A path to output debug files to.")
	flag.Parse()
	return arguments
}

func getGitHubClient(ctx context.Context) (*github.Client, error) {
	var token string
	token, ok := os.LookupEnv("GITHUB_TOKEN")
	if !ok {
		return nil, errors.New("GITHUB_TOKEN environment variable is not set.")
	}

	tokenSource := oauth2.StaticTokenSource(&oauth2.Token{AccessToken: token})
	tokenClient := oauth2.NewClient(ctx, tokenSource)

	return github.NewClient(tokenClient), nil
}

// getSupportedReleases returns the set of GHES releases supported by the repository.
// These are computed by looking at the `enterprise-*-backports` labels available in the repository as well as the enterprise releases file.
func getSupportedReleases(ctx context.Context, gitHubClient *github.Client) ([]string, error) {
	var supportedReleases []string
	labels, _, err := gitHubClient.Issues.ListLabels(ctx, scannedRepositoryOwner, scannedRepositoryName, &github.ListOptions{})
	if err != nil {
		return nil, errors.Wrap(err, "Unable to list labels for repository.")
	}

	releasesFile, _, _, err := gitHubClient.Repositories.GetContents(ctx, enterpriseReleasesRepositoryOwner, enterpriseReleasesRepositoryName, enterpriseReleasesPath, &github.RepositoryContentGetOptions{})
	if err != nil {
		return nil, errors.Wrap(err, "Unable to get releases file.")
	}
	releasesFileContent, err := releasesFile.GetContent()
	if err != nil {
		return nil, errors.Wrap(err, "Unable to get releases file content.")
	}
	var releases map[string]types.EnterpriseRelease
	err = json.Unmarshal([]byte(releasesFileContent), &releases)
	if err != nil {
		return nil, errors.Wrap(err, "Unable to parse releases file.")
	}

	for _, label := range labels {
		matcher := supportedEnterpriseReleaseLabel.FindStringSubmatch(label.GetName())
		if matcher == nil {
			continue
		}
		releases, ok := releases[matcher[1]]
		if !ok {
			continue
		}
		if releases.End == "" {
			continue
		}
		endDate, err := time.Parse("2006-01-02", releases.End)
		if err != nil {
			return nil, errors.Wrap(err, "Unable to parse release end date.")
		}
		if endDate.Before(time.Now()) {
			continue
		}
		supportedReleases = append(supportedReleases, matcher[1])
	}

	// Sort by version number descending.
	sort.Slice(supportedReleases, func(i, j int) bool {
		iVersion, err := version.NewVersion(supportedReleases[i])
		if err != nil {
			log.Fatalf("Unable to parse version %s.", supportedReleases[i])
			return false
		}
		jVersion, err := version.NewVersion(supportedReleases[j])
		if err != nil {
			log.Fatalf("Unable to parse version %s.", supportedReleases[j])
			return false
		}
		return !iVersion.LessThan(jVersion)
	})

	return supportedReleases, nil
}

func grypeScan(ctx context.Context, image string, debugPath string) ([]types.GrypeMatch, error) {
	command := exec.CommandContext(ctx, "go", "run", "github.com/anchore/grype/cmd/grype", "--output", "json", "docker:"+image)
	output, err := command.Output()
	if err != nil {
		if exitError, ok := err.(*exec.ExitError); ok {
			log.Error(string(exitError.Stderr))
		}
		return nil, errors.Wrap(err, "Unable to run Grype scan.")
	}
	if debugPath != "" {
		err := os.WriteFile(debugPath, output, 0644)
		if err != nil {
			return nil, errors.Wrap(err, "Unable to write debug file.")
		}
	}
	report, err := types.ParseGrypeReport(output)
	if err != nil {
		return nil, err
	}
	return report.Matches, nil
}

func getVulnerabilities(ctx context.Context, gitHubClient *github.Client, branch string, debugPath string) (map[string]types.GrypeMatch, error) {
	branchInformation, _, err := gitHubClient.Repositories.GetBranch(ctx, scannedRepositoryOwner, scannedRepositoryName, branch, false)
	if err != nil {
		return nil, errors.Wrap(err, "Unable to get branch.")
	}
	commit := branchInformation.GetCommit().GetSHA()

	fullDebugPath := ""
	if debugPath != "" {
		fullDebugPath = fmt.Sprintf("%s/%s-%s.json", debugPath, branch, commit)
	}

	matches, err := grypeScan(ctx, scannedImage+":"+commit, fullDebugPath)
	if err != nil {
		return nil, errors.Wrap(err, "Unable to run Grype scan.")
	}

	matchesByID := types.GrypeMatchesByID(matches)

	return matchesByID, nil
}

func synchronizeIssues(ctx context.Context, gitHubClient *github.Client, vulnerabilities map[string]types.GrypeMatchWithAffectedVersions, dryRun bool) error {
	issueListOptions := &github.IssueListByRepoOptions{Labels: []string{issueLabel}, ListOptions: github.ListOptions{PerPage: 100}}
	currentIssues := []*github.Issue{}
	for {
		issues, response, err := gitHubClient.Issues.ListByRepo(ctx, issueRepositoryOwner, issueRepositoryName, issueListOptions)
		if err != nil {
			return errors.Wrap(err, "Unable to list issues for repository.")
		}
		currentIssues = append(currentIssues, issues...)
		if response.NextPage == 0 {
			break
		}
		issueListOptions.Page = response.NextPage
	}

	for _, issue := range currentIssues {
		matcher := issueTitle.FindStringSubmatch(issue.GetTitle())
		if matcher == nil {
			return errors.Errorf("Issue title %s did not match the expected format.", issue.GetTitle())
		}
		if _, ok := vulnerabilities[matcher[1]]; !ok {
			log.Infof("Closing issue #%d because it is no longer relevant.", issue.GetNumber())
			if !dryRun {
				_, _, err := gitHubClient.Issues.Edit(ctx, issueRepositoryOwner, issueRepositoryName, issue.GetNumber(), &github.IssueRequest{State: github.String("closed")})
				if err != nil {
					return errors.Wrap(err, "Couldn't mark issue as closed.")
				}
			}
		}
	}
	for vulnerabilityID, vulnerability := range vulnerabilities {
		log.Infof("Handling %s...", vulnerabilityID)
		title := fmt.Sprintf(
			"Vulnerable dependency %s of %s/%s affecting old Enterprise Server branches. [%s]",
			vulnerability.Match.Artifact.Name,
			scannedRepositoryOwner,
			scannedRepositoryName,
			vulnerabilityID,
		)
		tmpls := template.Must(template.ParseFS(issueTemplates, "templates/*.tmpl"))
		tmplData := struct {
			AffectedEnterpriseVersions []string
			Vulnerability              types.GrypeMatchWithAffectedVersions
		}{
			AffectedEnterpriseVersions: vulnerability.AffectedEnterpriseVersions,
			Vulnerability:              vulnerability,
		}
		var issueBody bytes.Buffer
		err := tmpls.ExecuteTemplate(&issueBody, "issue_body.tmpl", tmplData)
		if err != nil {
			return errors.Wrap(err, "Couldn't execute issue template.")
		}
		body := issueBody.String()

		var existingIssue *github.Issue
		for _, issue := range currentIssues {
			matcher := issueTitle.FindStringSubmatch(issue.GetTitle())
			if matcher == nil {
				return errors.Errorf("Issue title %s did not match the expected format.", issue.GetTitle())
			}
			if vulnerabilityID == matcher[1] {
				log.Infof("Found existing issue #%d for %s.", issue.GetNumber(), vulnerabilityID)
				existingIssue = issue
				break
			}
		}
		if existingIssue != nil {
			if existingIssue.GetTitle() != title || existingIssue.GetBody() != body {
				log.Infof("Updating issue #%d for %s...", existingIssue.GetNumber(), vulnerabilityID)
				if !dryRun {
					issue, _, err := gitHubClient.Issues.Edit(ctx, issueRepositoryOwner, issueRepositoryName, existingIssue.GetNumber(), &github.IssueRequest{Title: github.String(title), Body: github.String(body)})
					if err != nil {
						return errors.Wrap(err, "Couldn't update issue.")
					}
					log.Infof("Updated issue #%d.", issue.GetNumber())
				}
			}
			continue
		}
		log.Infof("Creating issue with title \"%s\" and body \"%s\".", title, body)
		if !dryRun {
			labels := []string{issueLabel}
			issue, _, err := gitHubClient.Issues.Create(ctx, issueRepositoryOwner, issueRepositoryName, &github.IssueRequest{Title: github.String(title), Body: github.String(body), Labels: &labels})
			if err != nil {
				return errors.Wrap(err, "Couldn't create issue.")
			}
			log.Infof("Created issue #%d.", issue.GetNumber())
		}
	}
	return nil
}

func realMain() error {
	ctx := context.Background()

	arguments := parseArguments()

	log.SetLevel(log.InfoLevel)
	if arguments.verbose {
		log.SetLevel(log.DebugLevel)
	}

	if arguments.dryRun {
		log.Info("Running in dry-run mode.")
	}

	gitHubClient, err := getGitHubClient(ctx)
	if err != nil {
		return err
	}

	log.Info("Getting default branch...")
	repository, _, err := gitHubClient.Repositories.Get(ctx, scannedRepositoryOwner, scannedRepositoryName)
	if err != nil {
		return errors.Wrap(err, "Unable to get repository.")
	}

	log.Info("Getting supported releases...")
	supportedReleases, err := getSupportedReleases(ctx, gitHubClient)
	if err != nil {
		return err
	}

	log.Info("Calculating baseline vulnerabilities...")
	baselineMatches, err := getVulnerabilities(ctx, gitHubClient, repository.GetDefaultBranch(), arguments.debugPath)
	if err != nil {
		return err
	}

	allVulnerabilities := map[string]types.GrypeMatchWithAffectedVersions{}
	for _, release := range supportedReleases {
		log.Infof("Calculating vulnerabilities for release %s...", release)
		branch := "enterprise-" + release + "-release"
		matches, err := getVulnerabilities(ctx, gitHubClient, branch, arguments.debugPath)
		if err != nil {
			return err
		}
		for id, match := range matches {
			if _, ok := baselineMatches[id]; ok {
				// We use the default branch as a baseline for what vulnerabilities are "fixable".
				// Because we regularly update all our dependencies on the default branch, any vulnerabilities that are still present there likely do not have a version that includes a fix.
				log.Debugf("Ignoring %s because it is present in the default branch.", id)
				continue
			}
			if strings.ToLower(match.Vulnerability.Severity) == "negligible" || strings.ToLower(match.Vulnerability.Severity) == "low" {
				log.Debugf("Ignoring %s because it only has a severity of %s.", id, strings.ToLower(match.Vulnerability.Severity))
				continue
			}
			if _, ok := allVulnerabilities[id]; !ok {
				allVulnerabilities[id] = types.GrypeMatchWithAffectedVersions{
					Match:                      match,
					AffectedEnterpriseVersions: []string{},
				}
			}
			matchAndAffectedVersions := allVulnerabilities[id]
			matchAndAffectedVersions.AffectedEnterpriseVersions = append(matchAndAffectedVersions.AffectedEnterpriseVersions, release)
			allVulnerabilities[id] = matchAndAffectedVersions
		}
	}

	for _, matchAndAffectedVersion := range allVulnerabilities {
		log.Infof("Found vulnerability %s in %s affecting %+v.", matchAndAffectedVersion.Match.Vulnerability.ID, matchAndAffectedVersion.Match.Artifact.Name, matchAndAffectedVersion.AffectedEnterpriseVersions)
	}

	if len(allVulnerabilities) == 0 {
		log.Info("No fixable vulnerabilities found.")
	}

	log.Info("Synchronizing issues...")
	err = synchronizeIssues(ctx, gitHubClient, allVulnerabilities, arguments.dryRun)
	if err != nil {
		return err
	}

	return nil
}

func main() {
	err := realMain()
	if err != nil {
		log.Fatalf("%+v", err)
	}
}
