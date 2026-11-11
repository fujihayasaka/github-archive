# typed: true
# frozen_string_literal: true

class ContentAuthorizer::ProjectAuthorizer < ContentAuthorizer
  attr_reader :owner, :project

  def initialize(actor, operation, data)
    super
    @project = data[:project]
    @owner = @project&.owner || data[:owner]
  end

  # Public: All of the authorization errors blocking the given actor from
  # creating or modifying a project. These should be assembled in priority order
  # (from most urgent/important to least) because the API will only return the
  # first error discovered.
  #
  # fail_fast - Bail out after the first failure.
  #
  # Returns an Array of ContentAuthorizationError objects.
  def errors(fail_fast: false)
    @errors ||= ([]).tap do |errors|
      if verified_email_required_to?(operation)
        if actor.must_verify_email?
          errors << ContentAuthorizationError::EmailVerificationRequired.new
          return errors if fail_fast
        end
      end

      if project&.locked_for?(Project::ProjectLock::PROJECT_RESYNCING) && !project.automation_context?
        errors << ContentAuthorizationError::ProjectLocked.new(lock_type: "automation resync")
        return errors if fail_fast
      end

      if owner.is_a?(Repository) && !in_automated_data_transformation?
        if owner.locked_on_migration?
          errors << ContentAuthorizationError::RepoLocked.new
          return errors if fail_fast
        elsif owner.archived?
          errors << ContentAuthorizationError::RepoArchived.new
          return errors if fail_fast
        end
      end

      if project&.locked_for?(Project::ProjectLock::PROJECT_CLONING) && !project.job_context?(Project::ProjectLock::PROJECT_CLONING)
        errors << ContentAuthorizationError::ProjectLocked.new(lock_type: "copying")
        return errors if fail_fast
      end
    end
  end
end
