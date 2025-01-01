# typed: true
# frozen_string_literal: true

class ContentAuthorizer::DiscussionPostAuthorizer < ContentAuthorizer
  # Public: All of the authorization errors blocking the given actor from
  # creating or modifying a team discussion. These should be assembled in
  # priority order (from most urgent/important to least) because the API will
  # only return the first error discovered.
  #
  # fail_fast - Bail out after the first failure.
  #
  # Returns an Array of ContentAuthorizationError objects.
  sig { params(fail_fast: T.untyped).returns(T.untyped) }
  def errors(fail_fast: false)
    ([]).tap do |errors|
      if verified_email_required_to?(operation) && actor.must_verify_email?
        errors << ContentAuthorizationError::EmailVerificationRequired.new
        return errors if fail_fast
      end
    end
  end
end
