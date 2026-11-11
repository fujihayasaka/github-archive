# typed: strict
# frozen_string_literal: true

module CodeQuality
  class PrCommentsManager
    extend PullRequestAnalyses::ReviewCommentsHelper

    sig do
      params(
        pull_request: PullRequest,
        commit_oid: String,
        diff: GitHub::Diff,
        analysis_configuration: String,
        findings: T.untyped,
        rules: T::Hash[String, Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Rule],
      )
      .void
    end
    def self.manage_automated_review_comments(
      pull_request:,
      commit_oid:,
      diff:,
      analysis_configuration:,
      findings:,
      rules:
    )
      # we look at the existing comments from the same analysis configuration
      # we can ignore those that had already been fixed
      # if we encounter a comment with the same id as an old *fixed* one we should post about it again
      existing_comments_map = AutomatedReviewComment.where(
        repository: pull_request.repository,
        pull_request:, source: :source_code_quality,
        fixed_at: nil,
      )
      .select { |comment| comment.metadata["analysis_configuration"] == analysis_configuration }
      .index_by { |comment| comment.resource_id }

      new_findings = []
      comments_to_update = []
      findings.each do |finding|
        proto_finding = Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Finding.new(finding)
        proto_result = T.must(proto_finding.annotation_result&.result)

        # we delete the finding from the existing findings map
        # so at the end only the fixed findings remain
        persisted_comment = existing_comments_map.delete(proto_result.stable_id)
        if persisted_comment.present?
          comments_to_update << { persisted_comment:, new_finding: proto_finding, new_rule: rules[proto_result.rule_identifier] }
        else
          new_findings << proto_finding
        end
      end

      # the comments left in the map should be marked as fixed
      comments_to_fix = existing_comments_map.values #TODO

      post_automated_review(
        pull_request:,
        commit_oid:,
        diff:,
        analysis_configuration:,
        findings: new_findings,
        rules:,
      )

      # we're not going to update the review comment body because
      #  - we generally want to block updates to the body of code quality review comments
      #  - the comment body is unlikely to change significantly anyway
      update_comments(comments_to_update:, analysis_configuration:, commit_oid:)

      handle_fixed_comments(existing_comments_map.values, pull_request)
    end

    class << self
      private

      sig do
        params(
          pull_request: PullRequest,
          commit_oid: String,
          diff: GitHub::Diff,
          analysis_configuration: String,
          findings: T::Array[Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Finding],
          rules: T::Hash[String, Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Rule],
        )
        .void
      end
      def post_automated_review(
        pull_request:,
        commit_oid:,
        diff:,
        analysis_configuration:,
        findings:,
        rules:
      )
        # create the pr review
        review = pull_request.build_automated_variant_review do |r|
          r.user = code_quality_bot
          # r.body = comment_message
          r.head_sha = commit_oid
          r.merge_base_sha = pull_request.find_best_merge_base_sha(head_sha: commit_oid)
        end

        # construct the review comments and code quality review comments outside the transaction
        # to avoid a slow running transaction
        review_comment_pairs = Hash.new
        findings.each do |finding|
          automated_review_comment = build_automated_review_comment(review:, finding:, analysis_configuration:, rules:)
          review_comment = build_review_comment(review:, finding:, diff:, body: automated_review_comment.format_body)

          next unless review_comment.present?

          review_comment_pairs[review_comment] = automated_review_comment
        end
        # then in a transaction we save and connect them
        PullRequestReview.transaction do
          comments_created = 0
          review_comment_pairs.each do |review_comment, automated_review_comment|
            if review_comment.save
              comments_created += 1
              automated_review_comment.pull_request_review_comment_id = review_comment.id
              automated_review_comment.save!
            else
              GitHub.logger.error("Failed to save review comment for finding, skipping", "error" => review_comment.errors.full_messages)
            end
          end

          # this is the same as when a manual review hits comment
          # (or 'approve' or 'request changes' (which conceivably we might want to do))
          review.comment! if comments_created > 0
        end
      end

      sig do
        params(
          review: PullRequestReview,
          finding: Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Finding,
          diff: GitHub::Diff,
          body: String,
        ).returns(T::nilable(PullRequestReviewComment))
      end
      def build_review_comment(review:, finding:, diff:, body:)
        result = T.must(finding.annotation_result&.result)
        comment_start_line = comment_start_line(result, diff)
        return nil unless comment_start_line

        # if the location is outside the diff the comment creation/saving seems to fail gracefully
        location = T.must(result.location)
        extra_attributes = extra_comment_attributes(location.start_line, location.end_line, comment_start_line)

        review.build_thread.build_first_comment(
          user: review.user,
          body: body,
          path: location.file_path,
          line: location.end_line,
          side: :right,
          start_line: extra_attributes[:start_line],
          start_side: extra_attributes[:start_side],
        )
      end

      sig do
        params(
          review: PullRequestReview,
          finding: Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Finding,
          analysis_configuration: String,
          rules: T::Hash[String, Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Rule],
        ).returns(AutomatedReviewComment)
      end
      def build_automated_review_comment(review:, finding:, analysis_configuration:, rules:)
        result = T.must(finding.annotation_result&.result)
        suggested_fix = finding.suggested_fix
        related_locations = finding.annotation_result&.related_locations.to_a

        rule = T.must(rules[result.rule_identifier])

        severity = CodeQuality.get_severity_level_from_rule_severity(rule.severity)

        context = {
          related_locations: related_locations,
          commit_oid: review.head_sha,
          entity: review.pull_request&.repository,
        }

        message = build_message(result.message_text, suggested_fix, context, review.pull_request&.repository)

        automated_review_comment = AutomatedReviewComment.new(
          repository_id: review.pull_request&.repository_id,
          pull_request_id: review.pull_request_id,
          source: :source_code_quality,
          resource_id: result.stable_id,
          title: rule.short_description,
          message: message,
          severity: severity,
          security_severity: :security_severity_none,
          metadata: {
            rule_sarif_id: rule.sarif_identifier,
            analysis_configuration: analysis_configuration,
          }
        )

        if suggested_fix.present?
          suggestion = ReviewComments::Suggestion.new(
            commit_sha: review.head_sha,
            files: suggested_fix.files.map do |file|
              ReviewComments::Suggestion::File.new(
                path: file.file_path,
                diff_content: file.diff_content
              )
            end
          )
          automated_review_comment.suggestion = suggestion
          automated_review_comment.suggestion_state = :suggestion_state_present
        end

        automated_review_comment
      end

      sig do
        params(
          comments_to_update: T::Array[T::Hash[Symbol, T.untyped]],
          analysis_configuration: String,
          commit_oid: String,
        ).void
      end
      def update_comments(comments_to_update:, analysis_configuration:, commit_oid:)
        comments_to_update.each do |update_args|
          new_finding = update_args[:new_finding]
          new_rule = update_args[:new_rule]
          new_suggestion = new_finding.suggested_fix

          result = new_finding.annotation_result.result
          severity = CodeQuality.get_severity_level_from_rule_severity(new_rule.severity)

          current_comment = update_args[:persisted_comment]

          related_locations = new_finding.annotation_result&.related_locations.to_a
          context = {
            related_locations: related_locations,
            commit_oid: commit_oid,
            entity: current_comment&.repository,
          }

          message = build_message(result.message_text, new_suggestion, context, current_comment&.repository)

          suggestion = current_comment.suggestion
          suggestion_state = current_comment.suggestion_state
          if new_suggestion.present? && suggestion_state != "suggestion_state_applied"
            suggestion = ReviewComments::Suggestion.new(
              commit_sha: commit_oid,
              files: new_suggestion.files.map do |file|
                ReviewComments::Suggestion::File.new(
                  path: file.file_path,
                  diff_content: file.diff_content
                )
              end
            )
            suggestion_state = :suggestion_state_present
          end

          current_comment.update!(
            title: new_rule.short_description,
            message: message,
            severity: severity,
            metadata: {
              rule_sarif_id: new_rule.sarif_identifier,
              analysis_configuration: analysis_configuration,
            },
            suggestion:,
            suggestion_state:,
          )
        end
      end

      sig do
        params(
          fixed_comments: T::Array[AutomatedReviewComment],
          pull_request: PullRequest
        ).void
      end
      def handle_fixed_comments(fixed_comments, pull_request)
        return if fixed_comments.empty?

        fixed_comments.each do |comment|
          comment.fix!
        end
      end

      sig { returns(T.untyped) }
      def code_quality_bot
        bot = Apps::Privileged.attribution_only_system_identity_for(:code_quality)
        raise "GitHub Code quality bot not found" if bot.nil?
        bot
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def logging_context
        {
          "code.namespace" => "CodeQuality::PRCommentsManager",
        }
      end

      sig { params(message: String, context: T::Hash[String, T.untyped]).void }
      def log_info(message, context = {})
        GitHub.logger.info(message, logging_context.merge(context).merge(
          "code.function" => caller_locations(1, 1)&.first&.base_label || "unknown_function",
        ))
      end

      sig do
        params(
          result_message_text: T.nilable(String),
          suggested_fix: T.untyped,
          context: T::Hash[Symbol, T.untyped],
          repository: T.nilable(Repository)
        ).returns(String)
      end
      def build_message(result_message_text, suggested_fix, context, repository)
        base_message = GitHub::Goomba::CodeQualityPRMessagePipeline.to_html(result_message_text.presence || "", context, nil)

        suggestion_description = if suggested_fix&.description.present?
          GitHub::Goomba::CodeQualityPRMessagePipeline.to_html(suggested_fix.description, context, nil)
        end

        return base_message if suggestion_description.blank?

        # Strip wrapping <p> tags when combining messages since we're joining with separator
        base_message_stripped = base_message.sub(/\A<p>(.*)<\/p>\z/m, '\1')
        suggestion_description_stripped = suggestion_description.sub(/\A<p>(.*)<\/p>\z/m, '\1')

        separator = base_message_stripped.present? ? "\n\n---\n\n" : ""
        "#{base_message_stripped}#{separator}#{suggestion_description_stripped}"
      end
    end
  end
end
