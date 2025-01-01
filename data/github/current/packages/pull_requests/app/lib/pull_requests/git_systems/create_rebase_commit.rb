# typed: strict
# frozen_string_literal: true

module PullRequests
  module GitSystems
    class CreateRebaseCommit
      sig do
        params(
          repository: Repository,
          base_sha: String,
          head_sha: String,
          name: String,
          email: String,
          timestamp: T.nilable(Time),
          timeout: T.nilable(ActiveSupport::Duration)
        ).void
      end
      def initialize(repository:, base_sha:, head_sha:, name:, email:, timestamp:, timeout:)
        @repository = repository
        @base_sha = base_sha
        @head_sha = head_sha
        @name = name
        @email = email
        @timestamp = timestamp
        @timeout = timeout
      end

      sig { returns(T.any(Commit::Conflict, Commit::Created, Commit::Error, Errors)) }
      def call
        timeout = T.let(false, T::Boolean)
        exception = T.let(nil, T.nilable(Exception))
        sha = begin
          GitHub.logger.with_named_tags({ "code.function": "rebase" }) do
            committer_hash = {
              name: @name,
              email: @email,
              time: @timestamp,
            }

            options = {
              timeout: @timeout,
              use_tmp_objdir_mode: "migrate-on-success",
            }

            options[:max_loose_objects_written] = begin
              if tmp_objdir_experiment_threshold > 0
                tmp_objdir_experiment_threshold.floor.to_s
              elsif loose_object_limit != nil
                loose_object_limit
              end
            end

            if @repository.feature_enabled?(:tmp_objdir_experiment)
              if @repository.feature_enabled?(:tmp_objdir_experiment_pack)
                options[:use_tmp_objdir_mode] = "pack-and-migrate-on-success"
              end

              if tmp_objdir_experiment_threshold > 0
                options[:keep_unpacked_threshold] = tmp_objdir_experiment_threshold.floor.to_s
              end

              result, dogstats = @repository.rpc.rebase_tmp_objdir_experiment(
                @head_sha,
                @base_sha,
                committer_hash,
                **options
              )

              dogstats.each { |args| GitHub.dogstats.count(*args) }

              result
            else
              @repository.rpc.rebase(
                @head_sha,
                @base_sha,
                committer_hash,
                **options
              )
            end
          end
        rescue GitRPC::Backend::RebaseTimeout, GitRPC::GitmonClient::AbortError, GitRPC::NetworkError, GitRPC::NoDataError => e
          exception = e
          timeout = true
          nil
        rescue GitRPC::Protocol::DGit::ResponseError => e
          exception = e
          # Treat split timeouts--some nodes timed out, others succeeded--as
          # equivalent to a unanimous timeout, rather than propagating a
          # messy ResponseError.
          is_timeout_or_non_voting_route = e.errors.all? do |route, error|
            error.is_a?(GitRPC::Backend::RebaseTimeout) ||
              error.is_a?(GitRPC::GitmonClient::AbortError) ||
              error.is_a?(GitRPC::Timeout) ||
              error.is_a?(GitRPC::NoDataError) ||
              error.is_a?(BERTRPC::ProtocolError) ||
              !route.voting?
          end

          if is_timeout_or_non_voting_route
            timeout = true
            nil
          else
            return Commit::Error.new(exception:)
          end
        rescue Exception => e # rubocop:disable Lint/GenericRescue
          case error = GitSystems.classify_exception(e)
          when Errors
            return error
          when nil
            raise
          end
        end

        if timeout
          Errors::Timeout.new(exception: exception || StandardError.new("create_rebase_commit timeout"))
        elsif sha.nil?
          Commit::Conflict.new
        else
          Commit::Created.new(sha:, head_sha: @head_sha, base_sha: @base_sha)
        end
      end

      private

      # The feature flag is interpreted as a percentage of 100k objects, i.e. each percentage point allows 1,000 more
      # loose objects to be written
      sig { returns(Integer) }
      def tmp_objdir_experiment_threshold
        GitHub.flipper[:tmp_objdir_experiment_threshold].percentage_of_time_value * 1000
      end

      sig { returns(T.nilable(Integer)) }
      def loose_object_limit
        ENV["REBASE_LIMIT_LOOSE_OBJECTS"]&.to_i
      end
    end
  end
end
