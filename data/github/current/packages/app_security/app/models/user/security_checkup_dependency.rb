# typed: true
# frozen_string_literal: true

module User::SecurityCheckupDependency
  extend T::Helpers
  requires_ancestor { User }

  SECURITY_CHECKUP_INTERVAL = 3.months
  SECURITY_CHECKUP_POSTPONED_INTERVAL = 1.week
  SECURITY_CHECKUP_RECENCY_INTERVAL = 1.hour

  # User Security Checkup
  #
  # Every SECURITY_CHECKUP_INTERVAL, we show users the Security Checkup screen.
  #
  # When they complete the screen (security_checkup_completed), we record the time,
  # which we then compare against SECURITY_CHECKUP_INTERVAL to determine whether
  # to show them the screen again.
  #
  # When the user chooses to postpone the Security Checkup (security_checkup_postponed),
  # we update security_checkup_completed_at by SECURITY_CHECKUP_POSTPONED_INTERVAL,
  # moving the reminder forward that amount of time.
  #
  # In designing this implementation, we considered storing the timestamp as something
  # along the lines of `security_checkup_next_due_at`, but decided against doing so
  # as that would limit our ability to change the SECURITY_CHECKUP_INTERVAL, at least
  # without doing a transition of some sort.

  def security_checkup_key
    "user.security_checkup_completed_at.#{self.id}"
  end

  def security_checkup_completed(type = nil)
    GitHub.dogstats.increment("authn_kv", tags: ["action:write", "callsite:security_checkup"])
    kv_success = GitHub::Authentication::KV.store.try_set(security_checkup_key, Time.now.utc.to_s)
    unless kv_success
      GitHub.dogstats.increment("kv_unavailable", tags: { service_owner: :account_login, callsite: :security_checkup_completed, action: :set })
    end

    if type == "updated"
      GitHub.dogstats.increment("authn_kv", tags: ["action:write", "callsite:security_checkup_action"])
      kv_success = GitHub::Authentication::KV.store.try_set(security_checkup_action_key, "true", expires: SECURITY_CHECKUP_RECENCY_INTERVAL.from_now)
      unless kv_success
        GitHub.dogstats.increment("kv_unavailable", tags: { service_owner: :account_login, callsite: :security_checkup_completed_action, action: :set })
      end
    end
  end

  def security_checkup_postponed
    GitHub.dogstats.increment("authn_kv", tags: ["action:write", "callsite:security_checkup"])
    kv_success = GitHub::Authentication::KV.store.try_set(security_checkup_key, (Time.now.utc - SECURITY_CHECKUP_INTERVAL + SECURITY_CHECKUP_POSTPONED_INTERVAL).to_s)
    unless kv_success
      GitHub.dogstats.increment("kv_unavailable", tags: { service_owner: :account_login, callsite: :security_checkup_postponed, action: :set })
    end
  end

  def security_checkup_due?
    return false unless two_factor_authentication_enabled?

    GitHub.dogstats.increment("authn_kv", tags: ["action:read", "callsite:force_security_checkup"])
    if GitHub::Authentication::KV.store.get(force_security_checkup_key).value { nil } == "true"
      return true
    end

    GitHub.dogstats.increment("authn_kv", tags: ["action:read", "callsite:security_checkup"])
    value = GitHub::Authentication::KV.store.get(security_checkup_key).value { nil }

    if value.present?
      Time.parse(value) < Time.now.utc - SECURITY_CHECKUP_INTERVAL
    elsif two_factor_credential&.created_at
      # Fall back to an offset of the two factor credential creation date, to prevent
      # us from nagging users who _just_ enrolled.
      T.must(T.must(two_factor_credential).created_at) < Time.now.utc - SECURITY_CHECKUP_POSTPONED_INTERVAL
    else
      true
    end
  end

  def security_checkup_action_key
    "security-checkup-updated:#{self.id}"
  end

  def force_security_checkup_key
    "security-checkup-force:#{self.id}"
  end

  def force_security_checkup!
    ActiveRecord::Base.connected_to(role: :writing) do
      GitHub.dogstats.increment("authn_kv", tags: ["action:write", "callsite:force_security_checkup"])
      kv_success = GitHub::Authentication::KV.store.try_set(force_security_checkup_key, "true")
      unless kv_success
        GitHub.dogstats.increment("kv_unavailable", tags: { service_owner: :account_login, callsite: :force_security_checkup, action: :set })
      end
    end
  end

  def clear_force_security_checkup!
    GitHub.dogstats.increment("authn_kv", tags: ["action:read", "callsite:force_security_checkup"])
    force_security_checkup_value = GitHub::Authentication::KV.store.get(force_security_checkup_key).value { nil }

    if force_security_checkup_value.present?
      ActiveRecord::Base.connected_to(role: :writing) do
        begin
          GitHub.dogstats.increment("authn_kv", tags: ["action:delete", "callsite:force_security_checkup"])
          GitHub::Authentication::KV.store.del(force_security_checkup_key)
        rescue GitHub::KV::UnavailableError
          GitHub.dogstats.increment("kv_unavailable", tags: { service_owner: :account_login, callsite: :clear_force_security_checkup, action: :del })
        end
      end
    end
  end

  def two_factor_related_global_notice?
    notice_name = self.global_notice.name

    %w(low_two_factor_methods sms_low_availability_country).include?(notice_name)
  end

  def recovery_codes_related_global_notice?
    notice_name = self.global_notice.name

    %w(two_factor_low_recovery_codes two_factor_recovery_codes year_old_recovery_codes).include?(notice_name)
  end

  def verified_emails_related_global_notice?
    notice_name = self.global_notice.name

    %w(one_verified_email verified_emails).include?(notice_name)
  end

  def recently_took_action_on_security_checkup?
    GitHub.dogstats.increment("authn_kv", tags: ["action:read", "callsite:security_checkup_action"])
    !!GitHub::Authentication::KV.store.get(security_checkup_action_key).value { nil }
  end

  def instrument_security_checkup(event)
    GitHub.dogstats.increment("user.security_checkup", tags: ["action:#{event}"])
    instrument "security_checkup_#{event}".to_sym, { actor: self }
  end

  def recovery_codes_status
    start = Time.now
    return nil unless GitHub.flipper[:recovery_codes_last_viewed_details_via_audit_log].enabled?

    return @recovery_codes_status if defined? @recovery_codes_status
    @recovery_codes_status = begin
      query = {
        user_id: self.id,
      }
      recovery_events = Audit::Driftwood::Query.new_2fa_user_query(query).execute.results

      return nil unless recovery_events.any?

      latest_event = recovery_events.first

      {
        action: latest_event[:action].split("_").last.capitalize,
        created_at: Time.at(latest_event[:created_at] / 1000),
      }
    end
  rescue StandardError => e # rubocop:todo Lint/GenericRescue
    GitHub.dogstats.increment("user.recovery_codes_status.error")
    Failbot.report(e)
    rescued = true
    nil
  ensure
    GitHub.dogstats.timing("user.recovery_codes_status.overhead", (Time.now - T.must(start)).to_i * 1000, tags: ["rescued:#{!!rescued}"])
  end
end
