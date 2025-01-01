# typed: true
# frozen_string_literal: true

module Newsies
  module Emails
    class SecurityAdvisoryNotification < Newsies::Emails::Message
      include ActionView::Helpers::TextHelper
      include GitHub::Memoizer

      # This constant represents the default number of affected repositories we show in the email generated
      DEFAULT_EMAIL_REPOSITORY_COUNT = 35

      def self.matches?(comment)
        comment.is_a?(::VulnerabilityAlertingEvent::SecurityAdvisoryNotification)
      end

      def security_advisory
        comment.notifications_thread
      end

      def security_advisory_permalink
        comment.permalink
      end

      def security_advisory_title
        security_advisory.summary
      end

      def ghsa_id
        security_advisory.ghsa_id
      end

      def title
        if owner.organization?
          "#{pluralize(affected_repository_count, "repository")} in your #{owner.display_login} organization might be affected by a security vulnerability in #{security_advisory.affects.first}"
        else
          "#{pluralize(affected_repository_count, "repository")} in your GitHub account might be affected by a security vulnerability found in #{security_advisory.affects.first}"
        end
      end

      def vulnerability_alerting_event
        comment.vulnerability_alerting_event
      end

      def primer_html_template_enabled?
        true
      end

      def notification_settings_url
        UrlHelpers.settings_notification_preferences_url(host: GitHub.url)
      end

      memoize def footer_links
        [
          { url: "#{GitHub.url}/login", text: "Sign in to GitHub" },
          { url: "#{GitHub.help_url}/articles/github-terms-of-service/", text: "Terms" },
          { url: "#{GitHub.help_url}/articles/github-privacy-policy/", text: "Privacy" },
          { url: notification_settings_url, text: "Notification settings" },
          { url: unsubscribe_vuln_url, text: "Unsubscribe" }
        ]
      end

      delegate :severity, :packages, :alert_url, :helpers, :advisory_url, :alerts_by_package_and_repository,
      :repositories_for_package, :affected_repository_count, to: :view_model
      def view_model
        Mailers::Vulnerability::CombinedAlertView.new(
          vulnerability_alerting_event: vulnerability_alerting_event,
          user: owner,
          email: recipient_email,
          alerts: alerts)
      end

      def subject
        "[#{owner}] A security advisory on #{security_advisory.affects.first} affects at least one of your repositories"
      end

      def list_id
        address = "<#{notifications_list}.#{ghsa_id}.#{GitHub.urls.host_name}>"
        "#{notifications_list}/#{ghsa_id} #{address}"
      end

      # We are overriding these methods because the originals expect name_with_owner
      # which do not make sense in our context
      def notifications_list_email(list, email)
        email = quote_email_address(email)
        %{"#{list}/#{ghsa_id}" #{email}}
      end

      def noreply_list_address
        if GitHub.email_replies_enabled? && !GitHub.mail_use_noreply_addr
          notifications_list_email(notifications_list, "#{ghsa_id}@noreply.#{GitHub.urls.smtp_domain}")
        else
          notifications_list_email(notifications_list, GitHub.urls.noreply_address)
        end
      end

      # Unique identifier for this alert used in email messages.
      def message_id
        "<#{owner}/security-advisories/#{vulnerability_alerting_event.id}@#{GitHub.urls.host_name}>"
      end

      # Hint to email clients how to group related alert emails.
      # We're choosing to group these emails by organization/owner as this follows newsies' org routing conventions.
      # This will allow us to thread advisory emails together based on the organization affected.
      # This approach is better than grouping by security advisory because advisories are often reported only once.
      def in_reply_to
        "<#{owner}/security-advisories@#{GitHub.urls.host_name}>"
      end

      def body
        :security_advisory_notification
      end

      def body_html?
        true
      end

      def body_html
        :security_advisory_notification_html
      end

      # Needed to define this method for notifications to work
      # TODO: this seems to be used for org routing (typically entity being a repo?)
      # Before we GA, we need to ensure we respect org routing.
      def entity
        comment
      end

      def tokenized_list_address
        GitHub.urls.noreply_address
      end

      # Can't unsubscribe from OnProcessAlertsNotification either.
      def tokenized_unsubscribe_address
      end

      def owner
        comment.owner
      end

      def headers
        # The "super" method at Newsies::Emails::Message#headers sets this
        # instance variable for memoization. We don't want to update the hash
        # for every call to this method.
        return @headers if @headers

        super.update(
          "X-GitHub-Severity" => security_advisory.severity,
          "List-Unsubscribe-Post" => "List-Unsubscribe=One-Click",
          "List-Unsubscribe" => "<#{unsubscribe_dependabot_notifications_url}>"
        )

        super
      end

      # Generates alerts for the user receiving the newsies notification
      # User to send notifications to is obtained from newsies settings
      # instead of using the owner which could be the user or org on which vulnerabilities were found.
      def alerts
        return @alerts if defined? @alerts

        @alerts = VulnerabilityAlertingEvent::AlertCollector.new(
          vulnerability_alerting_event: vulnerability_alerting_event,
          user: settings_user
        ).notifiable_alerts_for_owner(owner)
      end

      def deliverable?
        super && alerts.present?
      end

      def default_email_repository_count
        DEFAULT_EMAIL_REPOSITORY_COUNT
      end
    end
  end
end
