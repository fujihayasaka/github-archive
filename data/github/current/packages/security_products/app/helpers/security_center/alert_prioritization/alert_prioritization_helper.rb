# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityCenter
  module AlertPrioritization
    class AlertPrioritizationHelper
      extend BlackbirdIndexHelper
      include ::GitHub::SecurityCenter::LoggingHelper

      class UserMissingActiveSessionError < StandardError

        sig { params(msg: String).void }
        def initialize(msg = "User must have an active session")
          super(msg)
        end
      end

      # Check if a repository is indexed for semantic search.
      sig { params(repo: ::Repository, user: ::User).returns(T::Boolean) }
      def self.is_repo_indexed_for_semantic_search(repo:, user:)
        GitHub.logger.with_named_tags(
          "gh.repo.id" => repo.id,
          "gh.repo.name_with_owner" => repo.name_with_display_owner,
          "gh.user.id" => user.id,
          "gh.user.login" => user.display_login
        ) do
          log_timing(step: "check semantic code search") do
            return false unless cir = CopilotIndexedRepositories.find_by(repository: repo.id)
            cir.semantic_code_search_ok?
          end
        end
      end

      # Retry a block of code a specified number of times.
      sig do
        params(
          block_description: String,
          max_retries: Integer,
          raise_on_retry_exhaustion: T::Boolean,
          retry_wait_sec: Integer,
          blk: T.untyped
        ).returns([T.untyped, T.nilable(T.any(StandardError, Twirp::Error))])
      end
      def self.with_retry(block_description:, max_retries: 3, raise_on_retry_exhaustion: true, retry_wait_sec: 2, &blk)
        GitHub.logger.with_named_tags(block_description:, max_retries:, raise_on_retry_exhaustion:, retry_wait_sec:) do
          attempts = 1

          begin
            res = yield
            [res, nil]
          rescue => err # rubocop:todo Lint/GenericRescue
            attempts += 1

            if attempts > max_retries
              Failbot.report(err)
              log_warn(err.message)

              raise err if raise_on_retry_exhaustion
              return [nil, err]
            end

            log_warn("Block \"#{block_description}\" - failed. Retrying…")
            sleep(retry_wait_sec)
            retry
          end
        end
      end
    end
  end
end
