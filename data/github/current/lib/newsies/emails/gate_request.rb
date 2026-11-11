# typed: true
# frozen_string_literal: true

module Newsies
  module Emails
    class GateRequest < Newsies::Emails::Message
      include ActionView::Helpers::TextHelper
      include Scientist

      def self.matches?(comment)
        comment.is_a?(::GateRequest)
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

      def repository
        @_repository ||= comment.check_run.repository
      end

      def repo_name
        repository.name_with_display_owner
      end

      def workflow_run
        comment.check_run.check_suite.workflow_run
      end

      def heading
        "[#{repo_name}] #{workflow_run.name} workflow run"
      end

      def content
        [
          heading,
          "Review Pending Deployments: #{workflow_run.permalink}",
          description,
        ].join("\n\n")
      end

      def content_html
        message = [
          heading,
          tag.p(link_to("Review Pending Deployments", workflow_run.permalink)),
          description,
        ]

        safe_join(message)
      end

      def body
        :gate_request
      end

      def body_html
        :gate_request_html
      end

      def body_html?
        true
      end

      def footer
        [
          "-- ",
          reason_in_words,
          "Manage your GitHub Actions notifications: #{notification_settings_url}",
        ].join("\n")
      end

      def footer_html
        link_to_notification = link_to("Manage your GitHub Actions notifications", notification_settings_url)
        msg = [
          MDASH,
          reason_in_words,
          link_to_notification,
        ]

        msg = safe_join(msg, tag.br)
        msg += mark_read_image if tracking_image_enabled?

        tag.p(msg, style: "font-size:small;-webkit-text-size-adjust:none;color:#666;")
      end

      def icon_path
        "/images/email/icons/clock.png"
      end

      def description
        "#{workflow_run.name}: #{comment.gate.environment.name} is waiting for your review"
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
        check_runs = Checks.domain.check_runs.unsafe_for_ids(
          waiting_check_run_ids,
          repository_id: repository.id
        )
      end

      def check_run_ids
        @check_run_ids ||= Checks.domain.check_runs.latest_ids(repository_id: repository.id, check_suite_id: workflow_run.check_suite.id, head_sha: workflow_run.check_suite.head_sha, latest_check_suite_run_only: workflow_run.check_suite.actions_app?)
      end

      def pending_gate_requests
        ::GateRequest.includes(gate: :environment).where(state: 0, check_run_id: check_run_ids).filter { |gate_request| gate_request.approval_status(email_recipient) == "pending" }
      end

      # the recipient of the email, for easier stubbing
      def email_recipient
        user
      end

      def notification_settings_url
        UrlHelpers.settings_notification_preferences_url(host: GitHub.url)
      end
    end
  end
end
