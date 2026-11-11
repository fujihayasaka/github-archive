# typed: true
# frozen_string_literal: true

class ContentAuthorizer::WikiAuthorizer < ContentAuthorizer
  attr_accessor :wiki

  def initialize(actor, operation, data)
    super
    # an Unsullied::Wiki object used to compare its owner against
    @wiki = data.fetch(:wiki) { GitHub::NullWiki.new }
  end

  def self.valid_operations
    super + [:revert]
  end

  def self.operations_requiring_verified_email
    super + [:delete, :destroy, :revert]
  end

  # Public: All of the authorization errors blocking the given actor from
  # creating or mutating a wiki. These should be assembled in priority order
  # (from most urgent/important to least) because the API will only return the
  # first error discovered.
  #
  # fail_fast - Bail out after the first failure.
  #
  # Returns an Array of ContentAuthorizationError objects.
  def errors(fail_fast: false)
    ([]).tap do |errors|
      if actor.must_verify_email? && verified_email_required_to?(operation)
        errors << ContentAuthorizationError::EmailVerificationRequired.new
        return errors if fail_fast
      end

      if GitHub.spamminess_check_enabled? && actor.spammy? && wiki.repository.owner_id != actor.id
        errors << ContentAuthorizationError::SpammyCantDoThat.new(operation, "wiki pages")
        return errors if fail_fast
      end
    end
  end
end
