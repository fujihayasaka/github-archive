# typed: true
# frozen_string_literal: true

module Newsies
  module Emails
    class WorkflowRunApprovalNotification < Newsies::Emails::Message
      include ActionView::Helpers::TextHelper

      def self.matches?(comment)
        comment.is_a?(::WorkflowRunApprovalNotification)
      end

      delegate :workflow_run, to: :comment

      def deliverable?
        unless settings.try(:continuous_integration_email?) && comment.deliver?(settings) && environments.any?
          return false
        end

        # It's not deliverable if it's delivered via Notifyd
        !Notifyd::Flags.new(settings_user).enable_ci_activity?.tap do |enabled|
          GitHub.dogstats.increment(
            "notifyd.ci_activity.emails",
            tags: ["sent_via_notifyd:#{enabled}"],
          )
        end
      end

      # Can't reply to approval request
      def tokenized_list_address
        GitHub.urls.noreply_address
      end

      # Can't unsubscribe from approval request
      def tokenized_unsubscribe_address
      end

      # Enable fancy primer layout templates
      def primer_html_template_enabled?
        true
      end

      def primer_layout
        :primer_layout_custom_padding
      end

      def subject
        "[#{repo_name}] #{workflow_run.name}: Your review was requested to deploy"
      end

      def entity
        repository
      end

      def inbox_snippet
        comment.body
      end

      def repository
        @_repository ||= comment.repository
      end

      def repo_name
        repository.name_with_display_owner
      end

      def heading
        "[#{repo_name}] #{workflow_run.name} workflow run"
      end

      def content
        [
          heading,
          "Review Pending Deployments: #{comment.permalink}",
          description,
        ].join("\n\n")
      end

      def content_html
        message = [
          heading,
          tag.p(link_to("Review Pending Deployments", comment.permalink)),
          description,
        ]

        safe_join(message)
      end

      def body
        return :workflow_run_approval_notification if primer_html_template_enabled?
        super
      end

      def body_html
        return :workflow_run_approval_notification_html if primer_html_template_enabled?
        super
      end

      def footer
        [
          "-- ",
          reason_in_words,
          "Manage your GitHub Actions notifications: #{notification_settings_url}",
        ].join("\n")
      end

      def footer_html
        if primer_html_template_enabled?
          link_to_notification = link_to("Manage your GitHub Actions notifications", notification_settings_url)
        else
          link_to_notification = safe_join([
            "Manage your GitHub Actions notifications ",
            link_to("here", notification_settings_url),
            ".",
          ])
        end
        msg = [
          MDASH,
          reason_in_words,
          link_to_notification,
        ]

        msg = safe_join(msg, tag.br)
        msg += mark_read_image if tracking_image_enabled?

        tag.p(msg, style: "font-size:small;-webkit-text-size-adjust:none;color:#666;")
      end

      # guaranteed that a single check_run will have at most one manual_approval
      def environment_name(check_run)
        manual_approval_request = check_run.gate_requests.find do |gate_request|
          gate_request.gate.type == "manual_approval"
        end

        manual_approval_request&.gate&.environment&.name || ""
      end

      def waiting_check_runs
        waiting_check_run_ids = pending_gate_requests.pluck(:check_run_id)
        CheckRun.where(id: waiting_check_run_ids).to_a
      end

      def check_run_ids
        @check_run_ids ||= workflow_run.check_suite.fetch_latest_check_run_ids
      end

      def pending_gate_requests
        GateRequest.includes(gate: :environment).where(state: 0, check_run_id: check_run_ids).filter { |gate_request| gate_request.approval_status(email_recipient) == "pending" }
      end

      def icon_path
        "/images/email/icons/clock.png"
      end

      # this email is being sent to different users, and each user may be part of a different environment so make sure to check
      def environments
        environments = Set.new

        pending_gate_requests.each do |gate_request|
          if gate_request.approval_status(email_recipient) == "pending"
            environments << gate_request.gate&.environment&.name
          end
        end
        environments
      end

      # if there isn't at least one environment, the email is marked as non-deliverable
      def description
        if environments.empty?
          description = "has an environment waiting for your review"
        else
          description = "#{environments.first} is waiting for your review"
        end
        "#{workflow_run.name}: #{description}"
      end

      # the recipient of the email, for easier stubbing
      def email_recipient
        settings_user
      end

      def notification_settings_url
        UrlHelpers.settings_notification_preferences_url(host: GitHub.url)
      end
    end
  end
end
