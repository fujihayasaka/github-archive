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
    return false unless self.has_ongoing_copilot_business_trial?
    true
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
    return false if feature_flag_check && !self.feature_enabled?(:expired_trial_deletion)
    return false if enterprise_managed_user_enabled? && !self.feature_enabled?(:emu_trial_deletion)
    return false if has_commercial_interaction_restriction?
    return false unless self.trial_expired?
    return false if self.invoiced?
    return false if self.deleted?
    return false if self.staff_owned?
    return false if self.trial_conversion_initiated?
    # If all of the above have passed and we have set this field we are eligible
    return true if self.trial_deleted_at.present?
    # This prevents us from setting the trial_deleted_at field except through a transition or manually
    return false if feature_flag_check && self.organizations.any? && !self.feature_enabled?(:expired_trial_org_deletion)
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
end
