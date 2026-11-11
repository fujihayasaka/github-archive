# typed: strict
# frozen_string_literal: true

module PullRequests
  module Shared
    # A structured logger for collecting and flushing contextual data to Splunk.
    #
    # This logger accumulates key-value pairs in a payload that gets sent to Splunk via
    # GitHub's logging infrastructure. Since Splunk doesn't support nested JSON structures
    # for field extraction, all data must be flattened using dotted key paths (e.g.,
    # "gh.user.id" instead of nested objects). This allows Splunk to properly index and
    # search each field.
    #
    # The logger supports hierarchical contexts through child loggers, allowing for multiple
    # related log entries that share a common base payload.
    #
    # == Key Naming Convention
    #
    # All log keys MUST follow the following key pattern:
    #
    #   gh.<domain>.<feature>.[<operation>[.<attribute>] | <outcome>] = <value>
    #
    # Segments:
    #   - gh              : Static top-level namespace for all GitHub Splunk logs.
    #   - <domain>        : The bounded domain or top-level package (e.g.,
    #                        "pull_requests", "issues", "billing", "orgs").
    #   - <feature>       : The specific feature within the domain (e.g., "synchronize",
    #                        "auto_merge", "merge", "auto_merge_request").
    #   - <operation>     : (Optional) A verb or action being performed (e.g., "enqueue",
    #                        "creation", "evaluation", "create_commits").
    #   - <attribute>     : (Optional) A specific property of the operation (e.g., "id",
    #                        "merge_method", "duration_ms", "actor_id").
    #   - <outcome>       : The terminal result of an operation. Use this at the feature or
    #                        operation level to record a result (e.g., "outcome").
    #   - <value>         : The logged value. Outcomes should use snake_case descriptive
    #                        strings (e.g., "success", "error_validation_failed",
    #                        "skipped_already_enqueued").
    #
    # Guidelines:
    #   - Use the `default_prefix` constructor parameter to set the `gh.<domain>.<feature>`
    #     prefix (e.g., `gh.pull_requests.synchronize`) once, so individual `append`
    #     calls only supply the leaf keys.
    #   - Use the `feature` constructor parameter to automatically append a
    #     `gh.pull_requests.feature` key identifying the feature area in every log entry.
    #   - Reserve the key name `outcome` for the terminal result of an operation. Outcome
    #     values should be descriptive snake_case strings.
    #   - Use `code.namespace` and `code.function` (with prefix: "code") to record the
    #     originating class and method for traceability.
    #   - Use the built-in context helpers (`append_pull_request_context`,
    #     `append_repository_context`, `append_exception`) for standard entity data so
    #     the key structure stays consistent across all callers.
    #
    # Example — synchronize operation (based on existing usage):
    #
    #   logger = Logger.new(
    #     default_prefix: "gh.pull_requests.synchronize",
    #     feature: "synchronize"
    #   )
    #   logger.append_pull_request_context(pull_request)
    #   logger.append({ namespace: "SynchronizationDependency", function: "synchronize!" }, prefix: "code")
    #   logger.append({ forced: false, ref: "main", changing_base: false })
    #   logger.append({ outcome: "success" })
    #   logger.flush
    #
    #   # Produces a Splunk event with flattened fields like:
    #   #   gh.pull_requests.feature                 = "synchronize"
    #   #   gh.pull_requests.synchronize.forced       = false
    #   #   gh.pull_requests.synchronize.ref          = "main"
    #   #   gh.pull_requests.synchronize.changing_base = false
    #   #   gh.pull_requests.synchronize.outcome      = "success"
    #   #   gh.pull_request.id                        = 456
    #   #   gh.pull_request.head_sha                  = "abc123"
    #   #   gh.repo.id                                = 789
    #   #   code.namespace                            = "SynchronizationDependency"
    #   #   code.function                             = "synchronize!"
    #
    # Example usage:
    #   logger = Logger.new
    #   logger.append({ user_id: 123 }, prefix: "gh.user")  # Creates "gh.user.user_id"
    #   logger.append_pull_request_context(pull_request)
    #   logger.flush  # Sends flattened data to Splunk via GitHub.logger
    #
    # When using child contexts:
    #   logger.for(:merge_attempt) do |child|
    #     child.append({ attempt: 1, status: "success" })
    #   end
    #   logger.flush  # Produces multiple Splunk events, one per child, each with parent payload
    class Logger
      Payload = T.type_alias { T::Hash[T.untyped, T.untyped] }

      DEFAULT_PREFIX = "gh.pull_request"

      sig { returns(Payload) }
      attr_reader :payload

      delegate :first, to: :to_a

      # Initializes a new Logger instance with an optional base payload.
      #
      # The payload will be converted to use indifferent access to prevent duplicate keys
      # from String/Symbol identity differences.
      #
      # default_prefix - Optional default prefix applied to all `append` calls that don't specify
      #   their own prefix. Defaults to nil for backwards compatibility.
      # feature - Optional feature name string. If provided, it is appended to the payload
      #   using the default prefix.
      sig { params(payload: Payload, default_prefix: T.nilable(String), feature: T.nilable(String)).void }
      def initialize(payload = {}, default_prefix: nil, feature: nil)
        # Utilize `with_indifferent_access` to ensure that duplicate keys can't occur between String/Symbol identity.
        @payload = T.let(payload.with_indifferent_access, HashWithIndifferentAccess)
        @default_prefix = T.let(default_prefix, T.nilable(String))

        # Allow for multiple contexts.
        @children = T.let({}, T::Hash[T.untyped, Logger])

        if feature
          append({ feature: }, prefix: DEFAULT_PREFIX)
        end
      end

      # Appends an arbitrary Hash to the logging payload, with optional key prefixing.
      #
      # This is the primary method for adding structured data that will be sent to Splunk.
      # Since Splunk cannot extract fields from nested JSON, all keys are flattened using
      # dot notation. The prefix parameter creates namespaced fields that Splunk can index
      # and search (e.g., "gh.user.id", "gh.user.name").
      #
      # Nil values are converted to the string "nil" because Splunk filters out null values
      # by default, which would make them invisible in searches and dashboards.
      #
      # Example:
      #   append({ id: 123, name: "octocat" }, prefix: "gh.user")
      #   # Results in flattened Splunk fields: "gh.user.id"=123, "gh.user.name"="octocat"
      sig { params(hash: Payload, prefix: T.nilable(String)).void }
      def append(hash, prefix: @default_prefix)
        hash.transform_keys! { "#{prefix}.#{_1}" } if prefix
        hash.transform_values! { _1.nil? ? "nil" : _1 } # Splunk filters out `nil` values by default.
        @payload.merge!(hash)
      end

      # Appends PullRequest domain-specific context to the payload.
      #
      # Extracts key attributes from a PullRequest and adds them with the "gh.pull_request"
      # prefix for Splunk indexing. The data is flattened so Splunk can search fields like
      # "gh.pull_request.id" and "gh.pull_request.head_sha". Also automatically appends the
      # associated Issue context if present, and includes basic repository information.
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
        }, prefix: DEFAULT_PREFIX)

        if issue = pull.issue # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          append_issue_context(issue)
        end

        append({ id: pull.repository_id }, prefix: "gh.repo")
      end

      # Appends Repository domain-specific context to the payload.
      #
      # Extracts relevant repository attributes and adds them with the "gh.repo" prefix
      # so they're searchable in Splunk as flattened fields.
      sig { params(repository: Repository).void }
      def append_repository_context(repository)
        append({
          id: repository.id,
          advisory_workspace: repository.advisory_workspace?.inspect,
        }, prefix: "gh.repo")
      end

      # Appends exception details to the payload for error tracking in Splunk.
      #
      # Captures the exception class name, message, and the first 5 lines of the backtrace
      # to provide debugging context without overwhelming the logs. All fields are flattened
      # with the given prefix for Splunk indexing.
      sig { params(exception: Exception, prefix: T.nilable(String)).void }
      def append_exception(exception, prefix: @default_prefix)
        append({
          exception: exception.class.name,
          exception_message: exception.message,
          exception_backtrace: exception.backtrace&.slice(0, 5)
        }, prefix:)
      end

      # Appends Issue context to the payload.
      #
      # Since pull requests are associated with issues, this extracts relevant issue
      # attributes and adds them with the "gh.pull_request" prefix for Splunk.
      sig { params(issue: Issue).void }
      def append_issue_context(issue)
        append({
          number: issue.number,
          issue_state: issue.state,
        }, prefix: DEFAULT_PREFIX)
      end

      # Appends outcome details to the payload for event tracking in Splunk.
      #
      # Dedicated method to log the outcome of an operation (e.g., "success", "failure") in a consistent way.
      sig { params(outcome: String, prefix: T.nilable(String)).void }
      def append_outcome(outcome, prefix: @default_prefix)
        append({
          outcome: outcome,
        }, prefix:)
      end

      # Creates or retrieves a child logger context for hierarchical logging.
      #
      # Child loggers allow you to create multiple related Splunk events that share a common
      # base payload from the parent. When the parent logger is flushed, each child produces
      # a separate Splunk event with the parent's flattened fields merged in.
      #
      # This is useful for logging multiple attempts, retries, or parallel operations where
      # each operation should create its own Splunk event but share common context fields.
      #
      # Returns the child logger instance, which can be configured with the optional block.
      #
      # Example:
      #   logger.for(:attempt_1) { |child| child.append({ status: "failed" }) }
      #   logger.for(:attempt_2) { |child| child.append({ status: "success" }) }
      #   logger.flush  # Produces 2 Splunk events, each with parent context + child data
      sig { params(key: T.untyped, block: T.nilable(T.proc.params(logger: Logger).void)).returns(Logger) }
      def for(key, &block)
        logger = @children[key] ||= Logger.new
        yield(logger) if block_given?
        logger
      end

      # Flushes all accumulated log data to Splunk via GitHub's logging infrastructure.
      #
      # Sends each log entry (parent or child) to GitHub.logger.info, which forwards to Splunk.
      # If child loggers exist, each child produces a separate Splunk event with the parent
      # payload merged in. If no children exist, a single Splunk event is created from the
      # parent payload. All data is sent as flattened key-value pairs for Splunk indexing.
      #
      # This method should be called at the end of an operation to ensure logs are persisted.
      sig { void }
      def flush
        to_a.each { GitHub.logger.info(_1) }
      end

      # Converts the logger's accumulated data into an array of log entry hashes.
      #
      # If child loggers exist, returns one hash per child with the parent payload merged in.
      # If no children exist, returns a single-element array containing just the parent payload.
      # All hashes contain flattened key-value pairs ready to be sent to Splunk.
      #
      # This method is primarily used internally by `flush`, but can be useful for testing
      # or inspecting what will be logged without actually sending data to Splunk.
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
