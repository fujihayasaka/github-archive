# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

module CodeScanning
  # Manages creating, updating, and resolving automated review comments on PRs
  # for AI-detected code scanning findings.
  #
  # This follows the same pattern as CodeScanning::PrCommentsManager and
  # CodeQuality::PrCommentsManager:
  # 1. Deduplication via resource_id (TODO)
  # 2. Build review comments outside transaction
  # 3. Save in transaction
  class AiFindingsPrCommentsManager
    extend PullRequestAnalyses::ReviewCommentsHelper

    MAX_REVIEW_COMMENTS = 20

    class Finding < T::Struct
      const :stable_id, String
      const :message, String
      const :severity, Symbol
      const :file_path, String
      const :start_line, Integer
      const :end_line, Integer
      const :suggestion, T.nilable(ReviewComments::Suggestion)
      const :suggestion_description, T.nilable(String)
      const :rule_id, T.nilable(String)
      const :model, T.nilable(String)
      const :source, T.nilable(String)

      # Satisfies the interface expected by PullRequestAnalyses::ReviewCommentsHelper#comment_start_line,
      # which accesses result.location.{file_path,start_line,end_line}.
      sig { returns(T.self_type) }
      def location
        self
      end
    end

    sig do
      params(
        pull_request: PullRequest,
        commit_oid: String,
        diff: GitHub::Diff,
        findings: T::Array[Finding],
      ).void
    end
    def self.manage_automated_review_comments(pull_request:, commit_oid:, diff:, findings:)
      return if findings.empty?

      # Deduplicate incoming findings by stable_id to avoid posting multiple comments
      # for the same finding within a single batch.
      deduped_findings = findings.uniq(&:stable_id)

      # Get existing comment resource IDs to avoid duplicates with already-posted comments
      existing_resource_ids = AutomatedReviewComment.where(
        repository: pull_request.repository,
        pull_request: pull_request,
        resource_id: deduped_findings.map(&:stable_id),
        source: :source_code_scanning_ai,
      ).pluck(:resource_id).to_set

      # Filter to only new findings (not already posted)
      new_findings = deduped_findings.reject { |finding| existing_resource_ids.include?(finding.stable_id) }

      return if new_findings.empty?

      # Post only new findings as review comments
      post_automated_review(
        pull_request: pull_request,
        commit_oid: commit_oid,
        diff: diff,
        findings: new_findings,
      )
    end

    class << self
      private

      sig do
        params(
          pull_request: PullRequest,
          commit_oid: String,
          diff: GitHub::Diff,
          findings: T::Array[Finding],
        ).void
      end
      def post_automated_review(pull_request:, commit_oid:, diff:, findings:)
        return if findings.empty?

        # Skip if the commit is not the head commit
        if commit_oid != pull_request.head_sha
          log_info(
            "Skipping AI findings PR comments for stale commit",
            "gh.pull_request.id" => pull_request.id,
            "gh.commit.requested_sha" => commit_oid,
            "gh.pull_request.head_sha" => pull_request.head_sha,
          )
          return
        end

        # Skip if PR is locked
        if pull_request.issue&.locked?
          log_info(
            "Skipping AI findings PR comments for locked pull request",
            "gh.pull_request.id" => pull_request.id,
          )
          return
        end

        # Limit to MAX_REVIEW_COMMENTS to avoid flooding PRs
        findings_to_post = order_by_severity(findings).take(MAX_REVIEW_COMMENTS)

        if findings.size > MAX_REVIEW_COMMENTS
          log_info(
            "Too many AI findings to post, limiting to #{MAX_REVIEW_COMMENTS}",
            "gh.pull_request.id" => pull_request.id,
            "gh.findings.total" => findings.size,
          )
        end

        # Create the PR review with automated variant
        review = pull_request.build_automated_variant_review do |r|
          r.user = code_scanning_bot
          r.head_sha = commit_oid
          r.merge_base_sha = pull_request.find_best_merge_base_sha(head_sha: commit_oid)
        end

        # Build review comments and automated review comments outside the transaction
        # to avoid slow running transactions
        review_comment_pairs = T.let({}, T::Hash[PullRequestReviewComment, AutomatedReviewComment])

        findings_to_post.each do |finding|
          automated_review_comment = build_automated_review_comment(review: review, finding: finding)
          review_comment = build_review_comment(
            review: review,
            finding: finding,
            diff: diff,
            body: automated_review_comment.format_body,
          )

          next unless review_comment.present?

          review_comment_pairs[review_comment] = automated_review_comment
        end

        return if review_comment_pairs.empty?

        # Save in a transaction
        comments_created = 0
        PullRequestReview.transaction do
          review_comment_pairs.each do |review_comment, automated_review_comment|
            if review_comment.save
              comments_created += 1
              automated_review_comment.pull_request_review_comment_id = review_comment.id
              automated_review_comment.save!
            else
              log_error(
                "Failed to save review comment for AI finding",
                "error" => review_comment.errors.full_messages,
                "gh.finding.stable_id" => automated_review_comment.resource_id,
              )
            end
          end

          # Finalize the review if we created any comments
          review.comment! if comments_created > 0
        end

        log_info(
          "Posted AI finding review comments",
          "gh.pull_request.id" => pull_request.id,
          "gh.comments.created" => comments_created,
        )
      end

      sig { params(findings: T::Array[Finding]).returns(T::Array[Finding]) }
      def order_by_severity(findings)
        # :severity_none, :severity_note, :severity_low, :severity_medium, :severity_high, :severity_critical
        critical_findings = T.let([], T::Array[Finding])
        high_findings = T.let([], T::Array[Finding])
        medium_findings = T.let([], T::Array[Finding])
        low_findings = T.let([], T::Array[Finding])
        note_findings = T.let([], T::Array[Finding])
        none_findings = T.let([], T::Array[Finding])

        findings.each do |finding|
          case finding.severity
          when :severity_critical
            critical_findings << finding
          when :severity_high
            high_findings << finding
          when :severity_medium
            medium_findings << finding
          when :severity_low
            low_findings << finding
          when :severity_note
            note_findings << finding
          else
            none_findings << finding
          end
        end

        critical_findings + high_findings + medium_findings + low_findings + note_findings + none_findings
      end

      sig do
        params(
          review: PullRequestReview,
          finding: Finding,
        ).returns(AutomatedReviewComment)
      end
      def build_automated_review_comment(review:, finding:)
        message = build_message(finding.message, finding.suggestion_description)

        arc = AutomatedReviewComment.new(
          repository_id: review.pull_request&.repository_id,
          pull_request_id: review.pull_request_id,
          source: :source_code_scanning_ai,
          resource_id: finding.stable_id,
          message: message,
          severity: finding.severity,
          security_severity: :security_severity_none,
          metadata: {
            "rule_id" => finding.rule_id,
            "model" => finding.model,
            "finding_source" => finding.source
          }.compact,
        )

        if finding.suggestion.present?
          arc.suggestion = finding.suggestion
          arc.suggestion_state = :suggestion_state_present
        end

        arc
      end

      sig do
        params(
          review: PullRequestReview,
          finding: Finding,
          diff: GitHub::Diff,
          body: String,
        ).returns(T.nilable(PullRequestReviewComment))
      end
      def build_review_comment(review:, finding:, diff:, body:)
        start_line = comment_start_line(finding, diff)
        return nil unless start_line

        extra_attributes = extra_comment_attributes(finding.start_line, finding.end_line, start_line)

        review.build_thread.build_first_comment(
          user: review.user,
          body: body,
          path: finding.file_path,
          line: finding.end_line,
          side: :right,
          start_line: extra_attributes[:start_line],
          start_side: extra_attributes[:start_side],
        )
      end

      sig { returns(T.untyped) }
      def code_scanning_bot
        integration = Apps::Privileged.integration(:code_scanning) or fail "code scanning integration not installed!"
        integration.bot
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def logging_context
        {
          "code.namespace" => "CodeScanning::AiFindingsPrCommentsManager",
        }
      end

      sig { params(message: String, context: T::Hash[T.untyped, T.untyped]).void }
      def log_info(message, context = {})
        GitHub.logger.info(message, logging_context.merge(context).merge(
          "code.function" => caller_locations(1, 1)&.first&.base_label || "unknown_function",
        ))
      end

      sig { params(message: String, context: T::Hash[T.untyped, T.untyped]).void }
      def log_error(message, context = {})
        GitHub.logger.error(message, logging_context.merge(context).merge(
          "code.function" => caller_locations(1, 1)&.first&.base_label || "unknown_function",
        ))
      end

      sig { params(message: T.nilable(String), suggestion_description: T.nilable(String)).returns(String) }
      def build_message(message, suggestion_description = nil)
        base_message = GitHub::Goomba::CodeQualityPRMessagePipeline.to_html(message.presence || "", {}, nil)

        return base_message if suggestion_description.blank?

        suggestion_description_html = GitHub::Goomba::CodeQualityPRMessagePipeline.to_html(suggestion_description, {}, nil)

        # Strip wrapping <p> tags when combining messages since we're joining with a separator
        base_message_stripped = base_message.sub(/\A<p>(.*)<\/p>\z/m, '\1')
        suggestion_description_html_stripped = suggestion_description_html.sub(/\A<p>(.*)<\/p>\z/m, '\1')

        separator = base_message_stripped.present? ? "\n\n---\n\n" : ""
        "#{base_message_stripped}#{separator}#{suggestion_description_html_stripped}"
      end
    end
  end
end
