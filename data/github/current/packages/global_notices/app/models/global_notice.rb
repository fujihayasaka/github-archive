# typed: strict
# frozen_string_literal: true

class GlobalNotice < ApplicationRecord::Domain::UsersCollab
  extend T::Sig
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
    enterprise_cloud_trial: GlobalNoticeNext::EnterpriseCloudTrialCheck,
    one_verified_email: GlobalNoticeNext::OneVerifiedEmailCheck,
    year_old_recovery_codes: GlobalNoticeNext::YearOldRecoveryCodes,
    low_two_factor_methods: GlobalNoticeNext::LowTwoFactorMethodsCheck,
    sms_low_availability_country: GlobalNoticeNext::SmsLowAvailabilityCountryCheck,
    open_source_survey_2024: GlobalNoticeNext::OpenSourceSurveyCheck,
  }.freeze, T::Hash[Symbol, T.class_of(GlobalNoticeNext::BaseCheck)])

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

  sig { returns(T::Boolean) }
  def unset
    persist_notice(:no_notice)
  end

  sig { params(new_name: T.any(String, Symbol)).returns(T::Boolean) }
  def set(new_name)
    if NOTICES_BY_PRIORITY.keys.include?(new_name.to_sym)
      current_notice_priority = NOTICES_BY_PRIORITY.keys.index(name.to_sym)
      new_notice_priority = T.must(NOTICES_BY_PRIORITY.keys.index(new_name.to_sym))

      # If there is a current notice, and it's lower in the list than the new
      # notice, set it as the new notice
      if !current_notice_priority || current_notice_priority > new_notice_priority
        persist_notice(new_name)
      end
      false
    else
      raise ArgumentError.new("notice name '#{new_name}' is not a valid notice name. Please add it to NOTICES_BY_PRIORITY list")
    end
  end

  # Public: Refreshes the current notices last checked at, or determines which
  # new notice to show, if any.
  sig { void }
  def refresh
    NOTICES_BY_PRIORITY.each do |notice_name, notice_class|
      check = notice_class.new(viewer: user)
      if check.should_show_notice?
        persist_notice(notice_name, true)
        return
      end
    end

    persist_notice(:no_notice, true)
  end

  private

  sig { params(name: T.any(String, Symbol), set_last_checked: T::Boolean).returns(T::Boolean) }
  def persist_notice(name, set_last_checked = false)
    self.last_checked_at = Time.current.utc if set_last_checked
    self.name = name
    save
  rescue ActiveRecord::RecordNotUnique
    self.class.find_by(user: user)&.set(name)
  end
end
