# typed: true
# frozen_string_literal: true

class Environments::ProtectedBranchesGateComponent < ApplicationComponent
  include BranchDeploymentPolicyHelper

  def initialize(repository:, page:, edit_repository_branches_path:)
    @repository = repository
    @page = page
    @edit_repository_branches_path = edit_repository_branches_path
  end

  memoize def protected_branches
    @repository.protected_branches.paginate(
      page: @page || 1,
      per_page: 100,
    )
  end

  memoize def protected_branch_names
    protected_branches.map { |protected_branch| protected_branch.name  }
  end

  memoize def matching_rules
    get_match_ref_rule_count(@repository.heads, protected_branch_names)
  end

  def matching_count(name)
    matching_rules[:matchings][name].length
  end

  def scrub_name(name)
    name.dup.force_encoding("utf-8")
  end

  def pr_pattern_matching_enabled?
    FeatureFlag.vexi.enabled?("actions_branch_policy_pr_event_ref_matching", @repository, default: false) ||
      FeatureFlag.vexi.enabled?("actions_branch_policy_pr_event_ref_matching", @repository.owner, default: false)
  end

  def is_pull_request_pattern?(name)
    return false unless pr_pattern_matching_enabled?

    # Match both wildcard pattern "refs/pull/*/merge" and specific PR patterns like "refs/pull/10/merge"
    name.match?(/\Arefs\/pull\/(?:\*|\d+)\/merge\z/)
  end
end
