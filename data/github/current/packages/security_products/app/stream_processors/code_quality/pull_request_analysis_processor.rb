# typed: strict
# frozen_string_literal: true

module CodeQuality
  # Once Turboquality has completed the generation of suggested fixes for an Analysis, it
  # signals on the PullRequestAnalysis topic.
  # We use this to post the findings on the corresponding PR
  class PullRequestAnalysisProcessor < GitHub::StreamProcessors::SingleMessageProcessor
    include GitHub::StreamProcessors::TransientErrorResiliency
    include GitHub::Memoizer
    include PullRequestAnalyses::ReviewCommentsHelper

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

    sig { override.params(message: GitHub::StreamProcessors::Message).returns(T.anything) }
    def process_message(message)
      analysis = message.value
      repo_id = analysis[:repository_id]
      analyzed_commit_oid = analysis[:commit_oid]
      analysis_configuration = analysis[:analysis_configuration]
      logging_context.merge!(
        "gh.repo.id" => repo_id,
        "git.commit.oid" => analyzed_commit_oid,
        "gh.ref" => analysis[:ref],
        "gh.code_quality.analysis_configuration" => analysis_configuration,
      )

      log_info(
        "Received new pull request analysis message",
        "code.function" => "process_message",
      )

      repository = if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
        T.cast(Repositories.domain.by_id(repo_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
      else
        Repository.find_by(id: repo_id)
      end
      # The repository has been deleted, return early
      return if repository.nil?
      return unless CodeQuality.enabled?(repository) && repository.active?

      # identify the PR to post the findings to
      pull_request = find_pull_request(repository, analysis[:ref])
      logging_context.merge!(
        "gh.pull_request.id" => pull_request&.id,
      )
      return unless pull_request.present? && should_review_pull_request?(pull_request, analyzed_commit_oid)

      with_primaries ApplicationRecord::Notify  do
        CodeQualityPullRequestAnalyses.record(
          repository:,
          pull_request:,
          commit_oid: analyzed_commit_oid,
          analysis_configuration: analysis_configuration,
        )
      end

      diffs = find_pull_comparison(pull_request, analyzed_commit_oid)&.diffs
      if diffs.nil?
        log_info("no diff to post comments on - aborting review comment creation.")
        return
      end
      diffs.add_paths(analysis[:findings].map { |f| f[:annotation_result][:result][:location][:file_path] }, side: :b)

      proto_rules = analysis[:rules].each_with_object({}) do |(rule_id, rule), h|
        proto_rule = Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Rule.new(rule)
        h[rule_id] = proto_rule
      end

      if CodeQuality.automated_review_comment_enabled?(repository)
        with_primaries ApplicationRecord::IssuesPullRequests, ApplicationRecord::Notify  do
          CodeQuality::PrCommentsManager::manage_automated_review_comments(
            pull_request:,
            commit_oid: analyzed_commit_oid,
            diff: diffs,
            analysis_configuration:,
            findings: analysis[:findings],
            rules: proto_rules,
          )
        end
        return
      end

      # we look at the existing findings from the same analysis configuration
      # we can ignore those that had already been fixed
      # if we encounter a finding with the same id as an old *fixed* one we should post about it again
      persisted_findings_map = CodeQualityPullRequestFinding.find_all(repository:, pull_request:)
        .select { |finding| finding.analysis_configuration == analysis_configuration }
        .reject(&:fixed?)
        .index_by(&:stable_id)

      new_findings = []
      findings_to_update = []

      analysis[:findings].each do |finding|
        proto_finding = Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Finding.new(finding)
        proto_result = T.must(proto_finding.annotation_result&.result)

        # we delete the finding from the existing findings map
        # so at the end only the fixed findings remain
        persisted_finding = persisted_findings_map.delete(proto_result.stable_id)
        if persisted_finding.present?
          findings_to_update << { persisted_finding:, new_finding: proto_finding, new_rule: proto_rules[proto_result.rule_identifier] }
        else
          new_findings << proto_finding
        end
      end

      post_review(
        repository,
        pull_request,
        analysis_configuration,
        analysis[:comment],
        new_findings,
        proto_rules,
        analyzed_commit_oid,
        diffs
      ) unless new_findings.empty?

      with_primaries ApplicationRecord::Notify  do
        # we're not going to update the review comment body because
        #  - we generally want to block updates to the body of code quality review comments
        #  - the comment body is unlikely to change significantly anyway
        findings_to_update.each { |update_args| update_finding(**update_args, analysis_configuration:) }

        with_primaries ApplicationRecord::IssuesPullRequests  do
          handle_fixed_findings(persisted_findings_map.values, repository, pull_request)
        end
      end
    end

    private

    sig do
      params(
        repository: Repository,
        pull_request: PullRequest,
        analysis_configuration: String,
        comment_message: String,
        new_findings: T::Array[Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Finding],
        rules: T::Hash[String, Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Rule],
        commit_oid: String,
        diffs: GitHub::Diff,
      ).void
    end
    def post_review(repository, pull_request, analysis_configuration, comment_message, new_findings, rules, commit_oid, diffs)
      # create the pr review with variant_type code_quality
      review = pull_request.build_code_quality_variant_review do |r|
        r.user = code_quality_bot
        r.body = comment_message
        r.head_sha = commit_oid
        r.merge_base_sha = pull_request.find_best_merge_base_sha(head_sha: commit_oid)
      end


      # we have the expectation that the rules are indexed by their sarif_identifier
      persisted_finding_arguments = new_findings.filter_map do |new_finding|
        result = T.must(new_finding.annotation_result&.result)
        rule = T.must(rules[result.rule_identifier])
        review_comment = build_review_comment(review:, result:, rule:, diffs:)

        next unless review_comment.present?

        {
          review_comment:,
          analysis_configuration:,
          commit_oid:,
          proto_finding: new_finding,
          proto_rule: rule
        }
      end

      comments_created = 0
      with_primaries ApplicationRecord::IssuesPullRequests, ApplicationRecord::Notify  do
        PullRequestReview.transaction do
          persisted_finding_arguments.each do |args|
            review_comment = args[:review_comment]
            if review_comment.save
              comments_created += 1
              build_code_quality_finding(**args).save
            else
              log_error("Failed to save review comment for finding, skipping",
                "error" => review_comment.errors.full_messages,
              )
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
        diffs: GitHub::Diff,
      ).returns(T::nilable(PullRequestReviewComment))
    end
    def build_review_comment(review:, result:, rule:, diffs:)
      comment_start_line = comment_start_line(result, diffs)
      return nil unless comment_start_line

      thread = review.build_thread

      # if the location is outside the diff the comment creation/saving seems to fail gracefully
      location = T.must(result.location)

      comment_body = []
      comment_body << "## #{ rule.short_description}" if rule.short_description.present?
      comment_body << "#{ result.message_text }" if result.message_text.present?

      extra_attributes = extra_comment_attributes(location.start_line, location.end_line, comment_start_line)

      thread.build_first_comment(
        user: review.user,
        body: comment_body.join("\n\n"),
        path: location.file_path,
        line: location.end_line,
        side: :right,
        start_line: extra_attributes[:start_line],
        start_side: extra_attributes[:start_side],
      )
    end

    sig do
      params(
        review_comment: PullRequestReviewComment,
        analysis_configuration: String,
        commit_oid: String,
        proto_finding: Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Finding,
        proto_rule: Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Rule,
      ).returns(CodeQualityPullRequestFinding)
    end
    def build_code_quality_finding(review_comment:, analysis_configuration:, commit_oid:, proto_finding:, proto_rule:)
      CodeQualityPullRequestFinding.finding(
        review_comment:,
        analysis_configuration:,
        commit_oid:,
        proto_finding:,
        proto_rule:
      )
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

    sig do
      params(
        persisted_finding: CodeQualityPullRequestFinding,
        new_finding: Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Finding,
        new_rule: Hydro::Schemas::Turboquality::V0::PullRequestAnalysis::Rule,
        analysis_configuration: String,
      ).void
    end
    def update_finding(persisted_finding:, new_finding:, new_rule:, analysis_configuration:)
      persisted_finding.update!(analysis_configuration:, finding: new_finding, rule: new_rule)
    end

    sig do
      params(
        fixed_findings: T::Array[CodeQualityPullRequestFinding],
        repository: Repository,
        pull_request: PullRequest
      ).void
    end
    def handle_fixed_findings(fixed_findings, repository, pull_request)
      return if fixed_findings.empty?

      # get all the comments for the findings that were fixed because we need to resolve their conversations
      comments = PullRequestReviewComment.where(
        repository_id: repository.id,
        pull_request_id: pull_request.id,
        id: fixed_findings.map(&:review_comment_id)
      ).preload(:pull_request_review_thread, :pull_request_review).index_by(&:id)
      fixed_findings.each do |finding|
        review_thread = comments[finding.review_comment_id].pull_request_review_thread
        if review_thread.conversation?
          # we resolve the review thread if it is a conversation
          review_thread.resolve(resolver: code_quality_bot)
          log_info("Autoresolving conversation for fixed code quality finding",
            "gh.pull_request_review_comment.id" => finding.review_comment_id,
          )
        end
        finding.fix!
      end
    end

    sig { returns(T.untyped) }
    memoize def code_quality_bot
      bot = Apps::Privileged.attribution_only_system_identity_for(:code_quality)
      raise "GitHub Code quality bot not found" if bot.nil?

      bot
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
