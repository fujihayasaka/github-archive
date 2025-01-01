# typed: true
# frozen_string_literal: true

class ContentAuthorizer::MergeQueueAuthorizer < ContentAuthorizer
  attr_accessor :repo

  def initialize(actor, operation, data)
    super
    @repo = data[:repo] || GitHub::NullRepository.new
  end

  def self.valid_operations
    super + [:lock, :unlock_merge_group, :force_clear_merge_queue, :unlock_and_reset_merge_group, :merge_locked_merge_group]
  end

  # Public: All of the authorization errors blocking the given actor from
  # creating or mutating the target. These should be assembled in priority order
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
    end
  end
end
