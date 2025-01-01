# typed: true
# frozen_string_literal: true

module Site
  # This class helps determine what global notices we should show. It has
  # logic to responsibly only show one notice at at a time, and checks for notices that are set by
  # background jobs or by user actions
  class GlobalNoticeNextComponent < ApplicationComponent
    include UrlHelpers

    cattr_accessor :check_for_notices_elapsed
    attr_reader :hide_two_factor_recover_code_warning, :hide_email_verification_warning

    delegate :type, to: :active_notice

    def notice_ever_been_set?
      viewer.global_notice.persisted?
    end

    def initialize(viewer:, hide_two_factor_recover_code_warning: false, hide_email_verification_warning: false, hide_security_warning: false)
      @hide_two_factor_recover_code_warning = hide_two_factor_recover_code_warning
      @hide_email_verification_warning = hide_email_verification_warning
      @hide_security_warning = hide_security_warning
      @viewer = viewer
    end

    # Determines if this component is rendered.
    #
    # We only want to render the component if a notice is actually set, and if
    # the notice is still valid. If the notice shouldn't be rendered, enqueue a
    # job to determine if there's any other notices we should render.
    def render?
      return false unless active_notice.present?

      show_global_notice?
    end

    private

    memoize def this_organization
      helpers.current_organization || helpers.current_repository&.organization
    end

    attr_reader :viewer

    memoize def active_notice_name
      viewer.global_notice.name
    end

    memoize def active_notice
      viewer.global_notice.notice
    end

    memoize def spammy_orgs
      viewer.owned_organizations.select do |org|
        org.spammy?
      end
    end

    memoize def spammy_businesses
      viewer.businesses(membership_type: :admin).select do |business|
        business.spammy?
      end
    end

    memoize def troubled_org
      @viewer.billing_troubled_orgs.first
    end

    memoize def troubled_business
      @viewer.billing_troubled_businesses.first
    end

    memoize def disabled_org
      @viewer.disabled_orgs.first
    end

    memoize def manual_dunning_org
      @viewer.manual_dunning_orgs.first
    end

    memoize def manual_dunning_business
      @viewer.manual_dunning_businesses.first
    end

    memoize def over_plan_limit_org
      viewer.over_plan_limit_orgs.first
    end

    memoize def billingless_org
      viewer.billingless_org
    end

    memoize def two_factor_recovery_codes_remaining
      viewer.two_factor_credential.number_of_remaining_codes
    end

    memoize def two_factor_recovery_code_banner?
      viewer.recovery_codes_related_global_notice?
    end

    memoize def verified_email_related_banner?
      viewer.verified_emails_related_global_notice?
    end

    memoize def current_notice_is_security_banner?
      %w(two_factor_low_recovery_codes two_factor_recovery_codes one_verified_email verified_emails low_two_factor_methods year_old_recovery_codes sms_low_availability_country).include?(active_notice_name)
    end

    memoize def render_security_banners?
      return true if active_notice_name == "two_factor_low_recovery_codes"
      return false unless current_user.feature_enabled?(:actionable_two_factor_security_checkup)
      %w(verified_emails one_verified_email low_two_factor_methods year_old_recovery_codes sms_low_availability_country).include?(active_notice_name)
    end

    memoize def security_banner_info
      case active_notice_name
      when "two_factor_low_recovery_codes"
        {
          id: "two-factor-low-recovery-codes",
          link: settings_auth_recovery_codes_url(notice: active_notice_name, host: GitHub.urls.host_name),
          button_text: "View recovery codes",
          banner_text: "You only have #{two_factor_recovery_codes_remaining} recovery codes remaining. View and generate new recovery codes now."
        }
      when "verified_emails"
        {
          id: "verified-emails",
          link: settings_email_preferences_url(notice: "no_verified_emails", host: GitHub.urls.host_name),
          button_text: "Email settings",
          banner_text: "You do not have a verified email associated with your GitHub account. Add a verified email address from your email settings."
        }
      when "sms_low_availability_country"
        {
          link: settings_security_url(notice: active_notice_name, host: GitHub.urls.host_name),
          button_text: "View 2FA settings",
          banner_text: "SMS 2FA method is prone to fraud and and may be unreliable as it depends on delivery success rates in your region. To ensure consistent access to your account, please configure an additional 2FA method.",
          dismiss_path: dismiss_notice_path(:sms_low_availability_country),
          dismiss_aria_label: "Dismiss SMS low availability notice"
        }
      when "one_verified_email"
        {
          id: "one-verified-email",
          link: settings_email_preferences_url(notice: active_notice_name, host: GitHub.urls.host_name),
          button_text: "Email settings",
          banner_text: "You only have a single verified email address. We recommend verifying at least one more email address to ensure you can recover your account if you lose access to your primary email.",
          dismiss_path: dismiss_notice_path(:one_verified_email),
          dismiss_aria_label: "Dismiss single verified email notice"
        }
      when "low_two_factor_methods"
        {
          id: "low-two-factor-methods",
          link: settings_security_url(notice: active_notice_name, host: GitHub.urls.host_name),
          button_text: "View 2FA settings",
          banner_text: "Please configure another 2FA method to reduce your risk of permanent account lockout. #{current_user.two_factor_sms_permitted? ? "If you use SMS for 2FA, we strongly recommend against SMS as it is prone to fraud and delivery may be unreliable depending on your region." : ""}",
          dismiss_path: dismiss_notice_path(:low_two_factor_methods),
          dismiss_aria_label: "Dismiss low two factor methods notice"
        }
      when "year_old_recovery_codes"
        {
          id: "year-old-recovery-codes",
          link: settings_auth_recovery_codes_url(notice: active_notice_name, host: GitHub.urls.host_name),
          button_text: "View recovery codes",
          banner_text: "Your recovery codes have not been saved in the past year. Make sure you still have them stored somewhere safe by viewing and downloading them again.",
          dismiss_path: dismiss_notice_path(:year_old_recovery_codes),
          dismiss_aria_label: "Dismiss year old recovery codes notice"
        }
      end
    end

    def hide_security_banner?
      # a bit hacky, but we don't want to show security related banners on certain pages (logout, add account, switch account, etc)
      return true if %w(sessions signup oauth identity_management switch_account).include?(controller_name) && current_notice_is_security_banner? && current_user.feature_enabled?(:actionable_two_factor_security_checkup)
      false
    end

    # method to determine if we should show the global notice as there are some scenarios where we hide the notice
    def show_global_notice?
      if active_notice.should_show_notice?
        if hide_security_banner? || (current_notice_is_security_banner? && @hide_security_warning)
          # Work around existing logic to hide notices on certain pages
          false
        elsif two_factor_recovery_code_banner? && @hide_two_factor_recover_code_warning
          # Work around existing logic to hide notices on certain pages
          false
        elsif verified_email_related_banner?
          if @hide_email_verification_warning
            false
          else
            # Give the user some time before we bug them to verify email
            !current_user.joined_too_recently_for_email_verification_reminder?
          end
        elsif active_notice_name == "enterprise_cloud_trial" && !this_organization&.persisted?
          false
        else
          true
        end
      else
        if @viewer.feature_enabled?(:delay_global_notice_next_refresh_job)
          # Users that meet multiple global notices criterias, may get overwhelmed.
          # IE. If they see a notice, and immediately take action to resolve it.
          # And on the next render, they get shown a new notice. (with no time in between to breathe)
          #
          # Lets help with this by delaying the next job kick off by a few minutes.
          #
          # To note, this will not help if there are notices that are directly set
          # in the models.
          GlobalNoticeNextRefreshJob.set(wait: 5.minutes).perform_later(@viewer.id)
        else
          GlobalNoticeNextRefreshJob.perform_later(@viewer.id)
        end
        false
      end
    end

    def troubled_org_downgrade_url
      if troubled_org.plan.business?
        settings_org_billing_url(troubled_org, host: GitHub.urls.host_name)
      else
        org_plans_url(troubled_org, host: GitHub.urls.host_name)
      end
    end

    def private_repository_overage(target)
      "#{target.private_repo_count_for_limit_check} of #{target.plan_limit(:repos, visibility: "private")}"
    end
  end
end
