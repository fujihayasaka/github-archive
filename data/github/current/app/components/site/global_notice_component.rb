# typed: true
# frozen_string_literal: true

module Site
  # This class helps determine what global notices we should show. It has
  # logic to responsibly only show one notice at at a time, and only query
  # every 10 minutes to stop unnecessary queries.
  class GlobalNoticeComponent < ApplicationComponent
    include UrlHelpers

    cattr_accessor :check_for_notices_elapsed
    attr_reader :hide_two_factor_recover_code_warning
    attr_reader :type
    attr_reader :length_limited
    attr_reader :active
    attr_reader :troubled_org
    attr_reader :repo_count
    attr_reader :license
    attr_reader :certificate
    attr_reader :maintenance_scheduled
    attr_reader :maintenance_mode_message
    attr_reader :announcement
    attr_reader :hide_email_verification_warning
    attr_reader :spammy_orgs
    attr_reader :spammy_businesses
    attr_reader :reserved_account_logins

    def initialize(hide_two_factor_recover_code_warning: false, hide_email_verification_warning: false)
      @hide_two_factor_recover_code_warning = hide_two_factor_recover_code_warning
      @hide_email_verification_warning = hide_email_verification_warning
    end

    def before_render
      start_time = GitHub::Dogstats.monotonic_time
      check_for_notices
      self.class.check_for_notices_elapsed = GitHub::Dogstats.duration(start_time)
    end

    def render?
      active.present?
    end

    # user - The user to which these notices belong
    def check_for_notices
      @cache_key = "global_notice:#{current_user}:v1"

      @type = "warn"
      @active = nil

      # Enterprise checks are not cached
      if GitHub.enterprise?
        @license = GitHub::Enterprise.license
        @certificate = GitHub::Enterprise.certificate
        check_license_expiration
        check_license_seat_limit         unless @active
        check_certificate_expiration     unless @active
        check_maintenance                unless @active
        check_emails                     unless @active
        check_announcement               unless @active
        check_two_factor_low_recovery_codes unless @active
        check_two_factor_recovery_codes  unless @active
        check_staff_has_two_factor_enabled              unless @active
        check_reserved_accounts          unless @active
      else
        # Check for sponsorship rollback before checking the cache, so sponsors
        # will be notified sooner if a billing error cancelled their sponsorship.
        perform(:check_sponsorship_rollback)

        return if cached?

        perform(:check_ofac_flagged)
        perform(:check_verified_emails)            unless @active
        perform(:check_billing_email)              unless @active

        perform(:check_personal_billing_trouble)   unless @active
        perform(:check_org_billing_trouble)        unless @active
        perform(:check_expired_education_coupon)   unless @active
        perform(:check_disabled_org_repos)         unless @active
        perform(:check_disabled_personal_billing)  unless @active
        perform(:check_disabled_org_billing)       unless @active

        perform(:check_billingless_org)            unless @active
        perform(:check_spammy)                     unless @active
        perform(:check_spammy_orgs)                unless @active
        perform(:check_spammy_businesses)          unless @active
        perform(:check_two_factor_recovery_codes)  unless @active
        perform(:check_staff_has_two_factor_enabled) unless @active
      end

      if @active.nil?
        GitHub.cache.set(@cache_key, "nope", 10.minutes)
      end
    end

    # Set a check as active (needing to display). Handles setting cache keys
    # and such.
    #
    # key - A Symbol of the method name that triggered a notice.
    #
    # Returns nothing.
    def set_active(key)
      @active = key
      GitHub.cache.set(@cache_key, key.to_s, 10.minutes)
    end

    # We cache the checking of notices once every 10 minutes to help reduce
    # queries for dotcom. Cache value should be a string method name, or
    # "nope" (or nil)
    #
    # Returns true if a cache exists.
    def cached?
      cached = GitHub.cache.get(@cache_key)
      if cached == "nope"
        @cached = true
        return true
      elsif cached
        # Recheck the method so we're not displaying outdated notices
        @cached = true
        perform(cached.to_sym)
        return true
      end
      false
    end

    # Check if the user has been flagged, and the feature flag is on
    def check_ofac_flagged
      if current_user.has_any_trade_restrictions? && !current_user.dismissed_notice?(Billing::OFACCompliance::USER_NOTICE_FLAG)
        set_active(Billing::OFACCompliance::USER_NOTICE_FLAG)
      end
    end

    # Ensure users have at least one verified email
    # Sends an email verification reminder mailer job if a user visits GitHub
    # and triggers email verification needed banner
    def check_verified_emails
      return false if hide_email_verification_warning
      return unless current_user.show_verification_reminder?
      set_active(:check_verified_emails)

      if GitHub.email_verification_enabled?
        UserSignupFollowupJob.perform_later(current_user)
      end
    end

    # Does this person have an invalid billing email?
    def check_billing_email
      return unless current_user.billing_email_invalid?
      set_active(:check_billing_email)
    end

    # Does this person have a rolled-back sponsorship cancellation?
    def check_sponsorship_rollback
      unless !current_user.dismissed_notice?(:sponsorship_rollback) &&
             current_user.has_sponsorship_rollback?
        return
      end
      set_active(:check_sponsorship_rollback)
    end

    # Does this person's personal account have billing issues?
    def check_personal_billing_trouble
      return unless current_user.billing_trouble?
      set_active(:check_personal_billing_trouble)
    end

    # Does one of the orgs this person is responsible for have billing trouble?
    def check_org_billing_trouble
      return unless current_user.org_billing_trouble?
      @troubled_org = current_user.billing_troubled_orgs.first
      set_active(:check_org_billing_trouble)
    end

    def troubled_org_downgrade_url
      if troubled_org.plan.business?
        settings_org_billing_url(@troubled_org, host: GitHub.urls.host_name)
      else
        org_plans_url(@troubled_org, host: GitHub.urls.host_name)
      end
    end

    # Is one of the orgs this person is responsible for over its plan limit?
    def check_disabled_org_repos
      return unless current_user.org_over_plan_limit?
      @type         = "error"
      @troubled_org = current_user.over_plan_limit_orgs.first
      @repo_count   = private_repository_overage(@troubled_org)
      set_active(:check_disabled_org_repos)
    end

    def check_disabled_personal_billing
      return unless current_user.disabled? && current_user.paid_plan?
      @type = "error"
      set_active(:check_disabled_personal_billing)
    end

    def check_expired_education_coupon
      return if current_user.enabled?
      return if current_user.plan.free? || current_user.payment_amount.zero?
      return if !current_user.expired_education_coupon?

      @type = "error"
      set_active(:check_expired_education_coupon)
    end

    def check_disabled_org_billing
      return unless current_user.disabled_orgs?
      @type = "error"
      @troubled_org = current_user.disabled_orgs.first
      return if @troubled_org.deleted?
      set_active(:check_disabled_org_billing)
    end

    def check_billingless_org
      return unless current_user.owns_billingless_org?
      @type = "error"
      @troubled_org = current_user.billingless_org
      set_active(:check_billingless_org)
    end

    def check_spammy
      return unless current_user.spammy?
      @type = "error"
      set_active(:check_spammy)
    end

    def check_spammy_orgs
      @spammy_orgs = current_user.owned_organizations.select do |org|
        org.spammy?
      end
      return unless @spammy_orgs.any?
      @type = "error"
      set_active(:check_spammy_orgs)
    end

    def check_spammy_businesses
      @spammy_businesses = current_user.businesses(membership_type: :admin).select do |business|
        business.spammy?
      end
      return unless @spammy_businesses.any?
      @type = "error"
      set_active(:check_spammy_businesses)
    end

    # Enterprise-only check
    def check_two_factor_low_recovery_codes
      return false if hide_two_factor_recover_code_warning
      return unless current_user.two_factor_authentication_enabled? &&
      current_user.two_factor_credential.number_of_remaining_codes < 5

      set_active(:check_two_factor_low_recovery_codes)
    end

    def check_two_factor_recovery_codes
      return if hide_two_factor_recover_code_warning
      return unless current_user.two_factor_authentication_enabled? &&
        !current_user.two_factor_credential.recovery_codes_viewed?
      set_active(:check_two_factor_recovery_codes)
    end

    def check_staff_has_two_factor_enabled
      return unless current_user.site_admin_without_two_factor_check? && !current_user.site_admin?
      set_active(:check_staff_has_two_factor_enabled)
    end

    # Enterprise-only check
    def check_license_expiration
      return unless @license.show_warning?(current_user, :expiration) && @license.close_to_expiration?
      set_active(:check_license_expiration)
    end

    # Enterprise-only check
    def check_license_seat_limit
      return unless @license.show_warning?(current_user, :seat_limit) && @license.close_to_seat_limit? && GitHub.licensed_mode?
      @type = "error"
      set_active(:check_license_seat_limit)
    end

    # Enterprise-only check
    def check_certificate_expiration
      return unless @certificate&.show_warning?(current_user) && @certificate&.close_to_expiration?
      set_active(:check_certificate_expiration)
    end

    # Enterprise-only check
    def check_maintenance
      return unless @maintenance_scheduled = GitHub::Enterprise.maintenance_scheduled
      @maintenance_mode_message = GitHub::Enterprise.maintenance_mode_message
      set_active(:check_maintenance)
    end

    # Enterprise-only check (can have users with no email address)
    def check_emails
      return unless current_user.emails.size == 0
      return unless current_user.change_email_enabled?
      set_active(:check_emails)
    end

    # Enterprise-only check (is there an admin-defined announcement)
    def check_announcement
      @announcement = GitHub::Enterprise.announcement
      return if @announcement.text.blank?
      unless current_user.has_dismissed_announcement?(uuid: @announcement.uuid)
        @length_limited = true
        set_active(:check_announcement)
      end
    end

    def check_reserved_accounts
      return unless current_user.site_admin?
      @reserved_account_logins = User.where(login: GitHub::DeniedLogins.to_a).pluck(:display_login)
      return if @reserved_account_logins.empty?
      set_active(:check_reserved_accounts)
    end

    def license_seat_limit_text
      if license.metered?
        "Activate more cloud users and update your license"
      else
        "Purchase more seats"
      end
    end

    def download_new_license_url
      if license.metered? && enterprise_licensing_url = DotcomConnection.new.dotcom_enterprise_licensing_url
        return enterprise_licensing_url
      end
      enterprise_web_url("/purchase")
    end

    private

    def private_repository_overage(target)
      "#{target.private_repo_count_for_limit_check} of #{target.plan_limit(:repos, visibility: "private")}"
    end

    def perform(method_name)
      check = method(method_name)

      start_time = GitHub::Dogstats.monotonic_time
      check.call
      duration = GitHub::Dogstats.duration(start_time)

      is_cached = defined?(@cached) ? @cached : false

      GitHub.logger.info(
        "global-notice-checked",
        {
          "code.location": check.name.to_s,
          "gh.global_notice.check.duration": duration,
          "gh.global_notice.check.cached": is_cached,
          "gh.request_id": GitHub.context[:request_id]
        }
      )
    end
  end
end
