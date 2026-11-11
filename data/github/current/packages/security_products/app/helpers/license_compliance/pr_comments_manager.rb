# typed: strict
# frozen_string_literal: true

module LicenseCompliance
  class PrCommentsManager
    class << self
      sig do
        params(
        pull_request: PullRequest,
        open_license_alerts: T::Array[Hydro::Schemas::Github::Dependencygraph::V1::Entities::LicenseComplianceAlert],
        remediation_guidance: T.nilable(String),
        ).void
      end
      def manage_automated_review_comments(
        pull_request:,
        open_license_alerts:,
        remediation_guidance: ""
      )
        comparison = pull_request.async_pull_comparison.sync
        diff = comparison&.diffs&.presence

        if diff && !open_license_alerts.empty?
          post_review(pull_request, diff, open_license_alerts, remediation_guidance)
        end

        fix_existing_comments(pull_request, open_license_alerts)
      end

      sig { params(pull_request: PullRequest, alert_id: Integer).void }
      def mark_automated_review_comment_as_fixed(pull_request, alert_id)
        comment = AutomatedReviewComment.find_by(
          repository: pull_request.repository,
          pull_request: pull_request,
          source: :source_license_compliance,
          resource_id: alert_id.to_s,
          fixed_at: nil,
        )
        return unless comment

        comment.fix!
        notify_review_socket(comment)
      end

      sig do
        params(
          pull_request: PullRequest,
          alert_id: Integer,
          alert_status: T.nilable(String),
          actor_id: Integer,
          closure_reason: T.nilable(String)
        ).void
      end
      def update_automated_review_comment_metadata(pull_request:, alert_id:, alert_status:, actor_id:, closure_reason:)
        comment = AutomatedReviewComment.find_by(
          repository: pull_request.repository,
          pull_request: pull_request,
          source: :source_license_compliance,
          resource_id: alert_id.to_s,
        )
        return unless comment
        metadata = comment.metadata || {}

        metadata[ReviewComments::Evaluators::LicenseCompliance::METADATA_KEY_ALERT_STATUS] = alert_status
        metadata[ReviewComments::Evaluators::LicenseCompliance::METADATA_KEY_ACTOR_ID] = actor_id
        metadata[ReviewComments::Evaluators::LicenseCompliance::METADATA_KEY_CLOSURE_REASON] = closure_reason

        comment.metadata = metadata
        comment.save!
        notify_review_socket(comment)
      end

      private

      sig do
        params(
          pull_request: PullRequest,
          diff: GitHub::Diff,
          open_license_alerts: T::Array[Hydro::Schemas::Github::Dependencygraph::V1::Entities::LicenseComplianceAlert],
          remediation_guidance: T.nilable(String),
        ).void
      end
      def post_review(pull_request, diff, open_license_alerts, remediation_guidance)
        # Early return if diff is empty - nowhere to attach comments
        return if diff.empty?

        # Get first file in diff as fallback for alerts on files not in the diff
        fallback_path = diff.entries.first&.path

        # Early return if no files available
        return if fallback_path.nil?

        # Query existing comments to avoid creating duplicates
        # This includes both fixed and unfixed comments - once an alert has a comment thread,
        # we keep using that thread for the alert's entire lifecycle
        existing_comment_alert_ids = AutomatedReviewComment.where(
          repository: pull_request.repository,
          pull_request: pull_request,
          source: :source_license_compliance,
        ).pluck(:resource_id).to_set

        # Filter to only new alerts that don't already have comments
        new_license_alerts = open_license_alerts.reject do |alert|
          existing_comment_alert_ids.include?(alert.alert_id.to_s)
        end

        # Early return if all alerts already have comments
        return if new_license_alerts.empty?

        review_user_bot = license_compliance_bot
        review = pull_request.build_automated_variant_review do |r|
          r.user = review_user_bot
          r.body = format_review_body(T.must(remediation_guidance))
          r.head_sha = pull_request.head_sha
          r.merge_base_sha = pull_request.find_best_merge_base_sha(head_sha: pull_request.head_sha)
        end

        review_comment_pairs = {}
        new_license_alerts.each do |alert|
          # Check if the alert's manifest file is in the diff
          alert_file_in_diff = diff.delta_for_path(alert.manifest_name, side: :b)

          # Use alert's file if it's in diff, otherwise use fallback
          comment_path = alert_file_in_diff ? alert.manifest_name : fallback_path

          # Indicate when comment is attached to a different file
          is_fallback = comment_path != alert.manifest_name
          title_suffix = is_fallback ? " (file not in PR, comment attached to #{comment_path})" : ""

          thread = review.build_thread(subject_type: :file)
          review_comment = thread.build_first_comment(
            user: review_user_bot,
            # When automated comment FF is on this comment is not visible in the UI
            body: alert_message_text(alert) + "\n\n" + view_alert_link(alert, pull_request),
            path: comment_path,
            diff: diff,
          )

          automated_review_comment = AutomatedReviewComment.new(
            repository_id: pull_request.repository_id,
            pull_request_id: pull_request.id,
            source: :source_license_compliance,
            resource_id: alert.alert_id.to_s,
            title: "Non-Compliant license expression found on #{alert.package_name}#{title_suffix}",
            message: alert_message_text(alert) + "\n\n" + view_alert_link(alert, pull_request),
            severity: :severity_none,
            security_severity: :security_severity_none,
          )

          review_comment_pairs[review_comment] = automated_review_comment
        end

        # Save all review comments and automated review comments in a single transaction
        PullRequestReview.transaction do
          comments_created = 0

          review_comment_pairs.each do |review_comment, automated_review_comment|
            review_comment.save!
            comments_created += 1

            automated_review_comment.pull_request_review_comment_id = review_comment.id
            automated_review_comment.save!
          end

          review.comment! if comments_created > 0
        end
      end

      sig { params(pull_request: PullRequest, open_license_alerts: T.untyped).void }
      def fix_existing_comments(pull_request, open_license_alerts)
        open_alert_ids = open_license_alerts.map { |alert| alert.alert_id.to_s }.to_set
        AutomatedReviewComment.where(
          repository: pull_request.repository,
          pull_request: pull_request,
          source: :source_license_compliance,
          fixed_at: nil,
        ).find_each do |comment|
          comment.fix! unless open_alert_ids.include?(comment.resource_id)
        end
      end

      # Notifies pull request review channel so the automated review comment UI auto-updates
      # without requiring a full page refresh
      sig { params(comment: AutomatedReviewComment).void }
      def notify_review_socket(comment)
        review_ids = PullRequestReviewComment.where(id: comment.pull_request_review_comment_id).pluck(:pull_request_review_id)
        PullRequestReview.where(id: review_ids).each(&:notify_socket_subscribers)
      end

      sig { returns(T.untyped) }
      def license_compliance_bot
        bot = Apps::Privileged.attribution_only_system_identity_for(:license_compliance)
        raise "GitHub License Compliance bot not found" if bot.nil?
        bot
      end

      sig { params(remediation_guidance: T.nilable(String)).returns(String) }
      def format_review_body(remediation_guidance)
        return "" unless remediation_guidance.present?

        "Your enterprise has provided remediation guidance.\n\n---\n\n#{remediation_guidance}"
      end

      sig { params(alert: T.untyped).returns(String) }
      def alert_message_text(alert)
        if alert.nil? || alert.spdx_license_expression.empty?
          return "No license detected, and the package is not specifically allowed by your license policy"
        end
        "Detected expression _#{alert.spdx_license_expression}_ which has not been allowed by your license policy"
      end

      sig do
        params(
          alert: T.untyped,
          pull_request: PullRequest
        ).returns(String)
      end
      def view_alert_link(alert, pull_request)
        "[View alert details](#{UrlHelpers.repository_license_compliance_alert_url(
          host: GitHub.url,
          user_id: pull_request.repository&.owner_display_login,
          repository: pull_request.repository,
          number: alert.alert_number,
        )})"
      end
    end
  end
end
