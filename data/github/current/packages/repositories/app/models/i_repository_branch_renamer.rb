# typed: strict
# frozen_string_literal: true

module IRepositoryBranchRenamer
  extend T::Sig
  extend T::Helpers
  include Kernel

  abstract!

  sig { abstract.returns(String) }
  def old_name; end

  sig { abstract.returns(::Repository) }
  def repository; end

  sig { abstract.returns(T.nilable(::RepositoryBranchRename)) }
  def rename; end

  sig { abstract.returns(T.nilable(String)) }
  def human_error; end

  sig { abstract.returns(T.nilable(Symbol)) }
  def error; end

  sig { abstract.params(raw_new_name: T.nilable(String), actor: User, entry_point: Symbol).returns(T::Boolean) }
  def start_rename(raw_new_name, actor:, entry_point:); end

  sig { abstract.returns(Integer) }
  def failed_pr_retarget_count; end

  sig { abstract.returns(T.nilable(User)) }
  def repository_owner; end

  sig { abstract.returns(T.nilable(String)) }
  def new_name; end

  sig { abstract.returns(T.nilable(User)) }
  def user; end

  sig { abstract.returns(T.nilable(T::Boolean)) }
  def default_branch?; end

  sig { abstract.returns(T.nilable(String)) }
  def old_sha; end
end
