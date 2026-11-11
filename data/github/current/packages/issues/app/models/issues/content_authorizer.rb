# typed: true
# frozen_string_literal: true

class Issues::ContentAuthorizer < ContentAuthorizer
  include GitHub::ResilienceMixin

  attr_accessor :repo

  def initialize(actor, operation, data)
    super
    @repo = data[:repo] || GitHub::NullRepository.new
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

      if repo.archived?
        errors << ContentAuthorizationError::RepoArchived.new
        return errors if fail_fast
      end

      is_importing = repo.is_a?(Repository) && with_database_error_fallback(fallback: false) do
        ImportExport.domain.is_importing?(repo)
      end

      if !in_automated_data_transformation? && (repo.locked_on_migration? || is_importing)
        errors << ContentAuthorizationError::RepoLocked.new
        return errors if fail_fast
      end
    end
  end
end
