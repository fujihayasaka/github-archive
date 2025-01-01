# typed: true
# frozen_string_literal: true

# Encapsulates organization invitation rate limiting behaviors.
#
# An organization can be classified as:
# * untrusted - the organization is brand new (and untrusted)
# * trusted   - the organization has existed for a minimum period of time
# * paying    - the organization is on a paid plan/paying for seats
#
class OrganizationInvitation::RateLimitPolicy
  attr_reader :organization

  TRUSTED_AGE_REQUIREMENT = 1.month

  TTL = 1.day

  LIMITS = {
    untrusted: GitHub.org_invite_rate_limit_untrusted,
    trusted: GitHub.org_invite_rate_limit_trusted,
    paying: GitHub.org_invite_rate_limit_paying,
  }

  def initialize(organization)
    @organization = organization
  end

  def classification
    load_custom_limit
    if custom?
      :custom
    elsif paying?
      :paying
    elsif trusted?
      :trusted
    else
      :untrusted
    end
  end

  def paying?
    return false if custom?
    organization.plan.paid?
  end

  def trusted?
    return false if custom?
    paying? || organization.created_at < TRUSTED_AGE_REQUIREMENT.ago
  end

  def custom?
    load_custom_limit
    !!@custom_limit
  end

  # Public: The time at which the custom limit expires if set.
  #
  # Returns Time
  def custom_limit_expires_at
    return @custom_limit_expires_at if defined?(@custom_limit_expires_at)
    @custom_limit_expires_at = if custom?
      GitHub.kv.ttl(custom_limit_key).value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv
    else
      nil
    end
  end

  # The limit of how many times an invitation can be sent per IP address in
  # a long period (usually 1 day).
  #
  # Returns an Integer limit that can be combined with a ttl.
  def limit
    load_custom_limit
    @limit ||= LIMITS[classification]
  end
  attr_writer :limit

  # The lifespan of an organization invite rate limit in a long period.
  #
  # Returns an Integer duration representing time in seconds.
  def ttl
    TTL
  end

  def custom_limit_key
    "orgs.#{organization.id}.invitations.rate_limit"
  end

  # Public: Set a custom rate limit for this policy.
  #
  # custom_limit - Integer or a String that can be cast as an Integer,
  #   such as from query parameters, representing the custom limit.
  # expires_at - Time at which the custom limit should expire
  #
  # Returns Hash containing:
  # - `success` key always, containing a Boolean value indicating success
  # - `expires_at` key optionally, if a valid expires_at value was set
  # - `errors` key optionally if unsuccessful, containing an Array of String representing errors
  def set_custom_limit(custom_limit, expires_at: nil)
    @limit = @custom_limit = Integer(custom_limit)

    expires_at_time = nil
    if expires_at.present?
      if valid_expires_at?(expires_at)
        expires_at_time = Date.parse(expires_at.to_s).to_time
      else
        return { success: false, errors: ["Rate limit expiry date must be a valid date in the future"] }
      end
    end
    GitHub.kv.set(custom_limit_key, @custom_limit.to_s, expires: expires_at_time) # rubocop:todo GitHub/DoNotUseGlobalKv

    payload = { limit: limit }
    payload[:expires_at] = expires_at_time if expires_at_time.present?
    organization.instrument :set_custom_invitation_rate_limit, payload

    result = { success: true, expires_at: expires_at_time }
    result[:expires_at] = expires_at_time if expires_at_time.present?
    result
  rescue ArgumentError
    { success: false }
  end

  # Public: Remove custom rate limit for this policy.
  #
  # Returns true.
  def clear_custom_limit
    GitHub.kv.del(custom_limit_key) # rubocop:todo GitHub/DoNotUseGlobalKv
    remove_instance_variable(:@limit) if defined?(@limit)
    remove_instance_variable(:@custom_limit) if defined?(@custom_limit)

    organization.instrument :clear_custom_invitation_rate_limit, limit: limit

    true
  end

  # Public: Records that this policy hit its rate limit.
  #
  # Called by controllers implementing Orgs::Invitations::RateLimiting as part
  # of the `at_limit` handling.
  #
  # Returns nothing.
  def record_rate_limited(action_name, controller_name)
    GitHub.dogstats.increment("rate_limited", tags: ["action:#{action_name}", "controller:#{controller_name}"])

    organization.instrument :rate_limited_invites,
      limit: limit, policy: classification
  end

  private

  # Private: Check whether a given expiry value is valid for a custom rate limit.
  #
  # expires_at - String containing the expiry date in the format YYYY-MM-DD.
  #
  # Returns Boolean.
  def valid_expires_at?(expires_at)
    Date.parse(expires_at.to_s).to_time.future?
  rescue ArgumentError
    false
  end

  # Internal: Load a custom limit Integer when it exists.
  #
  # Returns nil if no custom limit is set for the organization, or the custom
  # Integer limit otherwise.
  def load_custom_limit
    return @custom_limit if defined?(@custom_limit)
    @custom_limit =
      if custom_limit = GitHub.kv.get(custom_limit_key).value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv
        @limit = Integer(custom_limit)
      end
  end
end
