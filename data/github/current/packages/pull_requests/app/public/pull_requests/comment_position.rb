# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    # Public: Position a comment using blob-based positioning format.
    # This method handles comments that specify exact blob locations with commit OIDs,
    # file paths, and line numbers rather than diff-relative positions.
    #
    # repository       - The Repository object to position the comment within.
    # destination_base_commit_oid  - String base commit SHA for the positioning context. (desired end state)
    # destination_head_commit_oid  - String head commit SHA for the positioning context. (desired end state)
    # path             - String file path where the comment should be positioned.
    # line             - Integer line number within the file (optional for file-level comments).
    # side             - String, Symbol, or Side enum indicating which side of the diff.
    # start_line       - Integer starting line number for multi-line comments (optional).
    # start_side       - String, Symbol, or Side enum for start line side (optional).
    # source_base_commit_oid - String source base commit SHA. The original base commit that the comment targeted (optional).
    # source_head_commit_oid - String source head commit SHA. The original head commit that the comment targeted (optional).
    # diffs            - Array of pre-loaded GitHub::Diff objects for optimization (optional).
    #
    # Returns a Positioner::Values object containing the positioning result or error.
    #
    # Raises no exceptions - returns error objects for invalid parameters.
    sig do
      params(
        repository: Repository,
        destination_base_commit_oid: T.nilable(String),
        destination_head_commit_oid: T.nilable(String),
        path: T.nilable(String),
        line: T.nilable(Integer),
        side: T.nilable(T.any(String, Symbol, Positioner::Enums::Side)),
        start_line: T.nilable(Integer),
        start_side: T.nilable(T.any(String, Symbol, Positioner::Enums::Side)),
        source_base_commit_oid: T.nilable(String),
        source_head_commit_oid: T.nilable(String),
        diffs: T::Array[GitHub::Diff],
      ).returns(Positioner::Values)
    end
    def self.from_blob(repository:, destination_base_commit_oid:, destination_head_commit_oid:, path:, line:, side:, start_line:, start_side:, source_base_commit_oid: nil, source_head_commit_oid: nil, diffs: [])
      source_base_commit_oid ||= destination_base_commit_oid
      source_head_commit_oid ||= destination_head_commit_oid
      return CommentPosition::Errors::Parameter.new(source_base_commit_oid:) if source_base_commit_oid.nil? || invalid_oid?(source_base_commit_oid)
      return CommentPosition::Errors::Parameter.new(source_head_commit_oid:) if source_head_commit_oid.nil? || invalid_oid?(source_head_commit_oid)
      return CommentPosition::Errors::Parameter.new(destination_base_commit_oid:) if destination_base_commit_oid.nil? || invalid_oid?(destination_base_commit_oid)
      return CommentPosition::Errors::Parameter.new(destination_head_commit_oid:) if destination_head_commit_oid.nil? || invalid_oid?(destination_head_commit_oid)
      return CommentPosition::Errors::Parameter.new(path:) if path.nil? || path.blank?

      default = Positioner::Enums::Side::Right
      side = Positioner::Enums::Side.deserialize_with_default(side, default:)
      start_side = Positioner::Enums::Side.deserialize_with_default(start_side, default:)

      input = Positioner::Inputs::Blobs.new(
        path:, line:, side:, start_line:, start_side:,
        base_commit_oid: source_base_commit_oid, head_commit_oid: source_head_commit_oid,
      )

      # Call the Service with the required parameters
      ## we need to support passing in PR head and base sha to this call.
      service = Positioner::Service.new(
        repository:, base_commit_oid: destination_base_commit_oid, head_commit_oid: destination_head_commit_oid, diffs:,
        inputs: [input],
      )

      # Return the result from the Service invocation or default to an error.
      service.call[input] || CommentPosition::Errors::Unknown.new
    end

    # Public: Position a comment using diff-relative positioning format.
    # This method handles comments that specify locations using integer offsets
    # within diff hunks rather than absolute line numbers in files.
    #
    # repository       - The Repository object to position the comment within.
    # destination_base_commit_oid  - String base commit SHA for the diff range. (desired end state)
    # destination_head_commit_oid  - String head commit SHA for the diff range. (desired end state)
    # path             - String file path where the comment should be positioned.
    # position         - Integer offset from the top of the diff hunk.
    # source_base_commit_oid - String target base commit SHA. The original base commit that the comment targeted (optional).
    # source_head_commit_oid - String target head commit SHA. The original head commit that the comment targeted (optional).
    # diffs            - Array of pre-loaded GitHub::Diff objects for optimization (optional).
    #
    # Returns a Positioner::Values object containing the positioning result or error.
    #
    # Raises no exceptions - returns error objects for invalid parameters.
    sig do
      params(
        repository: Repository,
        destination_base_commit_oid: T.nilable(String),
        destination_head_commit_oid: T.nilable(String),
        path: T.nilable(String),
        position: T.nilable(Integer),
        source_base_commit_oid: T.nilable(String),
        source_head_commit_oid: T.nilable(String),
        diffs: T::Array[GitHub::Diff],
      ).returns(Positioner::Values)
    end
    def self.from_diff(repository:, destination_base_commit_oid:, destination_head_commit_oid:, path:, position:, source_base_commit_oid: nil, source_head_commit_oid: nil, diffs: [])
      source_base_commit_oid ||= destination_base_commit_oid
      source_head_commit_oid ||= destination_head_commit_oid
      return CommentPosition::Errors::Parameter.new(destination_base_commit_oid:) if destination_base_commit_oid.nil? || invalid_oid?(destination_base_commit_oid)
      return CommentPosition::Errors::Parameter.new(destination_head_commit_oid:) if destination_head_commit_oid.nil? || invalid_oid?(destination_head_commit_oid)
      return CommentPosition::Errors::Parameter.new(source_base_commit_oid:) if source_base_commit_oid.nil? || invalid_oid?(source_base_commit_oid)
      return CommentPosition::Errors::Parameter.new(source_head_commit_oid:) if source_head_commit_oid.nil? || invalid_oid?(source_head_commit_oid)
      return CommentPosition::Errors::Parameter.new(path:) if path.nil? || path.blank?
      return CommentPosition::Errors::Parameter.new(position:) if position.nil?

      input = Positioner::Inputs::DiffRelative.new(
        base_commit_oid: source_base_commit_oid, head_commit_oid: source_head_commit_oid, path:, position:
      )

      # Call the Service with the required parameters
      service = Positioner::Service.new(
        repository:, base_commit_oid: destination_base_commit_oid, head_commit_oid: destination_head_commit_oid, diffs:,
        inputs: [input],
      )

      # Return the result from the Service invocation or default to an error.
      service.call[input] || CommentPosition::Errors::Unknown.new
    end

    # Public: Position a comment using Positions format.
    # This method handles comments that specify locations using the positioning API format,
    # parsing the input and delegating to the appropriate positioning method.
    #
    # repository       - The Repository object to position the comment within.
    # base_commit_oid  - String base commit SHA for the positioning context.
    # head_commit_oid  - String head commit SHA for the positioning context.
    # positioning      - Hash containing the positioning data to be parsed.
    # diffs            - Array of pre-loaded GitHub::Diff objects for optimization (optional).
    #
    # Returns a Positioner::Values object containing the positioning result or error.
    #
    # Raises no exceptions - returns error objects for invalid parameters.
    sig do
      params(
        repository: Repository,
        base_commit_oid: T.nilable(String),
        head_commit_oid: T.nilable(String),
        positioning: T.untyped,
        diffs: T::Array[GitHub::Diff]
      ).returns(Positioner::Values)
    end
    def self.from_positioning(repository:, base_commit_oid:, head_commit_oid:, positioning:, diffs: [])
      return CommentPosition::Errors::Parameter.new(base_commit_oid:) if base_commit_oid.nil? || invalid_oid?(base_commit_oid)
      return CommentPosition::Errors::Parameter.new(head_commit_oid:) if head_commit_oid.nil? || invalid_oid?(head_commit_oid)

      positioning = Positions::Parser.parse(positioning, base_commit_oid:, head_commit_oid:)
      return positioning if positioning.is_a?(CommentPosition::Errors)

      input = Positioner::Inputs::Positioning.new(positioning:)

      result = Positioner::Service.new(
        inputs: [input],
        position_only: false,
        repository:, base_commit_oid:, head_commit_oid:, diffs:
      ).call

      # Return the result from the Service invocation or default to an error.
      result[input] || CommentPosition::Errors::Unknown.new
    end

    # Public: Determine the positioning for threads belonging to a single Pull Request.
    # This method processes existing thread data, extracts positioning information,
    # and performs repositioning calculations when needed for comment display.
    #
    # pull_request     - The PullRequest object containing the threads to position.
    # threads          - Array or ActiveRecord relation of PullRequestReviewThread objects.
    # base_commit_oid  - String base commit SHA (defaults to pull_request.base_sha).
    # head_commit_oid  - String head commit SHA (defaults to pull_request.head_sha).
    # position_only    - Boolean flag to control positioning calculation behavior.
    #
    # Returns a Hash mapping PullRequestReviewThread objects to their Positioner::Values.
    # Returns an empty Hash if the pull request has no repository.
    #
    # Raises no exceptions - filters out threads that cannot be mapped back successfully.
    sig do
      params(
        pull_request: PullRequest,
        threads: T.any(T::Array[PullRequestReviewThread], ActiveRecord::AssociationRelation),
        destination_base_commit_oid: T.nilable(String),
        destination_head_commit_oid: T.nilable(String),
        position_only: T::Boolean,
      ).returns(T::Hash[PullRequestReviewThread, Positioner::Values])
    end
    def self.from_pull_request_threads(pull_request:, threads:, destination_base_commit_oid: pull_request.base_sha, destination_head_commit_oid: pull_request.head_sha, position_only: false)
      return {} unless repository = pull_request.head_repository || pull_request.repository

      inputs = Positioner::Loaders::ThreadColumns.new(
        pull_request:,
        threads:,
        base_commit_oid: pull_request.base_sha,
        head_commit_oid: pull_request.head_sha,
      ).to_inputs

      result = Positioner::Service.new(
        repository:, inputs:, position_only:,
        base_commit_oid: destination_base_commit_oid,
        head_commit_oid: destination_head_commit_oid,
        diffs: pull_request.loaded_diffs
      ).call

      # Convert the keys back to threads.
      result.transform_keys do |input|
        threads.find { _1.id == input.identifier }
      end.compact
    end

    # Public: Determine the positioning for a single thread belonging to a single Pull Request.
    # This method processes existing thread data, extracts positioning information,
    # and performs repositioning calculations when needed for comment display.
    #
    # pull_request     - The PullRequest object containing the threads to position.
    # thread           - PullRequestReviewThread object.
    # base_commit_oid  - String base commit SHA (defaults to pull_request.base_sha).
    # head_commit_oid  - String head commit SHA (defaults to pull_request.head_sha).
    # position_only    - Boolean flag to control positioning calculation behavior.
    #
    # Returns a Positioner::Values object (either Positioner::Result or CommentPosition::Errors).
    sig do
      params(
        pull_request: PullRequest,
        thread: PullRequestReviewThread,
        destination_base_commit_oid: T.nilable(String),
        destination_head_commit_oid: T.nilable(String),
        position_only: T::Boolean,
      ).returns(Positioner::Values)
    end
    def self.from_pull_request_thread(pull_request:, thread:, destination_base_commit_oid: pull_request.base_sha, destination_head_commit_oid: pull_request.head_sha, position_only: false)
      T.must(from_pull_request_threads(pull_request:, threads: [thread], destination_base_commit_oid:, destination_head_commit_oid:, position_only:)[thread])
    end

    # Public: Determine the positioning for multiple threads belonging to a single Pull Request.
    # This method processes existing thread data, extracts positioning information,
    # and converts the results to Positions objects for comment display.
    #
    # pull_request     - The PullRequest object containing the threads to position.
    # threads          - Array or ActiveRecord relation of PullRequestReviewThread objects.
    # base_commit_oid  - String base commit SHA (defaults to pull_request.base_sha).
    # head_commit_oid  - String head commit SHA (defaults to pull_request.head_sha).
    # position_only    - Boolean flag to control positioning calculation behavior.
    #
    # Returns a Hash mapping PullRequestReviewThread objects to their Positions.
    sig do
      params(
        pull_request: PullRequest,
        threads: T.any(T::Array[PullRequestReviewThread], ActiveRecord::AssociationRelation),
        destination_base_commit_oid: T.nilable(String),
        destination_head_commit_oid: T.nilable(String),
        position_only: T::Boolean,
      ).returns(T::Hash[PullRequestReviewThread, Positions])
    end
    def self.positions_from_pull_request_threads(pull_request:, threads:, destination_base_commit_oid: pull_request.base_sha, destination_head_commit_oid: pull_request.head_sha, position_only: false)
      from_pull_request_threads(pull_request:, threads:, destination_base_commit_oid:, destination_head_commit_oid:, position_only:).transform_values do |result|
        case result
        when Positioner::Result
          result.positioning
        when PullRequests::CommentPosition::Errors
          Positions::Indeterminate.new(
            reason: result.to_error_tuple.map(&:to_s).join("_").to_sym,
            base_commit_oid: destination_base_commit_oid,
            head_commit_oid: destination_head_commit_oid,
          )
        else T.absurd(result)
        end
      end
    end

    # Public: Determine the positioning for a single thread belonging to a single Pull Request.
    # This method processes existing thread data, extracts positioning information,
    # and converts the result to a Positions object for comment display.
    #
    # pull_request     - The PullRequest object containing the thread to position.
    # thread           - PullRequestReviewThread object.
    # base_commit_oid  - String base commit SHA (defaults to pull_request.base_sha).
    # head_commit_oid  - String head commit SHA (defaults to pull_request.head_sha).
    # position_only    - Boolean flag to control positioning calculation behavior.
    #
    # Returns a Positions object.
    sig do
      params(
        pull_request: PullRequest,
        thread: PullRequestReviewThread,
        destination_base_commit_oid: T.nilable(String),
        destination_head_commit_oid: T.nilable(String),
        position_only: T::Boolean,
      ).returns(Positions)
    end
    def self.position_from_pull_request_thread(pull_request:, thread:, destination_base_commit_oid: pull_request.base_sha, destination_head_commit_oid: pull_request.head_sha, position_only: false)
      case result = positions_from_pull_request_threads(pull_request:, threads: [thread], destination_base_commit_oid:, destination_head_commit_oid:, position_only:)[thread]
      when Positions
        result
      when nil
        Positions::Indeterminate.new(reason: :unknown, base_commit_oid: destination_base_commit_oid, head_commit_oid: destination_head_commit_oid)
      else T.absurd(result)
      end
    end

    # Public: Request all threads associated with a Pull Request and return positioning results by thread ID.
    # This method efficiently loads all review threads for a pull request and processes their
    # positioning data, returning results keyed by thread identifier for easy lookup.
    #
    # pull_request     - The PullRequest object to load threads from.
    # base_commit_oid  - String base commit SHA (defaults to pull_request.base_sha).
    # head_commit_oid  - String head commit SHA (defaults to pull_request.head_sha).
    # position_only    - Boolean flag to control positioning calculation behavior.
    #
    # Returns a Hash mapping thread identifiers (String or Integer) to their Positioner::Values.
    # Returns an empty Hash if the pull request has no repository.
    #
    # Raises no exceptions - handles missing repositories gracefully.
    sig do
      params(
        pull_request: PullRequest,
        base_commit_oid: T.nilable(String),
        head_commit_oid: T.nilable(String),
        position_only: T::Boolean,
      ).returns(T::Hash[T.any(String, Integer), Positioner::Values])
    end
    def self.from_pull_request(pull_request:, base_commit_oid: pull_request.base_sha, head_commit_oid: pull_request.head_sha, position_only: false)
      return {} unless repository = pull_request.head_repository || pull_request.repository

      inputs = Positioner::Loaders::ThreadColumns.new(
        pull_request:,
        base_commit_oid: pull_request.base_sha,
        head_commit_oid: pull_request.head_sha,
      ).to_inputs

      result = Positioner::Service.new(
        repository:, inputs:, base_commit_oid:, head_commit_oid:, position_only:,
        diffs: pull_request.loaded_diffs
      ).call

      # Convert the keys back to threads.
      result.transform_keys(&:identifier)
    end

    # Public: Preload positioning data for multiple threads and store results on the thread objects.
    # This method efficiently calculates positioning for threads that don't already have it cached,
    # and stores the results in the `preloaded_positioning` attribute for later use.
    #
    # pull_request     - The PullRequest object containing the threads to position.
    # threads          - Array of PullRequestReviewThread objects to preload positioning for.
    #
    # Returns nothing - modifies the threads in place by setting their `preloaded_positioning` attribute.
    # Only processes threads that don't already have preloaded positioning data.
    #
    # Raises no exceptions - silently skips threads that cannot be positioned or have errors.
    sig do
      params(
        pull_request: PullRequest,
        threads: T::Array[PullRequestReviewThread]
      ).void
    end
    def self.preload_positionings_for_threads(pull_request:, threads:)
      from_pull_request_threads(
        pull_request:,
        threads: threads.filter { _1.preloaded_positioning.nil? }
      ).each do |thread, result|
        next if result.nil? || result.is_a?(PullRequests::CommentPosition::Errors)

        thread.preloaded_positioning = result.positioning
      end
    end

    # Private: Determine if the OID is not a valid SHA.
    sig { params(oid: T.untyped).returns(T::Boolean) }
    def self.invalid_oid?(oid) = !GitRPC::Util.valid_full_oid?(oid)

    private_class_method :invalid_oid?
  end
end
