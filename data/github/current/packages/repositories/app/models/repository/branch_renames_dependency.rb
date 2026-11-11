# typed: true
# frozen_string_literal: true

module Repository::BranchRenamesDependency
  extend T::Helpers

  requires_ancestor { Repository }

  # Public: Check permission of the given user to rename the specified branch in this repository.
  #
  # actor - the currently authenticated User
  # branch - String branch name to check
  #
  # Returns a Boolean.
  def branch_renameable_by?(actor, branch:)
    ref = Git::Ref.new(repository, branch, nil, "refs/heads/")
    ref_renameable_by?(actor, ref: ref)
  end

  # Public: Check permission of the given user to rename the specified ref in this repository.
  #
  # actor - the currently authenticated User
  # branch - Git::Ref to check
  #
  # Returns a Boolean.
  sig { params(actor: T.untyped, ref: Git::Ref).returns(T::Boolean) }
  def ref_renameable_by?(actor, ref:)
    if ref.name.b == default_branch.b || ref.protected?
      if ref.protected_by_org_ruleset?
        # you need to be an admin of the org to rename org protected branches
        case actor
        when Bot
          return false unless owner&.resources.organization_administration.writable_by?(actor)
        when User
          return false unless owner&.adminable_by?(actor)
        end
      end

      default_branch_renameable_by?(actor)
    else
      non_default_branches_renameable_by?(actor)
    end
  end

  # Public: Get information about the last time the given branch was renamed, if ever.
  #
  # old_name - String name for what the branch used to be called; could be a branch
  #            that no longer exists in this repository; pass if `new_name` is not
  #            specified
  # new_name - String name for what the branch is currently called; pass if `old_name`
  #            is not specified
  #
  # Returns the most recent RepositoryBranchRename record for that branch or nil.
  def branch_rename_for(old_name: nil, new_name: nil)
    renames = branch_renames
    if old_name
      renames = renames.for_old_name(old_name)
    elsif new_name
      renames = renames.for_new_name(new_name)
    end
    renames.finished.latest.first
  end

  # Public: Get branches that are in the process of being renamed.
  #
  # Returns an Array of String branch names.
  def branches_being_renamed
    branch_renames.started.pluck(:old_name)
  end

  # Public: Get branch renames that failed when the rename was attempted recently.
  #
  # Returns a RepositoryBranchRename ActiveRecord::Relation.
  def recently_errored_branch_renames
    branch_renames.errored.since(2.weeks.ago)
  end

  # Public: Is the given branch in the middle of being renamed?
  #
  # branch - String branch name, e.g., "master"
  #
  # Returns a Boolean.
  def branch_being_renamed?(branch)
    branch_renames.where(old_name: branch).started.any?
  end

  # Public: Was the specified branch only given that name within the last two weeks?
  def branch_recently_renamed?(branch)
    branch_renames.for_new_name(branch).finished.since(2.weeks.ago).any?
  end

  private

  # Private: Can the given user rename a non-default branch in this repository?
  def non_default_branches_renameable_by?(actor)
    resources.contents.writable_by?(actor)
  end

  # Private: Can the given user rename the default branch of this repository?
  def default_branch_renameable_by?(actor)
    case actor
    when Botable
      resources.administration.writable_by?(actor)
    else
      adminable_by?(actor)
    end
  end
end
