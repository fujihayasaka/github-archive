# typed: true
# frozen_string_literal: true

class ContentAuthorizer::OrganizationInvitationAuthorizer < ContentAuthorizer
  # Public: All of the authorization errors blocking the given actor from
  # creating an organization invitation. These should be assembled in
  # priority order (from most urgent/important to least) because the API
  # will only return the first error discovered.
  #
  # fail_fast - Bail out after the first failure.
  #
  # Returns an Array of ContentAuthorizationError objects.
  def errors(fail_fast: false)
    errors = []

    if actor.must_verify_email? && verified_email_required_to?(operation)
      errors << ContentAuthorizationError::EmailVerificationRequired.new
      return errors if fail_fast
    end

    errors
  end
end
