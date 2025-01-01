# typed: strict
# frozen_string_literal: true

module PullRequests
  module GitSystems
    class BatchReadDiffPositions
      include GitHub::Memoizer

      class State < T::Enum
        enums do
          Success = new(:success)
          RemovedPath = new(:removed_path)
          InvalidPath = new(:invalid_path)
          ContentTooLarge = new(:content_too_large)
          Unknown = new(:unknown)
          Pending = new(:pending)
          ServiceUnavailable = new(:service_unavailable)
        end
      end

      Collection = T.type_alias do
        T::Hash[Repository, T::Hash[[String, String], T::Hash[String, {
          target_path: T.nilable(String),
          lines: T::Hash[Integer, T.nilable(Integer)],
          state: T.nilable(SpokesAPI::Types::DiffPositionState),
        }]]]
      end

      sig { params(max_attempts: Integer).void }
      def initialize(max_attempts: 3)
        @max_attempts = max_attempts
        @collection = T.let({}, Collection)
      end

      # Add a commit to the batch to be loaded.
      sig do
        params(
          repository: Repository,
          target_commit_oid: String,
          source_commit_oid: String,
          path: String,
          line: T.nilable(Integer),
        ).void
      end
      def request(repository:, target_commit_oid:, source_commit_oid:, path:, line: nil)
        commits = [source_commit_oid, target_commit_oid]

        hash = ((@collection[repository] ||= {})[commits] ||= {})[encode(path)] ||= {
          target_path: nil,
          state: nil,
          lines: {},
        }

        hash[:lines][line] = nil if line
      end

      # Execute the batch and read from the results.
      sig do
        params(
          repository: Repository,
          target_commit_oid: String,
          source_commit_oid: String,
          path: String,
          line: T.nilable(Integer),
        ).returns([T.nilable(SpokesAPI::Types::DiffPositionState), T.nilable(String), T.nilable(Integer)])
      end
      def read(repository:, target_commit_oid:, source_commit_oid:, path:, line: nil)
        response = @collection.dig(repository, [source_commit_oid, target_commit_oid], encode(path)) || {}

        [
          response.dig(:state),
          decode(response.dig(:target_path)),
          response.dig(:lines, line)
        ]
      end

      sig { void }
      memoize def execute
        @collection.each do |repository, commits|
          commits.each do |(source_oid, target_oid), paths|
            targets = paths.filter { _2[:state].nil? }.to_h { [_1, _2[:lines].keys] }

            if targets.any?
              case result = Repositories.domain.diffs.diff_positions(repository:, source_oid:, target_oid:, targets:)
              when GH::Result::Ok
                responses = result.value
              when GH::Result::Error::ServiceRateLimited, GH::Result::Error::ServiceUnreachable
                # TODO: Retry
                next
              when GH::Result::Error
                # TODO: Hard failure, can't be retried.
                next
              else T.absurd(result)
              end

              responses.each do |path, response|
                hash = paths.fetch(path)

                case response
                when SpokesAPI::Types::DiffPositionState
                  paths.fetch(path)[:state] = response
                when Hash
                  hash = paths.fetch(path)
                  hash[:state] = SpokesAPI::Types::DiffPositionState::Success
                  hash.deep_merge!(response)
                else T.absurd(response)
                end
              end
            end
          end
        end
      end

      private

      # Path names in Git are always bytes. They may or may not be UTF-8, even if they would form a well-formed sequence of
      # UTF-8 codepoints. We have to convert between UTF-8 and ASCII-8BIT before passing them over the protocol, since the
      # protobuf has to allow for arbitrary non-NUL byte sequences.
      sig { params(string: String, to: Encoding).returns(String) }
      def encode(string, to: Encoding::ASCII_8BIT)
        string = string.dup if string.frozen?
        string.force_encoding(to).scrub
      end

      sig { params(string: T.nilable(String)).returns(T.nilable(String)) }
      def decode(string)
        return if string.nil?
        encode(string, to: Encoding::UTF_8)
      end
    end
  end
end
