# typed: strict
# frozen_string_literal: true

module CodeScanning
  # Processes PullRequestAiAnalysis Hydro messages and posts the AI-detected
  # findings as automated review comments on the pull request.
  class PullRequestAiAnalysisProcessor < GitHub::StreamProcessors::SingleMessageProcessor
    include GitHub::StreamProcessors::TransientErrorResiliency
    include GitHub::Memoizer

    DEFAULT_GROUP_ID = "code_scanning_pull_request_ai_analysis"
    DEFAULT_SUBSCRIBE_TO = T.let([
      /code_scanning\.v0\.PullRequestAiAnalysis\Z/,
    ].freeze, T::Array[Regexp])
    MAX_AMOUNT_OF_FINDINGS = 100

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
      self.transient_error_max_retries = 10
    end

    sig { override.params(message: GitHub::StreamProcessors::Message).returns(T.anything) }
    def process_message(message)
      payload = message.value
      repo_id = payload[:repository_id]
      commit_oid = payload[:commit_oid]
      pull_request_id = payload[:pull_request_id]

      logging_context.merge!(
        "gh.repo.id" => repo_id,
        "git.commit.oid" => commit_oid,
        "gh.pull_request.id" => pull_request_id,
      )

      log_info("Received new pull request AI analysis message")

      repository = T.cast(Repositories.domain.by_id(repo_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
      if repository.nil?
        log_info("Repository not found, skipping")
        return message.skip("Repository not found, skipping")
      end

      unless repository.active?
        log_info("Repository is inactive, skipping")
        return message.skip("Repository is inactive, skipping")
      end

      return message.skip("Feature flag not enabled, skipping") unless FeatureFlag.vexi.enabled?(:code_scanning_ai_findings, repository, repository.owner, default: false)

      pull_request = PullRequest.find_by(id: pull_request_id, repository: repository)
      if pull_request.nil?
        log_info("Pull request not found, skipping")
        return message.skip("Pull request not found, skipping")
      end

      return message.skip("Pull request should not be processed, skipping") unless should_process_pull_request?(pull_request, commit_oid)

      proto_findings = payload[:findings].map do |f|
        Hydro::Schemas::CodeScanning::V0::PullRequestAiAnalysis::Finding.new(f)
      end

      findings = proto_findings.filter_map { |f| build_finding(f, commit_oid) }

      if findings.empty?
        log_info("No valid findings to post, skipping")
        return message.skip("No valid findings to post")
      end

      if findings.length > MAX_AMOUNT_OF_FINDINGS
        log_info("More than #{MAX_AMOUNT_OF_FINDINGS} findings, skipping", "gh.findings.count" => findings.length)
        return message.skip("More than #{MAX_AMOUNT_OF_FINDINGS}")
      end

      diffs = find_pull_comparison(pull_request, commit_oid)&.diffs
      if diffs.nil?
        log_info("No diff found for pull request, skipping")
        return message.skip("No diff found for pull request, skipping")
      end

      diffs.add_paths(findings.map(&:file_path), side: :b)

      log_info("Sending findings to PR comments manager")

      with_primaries ApplicationRecord::IssuesPullRequests, ApplicationRecord::Notify do
        CodeScanning::AiFindingsPrCommentsManager.manage_automated_review_comments(
          pull_request: pull_request,
          commit_oid: commit_oid,
          diff: diffs,
          findings: findings,
        )
      end

      log_info("Finished processing pull request AI analysis message")
    end

    private

    sig do
      params(
        proto_finding: Hydro::Schemas::CodeScanning::V0::PullRequestAiAnalysis::Finding,
        commit_oid: String,
      ).returns(T.nilable(CodeScanning::AiFindingsPrCommentsManager::Finding))
    end
    def build_finding(proto_finding, commit_oid)
      location = proto_finding.location
      return nil if location.nil?
      return nil if location.file_path.blank?

      stable_id = proto_finding.stable_id
      return nil if stable_id.blank?

      suggestion = build_suggestion(proto_finding, commit_oid)

      CodeScanning::AiFindingsPrCommentsManager::Finding.new(
        stable_id: stable_id,
        message: proto_finding.message,
        severity: map_severity(proto_finding.severity),
        file_path: location.file_path,
        start_line: location.start_line,
        end_line: location.end_line,
        suggestion: suggestion,
        suggestion_description: proto_finding.suggested_fix&.description.presence,
        rule_id: proto_finding.metadata["rule_id"].presence,
        model: proto_finding.metadata["model"].presence,
        source: proto_finding.source.presence,
      )
    end

    sig do
      params(
        proto_finding: Hydro::Schemas::CodeScanning::V0::PullRequestAiAnalysis::Finding,
        commit_oid: String,
      ).returns(T.nilable(ReviewComments::Suggestion))
    end
    def build_suggestion(proto_finding, commit_oid)
      suggested_fix = proto_finding.suggested_fix
      return nil if suggested_fix.nil? || suggested_fix.files.empty?

      ReviewComments::Suggestion.new(
        commit_sha: commit_oid,
        files: suggested_fix.files.map do |file|
          ReviewComments::Suggestion::File.new(
            path: file.file_path,
            diff_content: file.diff_content,
          )
        end,
      )
    end

    sig { params(severity: T.untyped).returns(Symbol) }
    def map_severity(severity)
      case severity
      when :SEVERITY_CRITICAL
        :severity_critical
      when :SEVERITY_HIGH
        :severity_high
      when :SEVERITY_MEDIUM
        :severity_medium
      when :SEVERITY_LOW
        :severity_low
      when :SEVERITY_NIT
        :severity_note
      else
        # SEVERITY_UNKNOWN and any unrecognized values
        :severity_none
      end
    end

    sig { params(pull_request: PullRequest, commit_oid: String).returns(T::Boolean) }
    def should_process_pull_request?(pull_request, commit_oid)
      return false unless pull_request.open?

      if commit_oid != pull_request.head_sha
        log_info(
          "Skipping AI findings PR comments for stale commit",
          "gh.commit.requested_sha" => commit_oid,
          "gh.pull_request.head_sha" => pull_request.head_sha,
        )
        return false
      end

      if pull_request.issue&.locked?
        log_info("Skipping AI findings PR comments for locked pull request")
        return false
      end

      true
    end

    sig do
      params(
        pull_request: PullRequest,
        commit_oid: String,
      ).returns(T.nilable(PullRequest::Comparison))
    end
    def find_pull_comparison(pull_request, commit_oid)
      merge_base = pull_request.merge_base
      PullRequest::Comparison.find(
        pull: pull_request,
        start_commit_oid: merge_base,
        end_commit_oid: commit_oid,
        base_commit_oid: merge_base,
      )
    end

    sig { params(message: String, context: T::Hash[String, T.untyped]).void }
    def log_info(message, context = {})
      GitHub.logger.info(message, logging_context.merge(context).merge(
        "code.function" => caller_locations(1, 1)&.first&.base_label || "unknown_function",
      ))
    end

    sig { returns(T::Hash[String, T.untyped]) }
    memoize def logging_context
      {
        "code.namespace" => "CodeScanning::PullRequestAiAnalysisProcessor",
      }
    end

    sig { params(message: GitHub::StreamProcessors::Message).returns(T::Hash[Symbol, T.untyped]) }
    def error_context_for_message(message)
      super(message).merge(
        repo_id: message.value[:repository_id],
        commit_oid: message.value[:commit_oid],
        pull_request_id: message.value[:pull_request_id],
      )
    end
  end
end
