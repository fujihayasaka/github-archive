# typed: true
# frozen_string_literal: true

module Newsies
  module Emails
    class VulnerableRepositoryNotification < Newsies::Emails::Message
      include ActionView::Helpers::TextHelper
      include GitHub::Memoizer

      # This constant represents the default number of alerts we show in the email generated
      DEFAULT_EMAIL_ALERT_COUNT = 20

      def self.matches?(comment)
        comment.is_a?(::VulnerabilityAlertingEvent::VulnerableRepositoryNotification)
      end

      def vulnerability_alerting_event
        comment.vulnerability_alerting_event
      end

      def subject
        "[#{comment.repository.name_with_display_owner}] Your repository has dependencies with security vulnerabilities"
      end

      def title
        if vulnerability_alerting_event.on_initialize?
          "Dependabot was enabled on #{repository.name_with_display_owner} and found #{pluralize(alerts.count, "vulnerable dependency")}"
        else
          "Updates to manifest files in #{repository.name_with_display_owner} introduced #{pluralize(alerts.count, "vulnerable dependency")}"
        end
      end

      def message_id
        "<vulnerable-repository/#{vulnerability_alerting_event.id}@#{GitHub.urls.host_name}>"
      end

      def primer_html_template_enabled?
        true
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

      def notification_settings_url
        UrlHelpers.settings_notification_preferences_url(host: GitHub.url)
      end

      # Hint to email clients how to group related alert emails.
      def in_reply_to
        "<#{repository.name_with_display_owner}/vulnerability-alerts@#{GitHub.urls.host_name}>"
      end

      def body
        :vulnerable_repository_notification
      end

      def body_html?
        true
      end

      def body_html
        :vulnerable_repository_notification_html
      end

      def repository
        comment.repository
      end

      # Needed to define this method for notifications to work
      # TODO: this seems to be used for org routing (typically entity being a repo?)
      # Before we GA, we need to ensure we respect org routing.
      def entity
        repository
      end

      def tokenized_list_address
        GitHub.urls.noreply_address
      end

      # Soon you'll be able to but as of yet,
      # Can't unsubscribe from the VulnerableRepositoryNotification.
      def tokenized_unsubscribe_address
      end

      # Override default behavior so that we include categories as part of
      # Sendgrid's SMTP API. This means that all OnBroadcastVulnerabilityNotification
      # emails will be delivered by Sendgrid.
      def category_tracking_enabled?
        true
      end

      def headers
        # The "super" method at Newsies::Emails::Message#headers sets this
        # instance variable for memoization. We don't want to update the hash
        # for every call to this method.
        return @headers if @headers

        super.update(
          "X-GitHub-Severity" => severity,
          "List-Unsubscribe-Post" => "List-Unsubscribe=One-Click",
          "List-Unsubscribe" => "<#{unsubscribe_dependabot_notifications_url}>"
        )

        super
      end

      def deliverable?
        super && alerts.present?
      end

      # Generates alerts for the user receiving the newsies notification
      # User to send notification to is obtained from newsies settings instead of using repository owner
      # This is so because the repository owner may not be the only person viewing the notification.
      def alerts
        return @alerts if defined? @alerts

        alerts = VulnerabilityAlertingEvent::AlertCollector.new(
          vulnerability_alerting_event: vulnerability_alerting_event,
          user: settings_user
        ).notifiable_alerts_for_repository(repository)

        # Sort alerts by highest severity first and by package they affect
        @alerts = alerts_by_package_with_highest_severity(alerts)
      end

      def severity
        return @severity if defined? @severity

        # Since alerts are already sorted by highest severity, the first alert should
        # contain the highest severity present in the array of alerts returned
        @severity = alerts.first&.vulnerability&.severity
      end

      # Groups alerts that affect the same package into a single alert
      # The alert chosen for each package is the one with the highest severity
      def alerts_by_package_with_highest_severity(alerts)
        package_names = alerts.map(&:package_name).compact.uniq

        highest_severity_alert_by_package = {}

        package_names.each do |package_name|
          matching_package_alerts = alerts.select { |alert| alert.package_name == package_name }

          matching_package_alerts_sorted_by_severity = matching_package_alerts.sort_by { |a| Vulnerability::SEVERITY_BY_INDEX[a.vulnerability.severity] }.reverse!

          highest_severity_alert_by_package[package_name] = matching_package_alerts_sorted_by_severity.first
        end

        alerts_per_package = highest_severity_alert_by_package.values
        alerts_per_package.sort_by { |a| T.must(Vulnerability::SEVERITY_BY_INDEX[a.vulnerability.severity]) }.reverse!
      end

      def default_email_alert_count
        DEFAULT_EMAIL_ALERT_COUNT
      end
    end
  end
end
