# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module Logging
      class Logger
        Payload = T.type_alias { T::Hash[T.untyped, T.untyped] }

        sig { returns(Payload) }
        attr_reader :payload

        delegate :first, to: :to_a

        sig { params(payload: Payload).void }
        def initialize(payload = {})
          # Utilize `with_indifferent_access` to ensure that duplicate keys can't occur between String/Symbol identity.
          @payload = T.let(payload.with_indifferent_access, HashWithIndifferentAccess)

          # Allow for multiple contexts.
          @children = T.let({}, T::Hash[T.untyped, Logger])
        end

        # Append an arbitrary Hash to the logging data, optionally prefix the keys with the given string.
        sig { params(hash: Payload, prefix: T.nilable(String)).void }
        def append(hash, prefix: nil)
          hash.transform_keys! { "#{prefix}.#{_1}" } if prefix
          hash.transform_values! { _1.nil? ? "nil" : _1 } # Splunk filters out `nil` values by default.
          @payload.merge!(hash)
        end

        # Append PullRequest domain specific data.
        sig { params(pull: PullRequest).void }
        def append_pull_request_context(pull)
          append({
            id: pull.id,
            base_sha: pull.base_sha,
            head_sha: pull.head_sha,
            base_repository_id: pull.base_repository_id,
            head_repository_id: pull.head_repository_id,
            merged_at: pull.merged_at || "nil",
            is_draft: pull.draft,
          }, prefix: "gh.pull_request")

          if issue = pull.issue
            append_issue_context(issue)
          end

          append({ id: pull.repository_id }, prefix: "gh.repo")
        end

        # Append Repository domain specific data.
        sig { params(repository: Repository).void }
        def append_repository_context(repository)
          append({
            id: repository.id,
            advisory_workspace: repository.advisory_workspace?.inspect,
          }, prefix: "gh.repo")
        end

        sig { params(exception: Exception, prefix: String).void }
        def append_exception(exception, prefix:)
          append({
            exception: exception.class.name,
            exception_message: exception.message,
            exception_backtrace: exception.backtrace&.slice(0, 5)
          }, prefix:)
        end

        sig { params(issue: Issue).void }
        def append_issue_context(issue)
          append({
            number: issue.number,
            issue_state: issue.state,
          }, prefix: "gh.pull_request")
        end

        # Serialize and append Commit data with a specific prefix.
        sig do
          params(
            prefix: String,
            commits: T.nilable(Commits::CommitTypes),
          ).void
        end
        def append_commits(prefix:, **commits)
          commits.each do |name, commit|
            append(Logging::Commits.to_hash(commit), prefix: "#{prefix}.#{name}") if commit
          end
        end

        # Context specific logging, allowing sharing data with a parent logging context.
        sig { params(key: T.untyped, block: T.nilable(T.proc.params(logger: Logger).void)).returns(Logger) }
        def for(key, &block)
          logger = @children[key] ||= Logger.new
          yield(logger) if block_given?
          logger
        end

        # Flush the log buffer to the logger.
        sig { void }
        def flush
          to_a.each { GitHub.logger.info(_1) }
        end

        # Return a collection of produced log messages.
        sig { returns(T::Array[T::Hash[String, T.untyped]]) }
        def to_a
          if @children.any?
            @children.values.map! { @payload.merge(_1.payload) }
          else
            [@payload]
          end
        end
      end
    end
  end
end
