# typed: strict
# frozen_string_literal: true

module RepositorySecurityHelper
  extend T::Helpers
  abstract!

  include GitHub::Memoizer

  sig { returns(T::Hash[Symbol, T::Boolean]) }
  def view_permissions
    return {} if current_user.nil? || current_repository.nil?

    {
      show_code_scanning: show_code_scanning?,
      show_code_quality: show_code_quality?,
    }
  end

  sig { abstract.returns(T.nilable(User)) }
  def current_user; end

  sig { abstract.returns(T.nilable(Repository)) }
  def current_repository; end

  private

  sig { returns(T::Hash[Symbol, T::Boolean]) }
  memoize def authz_view_permissions
    code_scanning_readable, code_quality_readable = Promise.all([
      repo.async_code_scanning_readable_by?(user),
      CodeQualityRepositoryPermissions.new(repo).async_code_quality_readable_by?(user)
    ]).sync

    {
      code_scanning_readable:,
      code_quality_readable:,
    }
  end

  sig { returns(T::Boolean) }
  memoize def readable_by_employee?
    GitHub.dotcom_request? && user.employee? && repo.readable_by?(user)
  end

  sig { returns(T::Boolean) }
  def show_code_quality?
    return true if readable_by_employee?

    authz_view_permissions.fetch(:code_quality_readable, false)
  end

  sig { returns(T::Boolean) }
  def show_code_scanning?

    repo.show_code_scanning?(user, code_scanning_readable:)
  end

  sig { returns(T::Boolean) }
  def code_scanning_readable
    return false unless repo.code_scanning_usable?

    readable_by_employee? || authz_view_permissions.fetch(:code_scanning_readable, false)
  end

  sig { returns(Repository) }
  def repo
    T.must(current_repository)
  end

  sig { returns(User) }
  def user
    T.must(current_user)
  end
end
