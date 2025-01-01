# typed: true
# frozen_string_literal: true

module Repository::BranchProtectionDependency
  extend ActiveSupport::Concern

  def branch_protection_for(branch)
    @branch_protection ||= {}
    @branch_protection[branch] ||= ProtectedBranch.for_repository_with_branch_name(self, branch)
  end

  def branch_protected?(branch)
    branch_protection_for(branch).present?
  end
end
