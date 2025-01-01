# typed: true
# frozen_string_literal: true

# Public: Used to rename a branch in a repository and update various records and references around
# the site that were pointing to the old branch name, such as pull requests and releases.
class RepositoryBranchRenamer
  include IRepositoryBranchRenamer

  attr_reader :old_name
  attr_reader :repository

  sig { params(branch_name: T.nilable(String), repository: Repository).returns(RepositoryBranchRenamer) }
  def self.for_starting_rename_process(branch_name:, repository:)
    new(repository: repository, old_name: branch_name)
  end

  def initialize(repository:, old_name:)
    @repository = repository
    @old_name = old_name
    @orchestration = nil
  end

  sig { override.params(raw_new_name: T.nilable(String), actor: User, entry_point: Symbol).returns(T::Boolean) }
  def start_rename(raw_new_name, actor:, entry_point:)
    @orchestration = RepositoryOrchestration.rename_branch(
      repository: repository,
      actor: actor,
      old_name: old_name,
      raw_new_name: raw_new_name,
      entry_point: entry_point
    )
    return false unless @orchestration.valid?
    @orchestration.execute!
    return false if @orchestration.skipped? || @orchestration.failed?

    true
  end

  sig { override.returns(T.nilable(String)) }
  def human_error
    @orchestration&.human_error
  end

  sig { override.returns(T.nilable(Symbol)) }
  def error
    @orchestration&.error
  end

  sig { override.returns(Integer) }
  def failed_pr_retarget_count
    (@orchestration && @orchestration.reload.data[:failed_pr_retarget_count]) || 0
  end

  sig { override.returns(T.nilable(RepositoryBranchRename)) }
  def rename
    @orchestration&.rename
  end

  sig { override.returns(T.nilable(User)) }
  def repository_owner
    repository.owner
  end

  sig { override.returns(T.nilable(String)) }
  def new_name
    rename&.new_name
  end

  sig { override.returns(T.nilable(User)) }
  def user
    rename&.user
  end

  sig { override.returns(T.nilable(T::Boolean)) }
  def default_branch?
    rename&.default_branch?
  end

  sig { override.returns(T.nilable(String)) }
  def old_sha
    rename&.old_sha
  end
end
