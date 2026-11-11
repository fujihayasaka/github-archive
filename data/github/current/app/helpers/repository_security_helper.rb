# typed: strict
# frozen_string_literal: true

module RepositorySecurityHelper
  extend T::Helpers
  abstract!

  include GitHub::Memoizer

  sig { returns(T::Hash[Symbol, T::Boolean]) }
  def view_permissions
    {
      show_code_scanning: helper_show_code_scanning?,
      show_code_quality: helper_show_code_quality?,
    }
  end

  sig { abstract.returns(T.nilable(User)) }
  def current_user; end

  sig { abstract.returns(T.nilable(Repository)) }
  def current_repository; end

  private

  sig { returns(T::Hash[Symbol, T::Boolean]) }
  memoize def authz_view_permissions
    repo = T.must(current_repository)
    user = T.must(current_user)
    code_scanning_readable, code_quality_readable = Promise.all([
      repo.async_code_scanning_readable_by?(user),
      CodeQualityRepositoryPermissions.new(repo).async_code_quality_readable_by?(user)
    ]).sync

    {
      code_scanning_readable:,
      code_quality_readable:,
    }
  end

  sig { params(block: T.proc.params(repo: Repository, user: User).returns(T::Boolean)).returns(T::Boolean) }
  def with_current_repo_and_user(&block)
    repo = current_repository
    user = current_user
    return false if repo.nil? || user.nil?

    block.call(repo, user)
  end

  sig { returns(T::Boolean) }
  memoize def readable_by_employee?
    with_current_repo_and_user do |repo, user|
      GitHub.dotcom_request? && user.employee? && repo.readable_by?(user)
    end
  end

  sig { returns(T::Boolean) }
  def helper_show_code_quality?
    with_current_repo_and_user do |repo|
      return false unless CodeQuality.available?(repo)

      return true if readable_by_employee?

      authz_view_permissions.fetch(:code_quality_readable, false)
    end
  end

  sig { returns(T::Boolean) }
  def helper_show_code_scanning?
    with_current_repo_and_user { |repo, user| repo.show_code_scanning?(user, code_scanning_readable:) }
  end

  sig { returns(T::Boolean) }
  def code_scanning_readable
    with_current_repo_and_user do |repo|
      return false unless repo.code_scanning_usable?
      readable_by_employee? || authz_view_permissions.fetch(:code_scanning_readable, false)
    end
  end
end
