# typed: true
# frozen_string_literal: true
class Environments::CustomBranchesAndTagsPoliciesComponent < ApplicationComponent
  include BranchDeploymentPolicyHelper
  def initialize(repository:, environment:)
    @repository = repository
    @environment = environment
  end

  def repository
    @repository
  end

  memoize def owner
    @repository.owner
  end

  def has_custom_branch_policies?
    @environment.branch_policy_gate.present? && branch_policies.any?
  end

  memoize def branch_policies
    @environment.branch_policy_gate.branch_policies
  end

  def branch_policy_names
    branch_policies.reject { |branch_policy| branch_policy.is_tag_policy? }.map { |branch_policy| branch_policy.name }
  end

  memoize def matching_branch_rules
    get_match_ref_rule_count(@repository.heads, branch_policy_names, check_max_target: true)
  end

  def matching_branch_count(name)
    matching_branch_rules[:total_count] == -1 ? -1 : matching_branch_rules[:matchings][name].length
  end

  def matching_branches(name)
    return [] unless matching_branch_rules[:matchings].key?(name)
    matching_branch_rules[:matchings][name].map! { |x| scrubbed_utf8(x) }
  end

  def tag_policy_names
    branch_policies.select { |branch_policy| branch_policy.is_tag_policy? }.map { |branch_policy| branch_policy.name }
  end

  memoize def matching_tag_rules
    get_match_ref_rule_count(@repository.tags, tag_policy_names, check_max_target: true)
  end

  def matching_tag_count(name)
    matching_tag_rules[:total_count] == -1 ? -1 : matching_tag_rules[:matchings][name].length
  end

  def matching_tags(name)
    return [] unless matching_tag_rules[:matchings].key?(name)
    matching_tag_rules[:matchings][name]&.map! { |x| scrubbed_utf8(x) }
  end

  def matching_ref_total_count
    message = ""
    message += pluralize(matching_branch_rules[:total_count], "branch") if matching_branch_rules[:total_count] != -1
    message += " and #{pluralize(matching_tag_rules[:total_count], "tag")}" if matching_tag_rules[:total_count] != -1
  end
end
