# typed: strict
# frozen_string_literal: true

module PullRequests
  module Merge
    extend T::Sig

    class Success < T::Struct
      # The head_sha of the target branch after merging.
      const :sha, String
    end

    class Failure < T::Struct
      # Status code produced by GitRPC.
      const :code, T.nilable(Symbol) # TODO: Convert to enum.
      const :error_message, String
    end

    # Perform the Merge operation on the given PullRequest.
    sig do
      params(
        pull_request: PullRequest,
        user: User,
        # The method to perform the merge with: merge, rebase, or squash.
        method: Symbol, # TODO: Convert to enum of merge/rebase/squash.
        expected_head_sha: T.nilable(String),
        commit_title: T.nilable(String),
        commit_body: T.nilable(String),
        commit_author_email: T.nilable(String),
        # Logging metadata to track where the merge was invoked from.
        source: T.nilable(Symbol), # TODO: Convert to enum.
        reflog_data: T.untyped,
      ).returns(T.any(Success, Failure))
    end
    def self.call(
      pull_request:,
      user:,
      method:,
      expected_head_sha: nil,
      commit_title: nil,
      commit_body: nil,
      commit_author_email: nil,
      source: nil,
      reflog_data: {}
    )
      orchestration = PullRequests::Orchestrations::Merge.create(
        repository: pull_request.repository,
        pull_request:,
        actor: user,
        method:,
        commit_title:,
        commit_body:,
        commit_author_email:,
        expected_head_sha:,
        source:,
        reflog_data:,
      )

      begin
        orchestration.execute!
      rescue Orchestration::ValidationError
        Failure.new(
          error_message: orchestration.errors.full_messages.join(", "),
          code: orchestration.send(:git_error_code),
        )
      else
        if orchestration.skipped? || orchestration.failed?
          Failure.new(
            error_message: orchestration.error_message.to_s,
            code: orchestration.send(:git_error_code),
          )
        else
          # TODO: We should support a public: true flag in the `data` options.
          Success.new(sha: orchestration.send(:merging_commit_sha))
        end
      end
    end
  end
end
