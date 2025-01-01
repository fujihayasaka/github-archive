# typed: true
# frozen_string_literal: true

module User::TwoFactorCheckupDependency
  extend T::Helpers
  requires_ancestor { User }

  GRACE_PERIOD_LENGTH = 28.days
  TOTAL_ALLOWED_DEFERMENTS = 3

  # Two Factor Checkup
  #
  # After a user configures their 2FA, we set a 28 day delay after which they are shown a 2FA checkup
  # asking them to complete a 2FA prompt to confirm they still have access to their configured method.
  # If the user has completed a 2FA prompt naturally, they will not be shown the checkup.

  def two_factor_checkup_key
    "user.two_factor_checkup_due_at.#{self.id}"
  end

  def two_factor_checkup_delay_key
    "user.two_factor_checkup_delay_count.#{self.id}"
  end

  def set_two_factor_checkup_date
    clear_two_factor_checkup_delay_count
    GitHub.dogstats.increment("authn_kv", tags: ["action:write", "callsite:two_factor_checkup"])
    GitHub::Authentication::KV.store.set(two_factor_checkup_key, (Time.now.utc + GRACE_PERIOD_LENGTH).to_s)
  end

  def clear_two_factor_checkup_date(force_hit_kv = false)
    return nil unless two_factor_authentication_enabled?

    # Don't hit the KV if the user has logged in since creating their 2FA credential (the KV value wont exist anymore)
    # but allow the force_hit_kv flag to override this behavior
    unless force_hit_kv
      latest_session = self.sessions.order(created_at: :desc).first
      return nil if !latest_session&.created_at.nil? && latest_session.created_at > T.must(self.two_factor_credential).created_at
    end

    GitHub.dogstats.increment("authn_kv", tags: ["action:delete", "callsite:two_factor_checkup"])
    GitHub::Authentication::KV.store.del(two_factor_checkup_key)
    clear_two_factor_checkup_delay_count
  end

  def clear_two_factor_checkup_delay_count
    return nil unless two_factor_authentication_enabled?

    GitHub.dogstats.increment("authn_kv", tags: ["action:delete", "callsite:two_factor_checkup_delay"])
    GitHub::Authentication::KV.store.del(two_factor_checkup_delay_key)
  end

  def increment_two_factor_checkup_delay_count
    return nil unless two_factor_authentication_enabled?

    new_delay_count = nil
    if can_delay_two_factor_checkup?
      GitHub.dogstats.increment("authn_kv", tags: ["action:write", "callsite:two_factor_checkup_delay"])
      new_delay_count = GitHub::Authentication::KV.store.increment(two_factor_checkup_delay_key)
    else
      return false
    end

    GitHub.dogstats.increment("authn_kv", tags: ["action:write", "callsite:two_factor_checkup"])
    GitHub::Authentication::KV.store.set(two_factor_checkup_key, (Time.now.utc + 1.day).to_s)
    GitHub.dogstats.increment("two_factor_checkup.delay_count", tags: ["count:#{new_delay_count}"])
    true
  end

  def is_due_for_two_factor_checkup?
    value = get_two_factor_checkup_date
    return false if value.nil?

    value <= Time.now.utc
  end

  def can_delay_two_factor_checkup?
    get_two_factor_checkup_delay_count.nil? ? true : get_two_factor_checkup_delay_count.to_i < TOTAL_ALLOWED_DEFERMENTS
  end

  def is_flagged_for_two_factor_checkup?
    get_two_factor_checkup_date.nil? ? false : true
  end

  private

  def get_two_factor_checkup_date
    return nil unless two_factor_authentication_enabled?

    GitHub.dogstats.increment("authn_kv", tags: ["action:read", "callsite:two_factor_checkup"])
    value = GitHub::Authentication::KV.store.get(two_factor_checkup_key).value { nil }

    return nil if value.nil?
    Time.parse(value)
  end

  def get_two_factor_checkup_delay_count
    return nil unless two_factor_authentication_enabled?

    GitHub.dogstats.increment("authn_kv", tags: ["action:read", "callsite:two_factor_checkup_delay"])
    GitHub::Authentication::KV.store.get(two_factor_checkup_delay_key).value { nil }
  end
end
