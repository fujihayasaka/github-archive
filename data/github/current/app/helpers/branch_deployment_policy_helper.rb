# typed: true
# frozen_string_literal: true

module BranchDeploymentPolicyHelper
  # Max taken from MAX_BRANCHES_TO_CALCULATE_WILDCARD_MATCHES in packages/branch_protections/app/models/protected_branch.rb
  MAX_TARGET_REFS = 10000

  def get_match_ref_rule_count(target_refs, ref_rules, check_max_target: false)
    wildcard_ref_rules, exact_ref_rules = ref_rules.partition { |rule| wildcard_rule?(rule) }
    total_count = 0
    matchings = ref_rules.map { |rule| [rule, []] }.to_h

    return { total_count: -1, matchings: {} }  if check_max_target && target_refs.size > MAX_TARGET_REFS

    target_refs.each do |ref|
      match = false

      # check exact name matching, and calculate count.
      if exact_ref_rules.include?(ref.name)
        match = true
        matchings[ref.name] << ref.name
      end

      # check wild card name matching
      wildcard_ref_rules.each do |wildcard_branch_rule|
        if matches?(wildcard_branch_rule, ref.name)
          match = true
          matchings[wildcard_branch_rule] << ref.name
        end
      end
      total_count += 1 if match
    end
    { total_count: total_count, matchings: matchings }
  end

  CONTAINS_WILDCARD = /\*|\?|\\|\[/.freeze
  def wildcard_rule?(rule)
    rule.match?(CONTAINS_WILDCARD)
  end

  def matches?(branch_rule, branch_name)
    File.fnmatch?(branch_rule, branch_name, File::FNM_PATHNAME)
  end
end
