# typed: true
# frozen_string_literal: true

module CodeScanning
  class PullRequestAlertSummaryGenerator
    extend T::Sig
    extend T::Helpers

    class TurboscanError < StandardError
      attr_accessor :twirp_error
      attr_accessor :repo_id

      def initialize(msg, repo_id: nil, twirp_error: nil)
        super(msg)
        self.repo_id = repo_id
        self.twirp_error = twirp_error
      end
    end

    # It's important that this does not inherit from TurboscanError as we will discard this particular error in CreateCodeScanningAnnotationsJob.
    class TurboscanNotFoundError < StandardError
      attr_reader :repo_id

      def initialize(msg, repo_id: nil)
        super(msg)
        @repo_id = repo_id
      end
    end

    attr_reader :pull_request
    attr_reader :merge_commit_oid, :head_commit_oid
    attr_reader :base_ref_name, :merge_ref_name, :head_ref_name

    def initialize(
      pull_request:,
      merge_ref_name:,
      head_ref_name:,
      merge_commit_oid:,
      head_commit_oid:,
      base_ref_name:
    )
      @pull_request = pull_request
      @merge_commit_oid = merge_commit_oid
      @head_commit_oid = head_commit_oid
      @merge_ref_name = merge_ref_name
      @head_ref_name = head_ref_name
      @base_ref_name = base_ref_name
    end

    def generate(check_run)
      base_log_context = {
        "code.namespace" => "CodeScanning::PullRequestAlertSummaryGenerator",
        "code.function" => "generate",
        "gh.repo.id" => check_run.repository&.id,
        "gh.check_run.id" => check_run.id,
      }

      if check_run.repository
        base_log_context["gh.code_scanning.pr_alerts.check_run.url"] = UrlHelpers.check_run_url(
          host: GitHub.url,
          user_id: check_run.repository.owner,
          repository: check_run.repository,
          id: check_run.id
        )
      end

      if pull_request.blank?
        GitHub.logger.warn("Pull request is nil", base_log_context)
        raise "Pull request is nil in PullRequestAlertSummaryGenerator" # We raise so that the job fails
      end

      repository = check_run.repository
      tool_name = check_run.code_scanning_tool_name

      request_fixed_alerts = GitHub.flipper[:code_scanning_pr_fixed_alerts].enabled?(repository) || GitHub.flipper[:code_scanning_pr_fixed_alerts].enabled?(repository.owner)

      file_changes = Scientist.run("code-scanning-pr-alerts-diff") do |e|
        e.context(
          repo_id: check_run.repository_id,
          pr_no: pull_request.number,
          check_run_id: check_run.id
        )

        e.use do
          if !pull_request.diffs.available?
            GitHub.logger.warn("Diff unavailable", base_log_context)
            GitHub.dogstats.increment("code_scanning.pull_request_alerts.job", tags: ["result:diff-unavailable"])
            []
          elsif pull_request.diffs.truncated_for_timeout?
            GitHub.logger.warn("Diff truncated for timeout", base_log_context)
            GitHub.dogstats.increment("code_scanning.pull_request_alerts.job", tags: ["result:diff-timeout"])
            []
          else
            ::CodeScanning::PullRequestAlertSummaryGenerator.changed_lines(pull_request.diffs, include_deletions: request_fixed_alerts)
          end
        end

        e.try do
          # TODO: We most likely will not ship this, initially called the paginated/capped diff approach.
          #       But the experiment setup might still be useful for future experiments so we're keeping it around for now.
          #       Tracking issue: https://github.com/github/code-scanning/issues/11626
          pr_alerts_diff = CodeScanning::PullRequestAlertsDiff.new(pull_request)
          pr_alerts_diff.detect_changes!

          if pr_alerts_diff.unavailable_reason
            GitHub.logger.warn("Diff unavailable", base_log_context.merge("gh.code_scanning.pr_alerts.diff.unavailable_reason" => pr_alerts_diff.unavailable_reason))
            GitHub.dogstats.increment("code_scanning.pull_request_alerts.job", tags: ["result:diff-unavailable", "reason:#{pr_alerts_diff.unavailable_reason_symbol}"])
          end

          if pr_alerts_diff.truncated_reason
            GitHub.logger.warn("Diff truncated", base_log_context.merge("gh.code_scanning.pr_alerts.diff.truncated_reason" => pr_alerts_diff.truncated_reason))
            GitHub.dogstats.increment("code_scanning.pull_request_alerts.job", tags: ["result:diff-truncated", "reason:#{pr_alerts_diff.truncated_reason_symbol}"])
          end

          pr_alerts_diff.file_changes
        end

        e.ignore do |control, candidate|
          control_change_counts = control.each_with_object(Hash.new(0)) do |file_change, out|
            file_path = file_change[:file_path]
            out[file_path] += file_change[:changes].size
          end

          candidate_change_counts = candidate.each_with_object(Hash.new(0)) do |file_change, out|
            file_path = file_change[:file_path]
            out[file_path] += file_change[:changes].size
          end

          control_file_paths = Set.new(control_change_counts.keys)
          candidate_file_paths = Set.new(candidate_change_counts.keys)

          # The mismatch is expected (and can therefore be ignored) if the candidate has a file
          # that the control doesn't or if the candidate has more changes for a specific file.
          if candidate_file_paths.superset?(control_file_paths)
            candidate_change_counts.all? do |file_path, candidate_change_count|
              control_change_counts.fetch(file_path, 0) <= candidate_change_count
            end
          else
            false
          end
        end

        e.run_if do
          # No need to run experiment if code_scanning_pr_fixed_alerts is enabled as the new, candidate diff code
          # does not (yet) include deleted lines.
          !request_fixed_alerts
        end
      end

      response = GitHub::Turboscan.pull_request_alerts(
        repository_id: repository.id,
        tool: tool_name,
        head_commit_oid: head_commit_oid,
        merge_commit_oid: merge_commit_oid,
        base_ref_bytes: base_ref_name&.b,
        file_changes: file_changes
      )

      if response&.error&.code == :not_found
        raise TurboscanNotFoundError.new("Turboscan.PullRequestAlerts responded with 404", repo_id: repository.id)
      elsif response.nil? || response.data.nil? || response.error.present?
        GitHub.dogstats.increment("code_scanning.pull_request_alerts.job", tags: ["result:turboscan-error", "api:#{tool_name == "API"}", "status:#{response&.error&.code}"])
        raise TurboscanError.new("Turboscan.PullRequestAlerts endpoint failed for annotations job", repo_id: repository.id, twirp_error: response&.error)
      end

      GitHub.dogstats.increment("code_scanning.pull_request_alerts.job", tags: ["result:success"])

      data = T.must(response.data)

      PullRequestAlertSummarizer.new(
        pull_request_number: pull_request.number,
        repository: check_run.repository,
        tool_name: check_run.name,
        base_ref_name: base_ref_name,
        merge_ref_name: merge_ref_name,
        head_ref_name: head_ref_name,
        merge_commit_oid: merge_commit_oid,
        head_commit_oid: head_commit_oid,

        fixed_alerts: data.fixed_alerts,
        fixed_count: data.fixed_count,
        new_alerts: data.new_alerts,
        new_count: data.new_count,
        new_categories: data.new_categories,
        missing_categories: data.missing_categories,
        latest_upload_time: data.latest_upload_time&.to_time,
        security_critical_count: data.security_critical_count,
        security_high_count: data.security_high_count,
        security_medium_count: data.security_medium_count,
        security_low_count: data.security_low_count,
        error_count: data.error_count,
        warning_count: data.warning_count,
        note_count: data.note_count,
      )
    end

    sig { params(changed_lines: T::Array[Integer]).returns(T::Array[[Integer, Integer]]) }
    def self.line_ranges(changed_lines)
      # compact runs of consecutive lines numbers
      changed_lines.sort.inject([]) do |out, line|
        # update the latest range end position if this is the next line in the range
        if out.count > 0 && line == out.last[1] + 1
          out.last[1] = line
          next out
        end
        out.push [line, line]
      end
    end

    sig { params(diffs: ::GitHub::Diff, include_deletions: T::Boolean).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def self.changed_lines(diffs, include_deletions: false)
      diffs.filter_map do |change|
        current_file = { file_path: change.path, changes: [] }

        begin
          changed_lines = change.each_line.filter { |line| line.type == :addition }.map(&:right)

          line_ranges(changed_lines).each do |start_line, end_line|
            current_file[:changes] << { added: true, start_line:, end_line: }
          end
        end

        if include_deletions
          changed_lines = change.each_line.filter { |line| line.type == :deletion }.map(&:left)

          line_ranges(changed_lines).each do |start_line, end_line|
            current_file[:changes] << { added: false, start_line:, end_line: }
          end
        end

        # If there are no relevant changes then we don't need to process this file
        next if current_file[:changes].empty?

        current_file
      end
    end
  end
end
