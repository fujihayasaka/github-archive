# typed: strict
# frozen_string_literal: true

module CodeQuality
  # Once Turboquality has completed the generation of suggested fixes for an Analysis, it
  # signals on the PullRequestAnalysis topic.
  # We use this to post the findings on the corresponding PR
  class PullRequestAnalysisProcessor < GitHub::StreamProcessors::BaseProcessor
    include GitHub::StreamProcessors::TransientErrorResiliency
    include GitHub::Memoizer

    class Error < StandardError; end

    DEFAULT_GROUP_ID = "code_quality_processed_pr_analysis"
    DEFAULT_SUBSCRIBE_TO = T.let([
      /turboquality\.v0\.PullRequestAnalysis\Z/,
    ].freeze, T::Array[Regexp])

    options[:min_bytes] = 5.kilobytes
    options[:max_wait_time] = 0.2.seconds
    options[:max_bytes_per_partition] = 100.kilobytes
    options[:session_timeout] = 60.seconds
    options[:start_from_beginning] = false

    resolve_tenant_context do |message|
      Repositories::Public.get_active_or_deleted!(message.value[:repository_id]).owner&.business
    end

    sig { params(group_id: T.nilable(String), subscribe_to: T.nilable(T::Array[Regexp])).void }
    def setup(group_id: nil, subscribe_to: nil)
      options[:group_id] ||= DEFAULT_GROUP_ID
      options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
      self.transient_error_max_retries = 20
    end

    sig { params(message: GitHub::StreamProcessors::Message).void }
    def process_message(message)
      analysis = message.value
      repo_id = analysis[:repository_id]
      analyzed_commit_oid = analysis[:commit_oid]
      logging_context.merge!(
        "gh.repo.id" => repo_id,
        "git.commit.oid" => analyzed_commit_oid,
        "gh.ref" => analysis[:ref],
      )

      log_info(
        "Received new pull request analysis message",
        "code.function" => "process_message",
      )

      repo = Repository.find_by(id: repo_id)
      # The repository has been deleted, return early
      return if repo.nil?
      return unless repo.code_scanning_code_quality_pr_preview_enabled? && repo.active?

      # identify the PR to post the findings to
      pull_request = find_pull_request(repo, analysis[:ref])
      logging_context.merge!(
        "gh.pull_request.id" => pull_request&.id,
      )

      return unless pull_request.present? && should_review_pull_request?(pull_request, analyzed_commit_oid)

      post_review(pull_request, analysis[:comment], analysis[:findings], analysis[:rules], analyzed_commit_oid)
    end

    private

    sig do
      params(
        pull_request: PullRequest,
        comment_message: String,
        findings: T::Array[T::Hash[Symbol, T.untyped]],
        rules: T::Hash[String, T::Hash[Symbol, T.untyped]],
        head_commit_oid: String,
      ).void
    end
    def post_review(pull_request, comment_message, findings, rules, head_commit_oid)
      # create the pr review with variant_type code_quality
      review = pull_request.build_code_quality_variant_review do |r|
        r.user = code_quality_bot
        r.body = comment_message
        r.head_sha = head_commit_oid
        r.merge_base_sha = pull_request.find_best_merge_base_sha(head_sha: head_commit_oid)
      end

      # we have the expectation that the rules are indexed by their sarif_identifier
      comments_to_proto_findings = findings.each_with_object(Hash.new) do |finding, h|
        proto_finding = Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Finding.new(finding)

        proto_result = proto_finding.annotation_result&.result
        unless proto_result.present?
          report_error("Failed to extract proto_result from finding")
          return
        end

        rule = rules[proto_result.rule_identifier]
        unless rule.present?
          report_error("Failed to find rule for finding")
          return # should we accept a missing rule?
        end

        proto_rule = Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Rule.new(rule)

        comment = build_review_comment(review:, result: proto_result, rule: proto_rule)
        h[comment] = { finding: proto_finding, rule: proto_rule }
      end

      comments_created = 0
      with_primaries ApplicationRecord::IssuesPullRequests, ApplicationRecord::Notify  do
        PullRequestReview.transaction do
          comments_to_proto_findings.each do |review_comment, finding_data|
            if review_comment.save
              comments_created += 1
              build_code_quality_finding(review_comment, finding_data[:finding], finding_data[:rule]).save
            else
              # maybe we can use sth from the finding metadata here for the logging attributes
              log_error("Failed to save review comment for finding, skipping finding")
              # we don't raise, just post the comments we can
            end
          end

          # this is the same as when a manual review hits comment
          # (or 'approve' or 'request changes' (which conceivably we might want to do))
          review.comment! if comments_created > 0
        end
      end
    end

    sig do
      params(
        review: PullRequestReview,
        result: Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Result,
        rule: Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Rule,
      ).returns(T.untyped)
    end
    def build_review_comment(review:, result:, rule:)
      thread = review.build_thread

      location = T.must(result.location)

      comment_body = []
      comment_body << "## #{ rule.short_description}" if rule.short_description.present?
      comment_body << "#{ result.message_text }" if result.message_text.present?

      attributes = {
        user: review.user,
        body: comment_body.join("\n\n"),
        path: location.file_path,
        line: location.end_line,
        side: :right,
      }

      if location.start_line != location.end_line
        attributes.merge!(
          # TODO we may need to adjust the start line to prevent the comment location escaping the pr diff
          # in a similar way as we do for code scanning alerts
          # but for now let's keep it simple
          start_line: location.start_line,
          start_side: :right,
        )
      end

      thread.build_first_comment(**attributes)
    end

    sig do
      params(
        review_comment: PullRequestReviewComment,
        proto_finding: Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Finding,
        proto_rule: Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Rule,
      ).returns(CodeQualityPullRequestFinding)
    end
    def build_code_quality_finding(review_comment, proto_finding, proto_rule)
      CodeQualityPullRequestFinding.finding(review_comment:, proto_finding:, proto_rule:)
    end

    sig { params(repo: Repository, ref: String).returns(T.nilable(PullRequest)) }
    def find_pull_request(repo, ref)
      # Since code quality analyses are managed, the analysed commit is always the head commit, and the ref used is the
      # pseudo-ref refs/pull/N/head
      matcher = ref.match(/\Arefs\/pull\/([0-9]+)\/head\Z/)
      if matcher
        pr_number = matcher[1]
        PullRequest.with_number_and_repo(pr_number, repo)
      else
        log_info("No matching pull request found for ref")
        nil
      end
    end

    sig { params(pull_request: PullRequest, analyzed_commit_oid: String).returns(T::Boolean) }
    def should_review_pull_request?(pull_request, analyzed_commit_oid)
      return false unless pull_request.open?

      # if the PR has had pushes since the analysis, skip this message and wait for the next
      if pull_request.head_sha != analyzed_commit_oid
        log_info(
          "Pull request head sha doesn't match the analyzed commit - aborting review comment creation",
          "gh.pull_request.head_sha" => pull_request.head_sha,
        )
        return false
      end

      if pull_request.issue&.locked?
        log_info("Pull request is locked - aborting review comment creation")
        return false
      end

      true
    end

    sig { returns(T.untyped) }
    memoize def code_quality_bot
      #  we use the code scanning bot here for now until as the code quality one doens't exist yet
      code_scanning_app = Apps::Privileged.integration(:code_scanning) or fail "code scanning integration not installed!"
      code_scanning_app.bot
    end

    sig { params(message: String, context: T::Hash[String, T.untyped]).void }
    def log_info(message, context = {})
      GitHub.logger.info(message, logging_context.merge(context).merge(
        "code.function" => caller_locations(1, 1)&.first&.base_label || "unknown_function",
      ))
    end

    sig { params(message: String, context: T::Hash[String, T.untyped]).void }
    def log_error(message, context = {})
      GitHub.logger.error(message, logging_context.merge(context).merge(
        "code.function" => caller_locations(1, 1)&.first&.base_label || "unknown_function",
      ))
    end

    sig { returns(T::Hash[String, T.untyped]) }
    memoize def logging_context
      {
        "code.namespace" => "CodeQuality::PullRequestAnalysisProcessor"
      }
    end

    sig { params(message: GitHub::StreamProcessors::Message).returns(T::Hash[Symbol, T.untyped]) }
    def error_context_for_message(message)
      super(message).merge(
        repo_id: message.value[:repository_id],
        analyzed_commit_oid: message.value[:commit_oid]
      )
    end
  end
end
