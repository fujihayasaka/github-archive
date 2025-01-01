# typed: strict
# frozen_string_literal: true

# CodeQualityRepositoryPermissions is a centralised place for methods that check permissions
# related to code quality results for a repository.
class CodeQualityRepositoryPermissions

  sig { returns(Repository) }
  attr_reader :repository

  sig { params(repository: Repository).void }
  def initialize(repository)
    @repository = repository
  end

  # Main public interface methods

  sig { params(user: T.nilable(User)).returns(T::Boolean) }
  def code_quality_readable_by?(user)
    code_quality_readable_permission_check_only_by?(user)
  end

  sig { params(user: T.nilable(User)).returns(T::Boolean) }
  def code_quality_writable_by?(user)
    async_code_quality_allowed?(:write_code_quality, user).sync
  end

  private

  # Permission check without feature enablement checks
  sig { params(user: T.nilable(User)).returns(T::Boolean) }
  def code_quality_readable_permission_check_only_by?(user)
    # On dotcom, grants hubbers read-only access to code quality pages.
    # This functionality can be disabled by disabling employee mode (in the footer).
    # In the case of private repositories it is still required that the hubber has
    # gained read access to the repository through some means.
    if GitHub.dotcom_request? && user.present? && user.employee?
      return repository.readable_by?(user)
    end

    async_code_quality_allowed?(:read_code_quality, user).sync
  end

  # Authzd permission check for code quality results
  sig { params(action: Symbol, user: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_code_quality_allowed?(action, user)
    permissions = [:write_code_quality]
    # We pass a list of acceptable permissions to authz, i.e. permissions that will grant access if the user has them.
    # Write permission is always sufficient to grant access, and if we're validating a read action then the read
    # permission is considered allowed too.
    # These are fine-grained permissions; the authz policy also checks for more general role-based access as well.
    acceptable_permissions = [:write_code_quality]
    acceptable_permissions << :read_code_quality if action == :read_code_quality

    result =
      if user
        res = Platform::Loaders::Permissions::BatchAuthorize.load(
          action: action,
          actor: user,
          subject: repository,
          context: { permissions: acceptable_permissions }
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
