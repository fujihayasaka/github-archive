# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module DeleteCommits
      class Service
        include GitHub::Memoizer
        # OTel prefix for all Service related logs.
        DELETION = "merge_commits.delete_commits"

        class Outcome < T::Enum
          enums do
            NotRun = new("not_run")
            Success = new("success")
            Error = new("error")
          end
        end

        sig { params(repository: Repository, pull_request: PullRequest, requested_at: Time).void }
        def initialize(repository:, pull_request:, requested_at: Time.current)
          @repository = repository
          @pull_request = pull_request
          @requested_at = requested_at
        end

        sig { returns(Outcome) }
        def call
          outcome = T.let(Outcome::NotRun, Outcome)

          with_telemetry do
            case request = loader.request
            when Enums::InvalidRequestReason
              return Outcome::Error
            when Request
              logger.append(request.serialize, prefix: "gh.#{DELETION}.request")
            end

            case result = insert_merge_commit_request(request:)
            when ICommand::Result::Error
              logger.append_exception(result.exception || result.as_exception, prefix: "gh.#{DELETION}")
              return outcome = Outcome::Error
            end

            enqueue_batch_ref_updates_job

            return outcome = Outcome::Success
          ensure
            logger.append({ outcome: outcome.serialize }, prefix: "gh.#{DELETION}")
          end
        end

        protected

        sig { params(request: Request).returns(ICommand::InsertMergeCommitRequestResult) }
        def insert_merge_commit_request(request:)
          ICommand::Result.with_retry do
            command.insert_merge_commit_request!(
              pull_request_id:,
              priority: PullRequests::MergeCommit::Enums::Priority::Low,
              base_repository_id: request.base_repository_id,
              head_repository_id: request.head_repository_id,
              base_branch_sha: request.base_branch_sha,
              head_branch_sha: request.head_branch_sha,
              merge_sha: nil,
              merge_state: Enums::CommitState::PendingDeletion,
              merge_conflict: nil,
              rebase_sha: nil,
              rebase_state: Enums::CommitState::PendingDeletion,
              rebase_conflict: nil,
              requested_at: @requested_at,
            )
          end
        end

        sig { void }
        def enqueue_batch_ref_updates_job
          ICommand::Result.with_retry do
            command.enqueue_batch_ref_updates_job!(pull_request_id:)
          end
        end

        private

        sig { returns(String) }
        memoize def uuid = SecureRandom.uuid

        sig { returns(Logging::Logger) }
        memoize def logger = Logging::Logger.new

        sig { returns(Loader) }
        memoize def loader = Loader.new(pull_request: @pull_request, repository: @repository)

        sig { returns(Logging::Commands) }
        memoize def command
          Logging::Commands.new(
            delegate: Command.new(repository: @repository, pull_requests: [@pull_request])
          )
        end

        sig { returns(Integer) }
        def pull_request_id = @pull_request.id.to_i

        # Adds OTel context that can be used to aggregate exeuctions of the Merge Commit Request process.
        sig do
          type_parameters(:T).
          params(
            block: T.proc.returns(T.type_parameter(:T))
          ).returns(T.type_parameter(:T))
        end
        def with_telemetry(&block)
          Failbot.push(
            merge_commits_uuid: uuid,
            repository_id: @repository.id
          )

          logger.append({
            "code.namespace": "#{self.class.name}",
            "code.function": "call",
            "gh.merge_commits.uuid": uuid,
            "gh.merge_commits.feature": "delete_commits",
          })

          logger.append_repository_context(@repository)
          logger.append_pull_request_context(@pull_request)

          GitHub.tracer.in_span("pull_requests.#{DELETION}.service", kind: :internal, attributes: {
            "repository_id" => @repository.id,
            "pull_request_id" => pull_request_id,
            "uuid" => uuid
          }.compact) do
            GitHub.dogstats.distribution_time("pull_requests.#{DELETION}.service.duration", &block)
          end
        ensure
          logger.append({
            actions: command.actions.logs_for_pull_request_id(pull_request_id),
          }, prefix: "gh.#{DELETION}.request")

          logger.flush
        end
      end
    end
  end
end
