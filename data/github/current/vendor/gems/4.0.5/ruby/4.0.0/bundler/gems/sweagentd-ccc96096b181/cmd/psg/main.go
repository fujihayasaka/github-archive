package main

import (
	"context"
	"flag"
	"fmt"
	"math"
	"net/url"
	"os"
	"strconv"
	"strings"

	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobutils"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/problemstatement"
	gg "github.com/google/go-github/v75/github"
)

var (
	uri      = flag.String("url", "", "The full URL of the issue (for fix) or pull request (for fix-comment).")
	addTrue  = flag.Bool("add-true", false, "Add the test case to the internal/jobexecutor/testdata/evals/should-wake-true testdata directory.")
	addFalse = flag.Bool("add-false", false, "Add the test case to the internal/jobexecutor/testdata/evals/should-wake-false testdata directory.")
	app      = flag.String("app", "copilot-swe-agent", "The app login of the copilot app. [bot] will be appended to make the bot login.")
	nwo      = flag.String("nwo", "github/sweagentd", "Required. The repository name with owner in the format 'owner/repo'.")
	number   = flag.Int("number", 0, "The issue number (for fix) or the pull request number (for fix-comment).")
)

func main() {
	flag.Parse()

	token := os.Getenv("GITHUB_TOKEN")
	if err := run(context.Background(), token, *app, *uri, *nwo, *number); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}

func run(ctx context.Context, token, app, uri, nwo string, number int) error {
	if token == "" {
		return fmt.Errorf("GITHUB_TOKEN is required")
	}

	iurl, err := getIssueUrl(uri, nwo, number)
	if err != nil {
		return fmt.Errorf("getting issue url: %w", err)
	}

	if app == "" {
		return fmt.Errorf("app is required")
	}

	// ensure the format "app[bot]"
	app = strings.TrimSuffix(app, "[bot]")
	bot := fmt.Sprintf("%s[bot]", app)

	obsv := observability.NewNoopExporters()
	factory, err := github.NewTestClientFactory(obsv, "", "", app, bot, nil)
	if err != nil {
		return fmt.Errorf("creating test client factory: %w", err)
	}

	// App Provider
	copilotApp := agenticapp.NewCopilot(123, nil, "copilot", 123, "copilot-swe-agent[bot]", "", "", "", "")
	appProvider := agenticapp.NewProvider(copilotApp, nil)

	parts := strings.Split(nwo, "/")
	if len(parts) != 2 {
		return fmt.Errorf("nwo must be in the format 'owner/repo'")
	}
	ownerName, repoName := parts[0], parts[1]
	// Use 0 as the user ID here is temporary until we fully rollout the feature flag
	gh, err := factory.NewClientFromRepoName(ctx, copilotApp, repoName, ownerName, 0)
	if err != nil {
		return fmt.Errorf("creating github client: %w", err)
	}

	ps, err := generateProblemStatement(ctx, obsv, gh, iurl, appProvider)
	if err != nil {
		return fmt.Errorf("generating problem statement: %w", err)
	}

	fmt.Println(ps.Content)

	if *addTrue {
		if err := addTestCase(iurl, ps, true); err != nil {
			return fmt.Errorf("adding test case: %w", err)
		}
	}
	if *addFalse {
		if err := addTestCase(iurl, ps, false); err != nil {
			return fmt.Errorf("adding test case: %w", err)
		}
	}

	return nil
}

func generateProblemStatement(ctx context.Context, obsv observability.Exporters, gh github.ClientInterface, iurl issueUrl, appProvider *agenticapp.Provider) (*jobs.ProblemStatement, error) {
	u, err := gh.GetAuthenticatedUser(ctx)
	if err != nil {
		return nil, fmt.Errorf("getting authenticated user: %w", err)
	}

	owner := iurl.Owner
	repo := iurl.Repo
	number := iurl.Number

	r, err := gh.GetRepository(ctx, owner, repo)
	if err != nil {
		return nil, fmt.Errorf("getting repository: %w", err)
	}

	job := getJob(r, u, 1)

	issue, err := gh.GetIssue(ctx, owner, repo, number)
	if err != nil {
		return nil, fmt.Errorf("getting issue: %w", err)
	}

	var ps jobs.ProblemStatement

	// if the issue is a pull request and we have a comment ID or review ID,
	// we'll use that to determine which comments and reviews to consider "old"
	// otherwise, we'll just split the comments and reviews in half and add
	// half to the old job so the first half of the comments and reviews show
	// up as "old" in the problem statement and the second half show up as "new"
	if issue.IsPullRequest() {
		actx, err := gh.GetPullRequestContext(ctx, *r.NodeID, *issue.Number, appProvider.IsAgenticActor)
		if err != nil {
			return nil, fmt.Errorf("getting pull request context: %w", err)
		}

		var publishTime int64

		if iurl.CommentID != 0 {
			comment := actx.PullRequest.CommentByID(iurl.CommentID)
			if comment == nil {
				return nil, fmt.Errorf("comment not found: %d", iurl.CommentID)
			}
			publishTime = comment.PublishedAt.Unix()
		} else if iurl.ReviewID != 0 {
			review := actx.PullRequest.ReviewByID(iurl.ReviewID)
			job.ReviewIDs = append(job.ReviewIDs, iurl.ReviewID)
			if review == nil {
				return nil, fmt.Errorf("review not found: %d", iurl.ReviewID)
			}
			// Use the review builder for direct review links
			ps, err = problemstatement.NewReviewBuilder(obsv, actx, job, iurl.ReviewID, noopAuthorResolver{}, appProvider).Build(ctx)
			if err != nil {
				return nil, fmt.Errorf("building problem statement for review: %w", err)
			}
			return &ps, nil
		} else if iurl.ReviewCommentID != 0 {
			job.ReviewIDs = append(job.ReviewIDs, iurl.ReviewCommentID)
			reviewComment := actx.PullRequest.ReviewCommentByID(iurl.ReviewCommentID)
			if reviewComment == nil {
				return nil, fmt.Errorf("review comment not found: %d", iurl.ReviewCommentID)
			}
			publishTime = reviewComment.PublishedAt.Unix()

			// If this is a review comment reply, use the review reply builder
			if reviewComment.ReplyTo != nil {
				reviewID := reviewComment.PullRequestReview.GetID()
				ps, err = problemstatement.NewReviewBuilder(obsv, actx, job, reviewID, noopAuthorResolver{}, appProvider).Build(ctx)
				if err != nil {
					return nil, fmt.Errorf("building problem statement for review reply: %w", err)
				}
				return &ps, nil
			}
		}

		oldJob := getJob(r, u, 0)

		if actx.PullRequest.Comments.Len() > 1 {
			if iurl.CommentID != 0 {
				for _, comment := range actx.PullRequest.Comments.Nodes {
					if comment.GetID() == iurl.CommentID {
						break
					}
					oldJob.CommentIDs = append(oldJob.CommentIDs, comment.GetID())
				}
			} else if publishTime != 0 {
				for _, comment := range actx.PullRequest.Comments.Nodes {
					if comment.PublishedAt.Unix() >= publishTime {
						break
					}
					oldJob.CommentIDs = append(oldJob.CommentIDs, comment.GetID())
				}
			} else {
				half := int(math.Ceil(float64(actx.PullRequest.Comments.Len()) / 2))
				for _, comment := range actx.PullRequest.Comments.Nodes[:half] {
					oldJob.CommentIDs = append(oldJob.CommentIDs, comment.GetID())
				}
			}
		}
		if actx.PullRequest.Reviews.Len() > 1 {
			if iurl.ReviewID != 0 {
				for _, review := range actx.PullRequest.Reviews.Nodes {
					if review.GetID() == iurl.ReviewID {
						break
					}
					oldJob.ReviewIDs = append(oldJob.ReviewIDs, review.GetID())
				}
			} else if publishTime != 0 {
				for _, review := range actx.PullRequest.Reviews.Nodes {
					if review.PublishedAt.Unix() >= publishTime {
						break
					}
					oldJob.ReviewIDs = append(oldJob.ReviewIDs, review.GetID())
				}
			} else {
				half := int(math.Ceil(float64(actx.PullRequest.Reviews.Len()) / 2))
				for _, review := range actx.PullRequest.Reviews.Nodes[:half] {
					oldJob.ReviewIDs = append(oldJob.ReviewIDs, review.GetID())
				}
			}
		}

		jobutils.AddUnprocessedCommentsAndReviewsToJob(gh, actx, []*jobs.Job{oldJob}, job, appProvider.IsAgenticActor)

		ps, err = problemstatement.NewPullRequestBuilder(obsv, actx, job, noopAuthorResolver{}, appProvider).Build(ctx)
		if err != nil {
			return nil, fmt.Errorf("building problem statement for pull request: %w", err)
		}
	} else {
		actx, err := gh.GetIssueContext(ctx, *r.NodeID, *issue.Number, appProvider.IsAgenticActor)
		if err != nil {
			return nil, fmt.Errorf("getting issue context: %w", err)
		}

		ps, err = problemstatement.NewIssueBuilder(obsv, gh, actx, job.AgentID, noopAuthorResolver{}, appProvider).Build(ctx)
		if err != nil {
			return nil, fmt.Errorf("building problem statement for issue: %w", err)
		}
	}

	return &ps, nil
}

func getJob(repo *gg.Repository, user *gg.User, id int) *jobs.Job {
	return &jobs.Job{
		ID:           fmt.Sprintf("job-%d", id),
		AssignmentID: "assignment-id",
		RepoID:       *repo.ID,
		OwnerID:      *repo.Owner.ID,
		RepoNodeID:   *repo.NodeID,
		OwnerNodeID:  *repo.Owner.NodeID,
		ActorID:      *user.ID,
		ActorLogin:   *user.Login,
	}
}

type issueUrl struct {
	Owner           string
	Repo            string
	Number          int
	CommentID       int64
	ReviewID        int64
	ReviewCommentID int64
}

func getIssueUrl(uri, nwo string, number int) (issueUrl, error) {
	var err error
	var iurl issueUrl

	if uri == "" {
		if nwo == "" {
			return issueUrl{}, fmt.Errorf("url or nwo is required")
		}

		parts := strings.Split(nwo, "/")
		if len(parts) != 2 {
			return issueUrl{}, fmt.Errorf("nwo must be in the format 'owner/repo'")
		}
		owner := parts[0]
		repo := parts[1]

		if repo == "" || owner == "" {
			return issueUrl{}, fmt.Errorf("nwo must be in the format 'owner/repo'")
		}

		if number == 0 {
			return issueUrl{}, fmt.Errorf("url or number is required")
		}

		return issueUrl{
			Owner:  owner,
			Repo:   repo,
			Number: number,
		}, nil
	}

	iurl, err = parseUrl(uri)
	if err != nil {
		return issueUrl{}, err
	}

	return iurl, nil
}

// parseUrl parses the URL and returns the owner, repo, number, comment ID, review ID, and review comment ID.
// Examples:
//   - https://github.com/github/mcv3-boot/pull/7480#issuecomment-2798144602 (issue comment)
//   - https://github.com/github/padawan-testing/pull/166#discussion_r2053292243 (review comment - will use review reply builder if it's a reply)
//   - https://github.com/github/sweagentd/pull/1230#pullrequestreview-2781660663 (pull request review)
func parseUrl(uri string) (issueUrl, error) {
	u, err := url.Parse(uri)
	if err != nil {
		return issueUrl{}, fmt.Errorf("parsing url: %w", err)
	}

	parts := strings.Split(u.Path, "/")
	if len(parts) != 5 {
		return issueUrl{}, fmt.Errorf("url must be in the format '/:owner/:repo/issues|pull/:number'")
	}
	owner := parts[1]
	repo := parts[2]
	issueOrPull := parts[3]
	numberStr := parts[4]
	if issueOrPull != "issues" && issueOrPull != "pull" {
		return issueUrl{}, fmt.Errorf("url must be in the format '/:owner/:repo/issues|pull/:number'")
	}
	number, err := strconv.Atoi(numberStr)
	if err != nil {
		return issueUrl{}, fmt.Errorf("parsing number: %w", err)
	}

	var commentID int64
	var reviewID int64
	var reviewCommentID int64

	if u.Fragment != "" {
		switch {
		case strings.HasPrefix(u.Fragment, "issuecomment-"):
			commentID, err = strconv.ParseInt(strings.TrimPrefix(u.Fragment, "issuecomment-"), 10, 64)
		case strings.HasPrefix(u.Fragment, "pullrequestreview-"):
			reviewID, err = strconv.ParseInt(strings.TrimPrefix(u.Fragment, "pullrequestreview-"), 10, 64)
		case strings.HasPrefix(u.Fragment, "discussion_r"):
			reviewCommentID, err = strconv.ParseInt(strings.TrimPrefix(u.Fragment, "discussion_r"), 10, 64)
		}
	}
	if err != nil {
		// just ignore the error
	}

	iurl := issueUrl{
		Owner:           owner,
		Repo:            repo,
		Number:          number,
		CommentID:       commentID,
		ReviewID:        reviewID,
		ReviewCommentID: reviewCommentID,
	}

	return iurl, nil
}

func addTestCase(iurl issueUrl, ps *jobs.ProblemStatement, wake bool) error {
	testdataDir := fmt.Sprintf("internal/jobexecutor/testdata/evals/should-wake-%t", wake)

	var comment string
	if iurl.CommentID != 0 {
		comment = fmt.Sprintf("_comment_%d", iurl.CommentID)
	} else if iurl.ReviewID != 0 {
		comment = fmt.Sprintf("_review_%d", iurl.ReviewID)
	} else if iurl.ReviewCommentID != 0 {
		comment = fmt.Sprintf("_reviewcomment_%d", iurl.ReviewCommentID)
	}

	fileName := fmt.Sprintf("%s_%s_%d%s.txt", iurl.Owner, iurl.Repo, iurl.Number, comment)
	filePath := fmt.Sprintf("%s/%s", testdataDir, fileName)

	f, err := os.Create(filePath)
	if err != nil {
		return fmt.Errorf("creating test case file: %w", err)
	}
	defer f.Close()

	if _, err := f.WriteString(ps.Content); err != nil {
		return fmt.Errorf("writing test case file: %w", err)
	}

	return nil
}

// noopAuthorResolver is an AuthorResolver that returns the login as-is, since we don't expect this psg code to run on proxima or to have tenant awareness.
type noopAuthorResolver struct{}

func (n noopAuthorResolver) Resolve(ctx context.Context, userID uint64, login string) (string, error) {
	return login, nil
}
