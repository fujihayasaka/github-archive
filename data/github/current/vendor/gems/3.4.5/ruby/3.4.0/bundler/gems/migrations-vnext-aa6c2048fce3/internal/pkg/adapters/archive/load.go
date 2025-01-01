// Package archive contains the logic for loading resources from an archive and writing them to a DAG and object storage for further processing.
package archive

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"maps"
	"math/rand"
	"os"
	"path/filepath"
	"slices"
	"sort"
	"strconv"
	"strings"
	"syscall"

	"github.com/Azure/azure-storage-blob-go/azblob"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/blobstore"
	"github.com/github/migrations-vnext/internal/pkg/dag"
	"github.com/github/migrations-vnext/internal/pkg/keys"
	"github.com/github/migrations-vnext/internal/pkg/resource"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/google/uuid"
)

const (
	// defaultMaxIssueEventsPerBatch is the default maximum number of issue events that can be in a batch
	defaultMaxIssueEventsPerBatch = 100
	// maxRepoLabelsPerBatch is the maximum number of labels for a repository that can be in
	// a batch.
	maxRepoLabelsPerBatch = 100
	// maxMilestonesPerBatch is the maximum number of milestones that can be in
	// a batch.
	maxMilestonesPerBatch = 100
	// maxReactionsPerBatch is the maximum number of reactions for one subject that can
	// be in a batch.
	maxReactionsPerBatch = 100
	// maxCloseRefsPerBatch is the maximum number of close issue references that can
	// be in a batch.
	maxCloseRefsPerBatch = 100
)

type (
	// Loader is a struct that contains the logic for loading resources from an archive and writing them to a DAG
	// and object storage for further processing.
	Loader struct {
		defaultUserID          int64
		rootPath               string
		shuffleResources       bool
		allowedOrgs            []string
		manager                dag.Manager
		allowedResources       map[resource.Type]struct{}
		maxIssueEventsPerBatch int
		enterpriseID           int64
		logger                 log.Logger
		sasGenerator           blobstore.SASGenerator
	}
)

// NewLoader creates a new Loader instance with the provided options.
func NewLoader(opts ...Option) *Loader {
	loader := &Loader{maxIssueEventsPerBatch: defaultMaxIssueEventsPerBatch}
	for _, opt := range opts {
		opt(loader)
	}
	return loader
}

// ToDAG loads resources from an archive and writes the resource IDs and their dependencies to the DAG.
// Resource payloads are written to the object store using its resource ID as the key.
func (l *Loader) ToDAG() error {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Load resources from the archive
	// TODO: to avoid memory issues we should process the resources in batches and write them to the DAG
	//      as we process them to avoid keeping all the resources in memory
	resources, err := l.Resources()
	if err != nil {
		return fmt.Errorf("error loading resources: %w", err)
	}

	// Randomize the order of the resources to simulate out-of-order loading
	// Create a new random source using the seed
	if l.shuffleResources {
		resources = shuffleResources(resources)
	}

	// Iterate over the resources and add store them.
	// This will add them to the DAG and store their payloads in the
	// object store (if needed).
	for _, r := range resources {
		// create migration context with enterprise id
		r.MigrationContext = &v1.MigrationContext{EnterpriseId: l.enterpriseID, AdminUserId: l.defaultUserID}
		// add resource
		if err := l.manager.AddResource(ctx, r); err != nil {
			l.logger.WithError(err).Error("failed to add resource to DAG", kvp.Any("resource", r))
			return fmt.Errorf("error storing resource: %w", err)
		}
	}

	return nil
}

// Resources loads resources from an archive and returns them as a slice of v1.Resource.
//
// root - the path to the root of the archive
// logger - the logger to use
func (l *Loader) Resources() ([]*v1.Resource, error) {
	collector := NewResourceCollector()

	// Load organizations
	orgs, err := l.orgs(collector)
	if err != nil {
		return nil, fmt.Errorf("could not load orgs: %w", err)
	}

	// Load users
	firstOrg, ok := orgs[0].Resource.(*v1.Resource_Organization)
	if !ok {
		return nil, fmt.Errorf("error loading first organization: %w", err)
	}
	err = l.users(firstOrg.Organization.ResourceId, collector)
	if err != nil {
		return nil, fmt.Errorf("error loading users: %w", err)
	}

	// Load teams
	err = l.teams(collector)
	if err != nil {
		return nil, fmt.Errorf("error loading teams: %w", err)
	}

	// Load repositories
	err = l.repositories(collector)
	if err != nil {
		return nil, fmt.Errorf("error loading repositories: %w", err)
	}

	// Load protected branches
	err = l.protectedBranches(collector)
	if err != nil {
		return nil, fmt.Errorf("error loading protected branches: %w", err)
	}

	// Load attachments
	resourcesWithAttachments, err := l.attachments(collector)
	if err != nil {
		return nil, fmt.Errorf("error loading attachments: %w", err)
	}

	// Load issues
	milestoneToIssues, err := l.issues(resourcesWithAttachments, collector)
	if err != nil {
		return nil, fmt.Errorf("error loading issues: %w", err)
	}

	// Load pull requests
	milestonesToPRs, err := l.pullRequests(resourcesWithAttachments, collector)
	if err != nil {
		return nil, fmt.Errorf("error loading pull requests: %w", err)
	}

	// Load pull request review threads
	pullRequestReviewThreads, err := l.pullRequestReviewThreads()
	if err != nil {
		return nil, fmt.Errorf("error loading pull request review threads: %w", err)
	}

	// Load pull request review comments
	pullRequestReviewComments, err := l.pullRequestReviewComments(resourcesWithAttachments, collector)
	if err != nil {
		return nil, fmt.Errorf("error loading pull request review comments: %w", err)
	}

	// Load pull request reviews
	err = l.pullRequestReviews(pullRequestReviewThreads, pullRequestReviewComments, resourcesWithAttachments, collector)
	if err != nil {
		return nil, fmt.Errorf("error loading pull request reviews: %w", err)
	}

	// Load issue comments
	err = l.issueComments(resourcesWithAttachments, collector)
	if err != nil {
		return nil, fmt.Errorf("error loading issue comments: %w", err)
	}

	// Load issue events
	err = l.issueEvents(collector)
	if err != nil {
		return nil, fmt.Errorf("error loading issue events: %w", err)
	}

	// Load milestones
	err = l.milestones(mergeMapsAndDedup(milestoneToIssues, milestonesToPRs), collector)
	if err != nil {
		return nil, fmt.Errorf("error loading milestones: %w", err)
	}

	// Load projects
	err = l.projects(collector)
	if err != nil {
		return nil, fmt.Errorf("error loading projects: %w", err)
	}

	// Load commit comments
	err = l.commitComments(collector)
	if err != nil {
		return nil, fmt.Errorf("error loading commit comments: %w", err)
	}

	// Load releases
	err = l.releases(collector)
	if err != nil {
		return nil, fmt.Errorf("error loading releases: %w", err)
	}

	return collector.GetResources(), nil
}

func (l *Loader) orgs(c *ResourceCollector) ([]*v1.Resource, error) {
	if !l.resourceTypeAllowed(resource.TypeOrganization) {
		return nil, nil
	}

	orgs, err := loadResourceFiles[Organization](l.rootPath, "organizations")
	if err != nil {
		return nil, fmt.Errorf("failed to load organization files: %w", err)
	}
	if len(orgs) == 0 {
		return nil, errors.New("no organizations to load")
	}

	var organizations, organizationsSettings []*v1.Resource
	for i := range orgs {
		// If allowedOrgs is empty, we allow all orgs, otherwise we only allow the orgs in allowedOrgs
		if len(l.allowedOrgs) > 0 && !slices.Contains(l.allowedOrgs, orgs[i].Login) {
			continue
		}
		p, err := orgs[i].ToV1Organization()
		if err != nil {
			return nil, fmt.Errorf("error converting organization to v1: %w", err)
		}
		organizations = append(organizations, &v1.Resource{Resource: &v1.Resource_Organization{Organization: p}})
		organizationsSettings = append(organizationsSettings, &v1.Resource{Resource: &v1.Resource_InitialOrganizationSettings{InitialOrganizationSettings: orgs[i].ToV1InitialOrganizationSettings()}})
	}

	c.AddAll(organizations)
	c.AddAll(organizationsSettings)
	return organizations, nil
}

func (l *Loader) users(orgID string, c *ResourceCollector) error {
	if !l.resourceTypeAllowed(resource.TypeUser) {
		return nil
	}

	users, err := loadResourceFiles[User](l.rootPath, "users")
	if err != nil {
		return fmt.Errorf("failed to load user files: %w", err)
	}
	bots, err := loadResourceFiles[User](l.rootPath, "bots")
	if err != nil {
		return fmt.Errorf("failed to load bot files: %w", err)
	}
	users = append(users, bots...)

	var mannequins []*v1.Resource
	for i := range users {
		p, err := users[i].ToV1Mannequin(orgID)
		if err != nil {
			return fmt.Errorf("error converting user to v1: %w", err)
		}
		if p.ResourceId == "" {
			l.logger.Warn("user resource is empty, skipping", kvp.Any("resource", users[i]))
			continue
		}
		mannequins = append(mannequins, &v1.Resource{Resource: &v1.Resource_Mannequin{Mannequin: p}})
	}
	c.AddAll(mannequins)
	return nil
}

func (l *Loader) teams(c *ResourceCollector) error {
	if !l.resourceTypeAllowed(resource.TypeTeam) {
		return nil
	}

	ts, err := loadResourceFiles[Team](l.rootPath, "teams")
	if err != nil {
		return fmt.Errorf("failed to load team files: %w", err)
	}

	var teams []*v1.Resource
	for i := range ts {
		p, err := ts[i].ToV1Team()
		if err != nil {
			return fmt.Errorf("error converting team to v1: %w", err)
		}
		teams = append(teams, &v1.Resource{Resource: &v1.Resource_Team{Team: p}})
	}
	c.AddAll(teams)
	return nil
}

func (l *Loader) repositories(c *ResourceCollector) error {
	if !l.resourceTypeAllowed(resource.TypeRepository) {
		return nil
	}

	repos, err := loadResourceFiles[Repository](l.rootPath, "repositories")
	if err != nil {
		return fmt.Errorf("failed to load repository files: %w", err)
	}

	var repositories, batches, settings, actionsSettings []*v1.Resource
	for i := range repos {
		p, err := repos[i].ToV1Repository()
		if err != nil {
			return fmt.Errorf("error converting repo to v1: %w", err)
		}
		repositories = append(repositories, &v1.Resource{Resource: &v1.Resource_Repository{Repository: p}})
		settings = append(settings, &v1.Resource{Resource: &v1.Resource_InitialRepositorySettings{InitialRepositorySettings: repos[i].ToV1InitialRepositorySettings()}})
		actionsSettings = append(actionsSettings, &v1.Resource{Resource: &v1.Resource_InitialActionsSettings{InitialActionsSettings: repos[i].ToV1InitialActionsSettings()}})

		if !l.resourceTypeAllowed(resource.TypeLabel) {
			continue
		}

		allLabels := repos[i].ToV1RepositoryLabels()
		if len(allLabels) == 0 {
			continue
		}

		repoBatches, err := prepareRepositoryLabelsBatches(p.ResourceId, allLabels, maxRepoLabelsPerBatch)
		if err != nil {
			return fmt.Errorf("error preparing repo label batches: %w", err)
		}

		for _, b := range repoBatches {
			batches = append(batches, &v1.Resource{Resource: &v1.Resource_RepositoryLabelsBatch{RepositoryLabelsBatch: b}})
		}
	}
	c.AddAll(repositories)
	c.AddAll(batches)
	c.AddAll(settings)
	c.AddAll(actionsSettings)
	return nil
}

func (l *Loader) protectedBranches(c *ResourceCollector) error {
	if !l.resourceTypeAllowed(resource.TypeProtectedBranch) {
		return nil
	}

	branchSettings, err := loadResourceFiles[ProtectedBranch](l.rootPath, "protected_branches")
	if err != nil {
		return fmt.Errorf("failed to load protected branches files: %w", err)
	}

	var protectedBranches []*v1.Resource
	for i := range branchSettings {
		b, err := branchSettings[i].ToV1ProtectedBranch()
		if err != nil {
			return fmt.Errorf("error converting protected branch to v1: %w", err)
		}
		protectedBranches = append(protectedBranches, &v1.Resource{Resource: &v1.Resource_ProtectedBranch{ProtectedBranch: b}})
	}
	c.AddAll(protectedBranches)
	return nil
}

func (l *Loader) attachments(c *ResourceCollector) (map[string][]string, error) {
	if !l.resourceTypeAllowed(resource.TypeAttachment) {
		return make(map[string][]string), nil
	}
	if !l.resourceTypeAllowed(resource.TypeAttachment) {
		return make(map[string][]string), nil
	}

	ats, err := loadResourceFiles[Attachment](l.rootPath, "attachments")
	if err != nil {
		return nil, fmt.Errorf("failed to get attachment files: %w", err)
	}

	var attachments []*v1.Resource
	// Maps resourceIDs to a list of attachment resource ids (urls)
	resourceToAttachments := make(map[string][]string)
	for i := range ats {
		a, err := ats[i].ToV1Attachment()
		if err != nil {
			return nil, fmt.Errorf("error converting attachment to v1: %w", err)
		}
		attachments = append(attachments, &v1.Resource{Resource: &v1.Resource_Attachment{Attachment: a}})
		resourceToAttachments[a.ReferencedByResource] = append(resourceToAttachments[a.ReferencedByResource], a.ResourceId)
	}

	c.AddAll(attachments)
	return resourceToAttachments, nil
}

func (l *Loader) issues(resourcesWithAttachments map[string][]string, c *ResourceCollector) (map[string][]string, error) {
	if !l.resourceTypeAllowed(resource.TypeIssue) {
		return make(map[string][]string), nil
	}

	iss, err := loadResourceFiles[Issue](l.rootPath, "issues")
	if err != nil {
		return nil, fmt.Errorf("failed to get issue files: %w", err)
	}

	var issues, issueLabels, reactionsBatches []*v1.Resource
	milestoneToIssue := make(map[string][]string)
	for i := range iss {
		p, err := iss[i].ToV1Issue()
		if err != nil {
			return nil, fmt.Errorf("error converting issue to v1: %w", err)
		}
		if attachments, ok := resourcesWithAttachments[p.ResourceId]; ok {
			p.AttachmentResourceIds = attachments
		}
		issues = append(issues, &v1.Resource{Resource: &v1.Resource_Issue{Issue: p}})

		if iss[i].Milestone != "" {
			milestone, err := keys.ToMilestoneKey(iss[i].Milestone)
			if err != nil {
				return nil, fmt.Errorf("error converting milestone key: %w", err)
			}
			milestoneToIssue[milestone.String()] = append(milestoneToIssue[milestone.String()], p.ResourceId)
		}
		if len(iss[i].Reactions) > 0 && l.resourceTypeAllowed(resource.TypeReactions) {
			reactions := iss[i].Reactions.ExtractV1Reactions()
			batches := prepareReactionsBatches(reactions, p.ResourceId, v1.ReactionSubjectType_REACTION_SUBJECT_TYPE_ISSUE, maxReactionsPerBatch)
			for _, b := range batches {
				reactionsBatches = append(reactionsBatches, &v1.Resource{
					Resource: &v1.Resource_ReactionsBatch{
						ReactionsBatch: b,
					},
				})
			}
		}

		if !l.resourceTypeAllowed(resource.TypeLabel) || len(iss[i].Labels) == 0 {
			continue
		}

		issueLabels = append(issueLabels, &v1.Resource{
			Resource: &v1.Resource_IssueLabelsBatch{
				IssueLabelsBatch: &v1.IssueLabelsBatch{
					ResourceId:       fmt.Sprintf("issue-labels-%s-%s", p.ResourceId, uuid.New().String()),
					IssueResourceId:  p.ResourceId,
					LabelResourceIds: iss[i].Labels,
				},
			},
		})
	}
	c.AddAll(issues)
	c.AddAll(issueLabels)
	c.AddAll(reactionsBatches)
	return milestoneToIssue, nil
}

func (l *Loader) pullRequests(resourcesWithAttachments map[string][]string, c *ResourceCollector) (map[string][]string, error) {
	if !l.resourceTypeAllowed(resource.TypePullRequest) {
		return make(map[string][]string), nil
	}

	prs, err := loadResourceFiles[PullRequest](l.rootPath, "pull_requests")
	if err != nil {
		return nil, fmt.Errorf("failed to get pr files: %w", err)
	}

	var pullRequests, reactionsBatches, closeIssueReferenceBatches []*v1.Resource
	var closeIssueReferences []*v1.CloseIssueReference
	prToIssue := make(map[string][]string)
	for i := range prs {
		if prs[i].IsFromFork() {
			l.logger.Info("skipping PR from fork as they are not supported for now", kvp.String("pr", prs[i].URL))
			continue
		}
		p, err := prs[i].ToV1PullRequest()
		if err != nil {
			return nil, fmt.Errorf("error converting pr to v1: %w", err)
		}
		if attachments, ok := resourcesWithAttachments[p.ResourceId]; ok {
			p.AttachmentResourceIds = attachments
		}
		pullRequests = append(pullRequests, &v1.Resource{Resource: &v1.Resource_PullRequest{PullRequest: p}})

		if len(prs[i].Reactions) > 0 && l.resourceTypeAllowed(resource.TypeReactions) {
			reactions := prs[i].Reactions.ExtractV1Reactions()
			batches := prepareReactionsBatches(reactions, p.ResourceId, v1.ReactionSubjectType_REACTION_SUBJECT_TYPE_ISSUE, maxReactionsPerBatch)
			for _, b := range batches {
				reactionsBatches = append(reactionsBatches, &v1.Resource{
					Resource: &v1.Resource_ReactionsBatch{
						ReactionsBatch: b,
					},
				})
			}
		}
		refs := prs[i].ExtractV1CloseIssueReferences()
		closeIssueReferences = append(closeIssueReferences, refs...)

		if prs[i].Milestone != "" {
			milestone, err := keys.ToMilestoneKey(prs[i].Milestone)
			if err != nil {
				// TODO: the acme fixtures contains a milestone key that is not a valid milestone key
				l.logger.Error("error converting milestone key", kvp.Err(err))
				continue
			}
			prToIssue[milestone.String()] = append(prToIssue[milestone.String()], p.ResourceId)
		}
	}
	refBatches := prepareCloseIssueReferenceBatches(closeIssueReferences, maxCloseRefsPerBatch)
	for _, b := range refBatches {
		closeIssueReferenceBatches = append(closeIssueReferenceBatches, &v1.Resource{
			Resource: &v1.Resource_CloseIssueReferenceBatch{
				CloseIssueReferenceBatch: b,
			},
		})
	}
	c.AddAll(pullRequests)
	c.AddAll(reactionsBatches)
	c.AddAll(closeIssueReferenceBatches)
	return prToIssue, nil
}

func (l *Loader) pullRequestReviewThreads() ([]*v1.PullRequestReviewThread, error) {
	if !l.resourceTypeAllowed(resource.TypePullRequestReview) {
		return nil, nil
	}

	var reviewThreads []*v1.PullRequestReviewThread
	threads, err := loadResourceFiles[PullRequestReviewThread](l.rootPath, "pull_request_review_threads")
	if err != nil {
		return nil, fmt.Errorf("failed to get pr review thread files: %w", err)
	}

	for i := range threads {
		p, err := threads[i].ToV1PullRequestReviewThread()
		if err != nil {
			return nil, fmt.Errorf("error converting pr review thread to v1: %w", err)
		}

		reviewThreads = append(reviewThreads, p)
	}
	return reviewThreads, nil
}

func (l *Loader) pullRequestReviewComments(resourcesWithAttachments map[string][]string, c *ResourceCollector) ([]*v1.PullRequestReviewComment, error) {
	if !l.resourceTypeAllowed(resource.TypePullRequestReview) {
		return nil, nil
	}

	cs, err := loadResourceFiles[PullRequestReviewComment](l.rootPath, "pull_request_review_comments")
	if err != nil {
		return nil, fmt.Errorf("failed to get pr review comment files: %w", err)
	}

	var comments []*v1.PullRequestReviewComment
	var reactionsBatches []*v1.Resource
	for i := range cs {
		c, err := cs[i].ToV1PullRequestReviewComment()
		if err != nil {
			return nil, fmt.Errorf("error converting pr review comment to v1: %w", err)
		}
		comments = append(comments, c)

		if attachments, ok := resourcesWithAttachments[c.ResourceId]; ok {
			c.AttachmentResourceIds = attachments
		}

		if len(cs[i].Reactions) > 0 && l.resourceTypeAllowed(resource.TypeReactions) {
			reactions := cs[i].Reactions.ExtractV1Reactions()
			batches := prepareReactionsBatches(reactions, c.ResourceId, v1.ReactionSubjectType_REACTION_SUBJECT_TYPE_PULL_REQUEST_REVIEW_COMMENT, maxReactionsPerBatch)
			for _, b := range batches {
				reactionsBatches = append(reactionsBatches, &v1.Resource{
					Resource: &v1.Resource_ReactionsBatch{
						ReactionsBatch: b,
					},
				})
			}
		}
	}
	c.AddAll(reactionsBatches)
	return comments, nil
}

func (l *Loader) pullRequestReviews(threads []*v1.PullRequestReviewThread, comments []*v1.PullRequestReviewComment, resourcesWithAttachments map[string][]string, c *ResourceCollector) error {
	if !l.resourceTypeAllowed(resource.TypePullRequestReview) {
		return nil
	}

	reviews, err := loadResourceFiles[PullRequestReview](l.rootPath, "pull_request_reviews")
	if err != nil {
		return fmt.Errorf("failed to get pr review files: %w", err)
	}

	var pullRequestReviews, reactionsBatches []*v1.Resource
	for i := range reviews {
		// Convert the pull request review to a v1.PullRequestReview
		p, err := reviews[i].ToV1PullRequestReview()
		if err != nil {
			return fmt.Errorf("error converting pr review to v1: %w", err)
		}

		// Neither the import API nor Octoshift support pending pull request reviews
		if p.State == v1.PullRequestReviewState_PULL_REQUEST_REVIEW_STATE_PENDING {
			continue
		}

		// Add  comments and threads to the pull request review
		threads := reviewThreads(p.ResourceId, threads)
		for j := range threads {
			if len(threadComments(threads[j].ResourceId, comments)) == 0 {
				l.logger.Warn("no comments for thread", kvp.Any("thread", threads[j]))
				continue
			}
			threads[j].Comments = threadCommentsForReview(reviews[i].URL, threads[j].ResourceId, comments)
			p.Threads = append(p.Threads, threads[j])
			for z := range threads[j].Comments {
				p.AttachmentResourceIds = append(p.AttachmentResourceIds, threads[j].Comments[z].AttachmentResourceIds...)
			}
		}
		p.Comments = reviewComments(p.ResourceId, comments)
		for j := range p.Comments {
			p.AttachmentResourceIds = append(p.AttachmentResourceIds, p.Comments[j].AttachmentResourceIds...)
		}

		// Add the attachment resource ids to the pull request review
		if attachments, ok := resourcesWithAttachments[p.ResourceId]; ok {
			p.AttachmentResourceIds = append(p.AttachmentResourceIds, attachments...)
		}

		// Add the pull request review to the list of resources
		pullRequestReviews = append(pullRequestReviews, &v1.Resource{Resource: &v1.Resource_PullRequestReview{PullRequestReview: p}})

		// Extract the reactions from the pull request review and add them to the list of reactions batches
		if len(reviews[i].Reactions) > 0 && l.resourceTypeAllowed(resource.TypeReactions) {
			reactions := reviews[i].Reactions.ExtractV1Reactions()
			batches := prepareReactionsBatches(reactions, p.ResourceId, v1.ReactionSubjectType_REACTION_SUBJECT_TYPE_PULL_REQUEST_REVIEW, maxReactionsPerBatch)
			for _, b := range batches {
				reactionsBatches = append(reactionsBatches, &v1.Resource{
					Resource: &v1.Resource_ReactionsBatch{
						ReactionsBatch: b,
					},
				})
			}
		}

		l.logger.Info("pull request review", kvp.Any("pull_request_review", p))
	}

	c.AddAll(pullRequestReviews)
	c.AddAll(reactionsBatches)
	return nil
}

func (l *Loader) issueComments(resourcesWithAttachments map[string][]string, c *ResourceCollector) error {
	if !l.resourceTypeAllowed(resource.TypeIssueComment) {
		return nil
	}

	cs, err := loadResourceFiles[IssueComment](l.rootPath, "issue_comments")
	if err != nil {
		return fmt.Errorf("failed to get issue comment files: %w", err)
	}
	var comments, reactionsBatches []*v1.Resource
	for i := range cs {
		p, err := cs[i].ToV1IssueComment()
		if err != nil {
			return fmt.Errorf("error converting issue comment to v1: %w", err)
		}
		if attachments, ok := resourcesWithAttachments[p.ResourceId]; ok {
			p.AttachmentResourceIds = attachments
		}
		if len(cs[i].Reactions) > 0 && l.resourceTypeAllowed(resource.TypeReactions) {
			reactions := cs[i].Reactions.ExtractV1Reactions()
			batches := prepareReactionsBatches(reactions, p.ResourceId, v1.ReactionSubjectType_REACTION_SUBJECT_TYPE_ISSUE_COMMENT, maxReactionsPerBatch)
			for _, b := range batches {
				reactionsBatches = append(reactionsBatches, &v1.Resource{
					Resource: &v1.Resource_ReactionsBatch{
						ReactionsBatch: b,
					},
				})
			}
		}

		comments = append(comments, &v1.Resource{Resource: &v1.Resource_IssueComment{IssueComment: p}})
	}
	c.AddAll(comments)
	c.AddAll(reactionsBatches)
	return nil
}

func (l *Loader) issueEvents(c *ResourceCollector) error {
	if !l.resourceTypeAllowed(resource.TypeIssueEvent) {
		return nil
	}

	events, err := loadResourceFiles[IssueEvent](l.rootPath, "issue_events")
	if err != nil {
		return fmt.Errorf("failed to get issue events files: %w", err)
	}

	var batches []*v1.Resource
	var currRepoKeys []keys.RepositoryKey
	users := make(map[string]struct{})
	issues := make(map[string]struct{})
	prs := make(map[string]struct{})
	repos := make(map[string]struct{})
	batch := new(v1.IssueEventBatch)

	// addBatch adds a batch to the list of batches and creates a new one
	addBatch := func() {
		batch.ResourceId = fmt.Sprintf("issue-event-batch-%s", uuid.New().String())
		for user := range users {
			batch.UserResourceIds = append(batch.UserResourceIds, user)
		}
		for issue := range issues {
			batch.IssueResourceIds = append(batch.IssueResourceIds, issue)
		}
		for pr := range prs {
			batch.PullRequestResourceIds = append(batch.PullRequestResourceIds, pr)
		}
		for repo := range repos {
			batch.RepositoryResourceIds = append(batch.RepositoryResourceIds, repo)
		}
		batches = append(batches, &v1.Resource{Resource: &v1.Resource_IssueEventBatch{IssueEventBatch: batch}})
		batch = new(v1.IssueEventBatch)
		users = make(map[string]struct{})
		issues = make(map[string]struct{})
		prs = make(map[string]struct{})
		repos = make(map[string]struct{})
		currRepoKeys = nil
	}

	for i := range events {
		// Check if the issue event is supported
		if !events[i].IsSupported() {
			l.logger.Warn("skipping unsupported issue event", kvp.String("event", events[i].URL))
			continue
		}
		// Convert the issue event to a v1.IssueEvent
		p, err := events[i].ToV1IssueEvent()
		if err != nil {
			return fmt.Errorf("error converting issue event to v1: %w", err)
		}

		// We want to batch issue events by repository, so we need to check if the repo keys are different.
		// I.e: a given batch should only contain issue events for the same repository or repositories.
		repoKeys, err := repoKeysFromIssueEvent(p)
		if err != nil {
			return fmt.Errorf("error converting issue event to repo keys: %w", err)
		}
		// If the repo keys are different, add the current batch to the list of batches and create a new one
		if currRepoKeys != nil && !isSameRepoKeys(currRepoKeys, repoKeys) {
			addBatch()
		}
		currRepoKeys = repoKeys

		// Add the issue event to the batch
		batch.Events = append(batch.Events, p)
		users[p.ActorResourceId] = struct{}{}
		if p.SubjectIssueResourceId != "" {
			issues[p.GetSubjectIssueResourceId()] = struct{}{}
		}
		if p.SubjectUserResourceId != "" {
			users[p.GetSubjectUserResourceId()] = struct{}{}
		}
		if events[i].IsIssue() {
			issues[events[i].Issue] = struct{}{}
		}
		if events[i].IsPullRequest() {
			prs[events[i].PullRequest] = struct{}{}
		}
		if events[i].ReferencingPullRequest != "" {
			prs[events[i].ReferencingPullRequest] = struct{}{}
		}
		if p.CommitRepositoryResourceId != "" {
			repos[p.CommitRepositoryResourceId] = struct{}{}
		}
		if len(batch.Events) < l.maxIssueEventsPerBatch {
			continue
		}
		// Batch is full, add it to the list of batches and create a new one
		addBatch()
	}

	// Add the last batch to the list of batches
	if len(batch.Events) > 0 {
		addBatch()
	}
	c.AddAll(batches)
	return nil
}

func (l *Loader) milestones(milestoneToIssues map[string][]string, c *ResourceCollector) error {
	if !l.resourceTypeAllowed(resource.TypeMilestone) {
		return nil
	}

	ms, err := loadResourceFiles[Milestone](l.rootPath, "milestones")
	if err != nil {
		return fmt.Errorf("failed to get milestones files: %w", err)
	}

	var batches []*v1.Resource
	users := make(map[string]struct{})
	issues := make(map[string]struct{})
	batch := new(v1.MilestoneBatch)
	// addBatch adds a batch to the list of batches and creates a new one
	addBatch := func() {
		batch.ResourceId = fmt.Sprintf("milestone-batch-%s", uuid.New().String())
		for user := range users {
			batch.UserResourceIds = append(batch.UserResourceIds, user)
		}
		for issue := range issues {
			batch.IssueResourceIds = append(batch.IssueResourceIds, issue)
		}
		batches = append(batches, &v1.Resource{Resource: &v1.Resource_MilestoneBatch{MilestoneBatch: batch}})
		batch = new(v1.MilestoneBatch)
		users = make(map[string]struct{})
		issues = make(map[string]struct{})
	}

	for i := range ms {
		// Convert the milestone to a v1.Milestone
		p, err := ms[i].ToV1Milestone(milestoneToIssues)
		if err != nil {
			return fmt.Errorf("error converting milestone to v1: %w", err)
		}
		// Add the issue event to the batch
		batch.Milestones = append(batch.Milestones, p)
		users[p.UserResourceId] = struct{}{}
		for _, issue := range p.IssueResourceIds {
			issues[issue] = struct{}{}
		}
		if len(batch.Milestones) < maxMilestonesPerBatch {
			continue
		}
		// Batch is full, add it to the list of batches and create a new one
		addBatch()
	}

	// Add the last batch to the list of batches
	if len(batch.Milestones) > 0 {
		addBatch()
	}

	c.AddAll(batches)
	return nil
}

func (l *Loader) projects(c *ResourceCollector) error {
	if !l.resourceTypeAllowed(resource.TypeProject) {
		return nil
	}

	ps, err := loadResourceFiles[Project](l.rootPath, "projects")
	if err != nil {
		return fmt.Errorf("failed to get project files: %w", err)
	}

	var projects, projectColumns, projectCardsBatches []*v1.Resource
	for _, p := range ps {
		projects = append(projects,
			&v1.Resource{
				Resource: &v1.Resource_Project{
					Project: p.ToV1Project(),
				},
			},
		)
		for _, column := range p.extractV1ProjectColumns() {
			projectColumns = append(projectColumns,
				&v1.Resource{
					Resource: &v1.Resource_ProjectColumn{
						ProjectColumn: column,
					},
				},
			)
		}
		for _, batch := range p.extractV1ProjectCardsBatches() {
			projectCardsBatches = append(projectCardsBatches,
				&v1.Resource{
					Resource: &v1.Resource_ProjectCardsBatch{
						ProjectCardsBatch: batch,
					},
				},
			)
		}
	}
	c.AddAll(projects)
	c.AddAll(projectColumns)
	c.AddAll(projectCardsBatches)
	return nil
}

func (l *Loader) commitComments(c *ResourceCollector) error {
	if !l.resourceTypeAllowed(resource.TypeCommitComment) {
		return nil
	}

	cs, err := loadResourceFiles[CommitComment](l.rootPath, "commit_comments")
	if err != nil {
		return fmt.Errorf("failed to get commit comment files: %w", err)
	}
	var comments []*v1.Resource
	for i := range cs {
		p, err := cs[i].ToV1CommitComment()
		if err != nil {
			return fmt.Errorf("error converting commit comment to v1: %w", err)
		}
		comments = append(comments, &v1.Resource{Resource: &v1.Resource_CommitComment{CommitComment: p}})
	}
	c.AddAll(comments)
	return nil
}

func (l *Loader) releases(c *ResourceCollector) error {
	if !l.resourceTypeAllowed(resource.TypeRelease) {
		return nil
	}

	rs, err := loadResourceFiles[Release](l.rootPath, "releases")
	if err != nil {
		return fmt.Errorf("failed to get releases files: %w", err)
	}

	var releases, reactionsBatches, releaseAssets []*v1.Resource
	for i := range rs {
		r, err := rs[i].ToV1Release()
		if err != nil {
			return fmt.Errorf("error converting release to v1: %w", err)
		}
		// TODO Releases can also have user-attachments referenced in the body, but none of our test repos have them.
		if len(rs[i].Reactions) > 0 && l.resourceTypeAllowed(resource.TypeReactions) {
			reactions := rs[i].Reactions.ExtractV1Reactions()
			batches := prepareReactionsBatches(reactions, r.ResourceId, v1.ReactionSubjectType_REACTION_SUBJECT_TYPE_RELEASE, maxReactionsPerBatch)
			for _, b := range batches {
				reactionsBatches = append(reactionsBatches, &v1.Resource{
					Resource: &v1.Resource_ReactionsBatch{
						ReactionsBatch: b,
					},
				})
			}
		}
		for _, asset := range rs[i].extractReleaseAssets() {
			blobName := asset.ResourceId + "/" + asset.FileName
			asset.BlobKey = l.sasGenerator.BlobPath(v1.AssetKind_ASSET_KIND_RELEASE_ASSET, blobName)
			err := l.uploadAsset(v1.AssetKind_ASSET_KIND_RELEASE_ASSET, fmt.Sprintf("%s/%s", l.rootPath, asset.BlobKey), blobName, asset.ContentType, asset.Size)
			if err != nil {
				l.logger.Error("failed to upload asset, skipping", kvp.Err(err), kvp.String("asset", asset.BlobKey))
				continue
			}
			releaseAssets = append(releaseAssets, &v1.Resource{Resource: &v1.Resource_ReleaseAsset{ReleaseAsset: asset}})
		}
		releases = append(releases, &v1.Resource{Resource: &v1.Resource_Release{Release: r}})
	}

	c.AddAll(releaseAssets)
	c.AddAll(releases)
	c.AddAll(reactionsBatches)

	return nil
}

// uploadAsset uploads an asset file from the given path to the blob store.
func (l *Loader) uploadAsset(kind v1.AssetKind, filePath, blobName, contentType string, fileSize int64) error {
	l.logger.Info("uploading asset", kvp.String("path", filePath), kvp.String("blobname", blobName), kvp.String("content-type", contentType))
	pipeline := azblob.NewPipeline(azblob.NewAnonymousCredential(), azblob.PipelineOptions{})
	sasURL, err := l.sasGenerator.GenerateSignedURL(kind, blobName, contentType, fileSize)
	if err != nil {
		return fmt.Errorf("error generating signed URL: %w", err)
	}

	blockBlobURL := azblob.NewBlockBlobURL(sasURL, pipeline)

	file, err := os.Open(filePath)
	if err != nil {
		return fmt.Errorf("could not open asset file: %w", err)
	}
	defer file.Close()
	_, err = azblob.UploadStreamToBlockBlob(context.Background(), file, blockBlobURL, azblob.UploadStreamToBlockBlobOptions{})
	if err != nil {
		return fmt.Errorf("could not upload stream to blob: %w", err)
	}

	return nil
}

func getResourceFiles(root, resourceType string) ([]string, error) {
	var resourceFiles []string
	matches, err := filepath.Glob(filepath.Join(root, fmt.Sprintf("%s_*.json", resourceType)))
	if err != nil {
		return nil, fmt.Errorf("error getting resource files: %w", err)
	}
	for _, match := range matches {
		info, err := os.Lstat(match)
		if err != nil {
			return nil, fmt.Errorf("error getting file info for %s: %w", match, err)
		}
		if info.Mode()&os.ModeSymlink != 0 {
			continue // Ignore symlinks
		}
		if stat, ok := info.Sys().(*syscall.Stat_t); ok && stat.Nlink != 1 {
			continue // Ignore hard links
		}
		resourceFiles = append(resourceFiles, match)
	}
	// Sort the files by the number in the filename. If the filename
	// doesn't contain a number, it will be treated as 0.
	sort.Slice(resourceFiles, func(i, j int) bool {
		return extractNumber(resourceType, resourceFiles[i]) < extractNumber(resourceType, resourceFiles[j])
	})
	return resourceFiles, nil
}

// resourceTypeAllowed returns true if the resource type is allowed, otherwise false.
// If no resource types are allowed, all resource types are allowed.
func (l *Loader) resourceTypeAllowed(r resource.Type) bool {
	if len(l.allowedResources) == 0 {
		return true
	}
	_, ok := l.allowedResources[r]
	if !ok {
		l.logger.Info("resource type skipped", kvp.String("resource_type", r.String()))
	}
	return ok
}

// extractNumber returns the number from the filename of a resource file.
// The filename is expected to be in the format <resourceType>_<number>.json.
// If the number cannot be parsed, 0 is returned.
func extractNumber(resourceType, filename string) int {
	filename = strings.TrimPrefix(filename, resourceType+"_")
	filename = strings.TrimSuffix(filename, ".json")
	n, _ := strconv.Atoi(filename)
	return n
}

// shuffleResources randomly shuffles the Resources in the slice.
func shuffleResources(resources []*v1.Resource) []*v1.Resource {
	source := rand.NewSource(1)
	rand.New(source).Shuffle(len(resources), func(i, j int) { //nolint:gosec // use of weak random number generator is ok here
		resources[i], resources[j] = resources[j], resources[i]
	})
	return resources
}

// loadResourceFiles loads the resource files from the given root and resource type.
func loadResourceFiles[T any](root, resourceType string) ([]T, error) {
	files, err := getResourceFiles(root, resourceType)
	if err != nil {
		return nil, fmt.Errorf("failed to get resource files: %w", err)
	}
	var resp []T
	for _, path := range files {
		f, err := os.Open(path)
		if err != nil {
			return nil, fmt.Errorf("error opening resource file for reading: %w", err)
		}
		var resources []T
		if err = json.NewDecoder(f).Decode(&resources); err != nil {
			if cerr := f.Close(); cerr != nil {
				return nil, fmt.Errorf("error closing file: %w", cerr)
			}
			return nil, fmt.Errorf("error decoding resources: %w", err)
		}
		if err := f.Close(); err != nil {
			return nil, fmt.Errorf("error closing file: %w", err)
		}
		resp = append(resp, resources...)
	}
	return resp, nil
}

// mergeMapsAndDedup merges two maps of string slices and deduplicates the values.
func mergeMapsAndDedup(a, b map[string][]string) map[string][]string {
	c := make(map[string][]string)
	maps.Copy(c, a)
	maps.Copy(c, b)
	for k, v := range c {
		c[k] = dedup(v)
	}
	return c
}

// addDedup adds an element to a slice and returns the result with duplicates removed
func addDedup(slice []string, elem string) []string {
	if elem == "" {
		return dedup(slice)
	}
	return dedup(append(slices.Clone(slice), elem))
}

// dedup removes duplicates from a slice
func dedup[T string | dag.ID](slice []T) []T {
	s := slices.Clone(slice)
	slices.Sort(s)
	return slices.Compact(s)
}
