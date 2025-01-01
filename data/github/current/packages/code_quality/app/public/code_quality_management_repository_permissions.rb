# typed: strict
# frozen_string_literal: true

# CodeQualityManagementRepositoryPermissions is a centralised place for methods that check permissions
# related to managing code quality for a repository.
class CodeQualityManagementRepositoryPermissions

  sig { returns(Repository) }
  attr_reader :repository

  sig { params(repository: Repository).void }
  def initialize(repository)
    @repository = repository
  end

  # Main public interface methods

  # Permissions checks for manging Code Quality are adapted from SecurityProduct::Permissions::RepoAuthz, which used
  # to be called directly. Splitting it out allows it to change independently in future, and also moves towards the
  # goal described in the TODO comments in that class, which is to have more specific permission checks.
  sig { params(user: T.nilable(User)).returns(T::Boolean) }
  def code_quality_manageable_by?(user)
    async_code_quality_manageable_by?(user).sync
  end

  private

  sig { params(user: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_code_quality_manageable_by?(user)
    action = :manage_repo_security_products

    repository.async_owner.then do |owner|
      next repository.async_adminable_by?(user) unless owner.is_a?(::Organization)
      async_managing_code_quality_allowed?(action, user)
    end
  end

  # Authzd permission check for enabling/disabling code quality
  sig { params(action: Symbol, user: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_managing_code_quality_allowed?(action, user)
    result =
      if user
        res = Platform::Loaders::Permissions::BatchAuthorize.load(
          action: action,
          actor: user,
          subject: repository,
        )
      else
        Promise.resolve(Authzd::DENY)
      end

    result.then do |decision|
      if decision.error?
        Failbot.report(StandardError.new(decision.error),
          "gh.code_quality.authz_action": action,
          "gh.repo.id": repository.id,
          "gh.actor.login": user&.display_login
        )
      end
      decision.allow?
    end
  end
end
