# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    # A too-generally-named object describing the request to create merge/rebase commits and update the internal refs.
    #
    # This will end up with more data as we flush out behavior, but from the perspective of "what is the subset of data
    # that is required to run this"? This enables a way for us to log `before` and `after` state that the processor
    # uses to make decisions.
    class Request < T::Struct
      extend T::Sig

      module Commits
        extend T::Helpers
        include Kernel
        interface!
        sealed!

        class Pending
          include Commits
        end

        class Skipped
          include Commits
        end
      end

      class Mergeability < T::Enum
        enums do
          Mergeable = new("mergeable")
          Conflict = new("conflict")
          Indeterminate = new("indeterminate")
        end
      end

      class Invalid < T::Struct
        extend T::Sig

        class Reason < T::Enum
          enums do
            MissingPullRequest = new("missing_pull_request")
            DuplicateRequest = new("duplicate_request")
            ClosedOrMerged = new("closed_or_merged")
            MissingRepository = new("missing_repository")
            MissingBaseRepository = new("missing_base_repository")
            MissingBaseRefSha = new("missing_base_ref_sha")
            MissingHeadRepository = new("missing_head_repository")
            MissingHeadRefSha = new("missing_head_ref_sha")
            MergeableAndUpToDate = new("mergeable_and_up_to_date")
            IndeterminateAndUpToDate = new("indeterminate_and_up_to_date")
          end
        end

        const :reason, Reason
        const :pull_request_id, Integer
        const :pull_request_number, T.nilable(Integer)

        prop :record_created_at, T.nilable(Time)
        prop :processed_at, Time, factory: -> { Time.now }

        sig { returns(T::Hash[T.untyped, T.untyped]) }
        def to_logging_h
          {
            "gh.pull.id": pull_request_id,
            "gh.pull.number": pull_request_number,
            "gh.merge_commits.request.invalid_reason": reason.serialize,
            "gh.merge_commits.request.processing_time": processing_time,
          }
        end

        sig { returns(T::Hash[String, String]) }
        def to_stats_h
          {
            "pull_requests.merge_commits.request.merge_commit" => "result:#{reason.serialize}",
            "pull_requests.merge_commits.request.rebase_commit" => "result:#{reason.serialize}",
            "pull_requests.merge_commits.request.update_refs" => "result:#{reason.serialize}"
          }
        end

        sig { returns(T::Hash[String, Integer]) }
        def to_timing_stats_h
          { "pull_requests.merge_commits.request.processing_time" => processing_time }
        end

        sig { returns(Float) }
        def processing_time
          (processed_at - T.must(record_created_at)).to_f * 1000
        end

        sig { returns(Symbol) }
        def logging_type
          :invalid
        end
      end

      Commit = T.type_alias do
        T.any(
          Commits,
          PullRequests::GitSystems::Commit::Created,
          PullRequests::GitSystems::Commit::Conflict,
          PullRequests::GitSystems::Commit::Failed,
          PullRequests::GitSystems::Errors,
          ICommand::Result::Error,
          ICommand::Result::Timeout,
        )
      end

      const :pull_request_id, Integer
      const :pull_request_number, Integer
      const :pull_request_base_sha, String
      const :pull_request_head_sha, String
      const :pull_request_base_repository_id, T.nilable(Integer)
      const :pull_request_head_repository_id, T.nilable(Integer)

      const :previous_mergeability, T.nilable(Mergeability)
      prop  :current_mergeability, T.nilable(Mergeability)

      const :base_ref_name, String
      const :head_ref_name, String
      const :base_ref_sha, String
      const :head_ref_sha, String

      const :merge_ref_name, String
      const :rebase_ref_name, String

      prop :record_created_at, T.nilable(Time)
      prop :processed_at, T.nilable(Time)

      prop :merge_commit, Commit, default: Commits::Pending.new
      prop :rebase_commit, Commit, default: Commits::Pending.new
      prop :update_ref_result, T.nilable(ICommand::Result)

      sig { returns(T::Boolean) }
      def valid_merge_commit?
        case commit = merge_commit
        when PullRequests::GitSystems::Commit::Created then true
        else false
        end
      end

      # Generates a splunk queryable log to observe the merge commit process.
      sig { returns(T::Hash[T.untyped, T.untyped]) }
      def to_logging_h
        {
          "gh.pull.id": pull_request_id,
          "gh.pull.number": pull_request_number,
          "gh.pull.base_sha": pull_request_base_sha,
          "gh.pull.head_sha": pull_request_head_sha,
          "gh.pull.base_ref": base_ref_name,
          "gh.pull.head_ref": head_ref_name,
          "gh.pull.previous_mergeability": previous_mergeability&.serialize || "nil",
          "gh.pull.current_mergeability": current_mergeability&.serialize || "nil",
          "gh.pull.head_repo.id": pull_request_head_repository_id,
          "gh.pull.base_repo.id": pull_request_base_repository_id,
          "gh.merge_commits.request.head_ref_sha": head_ref_sha,
          "gh.merge_commits.request.base_ref_sha": base_ref_sha,
          "gh.merge_commits.request.merge_ref": merge_ref_name,
          "gh.merge_commits.request.rebase_ref": rebase_ref_name,
          "gh.merge_commits.request.processing_time": processing_time,
        }.merge!(
          **commit_to_logging_h(:merge_commit, merge_commit),
          **commit_to_logging_h(:rebase_commit, rebase_commit),
          **result_to_logging_h(:update_refs, update_ref_result),
        )
      end

      sig { returns(T::Hash[String, String]) }
      def to_stats_h
        result_to_stats_h(:merge_commit, merge_commit).merge!(
          **result_to_stats_h(:rebase_commit, rebase_commit),
          **result_to_stats_h(:update_refs, update_ref_result)
        )
      end

      sig { returns(T::Hash[String, Integer]) }
      def to_timing_stats_h
        { "pull_requests.merge_commits.request.processing_time" => processing_time }
      end

      sig { returns(Symbol) }
      def logging_type
        :valid
      end

      private

      # Serialize the commit
      sig { params(key: Symbol, commit: Commit).returns(T::Hash[Symbol, T.untyped]) }
      def commit_to_logging_h(key, commit)
        result = commit.class.to_s.demodulize.downcase

        hash = case commit
        when PullRequests::GitSystems::Commit::Created
          { result: }.merge(commit.serialize)
        when PullRequests::GitSystems::Commit::Failed
          { result:, code: commit.code }
        when PullRequests::GitSystems::Errors::Outage
          { result:, reason: commit.reason }
        when PullRequests::GitSystems::Errors::Timeout, ICommand::Result::Error, GitSystems::Errors::Fatal, ICommand::Result::Timeout
          { result:, error: commit.exception&.class || "nil" }
        when PullRequests::GitSystems::Commit::Conflict
          { result:, conflicts: commit.file_names.size }
        when Request::Commits
          { result: }
        else T.absurd(commit)
        end

        hash.transform_keys! { |k| :"gh.merge_commits.request.#{key}.#{k}" }
      end

      sig { params(key: Symbol, result: T.nilable(ICommand::Result)).returns(T::Hash[Symbol, T.untyped]) }
      def result_to_logging_h(key, result)
        hash = case result
        when ICommand::Result::Error, nil
          { result: "failed", error: result&.message || "nil" }
        when ICommand::Result::Success
          { result: "success" }
        else
          { result: "not_run" }
        end

        hash.transform_keys! { |k| :"gh.merge_commits.request.#{key}.#{k}" }
      end

      sig { params(key: Symbol, result: T.nilable(T.any(Commit, ICommand::Result, Request::Commits))).returns(T::Hash[String, String]) }
      def result_to_stats_h(key, result)
        string = case result
        when PullRequests::GitSystems::Commit::Conflict
          "conflict"
        when PullRequests::GitSystems::Errors::Outage
          "outage"
        when ICommand::Result::Timeout
          "timeout"
        when PullRequests::GitSystems::Commit::Failed,
          PullRequests::GitSystems::Errors::Timeout,
          GitSystems::Errors::Fatal,
          ICommand::Result::Error
          "failed"
        when PullRequests::GitSystems::Commit::Created,
          ICommand::Result::Success
          "success"
        when Request::Commits::Skipped
          "skipped"
        when nil
          "not_run"
        when PullRequests::MergeCommit::Request::Commits::Pending
          "pending"
        else
          T.absurd(result)
        end

        { "pull_requests.merge_commits.request.#{key}" => "result:#{string}" }
      end

      sig { returns(Float) }
      def processing_time
        time = processed_at || Time.now
        (time - T.must(record_created_at)).to_f * 1000
      end
    end
  end
end
