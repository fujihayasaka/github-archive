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

            Observability::Git.measure(rpc: :rebase, repository_id: @repository.id) do
              @repository.rpc.rebase(  # rubocop:disable GitHub/EnsureCommitAttribution
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
        rescue GitRPC::CommandFailed => exception
          return Commit::Error.new(exception:)
        rescue Exception => e # rubocop:disable Lint/RescueException
          case error = GitSystems.classify_exception(e, repository: @repository)
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
          if FeatureFlag.vexi.enabled?(:git_commits_via_push_job, @repository, default: false)
            AuthenticCommits::CommitContext.push_range(@base_sha, sha)
          end
          Commit::Created.new(sha:, head_sha: @head_sha, base_sha: @base_sha)
        end
      end

      sig { params(onto_oid: T.nilable(String)).returns(T.any(Commit::Conflict, Commit::Created, Commit::Error, Errors)) }
      def call_spokes(onto_oid: nil)
        committer_time = @timestamp || Time.current
        spokes_api = @repository.spokes_api(timeout: @timeout&.to_f)

        result = begin
          spokes_api.with_transaction do
            spokes_api.rebase( # rubocop:disable GitHub/EnsureCommitAttribution
              head_oid: @head_sha,
              base_oid: @base_sha,
              onto_oid:,
              committer: {
                name: @name,
                email: @email,
                time: committer_time,
              },
              mergeability_only: false,
              committer_only: false,
            )
          end
        rescue SpokesAPI::TwirpServerError => exception
          return Errors::Timeout.new(exception:)
        rescue SpokesAPI::ResourceExhausted => exception
          return Errors::Outage.new(reason: Errors::Outage::Reason::RateLimited, exception:)
        rescue => exception
          case error = GitSystems.classify_exception(exception, repository: @repository)
          when Errors then return error
          else return Commit::Error.new(exception:)
          end
        end

        case result.rebase_status
        when :STATUS_SUCCESS, :STATUS_ALREADY_MERGED
          rebased_oid = result.oid&.id
          if rebased_oid.nil?
            return Commit::Error.new(exception: StandardError.new("Rebase response contained no OID"))
          end

          if FeatureFlag.vexi.enabled?(:git_commits_via_push_job, @repository, default: false)
            AuthenticCommits::CommitContext.push_range(onto_oid || @base_sha, rebased_oid)
          end

          Commit::Created.new(sha: rebased_oid, head_sha: @head_sha, base_sha: @base_sha)
        when :STATUS_MERGE_CONFLICT
          Commit::Conflict.new
        else
          Commit::Error.new(exception: StandardError.new("Unexpected rebase status: #{result.rebase_status}"))
        end
      end
    end
  end
end
