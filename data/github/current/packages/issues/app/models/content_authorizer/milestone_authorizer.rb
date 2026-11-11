# typed: true
# frozen_string_literal: true

class ContentAuthorizer::MilestoneAuthorizer < ContentAuthorizer
  def initialize(actor, operation, data)
    super
    @repository = data[:repository]
  end

  # Public: All of the authorization errors blocking the given actor from
  # creating or modifying a milestone. These should be assembled in priority order
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

      if !in_automated_data_transformation? && @repository.locked_on_migration?
        errors << ContentAuthorizationError::RepoLocked.new
        return errors if fail_fast
      end

      if @repository.archived?
        errors << ContentAuthorizationError::RepoArchived.new
        return errors if fail_fast
      end
    end
  end
end
