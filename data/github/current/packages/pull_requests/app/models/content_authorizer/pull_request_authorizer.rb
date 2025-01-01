# typed: true
# frozen_string_literal: true

class ContentAuthorizer::PullRequestAuthorizer < ContentAuthorizer
  attr_accessor :repo

  def initialize(actor, operation, data)
    super
    @repo = data[:repo] || GitHub::NullRepository.new
  end

  def self.valid_operations
    super + [:apply_suggestions, :merge, :auto_merge, :enqueue, :dequeue]
  end

  # Public: All of the authorization errors blocking the given actor from
  # creating or mutating an issue. These should be assembled in priority order
  # (from most urgent/important to least) because the API will only return the
  # first error discovered.
  #
  # fail_fast - Bail out after the first failure.
  #
  # Returns an Array of ContentAuthorizationError objects.
  def errors(fail_fast: false)
    ([]).tap do |errors|
      if verified_email_required_to?(operation)
        if actor && actor.must_verify_email?
          errors << ContentAuthorizationError::EmailVerificationRequired.new
          return errors if fail_fast
        end
      end

      unless in_automated_data_transformation?
        if repo.archived?
          errors << ContentAuthorizationError::RepoArchived.new
          return errors if fail_fast
        end

        if repo.locked_on_migration?
          errors << ContentAuthorizationError::RepoLocked.new
        end
      end

      if !repo.is_a?(GitHub::NullObject)
        if operation == :create && actions_user? && disallow_actions_pull_request_creation?
          errors << ContentAuthorizationError::ActionsPullRequestCreationBlocked.new
        end
      end
    end
  end

  def actions_user?
    actor&.can_have_granular_permissions? && (integration = actor.try(:integration)) && integration.launch_github_app?
  end

  def disallow_actions_pull_request_creation?
    # The name of this setting is confusing but it is also meant to control if
    # PR creation is allowed from actions as well as approvals.
    !repo.actions_workflow_permission_can_approve_pr?
  end
end
