# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module CreateCommits
      class Service
        include Enums
        include GitHub::Memoizer

        ReturnValue = T.type_alias { T.any(Result, Enums::InvalidRequestReason) }

        sig { params(pull_request: PullRequest, logger: Logging::Logger, priority: Integer, requested_at: Time).void }
        def initialize(pull_request:, logger: Logging::Logger.new, priority: 0, requested_at: Time.current)
          @pull_request = pull_request
          @logger = logger
          @priority = priority
          @uuid = T.let(SecureRandom.uuid, String)
          @requested_at = requested_at
        end

        sig { returns(ReturnValue) }
        def call
          with_telemetry do
            if repository = @pull_request.repository
              logger.append_repository_context(repository)
            else
              reason = InvalidRequestReason::MissingRepository
              track_invalid_outcome(reason:)
              return reason
            end

            loader = Loader.new(
              repository:,
              pull_request: @pull_request,
              priority: @priority
            )

            case request = loader.request
            when Request
              logger.append(
                request.serialize.without("merge_commit", "rebase_commit"),
                prefix: "gh.#{CREATE_COMMITS}.request"
              )

              logger.append_commits(
                merge_commit: request.merge_commit,
                rebase_commit: request.rebase_commit,
                prefix: "gh.#{CREATE_COMMITS}.request"
              )

              track_commit_state({
                merge: request.merge_commit,
                rebase: request.rebase_commit,
              }, namespace: "request_commit")
            when InvalidRequestReason
              track_invalid_outcome(reason: request)
              return request
            end

            rebase_timeout = loader.rebase_timeout

            command = Logging::Commands.new(
              delegate: Command.new(
                repository:,
                pull_requests: [@pull_request]
              )
            )

            processor = Processor.new(command:, request:, rebase_timeout:, requested_at: @requested_at)

            result = begin
              processor.call
            rescue => exception # rubocop:todo Lint/GenericRescue
              exception
            end

            # Include all the performed side effects and configuration.
            logger.append({
              rebase_timeout:,
              actions: command.actions.to_a
            }, prefix: "gh.#{CREATE_COMMITS}")

            outcome = "unknown"

            begin
              case result
              when Result
                # Processor captured exception versus raised.
                track_exception(exception:) if exception = result.exception

                logger.append_commits(
                  merge_commit: result.merge_commit,
                  rebase_commit: result.rebase_commit,
                  prefix: "gh.#{CREATE_COMMITS}"
                )

                track_commit_state({
                  merge: result.merge_commit,
                  rebase: result.rebase_commit,
                }, namespace: "result_commit")

                outcome = result.outcome.serialize

                return result
              when Exception # Uncaught processor exception.
                track_exception(exception: result)

                outcome = Result::Outcome::Error.serialize

                raise result
              else
                T.absurd(result)
              end
            ensure
              logger.append({ outcome: }, prefix: "gh.#{CREATE_COMMITS}")
              GitHub.dogstats.increment("pull_requests.#{CREATE_COMMITS}.outcome", tags: ["outcome:#{outcome}"])
            end
          end
        ensure
          logger.flush
        end

        private

        # Shorthand constants for the logging namespaces with open telemetry.
        CREATE_COMMITS = "merge_commits.create_commits"

        sig { returns(Logging::Logger) }
        attr_reader :logger

        sig { params(reason: Enums::InvalidRequestReason).void }
        def track_invalid_outcome(reason:)
          GitHub.dogstats.increment("pull_requests.#{CREATE_COMMITS}.outcome", tags: ["outcome:invalid"])
          GitHub.dogstats.increment("pull_requests.#{CREATE_COMMITS}.invalid_request_reason", tags: ["reason:#{reason}"])

          logger.append({
            invalid_reason: reason.serialize,
            outcome: "invalid",
          }, prefix: "gh.#{CREATE_COMMITS}")
        end

        sig { params(exception: Exception).void }
        def track_exception(exception:)
          Failbot.report(exception)
          @logger.append_exception(exception, prefix: "gh.#{CREATE_COMMITS}")
        end

        sig { params(commits: T::Hash[Symbol, T.any(Result::MergeCommit, Result::RebaseCommit, Request::MergeCommit, Request::RebaseCommit)], namespace: String).void }
        def track_commit_state(commits, namespace:)
          commits.each do |type, commit|
            outcome = case commit
            when Entity::Commits::Skipped,
                Entity::Commits::Ineligible,
                Entity::Commits::Created,
                Entity::Commits::Reused,
                Entity::Commits::Conflict,
                Entity::Commits::Found,
                Entity::Commits::Pending
              commit.state_name
            when PullRequests::GitSystems::Commit::Failed
              "failed"
            when PullRequests::GitSystems::Errors::Outage
              "outage_#{commit.reason.serialize}"
            when PullRequests::GitSystems::Errors::Timeout,
                PullRequests::MergeCommit::ICommand::Result::Timeout
              "timeout"
            when PullRequests::GitSystems::Errors::Fatal
              "fatal"
            when PullRequests::MergeCommit::ICommand::Result::Error
              "error"
            else
              T.absurd(commit)
            end

            GitHub.dogstats.increment("pull_requests.#{CREATE_COMMITS}.#{namespace}", tags: [
              "outcome:#{outcome}",
              "type:#{type}"
            ])
          end
        end

        # Adds OTel context that can be used to aggregate exeuctions of the Merge Commit Request process.
        sig do
          type_parameters(:T).
          params(
            block: T.proc.returns(T.type_parameter(:T))
          ).returns(T.type_parameter(:T))
        end
        def with_telemetry(&block)
          Failbot.push(
            merge_commits_uuid: @uuid,
            repository_id: @pull_request.repository_id,
            pull_request_id: @pull_request.id,
          )

          logger.append({
            "code.namespace": "#{self.class.name}",
            "code.function": "call",
            "gh.merge_commits.uuid": @uuid,
            "gh.merge_commits.feature": "create_commits",
          })

          logger.append_pull_request_context(@pull_request)

          GitHub.tracer.in_span(
            "pull_requests.#{CREATE_COMMITS}.service",
            kind: :internal,
            attributes: {
              "repository_id" => @pull_request.repository_id,
              "pull_request_id" => @pull_request.id,
              "uuid" => @uuid
            }.compact
          ) do
            GitHub.dogstats.distribution_time("pull_requests.#{CREATE_COMMITS}.service.duration", &block)
          end
        end
      end
    end
  end
end
