package jobservice

import (
	"context"
	"encoding/json"
	"fmt"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	gg "github.com/google/go-github/v75/github"
)

// CheckRulesResult represents the result of checking repository and branch protection rules.
type CheckRulesResult struct {
	Rules                    []string `json:"rules"`
	HasBranchProtectionRules bool     `json:"has_branch_protection_rules"`
	HasRepositoryRules       bool     `json:"has_repository_rules"`
	IsBypassActor            bool     `json:"is_bypass_actor"`
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

// CheckRules checks the repository and branch protection rules for the given job and branch name.
func (s *Service) CheckRules(ctx context.Context, gh BranchRuleChecker, agent sweagentd.AgenticApp, job *jobs.Job, repoOwner, repoName, branchName string) *CheckRulesResult {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.CheckRules")
	defer span.End()

	logger := s.obsv.LoggerWithTelemetry(ctx)
	rules := []string{}
	result := &CheckRulesResult{}

	agentPrefixBranchExists, err := s.spokes.CheckForExistingBranches(ctx, uint64(job.RepoID), []string{agent.BranchPrefix()})
	if err != nil {
		logger.WithError(err).Error(fmt.Sprintf("failed to check if branch '%s' exists", agent.BranchPrefix()))
	} else if agentPrefixBranchExists[0] {
		rules = append(rules, fmt.Sprintf(github.RuleAgentPrefixBranchExists, agent.BranchPrefix()))
	}

	// Get the list of rulesets where Copilot can bypass rules
	bypassResponse, err := s.checkCopilotBypassActor(ctx, job)
	if err != nil {
		logger.WithError(err).Warn("failed to check if Copilot is a bypass actor, continuing with rule checks")
	}

	// Generate list of IDs of rulesets that are bypassable
	var bypassableRulesetIDs []uint64
	if bypassResponse != nil && bypassResponse.IsBypassActor {
		for _, ruleset := range bypassResponse.Rulesets {
			bypassableRulesetIDs = append(bypassableRulesetIDs, ruleset.RulesetId)
		}
		logger.Info("Copilot can bypass repository rulesets",
			kvp.Uint64s("bypassable_ruleset_ids", bypassableRulesetIDs))
	}

	// Check repository rules, filtering out rules from bypassable rulesets
	repositoryRules := s.getRepositoryRules(ctx, gh, job, repoOwner, repoName, branchName, bypassableRulesetIDs)
	if len(repositoryRules) > 0 {
		rules = append(rules, repositoryRules...)
		result.HasRepositoryRules = true
	}

	branchProtectionRules := s.getBranchProtectionRules(ctx, gh, job, branchName)
	if len(branchProtectionRules) > 0 {
		rules = append(rules, branchProtectionRules...)
		result.HasBranchProtectionRules = true
	}

	result.Rules = rules
	result.IsBypassActor = bypassResponse != nil && bypassResponse.IsBypassActor

	logger.Info("Completed repository rules check",
		kvp.Int("rules_count", len(rules)),
		kvp.Bool("is_bypass_actor", result.IsBypassActor),
		kvp.Bool("has_repository_rules", result.HasRepositoryRules),
		kvp.Bool("has_branch_protection_rules", result.HasBranchProtectionRules))

	return result
}

// Use REST API for repository rulesets
func (s *Service) getRepositoryRules(ctx context.Context, gh BranchRuleChecker, job *jobs.Job, repoOwner, repoName, branchName string, bypassableRulesetIDs []uint64) []string {
	logger := s.obsv.LoggerWithTelemetry(ctx)
	rules := []string{}

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
		addRuleWithRulesets(github.RuleBlockCreation, extractRulesetIDs(repoRules.Creation))
		addRuleWithRulesets(github.RuleRequireSignatures, extractRulesetIDs(repoRules.RequiredSignatures))
		addRuleWithRulesets(github.RuleRequirePullRequest, extractRulesetIDs(repoRules.PullRequest))
		addRuleWithRulesets(github.RuleCodeScanning, extractRulesetIDs(repoRules.CodeScanning))
		addRuleWithRulesets(github.RuleCommitMessagePattern, extractRulesetIDs(s.nonNegatedRules(repoRules.CommitMessagePattern)))

		// Check pattern-based rules
		s.processPatternRules(logger, repoRules.CommitAuthorEmailPattern, s.committerEmail, "commit author email", github.RuleCommitAuthorEmailPattern, appendRuleandRulesetID)
		s.processPatternRules(logger, repoRules.CommitterEmailPattern, s.committerEmail, "committer email", github.RuleCommitterEmailPattern, appendRuleandRulesetID)
		s.processPatternRules(logger, repoRules.BranchNamePattern, branchName, "branch name", github.RuleBranchNamePattern, appendRuleandRulesetID)

		// Log which rulesets are blocking Copilot from proceeding
		if len(blockingRulesetIDs) > 0 {
			logger.Info("Non-bypassable rulesets will stop Copilot from proceeding",
				kvp.Uint64s("blocking_ruleset_ids", blockingRulesetIDs))
		}
	}

	return rules
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
	logger log.Logger,
	rules []*gg.PatternBranchRule,
	value, ruleType, baseMessage string,
	addRuleFunc func(string, int64),
) {
	for _, rule := range rules {
		if isValid, message := s.validatePatternRule(logger, rule, value, ruleType, baseMessage); !isValid {
			addRuleFunc(message, rule.RulesetID)
			break
		}
	}
}

// validatePatternRule validates a value against a pattern rule
// Returns (true, "") if the rule passes, or (false, "<validation message here>") if the rule fails.
func (s *Service) validatePatternRule(logger log.Logger, rule *gg.PatternBranchRule, value, ruleType, baseMessage string) (bool, string) {
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

	// If rule fails, return error with formatted message
	return false, fmt.Sprintf("%s (%s)", baseMessage, operationDesc)
}

// Use GQL API for classic branch protection rules
func (s *Service) getBranchProtectionRules(ctx context.Context, gh BranchRuleChecker, job *jobs.Job, branchName string) []string {
	logger := s.obsv.LoggerWithTelemetry(ctx)
	rules := []string{}
	branchRules, err := gh.ListBranchProtectionRules(ctx, job.RepoNodeID)
	if err != nil {
		logger.WithError(err).Error("failed to list classic branch protection rules")
	}
	if branchRules != nil {
		branchRulesSuffix := "due to branch protection rules"
		for _, rule := range *branchRules {
			matched, _ := filepath.Match(rule.Pattern, branchName)
			if !matched {
				continue
			}
			if rule.BlocksCreations {
				rules = append(rules, fmt.Sprintf("%s %s", github.RuleBlockCreation, branchRulesSuffix))
			}
			if rule.RequiresCommitSignatures {
				rules = append(rules, fmt.Sprintf("%s %s", github.RuleRequireSignatures, branchRulesSuffix))
			}
			if rule.RequiresApprovingReviews {
				rules = append(rules, fmt.Sprintf("%s %s", github.RuleRequirePullRequest, branchRulesSuffix))
			}
		}
	}

	return rules
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
