# typed: true
# frozen_string_literal: true

class ContentAuthorizer::BlobAuthorizer < ContentAuthorizer
  def self.valid_operations
    # BlobController uses :save instead of :update, breaking REST naming conventions.
    # Protect :delete and :destroy, because they create commits.
    super | [:save, :delete, :destroy] - [:update]
  end

  def self.operations_requiring_verified_email
    self.valid_operations
  end

  # Public: All of the authorization errors blocking the given actor from
  # creating, editing, or deleting a blob. These should be assembled in priority order
  # (from most urgent/important to least) because the API will only return the
  # first error discovered.
  #
  # fail_fast - Bail out after the first failure.
  #
  # Returns an Array of ContentAuthorizationError objects.
  def errors(fail_fast: false)
    ([]).tap do |errors|
      return errors if slumlord? # The slumlord can do whatever he wants.

      if !actor
        errors << ContentAuthorizationError::AnonymousActor.new
        return errors if fail_fast
      end

      if verified_email_required_to?(operation) && actor.must_verify_email?
        errors << ContentAuthorizationError::EmailVerificationRequired.new
      end
    end
  end

  private

  def slumlord?
    actor == :slumlord
  end
end
