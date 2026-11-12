// Package onboarding provides functions to create onboarding comments and tips
// for new users of the Copilot coding agent.
package onboarding

import (
	"context"
	_ "embed"
	"errors"
	"net/http"
	"strings"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	gg "github.com/google/go-github/v75/github"
)

// OnboardingComment is the onboarding comment content.
//
//go:embed onboarding_comment.md
var OnboardingComment string

// OnboardingTip is the onboarding tip content.
//
//go:embed onboarding_tip.md
var OnboardingTip string

//go:embed onboarding_prompt.md
var onboardingPrompt string

const (
	featureFlagName    = "copilot_swe_agent_tips_onboarding"
	instructionsPath   = ".github/copilot-instructions.md"
	instructionsDir    = ".github/instructions"
	instructionsSuffix = ".instructions.md"
	agentsPath         = "AGENTS.md"
	claudePath         = "CLAUDE.md"
	geminiPath         = "GEMINI.md"
	maxFilesToCheck    = 5
)

type jobStore interface {
	GetJobForActorOnboarding(ctx context.Context, owner, repo, actor int64) (*jobs.Job, error)
}

type contentsCommenter interface {
	GetContents(ctx context.Context, owner, repo, path string, opts *gg.RepositoryContentGetOptions) (fileContent *gg.RepositoryContent, dirContent []*gg.RepositoryContent, err error)
	CreateComment(ctx context.Context, repoID int64, issueOrPRNumber int, body string) (*gg.IssueComment, error)
}

// CreateOnboardingCommentIfNeeded creates an onboarding comment on the pull request
// if there is just one known job for this repo -- the current job, this should be
// called after the jobs starts.
func CreateOnboardingCommentIfNeeded(
	ctx context.Context,
	ffClient featureflags.Client,
	jobStore jobStore,
	gh contentsCommenter,
	job *jobs.Job,
	repo *gg.Repository) (*gg.IssueComment, error) {
	// If onboarding is enabled, create a comment prompting the user to onboard the repo.
	if !ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureFlagName, job) {
		return nil, nil
	}

	existingJob, err := jobStore.GetJobForActorOnboarding(ctx, job.OwnerID, job.RepoID, job.ActorID)
	if err != nil {
		return nil, goerrors.Errorf("failed to get job for onboarding: %w", err)
	}

	if existingJob != nil {
		// If there is already a job for this repo/actor with an onboarding comment,
		// do not create another onboarding comment.
		return nil, nil
	}

	// - If copilot-instructions already exist and are non-empty, do not create an onboarding comment.
	// - If we fail to check, return the error.
	hasInstructions, err := hasRepoInstructions(ctx, gh, job, repo)
	if err != nil {
		return nil, err
	}
	if hasInstructions {
		return nil, nil
	}

	// Make an onboarding comment with a URI specific to this repository.
	commentMessage := strings.ReplaceAll(OnboardingComment, "{actor}", job.ActorLogin)
	commentMessage, err = SubstituteJobParameters(commentMessage, repo.Owner.GetLogin(), repo.GetName())
	if err != nil {
		return nil, err
	}

	comment, err := gh.CreateComment(ctx, job.RepoID, job.PullRequestNumber, commentMessage)
	if err != nil {
		return nil, goerrors.Errorf("failed to create initial comment on pull request: %w", err)
	}

	return comment, nil
}

// A magic string that is used to deep link users to an issue that onboards
// their repository with Copilot coding agent. This mechanism serves a few
// purposes:
// 1) it keeps our onboarding prompt private from competitors.
// 2) it allows us to change the onboarding prompt even for stale onboarding PRs that have been open a while.
// 3) it prevents users from interfering with our tuned onboarding prompt by adding their own comments.
const onboardingTipMagicString string = "<Onboard this repo>"

// SubstituteOnboardingTipIfEnabled substitutes the onboarding tip magic string
// with the actual onboarding prompt if the feature flag is enabled for the job's
// repo/owner/user.
func SubstituteOnboardingTipIfEnabled(ctx context.Context, ffClient featureflags.Client, job *jobs.Job, problemStatement string) string {
	if !ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureFlagName, job) ||
		!strings.Contains(problemStatement, onboardingTipMagicString) {
		return problemStatement
	}

	// Always substitute the entire magic string with the onboarding prompt.
	// This is intentional in case the user decided to add additional comments.
	// While good intentioned, we'll be running our prompt through evals.
	return onboardingPrompt
}

// SubstituteJobParameters takes a body string and replaces the {repo_owner} and {repo_name}
// placeholders with the actual values.
//
// Returns an error only if the content is invalid due to missing repoOwner or repoName. Strings that are
// unchanged do not return an error.
func SubstituteJobParameters(body, repoOwner, repoName string) (string, error) {
	newBody := strings.ReplaceAll(body, "{repo_owner}", repoOwner)
	newBody = strings.ReplaceAll(newBody, "{repo_name}", repoName)

	if body != newBody && (repoOwner == "" || repoName == "") {
		return "", goerrors.New("repoOwner and repoName cannot be empty")
	}

	return newBody, nil
}

func hasRepoInstructions(ctx context.Context, gh contentsCommenter, job *jobs.Job, repo *gg.Repository) (bool, error) {
	// Check if there are instructions in the repo.
	fileExists, err := fileExistsAndIsNonEmpty(ctx, gh, job, repo, instructionsPath)
	if fileExists || err != nil {
		return fileExists, err
	}

	// Check if there are any .instructions.md files in .github/instructions/ directory.
	// We limit the number of files to check for whitespace to prevent this from taking too long.
	hasInstructionFiles, _, err := hasInstructionFilesInDirectory(ctx, gh, job, repo, instructionsDir, maxFilesToCheck)
	if hasInstructionFiles || err != nil {
		return hasInstructionFiles, err
	}

	// Check if there are AGENTS.md instructions (Codex/OpenAI style).
	fileExists, err = fileExistsAndIsNonEmpty(ctx, gh, job, repo, agentsPath)
	if fileExists || err != nil {
		return fileExists, err
	}

	// Check if there are CLAUDE.md instructions (Claude style).
	fileExists, err = fileExistsAndIsNonEmpty(ctx, gh, job, repo, claudePath)
	if fileExists || err != nil {
		return fileExists, err
	}

	// Check if there are GEMINI.md instructions (Gemini style).
	fileExists, err = fileExistsAndIsNonEmpty(ctx, gh, job, repo, geminiPath)
	if fileExists || err != nil {
		return fileExists, err
	}

	return false, nil
}

func fileExistsAndIsNonEmpty(ctx context.Context, gh contentsCommenter, job *jobs.Job, repo *gg.Repository, filePath string) (bool, error) {
	// See if there is a file or directory at the specified path. GitHub has a single API for both.
	// Get the contents of the directory
	repoContent, _, err := getFileOrDirectoryContent(ctx, gh, job, repo, filePath)

	// If there is no content or an error, return false.
	if repoContent == nil || err != nil {
		return false, err
	}

	// Try to unpack the content as a string.
	fileContent, err := repoContent.GetContent()
	if err != nil {
		return false, err
	}

	// Check if instructions file exists and has non-whitespace content.
	if strings.TrimSpace(fileContent) != "" {
		return true, nil
	}

	return false, nil
}

func getFileOrDirectoryContent(
	ctx context.Context,
	gh contentsCommenter,
	job *jobs.Job,
	repo *gg.Repository,
	filePath string) (fileContent *gg.RepositoryContent, dirContent []*gg.RepositoryContent, err error) {
	// See if there is a file or directory at the specified path. GitHub has a single API for both.
	fileContent, dirContent, err = gh.GetContents(ctx, repo.Owner.GetLogin(), repo.GetName(), filePath, nil)
	if err != nil {
		// Check for a 404. 404 errors indicate that the file does
		// not exist and should not be treated as an error.
		var e *gg.ErrorResponse
		if errors.As(err, &e) &&
			e.Response != nil &&
			e.Response.StatusCode == http.StatusNotFound {
			return nil, nil, nil
		}

		return nil, nil, err
	}

	return fileContent, dirContent, nil
}

// hasInstructionFilesInDirectory recursively searches for any .instructions.md files
// in the specified directory and its subdirectories.
func hasInstructionFilesInDirectory(
	ctx context.Context,
	gh contentsCommenter,
	job *jobs.Job,
	repo *gg.Repository,
	dirPath string,
	maxFilesToCheck int,
) (bool, int, error) {
	// Get the contents of the directory
	_, dirContent, err := getFileOrDirectoryContent(ctx, gh, job, repo, dirPath)
	if err != nil {
		return false, maxFilesToCheck, err
	}

	// If dirContent is nil, this might be a file, not a directory
	if dirContent == nil {
		return false, maxFilesToCheck, nil
	}

	// Check each item in the directory
	for _, item := range dirContent {
		// If we've exceeded our file check limit, return false
		if maxFilesToCheck <= 0 {
			return false, 0, nil
		}

		if item.Name == nil || item.Type == nil {
			continue
		}

		itemName := *item.Name
		itemType := *item.Type

		hasInstructions := false
		var err error
		hasInstructions, maxFilesToCheck, err = fileOrDirectoryHasInstructions(ctx, gh, job, repo, itemName, itemType, maxFilesToCheck, dirPath)
		if err != nil {
			return false, maxFilesToCheck, err
		}

		// If we found instructions, return immediately
		if hasInstructions {
			return true, maxFilesToCheck, nil
		}
	}

	return false, maxFilesToCheck, nil
}

func fileOrDirectoryHasInstructions(
	ctx context.Context,
	gh contentsCommenter,
	job *jobs.Job,
	repo *gg.Repository,
	itemName,
	itemType string,
	maxFilesToCheck int,
	dirPath string) (bool, int, error) {
	if itemType == "dir" {
		maxFilesToCheck--

		// Recursively search subdirectories
		subDirPath := dirPath + "/" + itemName
		hasFiles, maxFilesToCheck, err := hasInstructionFilesInDirectory(ctx, gh, job, repo, subDirPath, maxFilesToCheck)
		if err != nil {
			return false, maxFilesToCheck, err
		}

		return hasFiles, maxFilesToCheck, nil
	}

	// If the item is a file and the file matches our pattern (ends with .instructions.md)
	// check if it's non-empty.
	if itemType == "file" && strings.HasSuffix(itemName, instructionsSuffix) {
		maxFilesToCheck--

		// Check if the file has non-empty content
		itemPath := dirPath + "/" + itemName
		hasContent, err := fileExistsAndIsNonEmpty(ctx, gh, job, repo, itemPath)
		if err != nil {
			return false, maxFilesToCheck, err
		}
		if hasContent {
			return true, maxFilesToCheck, nil
		}
	}

	return false, maxFilesToCheck, nil
}
