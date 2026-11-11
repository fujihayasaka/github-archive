package jobservice

import (
	"context"
	"encoding/json"
	"fmt"
	"path/filepath"
	"regexp"
	"strings"
	"sync"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	gg "github.com/google/go-github/v75/github"
	"go.opentelemetry.io/otel/attribute"
)

// CheckRulesResult represents the result of checking repository and branch protection rules.
type CheckRulesResult struct {
	Rules                    []string `json:"rules"`
	HasBranchProtectionRules bool     `json:"has_branch_protection_rules"`
	HasRepositoryRules       bool     `json:"has_repository_rules"`
	IsBypassActor            bool     `json:"is_bypass_actor"`
	RequireSignedCommits     bool     `json:"require_signed_commits"`
}

// RulesViolationError represents an error indicating that a job cannot be created
// due to repository or branch protection rules violations.
type RulesViolationError struct {
	CheckRulesResult *CheckRulesResult
}

// RulesString returns a string representation of the violated rules in JSON format
// that can be presented in user-facing error messages.
func (e *RulesViolationError) RulesString() string {
	rulesError := strings.Join(e.CheckRulesResult.Rules, "; ")
	rulesBytes, err := json.Marshal(e.CheckRulesResult.Rules)
	if err == nil {
		rulesError = string(rulesBytes)
	}
	return rulesError
}

func (e *RulesViolationError) Error() string {
	return fmt.Sprintf("job cannot be created due to repository rules violation: %s", e.RulesString())
}

// BranchRuleChecker defines the methods required to check branch rules.
type BranchRuleChecker interface {
	GetActionsPermissions(ctx context.Context, ownerLogin, repoName string) (*gg.ActionsPermissionsRepository, error)
	ListBranchProtectionRules(ctx context.Context, repoNodeID string) (*[]github.GQLBranchProtectionRule, error)
	ListRepositoryRulesForBranch(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error)
}

// InvariantRulesResult holds rule-check results that are independent of the
// target branch name: agent-prefix existence, bypass-actor status, and the
// repo-scoped branch-protection rules (fetched once, evaluated per branch).
type InvariantRulesResult struct {
	AgentPrefixRules      []string
	BypassResponse        *sweagentdTwirp.IsBypassActorResponse
	BypassableRulesetIDs  []uint64
	BranchProtectionRules *[]github.GQLBranchProtectionRule
}

// CheckRulesInvariant performs the branch-independent portion of the rules
// check: agent-prefix existence (Spokes), bypass-actor lookup (Twirp), and
// ListBranchProtectionRules (GQL, repo-scoped). These three network calls
// run concurrently. The result can be reused across multiple candidate
// branch names via CheckRulesForBranch.
func (s *Service) CheckRulesInvariant(ctx context.Context, gh BranchRuleChecker, agent sweagentd.AgenticApp, job *jobs.Job, checkAgentPrefixExists bool) *InvariantRulesResult {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.CheckRulesInvariant")
	defer span.End()
	span.SetAttributes(attribute.Bool("job.check_agent_prefix_exists", checkAgentPrefixExists))

	logger := s.obsv.LoggerWithTelemetry(ctx)
	inv := &InvariantRulesResult{}

	var wg sync.WaitGroup

	// 1. Agent-prefix existence check (Spokes)
	wg.Go(func() {
		if !checkAgentPrefixExists {
			return
		}
		agentPrefixBranchExists, err := s.spokes.CheckForExistingBranches(ctx, uint64(job.RepoID), []string{agent.BranchPrefix()})
		if err != nil {
			logger.WithError(err).Error(fmt.Sprintf("failed to check if branch '%s' exists", agent.BranchPrefix()))
		} else if agentPrefixBranchExists[0] {
			inv.AgentPrefixRules = append(inv.AgentPrefixRules, fmt.Sprintf(github.RuleAgentPrefixBranchExists, agent.BranchPrefix()))
		}
	})

	// 2. Bypass-actor check (Twirp)
	wg.Go(func() {
		resp, err := s.checkCopilotBypassActor(ctx, job)
		if err != nil {
			logger.WithError(err).Warn("failed to check if Copilot is a bypass actor, continuing with rule checks")
			return
		}
		inv.BypassResponse = resp
		if resp != nil && resp.IsBypassActor {
			for _, ruleset := range resp.Rulesets {
				inv.BypassableRulesetIDs = append(inv.BypassableRulesetIDs, ruleset.RulesetId)
			}
			logger.Info("Copilot can bypass repository rulesets",
				kvp.Uint64s("bypassable_ruleset_ids", inv.BypassableRulesetIDs))
		}
	})

	// 3. Branch protection rules (GQL, repo-scoped)
	wg.Go(func() {
		branchRules, err := gh.ListBranchProtectionRules(ctx, job.RepoNodeID)
		if err != nil {
			logger.WithError(err).Error("failed to list classic branch protection rules")
			return
		}
		inv.BranchProtectionRules = branchRules
	})

	wg.Wait()
	return inv
}

// CheckRulesForBranch performs the branch-specific portion of the rules check
// using pre-computed invariant results. It checks branch existence, repository
// rules (REST), and evaluates pre-fetched branch protection rules locally.
func (s *Service) CheckRulesForBranch(ctx context.Context, gh BranchRuleChecker, agent sweagentd.AgenticApp, job *jobs.Job, repoOwner, repoName, branchName string, inv *InvariantRulesResult) *CheckRulesResult {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.CheckRulesForBranch")
	defer span.End()

	logger := s.obsv.LoggerWithTelemetry(ctx)
	rules := append([]string{}, inv.AgentPrefixRules...)
	result := &CheckRulesResult{}

	// Check if the branch already exists
	branchAlreadyExists := false
	if s.ffs.IsEnabledForUserOrRepo(ctx, featureflags.CopilotSWEAgentPRCommentRulesCheck, job.ActorID, job.RepoID) {
		branchExists, err := s.spokes.CheckForExistingBranches(ctx, uint64(job.RepoID), []string{branchName})
		if err != nil {
			logger.WithError(err).Warn("failed to check if branch exists, assuming new branch")
		} else {
			branchAlreadyExists = branchExists[0]
		}
	}

	// Check repository rules, filtering out rules from bypassable rulesets
	repositoryRules, repoRequiresSigning := s.getRepositoryRules(ctx, gh, agent, job, repoOwner, repoName, branchName, inv.BypassableRulesetIDs, branchAlreadyExists)
	if len(repositoryRules) > 0 {
		rules = append(rules, repositoryRules...)
		result.HasRepositoryRules = true
	}

	// Evaluate pre-fetched branch protection rules locally
	branchProtectionRules, branchRequiresSigning := s.evaluateBranchProtectionRules(branchName, inv.BranchProtectionRules, branchAlreadyExists)
	if len(branchProtectionRules) > 0 {
		rules = append(rules, branchProtectionRules...)
		result.HasBranchProtectionRules = true
	}

	result.Rules = rules
	result.IsBypassActor = inv.BypassResponse != nil && inv.BypassResponse.IsBypassActor
	result.RequireSignedCommits = repoRequiresSigning || branchRequiresSigning

	logger.Info("Completed repository rules check",
		kvp.Int("rules_count", len(rules)),
		kvp.Bool("is_bypass_actor", result.IsBypassActor),
		kvp.Bool("has_repository_rules", result.HasRepositoryRules),
		kvp.Bool("has_branch_protection_rules", result.HasBranchProtectionRules),
		kvp.Bool("require_signed_commits", result.RequireSignedCommits))

	return result
}

// CheckRules checks the repository and branch protection rules for the given job and branch name.
// checkAgentPrefixExists controls whether to run the RuleAgentPrefixBranchExists check; pass true
// when creating a new agent-prefixed branch, false for existing branches (e.g. from HeadRef).
func (s *Service) CheckRules(ctx context.Context, gh BranchRuleChecker, agent sweagentd.AgenticApp, job *jobs.Job, repoOwner, repoName, branchName string, checkAgentPrefixExists bool) *CheckRulesResult {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.CheckRules")
	defer span.End()
	span.SetAttributes(attribute.Bool("job.check_agent_prefix_exists", checkAgentPrefixExists))

	inv := s.CheckRulesInvariant(ctx, gh, agent, job, checkAgentPrefixExists)
	return s.CheckRulesForBranch(ctx, gh, agent, job, repoOwner, repoName, branchName, inv)
}

// Use REST API for repository rulesets
func (s *Service) getRepositoryRules(ctx context.Context, gh BranchRuleChecker, agent sweagentd.AgenticApp, job *jobs.Job, repoOwner, repoName, branchName string, bypassableRulesetIDs []uint64, branchAlreadyExists bool) ([]string, bool) {
	logger := s.obsv.LoggerWithTelemetry(ctx)
	rules := []string{}
	requiresCommitSignatures := false

	// Pass bypassable ruleset IDs to filter them out during the API call
	repoRules, err := gh.ListRepositoryRulesForBranch(ctx, repoOwner, repoName, branchName, bypassableRulesetIDs)
	if err != nil {
		logger.WithError(err).Error("failed to list repository rules for branch")
	}
	if repoRules != nil {
		repoRulesSuffix := "due to repository rules"

		// Track which rulesets are blocking Copilot (non-bypassable)
		var blockingRulesetIDs []uint64

		// Helper to add a rule and track all ruleset IDs from a rule slice
		addRuleWithRulesets := func(ruleName string, rulesetIDs []int64) {
			if len(rulesetIDs) > 0 {
				rules = append(rules, fmt.Sprintf("%s %s", ruleName, repoRulesSuffix))
				for _, rulesetID := range rulesetIDs {
					blockingRulesetIDs = append(blockingRulesetIDs, uint64(rulesetID))
				}
			}
		}

		// Helper for pattern rules that need individual processing
		appendRuleandRulesetID := func(ruleName string, rulesetID int64) {
			rules = append(rules, fmt.Sprintf("%s %s", ruleName, repoRulesSuffix))
			blockingRulesetIDs = append(blockingRulesetIDs, uint64(rulesetID))
		}

		// Extract ruleset IDs from rule slices
		extractRulesetIDs := func(rules any) []int64 {
			var ids []int64
			switch r := rules.(type) {
			case []*gg.BranchRuleMetadata:
				for _, rule := range r {
					ids = append(ids, rule.RulesetID)
				}
			case []*gg.PullRequestBranchRule:
				for _, rule := range r {
					ids = append(ids, rule.RulesetID)
				}
			case []*gg.CodeScanningBranchRule:
				for _, rule := range r {
					ids = append(ids, rule.RulesetID)
				}
			case []*gg.PatternBranchRule:
				for _, rule := range r {
					ids = append(ids, rule.RulesetID)
				}
			}
			return ids
		}

		// Process simple rule types
		if !branchAlreadyExists {
			addRuleWithRulesets(github.RuleBlockCreation, extractRulesetIDs(repoRules.Creation))
		}
		// The signing requirement is handled by the runtime instead of
		// blocking job creation.
		if len(repoRules.RequiredSignatures) > 0 {
			requiresCommitSignatures = true
		}
		addRuleWithRulesets(github.RuleRequirePullRequest, extractRulesetIDs(repoRules.PullRequest))
		addRuleWithRulesets(github.RuleCodeScanning, extractRulesetIDs(repoRules.CodeScanning))
		addRuleWithRulesets(github.RuleCommitMessagePattern, extractRulesetIDs(s.nonNegatedRules(repoRules.CommitMessagePattern)))

		// Check pattern-based rules
		s.processPatternRules(ctx, logger, job, repoRules.CommitAuthorEmailPattern, agent.CommitEmail(), "commit author email", github.RuleCommitAuthorEmailPattern, appendRuleandRulesetID)
		s.processPatternRules(ctx, logger, job, repoRules.CommitterEmailPattern, s.committerEmail, "committer email", github.RuleCommitterEmailPattern, appendRuleandRulesetID)
		if !branchAlreadyExists {
			s.processPatternRules(ctx, logger, job, repoRules.BranchNamePattern, branchName, "branch name", github.RuleBranchNamePattern, appendRuleandRulesetID)
		}

		// Log which rulesets are blocking Copilot from proceeding
		if len(blockingRulesetIDs) > 0 {
			logger.Info("Non-bypassable rulesets will stop Copilot from proceeding",
				kvp.Uint64s("blocking_ruleset_ids", blockingRulesetIDs))
		}
	}

	return rules, requiresCommitSignatures
}

// BranchRulePatterns fetches repository rules for the given branch and returns a
// comma-separated string of non-negated PatternBranchRule patterns prefixed by their
// rule type (e.g. "branch_name: foo, commit_message: bar").
func (s *Service) BranchRulePatterns(ctx context.Context, gh BranchRuleChecker, repoOwner, repoName, branchName string, excludeRulesetIDs []uint64) (string, error) {
	repoRules, err := gh.ListRepositoryRulesForBranch(ctx, repoOwner, repoName, branchName, excludeRulesetIDs)
	if err != nil {
		return "", goerrors.Errorf("failed to list repository rules for branch: %w", err)
	}
	if repoRules == nil {
		return "", nil
	}

	// at present there can only be one BranchNamePattern rule per ruleset, but the API returns a slice.
	if len(repoRules.BranchNamePattern) > 0 {
		pat := repoRules.BranchNamePattern[0]
		res := "must "
		if pat.Parameters.Negate != nil && *pat.Parameters.Negate {
			res += "not "
		}
		// https://docs.github.com/en/enterprise-cloud@latest/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository#adding-metadata-restrictions
		// Patterns are matched as string literals, only regexps are interpreted.
		if pat.Parameters.Operator == gg.PatternRuleOperatorRegex {
			res += "match the pattern"
		} else {
			res += strings.ReplaceAll(string(pat.Parameters.Operator), "_", " ")
		}
		return res + " " + pat.Parameters.Pattern, nil
	}

	return "", nil
}

// nonNegatedRules returns a slice of non-negated rules from the provided slice
func (s *Service) nonNegatedRules(rules []*gg.PatternBranchRule) []*gg.PatternBranchRule {
	var result []*gg.PatternBranchRule
	for _, rule := range rules {
		if rule.Parameters.Negate == nil || !*rule.Parameters.Negate {
			result = append(result, rule)
		}
	}
	return result
}

// processPatternRules is a helper that validates pattern rules and adds blocking rules
func (s *Service) processPatternRules(
	ctx context.Context,
	logger log.Logger,
	job *jobs.Job,
	rules []*gg.PatternBranchRule,
	value, ruleType, baseMessage string,
	addRuleFunc func(string, int64),
) {
	for _, rule := range rules {
		if isValid, message := s.validatePatternRule(ctx, logger, job, rule, value, ruleType, baseMessage); !isValid {
			addRuleFunc(message, rule.RulesetID)
			break
		}
	}
}

// validatePatternRule validates a value against a pattern rule
// Returns (true, "") if the rule passes, or (false, "<validation message here>") if the rule fails.
func (s *Service) validatePatternRule(ctx context.Context, logger log.Logger, job *jobs.Job, rule *gg.PatternBranchRule, value, ruleType, baseMessage string) (bool, string) {
	pattern := rule.Parameters.Pattern
	op := rule.Parameters.Operator
	isNegated := rule.Parameters.Negate != nil && *rule.Parameters.Negate
	var matched bool
	var operationDesc string

	switch op {
	case gg.PatternRuleOperatorStartsWith:
		matched = strings.HasPrefix(value, pattern)
		if isNegated {
			operationDesc = "must not start with ***"
		} else {
			operationDesc = "must start with ***"
		}
	case gg.PatternRuleOperatorEndsWith:
		matched = strings.HasSuffix(value, pattern)
		if isNegated {
			operationDesc = "must not end with ***"
		} else {
			operationDesc = "must end with ***"
		}
	case gg.PatternRuleOperatorContains:
		matched = strings.Contains(value, pattern)
		if isNegated {
			operationDesc = "must not contain ***"
		} else {
			operationDesc = "must contain ***"
		}
	case gg.PatternRuleOperatorRegex:
		re, err := regexp.Compile(pattern)
		if err != nil {
			logger.WithError(err).Error(fmt.Sprintf("invalid %s pattern: %s", ruleType, pattern))
			return true, ""
		}
		matched = re.MatchString(value)
		if isNegated {
			operationDesc = "must not match regex ***"
		} else {
			operationDesc = "must match regex ***"
		}
	default:
		logger.Error(fmt.Sprintf("unknown %s pattern operator: %s", ruleType, op))
		return true, ""
	}

	// Apply negation if specified
	if isNegated {
		matched = !matched
	}

	// If rule passes, return nil
	if matched {
		return true, ""
	}

	if s.ffs.IsEnabledForUserOrRepo(ctx, featureflags.CopilotSWEAgentPatternRuleFailureDetails, job.ActorID, job.RepoID) {
		operationDesc = strings.ReplaceAll(operationDesc, "***", fmt.Sprintf("%q", pattern))
		operationDesc = fmt.Sprintf("%q %s", value, operationDesc)
	}

	// If rule fails, return error with formatted message
	return false, fmt.Sprintf("%s (%s)", baseMessage, operationDesc)
}

// checkCopilotBypassActor uses the IsBypassActor Twirp API to check
// if Copilot is configured as a bypass actor for repository rulesets.
// Returns the full bypass response containing ruleset details, or nil if not a bypass actor.
func (s *Service) checkCopilotBypassActor(ctx context.Context, job *jobs.Job) (*sweagentdTwirp.IsBypassActorResponse, error) {
	logger := s.obsv.LoggerWithTelemetry(ctx)

	logger.Debug("Checking if Copilot is bypass actor using enhanced API")

	// Get the app ID to check if it's configured as a bypass actor
	appID := job.AgentID

	// Call the enhanced IsBypassActor API
	req := &sweagentdTwirp.IsBypassActorRequest{
		RepositoryId: uint64(job.RepoID),
		ActorId:      uint64(appID),
	}

	resp, err := s.twirp.SweagentdAPI().IsBypassActor(ctx, req)
	if err != nil {
		return nil, goerrors.Errorf("failed to call IsBypassActor API: %w", err)
	}

	if resp.IsBypassActor {
		// Collect ruleset details for logging
		var rulesetDetails []string
		for _, ruleset := range resp.Rulesets {
			rulesetDetails = append(rulesetDetails, fmt.Sprintf("%s (ID: %d)", ruleset.RulesetName, ruleset.RulesetId))
		}

		logger.Info("The app is configured as a bypass actor",
			kvp.Int64("app_id", appID),
			kvp.Strings("bypassable_rulesets", rulesetDetails))
	} else {
		logger.Debug("The app is not configured as a bypass actor",
			kvp.Int64("app_id", appID))
	}

	return resp, nil
}

// evaluateBranchProtectionRules evaluates pre-fetched branch protection rules
// against a specific branch name without making any network calls.
func (s *Service) evaluateBranchProtectionRules(branchName string, branchRules *[]github.GQLBranchProtectionRule, branchAlreadyExists bool) ([]string, bool) {
	rules := []string{}
	requiresCommitSignatures := false
	if branchRules == nil {
		return rules, requiresCommitSignatures
	}

	branchRulesSuffix := "due to branch protection rules"
	for _, rule := range *branchRules {
		matched, _ := filepath.Match(rule.Pattern, branchName)
		if !matched {
			continue
		}
		if rule.BlocksCreations && !branchAlreadyExists {
			rules = append(rules, fmt.Sprintf("%s %s", github.RuleBlockCreation, branchRulesSuffix))
		}
		if rule.RequiresCommitSignatures {
			requiresCommitSignatures = true
		}
		if rule.RequiresApprovingReviews {
			rules = append(rules, fmt.Sprintf("%s %s", github.RuleRequirePullRequest, branchRulesSuffix))
		}
	}

	return rules, requiresCommitSignatures
}
