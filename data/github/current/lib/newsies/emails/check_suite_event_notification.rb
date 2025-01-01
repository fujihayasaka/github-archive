# typed: true
# frozen_string_literal: true

module Newsies
  module Emails
    class CheckSuiteEventNotification < Newsies::Emails::Message
      include ActionView::Helpers::TextHelper
      include GitHub::Memoizer

      MAX_JOBS_PER_EMAIL = 10

      def self.matches?(comment)
        comment.is_a?(::CheckSuiteEventNotification)
      end

      delegate :check_suite, to: :comment
      delegate :short_head_sha, :head_sha, :head_repository_id, to: :check_suite

      # Deliver if:
      # - user wants to be notified of all check suite results OR
      # - user only wants to know about failed check suites.
      # - we're on GHES, as for dotcom/proxima we use notifyd
      def deliverable?
        return unless GitHub.enterprise?

        settings.try(:continuous_integration_email?) && comment.deliver?(settings)
      end

      # Can't reply to a check suite update
      def tokenized_list_address
        GitHub.urls.noreply_address
      end

      # Can't unsubscribe from a check suite update
      def tokenized_unsubscribe_address
      end

      def subject
        if pull_request.present?
          "[#{repo_name}] PR run #{verb_conclusion}: #{workflow_name_with_attempt} - #{pull_request.title} (#{short_head_sha})"
        else
          "[#{repo_name}] Run #{verb_conclusion}: #{workflow_name_with_attempt} - #{branch_name} (#{short_head_sha})"
        end
      end

      def pull_request
        # there can be associated pull requests with the head_sha and branch on push events, ensure the event type matches up
        return nil unless check_suite.event == "pull_request"

        @_pull_request ||= repository.pull_requests.find_by(
          head_ref: branch_name,
          head_repository_id: head_repository_id,
          head_sha: head_sha,
        )
      end

      def entity
        repository
      end

      def inbox_snippet
        comment.body
      end

      def content
        [
          heading,
          basic_details.join("\n"),
          "View results: #{comment.permalink}",
          ["Jobs:", job_list_text].join("\n"),
        ].join("\n\n")
      end

      def content_html
        message = [
          tag.h2(heading),
          tag.p(safe_join(basic_details, tag.br)),
          tag.p(link_to("View results", comment.permalink)),
          tag.div(safe_join(["Jobs:", job_list_html])),
        ]

        safe_join(message)
      end

      def primer_html_template_enabled?
        true
      end

      def body
        return :check_suite_event_notification if primer_html_template_enabled?
        super
      end

      def body_html
        return :check_suite_event_notification_html if primer_html_template_enabled?
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

      def primer_layout
        :primer_layout_custom_padding
      end

      def heading
        return "[#{repo_name}] #{workflow_name} workflow run, Attempt ##{attempt}" if attempt.present?
        "[#{repo_name}] #{workflow_name} workflow run"
      end

      def basic_details
        [
          "Repository: #{repo_name}",
          "Workflow: #{workflow_name}",
          "Duration: #{run_duration}",
          "Finished: #{comment.updated_at}",
        ]
      end

      # Uses `ActiveSupport::Duration` to convert the seconds into a more
      # human-friendly phrase, e.g. "2 minutes and 5.3 seconds".
      def run_duration
        duration_in_seconds = check_suite.duration
        ActiveSupport::Duration.build(duration_in_seconds).inspect
      end

      def job_list_text
        check_runs.map do |check_run|
          "  * #{job_info(check_run, as_link: false).join(" ")}"
        end
      end

      def job_list_html
        tag.ul(safe_join(
          check_runs.map do |check_run|
            tag.li(safe_join(job_info(check_run, as_link: true), " "))
          end,
        ))
      end

      def check_runs
        @_check_runs ||= check_suite.latest_check_runs
      end

      def job_info(check_run, as_link:)
        [
          check_run_name(check_run, as_link: as_link),
          StatusCheckConfig.verb_state(check_run.conclusion),
          "(#{pluralize(check_run.annotation_count, "annotation")})",
        ]
      end

      def workflow_run_jobs_conclusion_description
        conclusions = check_runs.map(&:conclusion)

        # The order of the if-elsif-else statement is important
        if conclusions.none? || conclusions.all? { |c| c == StatusCheckConfig::STALE }
          # No conclusions or all conclusions are stale
          description = "No jobs were run"
        elsif conclusions.include?(StatusCheckConfig::ACTION_REQUIRED)
          # Any action required job + any other status
          description = "An action is required"
        elsif conclusions.all? { |c| c == StatusCheckConfig::SUCCESS }
          # all conclusions are success
          description = "All jobs were successful"
        elsif conclusions.all? { |c| c == StatusCheckConfig::FAILURE }
          # all conclusions are failed
          description = "All jobs have failed"
        elsif conclusions.all? { |c| c == StatusCheckConfig::TIMED_OUT }
          # all conclusions are timed_out
          description = "All jobs timed out"
        elsif conclusions.uniq.count == 1 && [StatusCheckConfig::CANCELLED, StatusCheckConfig::SKIPPED].include?(conclusions.first)
          # all jobs have the same conclusion which is either cancelled or skipped
          description = "All jobs were #{StatusCheckConfig.verb_state(conclusions.first)}"
        elsif conclusions.any? { |c| [StatusCheckConfig::CANCELLED, StatusCheckConfig::TIMED_OUT, StatusCheckConfig::FAILURE, StatusCheckConfig::STALE].include?(c) }
          # Any red status + any other status
          description = "Some jobs were not successful"
        elsif conclusions.all? { |c| [StatusCheckConfig::SUCCESS, StatusCheckConfig::SKIPPED].include?(c) }
          # Mix of success + skipped
          description = "All jobs that ran were successful"
        elsif conclusions.all? { |c| [StatusCheckConfig::SUCCESS, StatusCheckConfig::NEUTRAL, StatusCheckConfig::STALE].include?(c) }
          # Mix of success, neutral, stale
          description = "All jobs were run"
        else
          # Default
          description = "All jobs were completed"
        end

        "#{workflow_run_name_with_attempt}: #{description}"
      end

      def conclusion_icon_path(check_run)
        base_path = "/images/email/icons/"
        case check_run.conclusion
        when StatusCheckConfig::SUCCESS
          icon = "check-circle-fill-green.png"
        when StatusCheckConfig::ACTION_REQUIRED
          icon = "alert-red.png"
        when StatusCheckConfig::NEUTRAL
          icon = "square-fill-gray.png"
        when StatusCheckConfig::STALE
          icon = "issue-reopened-red.png"
        when StatusCheckConfig::SKIPPED
          icon = "skip-gray.png"
        else
          # cancelled, timed_out, failure
          icon = "x-circle-fill-red.png"
        end
        safe_join([base_path, icon])
      end

      def succeeded?
        check_runs.none? { |check_run| check_run.conclusion != "success" }
      end

      def detailed_conclusion_description(check_run)
        duration_in_seconds = check_run.duration
        duration = ActiveSupport::Duration.build(duration_in_seconds).inspect
        conclusion = check_run.conclusion

        conclusion_types_with_duration = [StatusCheckConfig::SUCCESS, StatusCheckConfig::FAILURE, StatusCheckConfig::TIMED_OUT, StatusCheckConfig::NEUTRAL]

        if conclusion_types_with_duration.include?(conclusion)
          verb = conclusion == StatusCheckConfig::NEUTRAL ? "neutral" : StatusCheckConfig.verb_state(conclusion)
          "#{verb} in #{duration}".capitalize
        else
          # skipped, cancelled, stale, action_required
          verb = conclusion == StatusCheckConfig::ACTION_REQUIRED ? "action required" : StatusCheckConfig.verb_state(conclusion)
          verb.capitalize
        end
      end

      def check_run_name(check_run, as_link:)
        if as_link
          link_to(check_run.visible_name, check_run.permalink(include_host: true))
        else
          check_run.visible_name
        end
      end

      def repository
        @_repository ||= comment.repository
      end

      def repo_name
        repository.name_with_display_owner
      end

      def workflow_name
        check_suite.name
      end

      memoize def attempt
        workflow_run&.current_attempt_num
      end

      def workflow_run
        check_suite.workflow_run
      end

      def workflow_name_with_attempt
        return "#{workflow_name}, Attempt ##{attempt}" if attempt.present?
        workflow_name
      end

      def workflow_run_name_with_attempt
        return workflow_name_with_attempt unless workflow_run&.explicit_name?

        return "#{workflow_run.name}, Attempt ##{attempt}" if attempt.present?
        workflow_run.name
      end

      def branch_name
        comment.head_branch
      end

      def verb_conclusion
        StatusCheckConfig.verb_state(comment.conclusion)
      end

      def notification_settings_url
        UrlHelpers.settings_notification_preferences_url(host: GitHub.url)
      end

      def rerequest_url
        UrlHelpers.rerequest_check_suite_url(
          check_suite,
          user_id: repository.owner,
          repository: repository,
          only_failed_check_runs: true,
          host: GitHub.url,
        )
      end
    end
  end
end
