# typed: true
# frozen_string_literal: true

class ContentAuthorizer::StarAuthorizer < ContentAuthorizer

  def initialize(actor, operation, data)
    super
    @starrable = data[:starrable]
  end

  # Public: All of the authorization errors blocking the given actor from
  # starring a repo. These should be assembled in priority order
  # (from most urgent/important to least) because the API will only
  # return the first error discovered.
  #
  # fail_fast - Bail out after the first failure.
  #
  # Returns an Array of ContentAuthorizationError objects.
  def errors(fail_fast: false)
    errors = []

    if email_verification_required?
      errors << ContentAuthorizationError::EmailVerificationRequired.new
      GitHub.dogstats.increment "user.star_blocked_by_email_verification"
      return errors if fail_fast
    end

    # This currently just checks if the author is blocked by the target owner, but more validation will be added in https://github.com/github/ce-community-and-safety/issues/1306
    unless authorized_to_star?
      errors << ContentAuthorizationError::ActorBlockedByTargetOwner.new
    end

    errors
  end

  private

  def email_verification_required?
    return false if GitHub.enterprise?
    actor.must_verify_email? && verified_email_required_to?(operation)
  end

  def authorized_to_star?
    if @starrable.is_a?(Repository)
      authorized_with_authzd?
    else
      authorized_with_legacy_check?
    end
  end

  def authorized_with_authzd?
    ::Permissions::Enforcer.authorize(actor: actor, action: :star_repo, subject: @starrable).allow?
  end

  def authorized_with_legacy_check?
    !(@starrable.respond_to?(:owner) && actor.blocked_by?(@starrable.owner))
  end
end
