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
end
