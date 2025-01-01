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
      existing_comments_map = AutomatedReviewComment.where(repository: pull_request.repository, pull_request:, source: :source_code_quality)
        .select { |comment| analysis_configuration_from_resource_id(comment.resource_id) == analysis_configuration }
        # .reject(&:fixed?)
        .index_by { |comment| stable_id_from_resource_id(comment.resource_id) }

      new_findings = []
      findings_to_update = []
      findings.each do |finding|
        proto_finding = Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Finding.new(finding)
        proto_result = T.must(proto_finding.annotation_result&.result)

        # we delete the finding from the existing findings map
        # so at the end only the fixed findings remain
        persisted_finding = existing_comments_map.delete(proto_result.stable_id)
        if persisted_finding.present?
          # findings_to_update << { persisted_finding:, new_finding: proto_finding, new_rule: proto_rules[proto_result.rule_identifier] }
          findings_to_update << { persisted_finding:, new_finding: proto_finding }
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

        # construct the review comments and code scanning review comments outside the transaction
        # to avoid a slow running transaction
        review_comment_pairs = Hash.new
        findings.each do |finding|
          result = T.must(finding.annotation_result&.result)
          suggested_fix = finding.suggested_fix

          automated_review_comment = build_automated_review_comment(review:, result:, suggested_fix:, analysis_configuration:, rules:)
          review_comment = build_review_comment(review:, result:, diff:, body: automated_review_comment.format_body)

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
          result: Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Result,
          diff: GitHub::Diff,
          body: String,
        ).returns(T::nilable(PullRequestReviewComment))
      end
      def build_review_comment(review:, result:, diff:, body:)
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
          result: Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Result,
          suggested_fix: T.nilable(Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::SuggestedFix),
          analysis_configuration: String,
          rules: T::Hash[String, Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Rule],
        ).returns(AutomatedReviewComment)
      end
      def build_automated_review_comment(review:, result:, suggested_fix:, analysis_configuration:, rules:)
        rule = T.must(rules[result.rule_identifier])

        severity = case rule.severity
        when "RULE_SEVERITY_NOTE"
          :severity_note
        when "RULE_SEVERITY_WARNING"
          :severity_warning
        when "RULE_SEVERITY_ERROR"
          :severity_error
        else
          :severity_note
        end

        automated_review_comment = AutomatedReviewComment.new(
          repository_id: review.pull_request&.repository_id,
          pull_request_id: review.pull_request_id,
          source: :source_code_quality,
          resource_id: build_resource_id(stable_id: result.stable_id, analysis_configuration:),
          title: rule.short_description,
          message: result.message_text.presence || "No message text",
          severity: severity,
        )

        if suggested_fix.present?
          suggestion = ReviewComments::Suggestion.new(
            description: suggested_fix.description.presence || "",
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

      sig { params(analysis_configuration: String, stable_id: String).returns(String) }
      def build_resource_id(analysis_configuration:, stable_id:)
        "#{analysis_configuration}:#{stable_id}"
      end

      sig { params(resource_id: String).returns(String) }
      def analysis_configuration_from_resource_id(resource_id)
        String(resource_id.split(":")[0])
      end

      sig { params(resource_id: String).returns(String) }
      def stable_id_from_resource_id(resource_id)
        String(resource_id.split(":")[1])
      end

      sig { returns(T.untyped) }
      def code_quality_bot
        bot = Apps::Privileged.attribution_only_system_identity_for(:code_quality)
        raise "GitHub Code quality bot not found" if bot.nil?
        bot
      end
    end
  end
end
