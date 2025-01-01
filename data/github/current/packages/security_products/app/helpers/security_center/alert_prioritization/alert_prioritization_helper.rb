# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityCenter
  module AlertPrioritization
    class AlertPrioritizationHelper
      extend T::Sig
      extend BlackbirdIndexHelper
      include ::GitHub::SecurityCenter::LoggingHelper

      class UserMissingActiveSessionError < StandardError
        extend T::Sig

        sig { params(msg: String).void }
        def initialize(msg = "User must have an active session")
          super(msg)
        end
      end

      # Check if a repository is indexed for semantic search.
      # NOTE: The user must have an active session and be able to read the repository for Blackbird to return the correct status.
      sig { params(repo: ::Repository, user: ::User).returns(T::Boolean) }
      def self.is_repo_indexed_for_semantic_search(repo:, user:)
        GitHub.logger.with_named_tags(
          "gh.repo.id" => repo.id,
          "gh.repo.name_with_owner" => repo.name_with_display_owner,
          "gh.user.id" => user.id,
          "gh.user.login" => user.display_login
        ) do
          log_timing(step: __method__.to_s) do
            blackbird_actor = ::Search::Blackbird::Client.actor(user, T.must(user.most_recent_session))
            tenant = ::Search::Blackbird::Client.tenant(GitHub::CurrentTenant.get)

            last_twirp_err = T.let(nil, T.nilable(Twirp::Error))
            res, retry_err = with_retry(block_description: __method__.to_s) do
              index_status = get_indexing_status(user, blackbird_actor, repo, tenant)

              raise StandardError.new("Error getting blackbird indexing status") if index_status.nil?
              index_status
            end

            if retry_err
              last_twirp_err = T.must(last_twirp_err)
              GitHub.dogstats.increment("#{T.must(self.class.name).underscore}.#{__method__}.status", tags: ["error_code:#{last_twirp_err.code}"])
              log_warn("Blackbird get repository status failed", "blackbird.error.code": last_twirp_err.code, "blackbird.error.msg": last_twirp_err.msg)

              return false
            end

            res.try(:code_status) == "indexed"
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
