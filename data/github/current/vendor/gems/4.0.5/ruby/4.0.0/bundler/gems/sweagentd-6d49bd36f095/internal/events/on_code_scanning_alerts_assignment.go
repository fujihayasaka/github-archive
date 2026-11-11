package events

import (
	"context"
	"fmt"
	"math/rand"
	"strconv"
	"strings"

	"github.com/github/feature-management-client-go/vexi/v2"
	"github.com/github/feature-management-client-go/vexi/v2/extensions"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	js "github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
)

func (h *Handler) OnCodeScanningAlertsAssigned(ctx context.Context, event CodeScanningAlertsAssignmentEvent) error {
	// for this event, the actor is the user that set the assignee
	assigner := event.Actor

	var alert_numbers []int64
	for _, alert := range event.Alerts {
		alert_numbers = append(alert_numbers, alert.Number)
	}

	if err := requestctx.AddCodeScanningAlerts(ctx, &requestctx.CtxCodeScanningAlerts{
		RepoID:       event.Repo.ID,
		OwnerID:      event.Repo.OwnerID,
		ActorID:      assigner.ID,
		Assignees:    event.Assignees,
		AlertNumbers: alert_numbers,
	}); err != nil {
		h.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to add code scanning alerts to context")
	}

	logger := h.obsv.LoggerWithTelemetry(ctx)

	actors := []vexi.Actor{
		extensions.NewRepository(strconv.FormatInt(event.Repo.ID, 10)),
		extensions.NewOrganization(strconv.FormatInt(event.Repo.OwnerID, 10)),
	}
	if !h.ffClient.IsEnabled(ctx, featureflags.CopilotSWEAgentIntegrationCodeScanningAlerts, actors...) {
		// do nothing and return early
		logger.Info("Ignoring code scanning alerts because feature flag is not enabled")
		return nil
	}

	app, err := h.appProvider.FindByID(ctx, event.AgentID)
	if err != nil {
		return fmt.Errorf("failed to find app by ID: %w", err)
	}

	gh, err := h.ghFactory.NewClientForRepo(ctx, app, &event)
	if err != nil {
		return fmt.Errorf("failed to create GitHub client: %w", err)
	}

	// Only process events where the actor has write access to the repo
	permission, err := gh.GetUserPermissionsForRepositoryByID(ctx, event.Repo.ID, assigner.Login)
	if err != nil {
		return fmt.Errorf("getting user permissions for repository: %w", err)
	}
	if !permission.Push {
		logger.Info("Ignoring code scanning alerts because actor does not have write access to the repo")
		return nil
	}

	actx, err := gh.GetRepositoryContext(ctx, event.Repo.NodeID)
	if err != nil {
		return fmt.Errorf("failed to get repository context: %w", err)
	}

	repo := actx.Repository
	owner := repo.Owner

	var resources []jobs.AssignmentResource
	for _, alert := range event.Alerts {
		resources = append(resources, jobs.AssignmentResource{
			Type: "code_scanning_alert",
			ID:   strconv.FormatInt(alert.Number, 10),
		})
	}

	// We will always create a new assignment for this event
	useAsyncSessions := h.ffClient.IsEnabledForUserOrRepo(ctx, featureflags.CopilotSWEAgentUseAsyncSessions, assigner.ID, repo.ID)
	assignment := jobs.NewAssignment(owner.GetID(), repo.ID, owner.NodeID, repo.NodeID, owner.Login, repo.Name, useAsyncSessions)
	assignment.AddDetachedResources(resources...)
	assignment, err = h.jobsStore.CreateAssignment(ctx, assignment)
	if err != nil {
		return fmt.Errorf("failed to create assignment: %w", err)
	}

	logger.Info("Assignment created for code scanning alerts",
		kvp.String("job.assignment_id", assignment.ID))

	err = h.onCodeScanningAlertsAssignedBuilder(ctx, gh, assignment, &repo, event, app)
	if err != nil {
		// NewErrUnhandledAssignmentError is used to create a new comment on the
		// issue or PR to inform the user that the assignment was not handled
		// successfully. For this event, we don't have an issue and don't have a
		// PR yet, so we can't do that. We can just log the error and return.
		return fmt.Errorf("failed to handle code scanning alerts assignment: %w", err)
	}
	return nil
}

func (h *Handler) onCodeScanningAlertsAssignedBuilder(
	ctx context.Context, gh github.ClientInterface, assignment *jobs.Assignment, repo *github.GQLRepository, event CodeScanningAlertsAssignmentEvent, app sweagentd.AgenticApp,
) error {
	ctx, span := h.obsv.Tracer.Start(ctx, "events.Handler.onCodeScanningAlertsAssignedBuilder")
	defer span.End()

	jobActor, err := h.getJobActor(ctx, event.Actor)
	if err != nil {
		return fmt.Errorf("failed to get job actor: %w", err)
	}

	// Fetch repository from GitHub API
	ggRepo, err := gh.GetRepositoryByID(ctx, repo.ID)
	if err != nil {
		return goerrors.Errorf("failed to get repository: %w", err)
	}

	alertNumbers := make([]string, len(event.Alerts))
	for i, alert := range event.Alerts {
		alertNumbers[i] = strconv.FormatInt(alert.Number, 10)
	}

	_, job, err := h.jobService.NewJobBuilder(jobs.AgentActionFix, ggRepo, repo.GetDefaultBranch()).
		ForAssignment(assignment).
		WithJobActor(*jobActor).
		WithTrigger().
		WithRequestStartedAt(event.Timestamp).
		WithEvent(js.Event{
			Type:        jobs.EventTypeCodeScanningAlertsAssignment,
			URL:         event.EventUrl,
			Identifiers: alertNumbers,
		}).
		WithRunOptions(jobs.RunOptions{
			RunName: fmt.Sprintf("Applying Code Scanning Autofix on PR #%d", assignment.PullRequestNumber),
		}).
		WithProblemStatementBuilder(func(c context.Context, job *jobs.Job) (jobs.ProblemStatement, error) {
			return buildProblemStatement(event, repo.NameWithOwner)
		}).
		WithFeaturesBuilder(func(c context.Context, j *jobs.Job) jobs.EnvironmentFeatures {
			// TODO: we need to use near sequential number to avoid collisions
			num := 1 + rand.Intn(1000)
			return jobs.EnvironmentFeatures{
				Branch: &jobs.BranchFeature{
					Name: fmt.Sprintf("apply-autofixes-%d", num),
				},
				PullRequest: &jobs.PullRequestFeature{
					TitlePlaceholder: "[WIP] Autofix Code Scanning Alert",
					BodyPlaceholder:  generatePRBodyForCodeScanningAlerts(alertNumbers),
				},
			}
		}).
		WithAgentID(app.AppID()).
		Build(ctx, gh)

	if err != nil {
		return fmt.Errorf("failed to build job: %w", err)
	}

	_, err = h.jobService.QueueJobForExecution(ctx, job)
	if err != nil {
		return fmt.Errorf("failed to queue job: %w", err)
	}

	return nil
}

func generatePRBodyForCodeScanningAlerts(alertNumbers []string) string {
	return fmt.Sprintf("Thanks for assigning these code scanning alerts (%s) to me.\nI'm starting to work on it and will keep this PR's description up to date as I form a plan and make progress.", strings.Join(alertNumbers, ", "))
}

func buildProblemStatement(event CodeScanningAlertsAssignmentEvent, repoNameWithOwner string) (jobs.ProblemStatement, error) {
	diff_ex := `
diff --git a/index.js b/index.js
--- a/index.js
+++ b/index.js
@@ -1 +1,2 @@
+const escape = require('escape-html');
 const express = require('express');
@@ -3,2 +4,2 @@
 const app = express();
-app.get('/', (req, res) => res.send("foo bar"));
\ No newline at end of file
+app.get('/', (req, res) => res.send(" foo bar baz"));
\ No newline at end of file
`

	var sb strings.Builder
	sb.WriteString("\n")
	sb.WriteString("This section lists some code changes.\n")
	sb.WriteString("You can find the code changes in following format\n")
	sb.WriteString("File: <file_path>\n")
	sb.WriteString("Diff:\n")
	sb.WriteString("<diff_content>\n")
	sb.WriteString("\n<diff_content> is base64 encoded string, Below is an example <diff_content> after decoding\n")
	sb.WriteString("\n\n")
	sb.WriteString(diff_ex)
	sb.WriteString("\n\n")
	sb.WriteString("It is possible to have multiple <diff_content> for same <file_path>.\n")
	sb.WriteString("Your goal is to apply the diffs in given files in following steps.\n")
	sb.WriteString("1. Decode base64 encoded <diff_content> to get the diff\n")
	sb.WriteString("2. Apply a <diff_content> for given <file_path>\n")
	sb.WriteString("3. Resolve any conflicts\n")
	sb.WriteString("4. Commit the changes for <file_path>, do not commit any other files!\n")
	sb.WriteString("5. Repeat step 1 to 4 for all the <diff_content> and <file_path>\n")
	sb.WriteString("Do not make any other changes anywhere in the repo, focus only the <diff_content> and <file_path>, only commit given <file_path>\n")
	sb.WriteString("\n")
	alert_links := make([]string, len(event.Alerts))
	for i, alert := range event.Alerts {
		alert_title := alert.Title
		alert_url := alert.Url
		if alert_title != "" && alert_url != "" {
			alert_links[i] = fmt.Sprintf("* [%s](%s)", alert_title, alert_url)
		} else {
			// fallback to just the alert number
			alert_links[i] = fmt.Sprintf("* [/security/code-scanning/%d](https://github.com/%s/security/code-scanning/%d)", alert.Number, repoNameWithOwner, alert.Number)
		}
		sb.WriteString("-- diffs to apply\n")
		for _, file := range alert.SuggestedFix.Files {
			sb.WriteString(fmt.Sprintf("File:%s\n", file.FilePath))
			sb.WriteString(fmt.Sprintf("Diff:\n%s\n", file.DiffContent))
		}
	}
	alert_links_str := strings.Join(alert_links, "\n")
	sb.WriteString("\n")
	sb.WriteString(fmt.Sprintf("In the final PR description add a block at the beginning of the PR but below the summary with section #### Potential fix for alerts #### then list these alerts %s", alert_links_str))
	sb.WriteString("\n Here is an example:\n")
	sb.WriteString("#### Potential fix for alerts ####\n")
	sb.WriteString(alert_links_str)
	sb.WriteString("\n")

	return jobs.ProblemStatement{
		Content:           sb.String(),
		ContentFilterMode: jobs.ProblemStatementContentFilterModeHiddenCharacters,
	}, nil
}
