# typed: true
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

module Stafftools
  module User
    class EmailsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      include UrlHelper

      attr_reader :user

      def settings_available?
        settings_response.success?
      end

      def page_title
        "#{user.login} - Emails"
      end

      def primary_github_email
        return unless user.emails.any?
        user.primary_user_email
      end

      def primary_github_email?(email)
        email.primary_role?
      end

      def backup_github_email?(email)
        email.backup_role?
      end

      def verified_classes
        "check"
      end

      def participating_handlers
        Array settings.participating_settings
      end

      def subscribed_handlers
        Array settings.subscribed_settings
      end

      def continuous_integration_handlers
        Array settings.continuous_integration_settings
      end

      def own_contributions
        notify_email_setting(settings.notify_own_via_email?)
      end

      def notify_comment
        notify_email_setting(settings.notify_comment_email?)
      end

      def notify_pull_request_review
        notify_email_setting(settings.notify_pull_request_review_email?)
      end

      def notify_pull_request_push
        notify_email_setting(settings.notify_pull_request_push_email?)
      end

      def notify_via_mobile_push
        notify_email_setting(settings.direct_mention_mobile_push?)
      end

      def notify_ci_failures
        notify_email_setting(settings.continuous_integration_failures_only?)
      end

      def notify_email_setting(value)
        value ? helpers.octicon("check", class: "color-fg-success") : helpers.octicon("x", class: "color-fg-danger")
      end

      def primary_notification_email
        return @primary_notification_email if defined?(@primary_notification_email)

        @primary_notification_email = if settings && email = settings.email(:global)
          email.address
        else
          nil
        end

        @primary_notification_email
      end

      def primary_notification_email?(email)
        email.to_s == primary_notification_email
      end

      def using_private_email?
        user.use_stealth_email?
      end

      def organizations_for(email)
        settings.organizations_by_email[email.to_s]
      end

      def organizations_for?(email)
        organizations_for(email).present?
      end

      def email_for_org(org)
        email_key = "org-#{org.id}"
        email = settings.email(email_key)
        if email
          email.address
        end
      end

      # Stealth email for a user
      def stealth_email
        StealthEmail.new(user).email
      end

      # The Gravatar check url for an email address.
      def gravatar_check_url(email)
        "http://en.gravatar.com/site/check/#{email}"
      end

      def email_notifications_enabled?
        subscribed_handlers.include?("email") || participating_handlers.include?("email")
      end

      def splunk_email_query(email)
        # this was previously .splunk -3d @production host=github-smtp* \"#{email}\"
        "index=prod-email ```or index=prod-resque```#{email}"
      end

      def emails
        @user.emails.user_entered_emails.primary_first
      end

      # Public: Removes short code from an email when called with one containing a short code
      #
      # Returns String
      def remove_shortcode(email)
        return email if @user.organization?
        @user.remove_shortcode(email)
      end

      # Public: Return the String tooltip for a bouncing email
      def bouncing_tooltip(email)
        if email.bouncing?
          "All attempts to deliver to this address have failed (hard bounce) " \
          "- notifications disabled until the address is verified"
        else
          raise ArgumentError, "not a bouncing email #{email}"
        end
      end

      def receives_any_marketing_email?
        subscription_list.any?
      end

      def subscription_list
        @user.newsletter_subscriptions.active
      end

      def subscription_audit_log_query
        "action:newsletter_preference user:#{@user.login}"
      end

      def subscription_audit_log_kql_query
        <<~KQL
          webevents
          | where action startswith "newsletter_preference"
          | where user == "#{@user.login}"
        KQL
      end

      def vulnerability_digest_emails
        digest_sub = subscription_list.where(name: "vulnerability").first

        digest_sub ? digest_sub.try(:kind).to_s : helpers.octicon("x", class: "color-fg-danger")
      end

      def vulnerability_email_notifications
        notify_email_setting(settings.vulnerability_email?)
      end

      def vulnerability_cli_notifications
        notify_email_setting(settings.vulnerability_cli?)
      end

      def vulnerability_web_notifications
        notify_email_setting(settings.vulnerability_web?)
      end

      def enterprise_managed_user_enabled?
        @user.organization? ? @user.enterprise_managed_user_enabled? : @user.is_enterprise_managed?
      end

      def first_emu_owner?
        @user.organization? ? false : @user.is_first_emu_owner?
      end

      def enterprise_managed_user_not_owner?
        return @enterprise_managed_user_not_owner if defined?(@enterprise_managed_user_not_owner)
        return false if @user.organization?

        @enterprise_managed_user_not_owner = @user.is_emu_and_not_first_owner?
      end

      def password_reset_enabled?
        !GitHub.auth.external_user?(@user) && (!enterprise_managed_user_enabled? || first_emu_owner?)
      end

      def email_unlink_enabled?
        !GitHub.enterprise? && !enterprise_managed_user_not_owner?
      end

      def disallow_emu_email_deletion?(email)
        enterprise_managed_user_not_owner? && email.primary?
      end

      private

      def settings_response
        @settings_response ||= GitHub.newsies.settings(user)
      end

      def settings
        @settings ||= settings_response.value
      end
    end
  end
end
