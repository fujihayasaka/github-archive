# typed: strict
# frozen_string_literal: true

class GlobalNotice < ApplicationRecord::Collab
  include GlobalNotices::IGlobalNotice

  # When adding new notices, please double check if the notice also needs to be in GHES.
  #   GHES still renders the old notice component.
  # If so, you need to add that check and UI to the old global notice component:
  #   app/components/site/global_notice_component.rb
  NOTICES_BY_PRIORITY = T.let({
    sponsorship_rollback: GlobalNoticeNext::SponsorshipRollbackCheck,
    ofac_flagged: GlobalNoticeNext::OFACFlaggedCheck,
    verified_emails: GlobalNoticeNext::VerifiedEmailsCheck,
    billing_email: GlobalNoticeNext::BillingEmailCheck,
    personal_billing_trouble: GlobalNoticeNext::PersonalBillingTroubleCheck,
    org_billing_trouble: GlobalNoticeNext::OrgBillingTroubleCheck,
    business_billing_trouble: GlobalNoticeNext::BusinessBillingTroubleCheck,
    personal_manual_dunning: GlobalNoticeNext::PersonalManualDunningCheck,
    org_manual_dunning: GlobalNoticeNext::OrgManualDunningCheck,
    business_manual_dunning: GlobalNoticeNext::BusinessManualDunningCheck,
    expired_education_coupon: GlobalNoticeNext::ExpiredEducationCouponCheck,
    disabled_org_repos: GlobalNoticeNext::DisabledOrgReposCheck,
    disabled_personal_billing: GlobalNoticeNext::DisabledPersonalBillingCheck,
    disabled_org_billing: GlobalNoticeNext::DisabledOrgBillingCheck,
    billingless_org: GlobalNoticeNext::BillinglessOrgCheck,
    spammy: GlobalNoticeNext::SpammyCheck,
    spammy_orgs: GlobalNoticeNext::SpammyOrgsCheck,
    spammy_businesses: GlobalNoticeNext::SpammyBusinessesCheck,
    two_factor_low_recovery_codes: GlobalNoticeNext::TwoFactorLowRecoveryCodesCheck,
    two_factor_recovery_codes: GlobalNoticeNext::TwoFactorRecoveryCodesCheck,
    check_staff_has_two_factor_enabled: GlobalNoticeNext::StaffTwoFactorEnabledCheck,
    upcoming_ghe_renewal: GlobalNoticeNext::BusinessUpcomingRenewalCheck,
    enterprise_cloud_trial: GlobalNoticeNext::EnterpriseCloudTrialCheck,
    one_verified_email: GlobalNoticeNext::OneVerifiedEmailCheck,
    year_old_recovery_codes: GlobalNoticeNext::YearOldRecoveryCodes,
    low_two_factor_methods: GlobalNoticeNext::LowTwoFactorMethodsCheck,
    sms_low_availability_country: GlobalNoticeNext::SmsLowAvailabilityCountryCheck,
    open_source_survey_2024: GlobalNoticeNext::OpenSourceSurveyCheck,
  }.freeze, T::Hash[Symbol, T.class_of(GlobalNoticeNext::BaseCheck)])

  NOTICES_BY_PRIORITY.each do |name, notice_class|
    # this isn't ideal but we need to instantiate the notice class to get the type and can_snooze values
    # the values don't change depending on the viewer so we can just use a nil viewer
    type = notice_class.new(viewer: nil).type
    snooze_interval = T.let(nil, T.nilable(ActiveSupport::Duration))
    if notice_class.const_defined?(:SNOOZE_INTERVAL)
      snooze_interval = notice_class.const_get(:SNOOZE_INTERVAL)
    end

    # Type only varies for one notice check class for which we will override it to be error always from now on.
    type = "error" if GlobalNoticeNext::BusinessUpcomingRenewalCheck == notice_class

    display_predicate = -> (viewer) { notice_class.new(viewer: viewer).should_show_notice? }
    GlobalNotices::Registry.instance.register(name, type:, snooze_interval:, &display_predicate)
  end

  GlobalNotices::Registry.instance.register(:no_notice) { |_| false }

  # scheduled notices to be evaluated by the ScheduledGlobalNoticeRefreshJob should be added here
  # and in order of priority to NOTICES_BY_PRIORITY
  SCHEDULED_NOTICES_BY_PRIORITY = T.let({
    one_verified_email: GlobalNoticeNext::OneVerifiedEmailCheck,
    year_old_recovery_codes: GlobalNoticeNext::YearOldRecoveryCodes,
  }.freeze, T::Hash[Symbol, T.class_of(GlobalNoticeNext::ScheduledBaseCheck)])

  enum :name, [
    :no_notice,
    :sponsorship_rollback,
    :ofac_flagged,
    :verified_emails,
    :billing_email,
    :personal_billing_trouble,
    :org_billing_trouble,
    :business_billing_trouble,
    :personal_manual_dunning,
    :org_manual_dunning,
    :business_manual_dunning,
    :expired_education_coupon,
    :disabled_org_repos,
    :disabled_personal_billing,
    :disabled_org_billing,
    :billingless_org,
    :spammy,
    :spammy_orgs,
    :spammy_businesses,
    :two_factor_low_recovery_codes,
    :two_factor_recovery_codes,
    :check_staff_has_two_factor_enabled,
    :enterprise_cloud_trial,
    :one_verified_email,
    :year_old_recovery_codes,
    :low_two_factor_methods,
    :sms_low_availability_country,
    :open_source_survey_2024,
    :upcoming_ghe_renewal,
  ]

  belongs_to :user

  sig { returns(T::Hash[Symbol, T.class_of(GlobalNoticeNext::ScheduledBaseCheck)]) }
  def self.scheduled_notices_by_priority
    SCHEDULED_NOTICES_BY_PRIORITY
  end

  sig { returns(T.nilable(GlobalNoticeNext::BaseCheck)) }
  def notice
    return if !name

    notice = NOTICES_BY_PRIORITY[name.to_sym]

    if notice
      notice.new(viewer: user)
    end
  end

  sig { returns(T::Boolean) }
  def set?
    !!(name.to_s != "no_notice" && notice)
  end

  sig { returns(Symbol) }
  def unset
    persist_notice(:no_notice)
  end

  sig { params(new_name: Symbol).returns(Symbol) }
  def set(new_name)
    if GlobalNotices::Registry.instance.supercedes_notice?(new_name: new_name, current_name: name.to_sym)
      persist_notice(new_name)
    else
      name.to_sym
    end
  end

  sig { returns(Symbol) }
  def refresh
    new_name = GlobalNotices::Registry.instance.refreshed_notice_name(T.must(user))
    persist_notice(new_name, true)
  end

  sig { params(name: T.any(String, Symbol), set_last_checked: T::Boolean).returns(Symbol) }
  def persist_notice(name, set_last_checked = false)
    self.last_checked_at = Time.current.utc if set_last_checked
    self.name = name
    save!

    # while refactoring global notices this will give us increased confidence that we're not breaking anything
    GitHub.dogstats.increment("global_notice.persisted", tags: ["notice_name:#{name}"])
    name.to_sym
  rescue ActiveRecord::RecordNotUnique
    T.must(GlobalNotice.find_by(user_id: user_id)).set(name.to_sym)
  end
end
