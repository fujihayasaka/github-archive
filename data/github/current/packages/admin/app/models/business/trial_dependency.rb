# typed: true
# frozen_string_literal: true

module Business::TrialDependency
  include BusinessesHelper
  include GitHub::Memoizer

  extend T::Helpers

  requires_ancestor { Business }

  sig { returns(T::Boolean) }
  def digital_front_door?
    return false if GitHub.single_business_environment?
    return false unless self.dfd_trial?
    return false unless self.metered_ghec_trial?
    return true if self.authenticated_through_digital_front_door?
    self.has_ongoing_copilot_business_trial?
  end

  sig { returns(T::Boolean) }
  memoize def recently_created_trial?
    return false if GitHub.single_business_environment?
    return true if self.trial?
    return false if self.trial_expired?
    return true if self.created_at >= Billing::EnterpriseCloudTrial::TRIAL_LENGTH.ago
    false
  end

  sig { returns(T::Boolean) }
  def copilot_trial_activation_blocked?
    FeatureFlag.vexi.enabled?(:block_enterprise_trial_copilot_activation, T.cast(self, Business), default: false)
  end

  sig { returns(T::Boolean) }
  def has_failed_trial_authorization?
    # If none of these conditions are met we aren't a DFD trial and why are you calling this method?
    return false if GitHub.single_business_environment?
    return false unless self.dfd_trial?
    return false unless self.trial?
    return false unless self.metered_ghe?

    # If there isn't a customer or we can't run authorizations we haven't started a DFD trial
    # or in a FUBAR state
    return false unless self.customer.present?
    return false unless self.can_be_authorized?

    # If we have an ongoing CfB trial the last authorization was successful
    return false if self.has_ongoing_copilot_business_trial?
    latest_authorization = self.billing_transactions.authorizations.last
    return false unless latest_authorization

    !T.must(latest_authorization).success?
  end

  sig { params(feature_flag_check: T::Boolean).returns(T::Boolean) }
  def eligible_for_expired_trial_deletion?(feature_flag_check: true)
    return false if has_commercial_interaction_restriction?
    return false unless self.trial_expired?
    return false if self.invoiced?
    return false if self.deleted?
    return false if self.staff_owned?
    return false if self.trial_conversion_initiated?
    # If all of the above have passed and we have set this field we are eligible
    return true if self.trial_deleted_at.present?
    true
  end

  sig { returns(T::Boolean) }
  def eligible_for_email_unverified_trial_deletion?
    return false if enterprise_managed?
    return false if has_commercial_interaction_restriction?
    return false unless trial?
    return false unless trial_email_verification_pending?
    return false if deleted?
    return false if staff_owned?
    return false if invoiced?
    return false if created_at >= 24.hours.ago
    true
  end

  def expired_trial_business_deletion_email_sent!
    with_database_error_fallback do
      Growth::LastActivity::KV.store.set(
        self.expired_trial_business_deletion_email_key,
        "true",
        expires: 48.hours.from_now
      )
    end
  end

  def expired_trial_business_deletion_email_sent?
    !!Growth::LastActivity::KV.store.get(
      self.expired_trial_business_deletion_email_key
    ).value { nil }
  end

  def expired_trial_business_deletion_email_key
    "expired_trial_business_email_sent.#{self.id}"
  end

  def set_microsoft_analytics_kv
    return if GitHub.single_or_multi_tenant_enterprise?
    EnterpriseAccounts::KV.store.set(self.microsoft_analytics_key, SecureRandom.uuid, expires: 7.days.from_now)
  end

  def get_microsoft_analytics_metadata
    unique_id = EnterpriseAccounts::KV.store.get(self.microsoft_analytics_key).value { nil }
    return if unique_id.nil?

    {
      order_id: unique_id,
      product_title: "GitHub Enterprise Trial",
    }
  end

  def microsoft_analytics_key
    key = "dfd_trial.creation.analytics_event.#{self.slug}"
  end

  def trial_selectable_organizations(user)
    return [] if self.enterprise_managed?
    user.owned_organizations.select { |org| org.selectable_for_enterprise_trial?(self) }
  end

  def enable_dfd_trial_experience(actor)
    self.update!(dfd_trial: true)

    business = T.cast(self, Business)
    result = business.enable_sku_based_trial(actor: actor, trial_days: business.new_advanced_security_trial_days, trial_source: :digital_front_door)

    GitHub.logger.warn(
      "exception.message": "Fail to create GHAS trial: #{result.error.message}",
      "gh.user.id": actor.id,
      "gh.business.id": self.id
    ) if result.error.present?
    self.set_microsoft_analytics_kv
  end

  sig { returns(T::Boolean) }
  def requires_email_verification?
    return false unless trial_email_verification_pending?

    owner = owners.first
    return false unless owner

    true
  end

  sig { params(actor: User).returns(T::Boolean) }
  def send_verification_email(actor)
    return false unless requires_email_verification?

    verification_code = generate_verification_code

    EnterpriseAccounts::KV.store.set(verification_code_key, verification_code, expires: 2.hours.from_now)

    BusinessMailer.trial_email_verification(self, actor, verification_code).deliver_later

    GitHub.dogstats.increment("business.email_verification.sent", tags: { business_id: id })
    true
  rescue => e
    GitHub.dogstats.increment("business.email_verification.send_error", tags: { error_class: e.class.name })
    false
  end

  sig { params(verification_code: T.nilable(String)).returns(T::Hash[Symbol, T.untyped]) }
  def verify_email_and_activate_trial(verification_code)
    if trial_email_verification_pending?
      return { success: false, error: "Invalid verification code" } unless verification_code_valid?(verification_code)

      clear_verification_code
      self.trial_completion_status = :no_trial_or_active_trial
      save!

      GitHub.dogstats.increment("business.email_verification.verified", tags: { business_id: id })
      { success: true }
    else
      { success: false, error: "Email verification not required" }
    end
  rescue => e
    GitHub.dogstats.increment("business.email_verification.verify_error", tags: { error_class: e.class.name })
    { success: false, error: "Verification failed" }
  end

  sig { void }
  def clear_verification_code
    EnterpriseAccounts::KV.store.del(verification_code_key)
  end

  private

  sig { returns(String) }
  def generate_verification_code
    format("%06d", SecureRandom.random_number(1_000_000))
  end

  sig { params(code: T.nilable(String)).returns(T::Boolean) }
  def verification_code_valid?(code)
    return false if code.blank?

    stored_code = EnterpriseAccounts::KV.store.get(verification_code_key).value { nil }

    return false unless stored_code

    ttl_result = EnterpriseAccounts::KV.store.ttl(verification_code_key).value { nil }
    return false if ttl_result.nil? || ttl_result <= 0

    code.to_s == stored_code
  rescue => e
    GitHub.dogstats.increment("business.email_verification.code_validation_error", tags: { error_class: e.class.name })
    false
  end

  sig { returns(String) }
  def verification_code_key
    "business:#{id}:trial_email_verification_code"
  end
end
