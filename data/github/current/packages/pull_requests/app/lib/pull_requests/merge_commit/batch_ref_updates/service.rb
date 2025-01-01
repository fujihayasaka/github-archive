# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module BatchRefUpdates
      class Service
        # OTel prefix for all Service related logs.
        BATCH_REF_UPDATES = "merge_commits.batch_ref_updates"

        sig { params(repository: Repository, batch_size: Integer, logger: Logging::Logger).void }
        def initialize(repository:, batch_size:, logger: Logging::Logger.new)
          @repository = repository
          @batch_size = batch_size
          @logger = logger
          @uuid = T.let(SecureRandom.uuid, String)
        end

        sig { returns(Result) }
        def call
          with_telemetry do
            loader = Loader.new(repository: @repository, batch_size: @batch_size)
            requests, invalid_requests = loader.requests

            track_counts(
              requests: requests.count,
              invalid_requests: invalid_requests.count,
              merge_commit_requests: loader.merge_commit_requests.count,
            )

            # Early return to prevent unnecessary database and git operations.
            if requests.empty? && invalid_requests.empty?
              return Result.new(outcome: Result::Outcome::NoRequests)
            end

            pull_requests = loader.pull_requests.each do |pull|
              @logger.for(pull.id).append_pull_request_context(pull)
            end

            requests.each do |request|
              @logger.for(request.pull_request_id) do |log|
                log.append(
                  request.serialize.without("merge_commit", "rebase_commit", "pull_request_id"),
                  prefix: "gh.#{BATCH_REF_UPDATES}.request"
                )

                log.append_commits(
                  merge_commit: request.merge_commit,
                  rebase_commit: request.rebase_commit,
                  prefix: "gh.#{BATCH_REF_UPDATES}.request"
                )
              end

              # Track the total time it took to update this PR.
              if requested_at = request.requested_at
                GitHub.dogstats.distribution(
                  "pull_requests.merge_commits.request.processing_time",
                  (Time.now - requested_at).to_f * 1000
                )
              end
            end

            invalid_requests.each do |request|
              @logger.for(request.pull_request_id).append({
                invalid_reason: request.reason.serialize
              }, prefix: "gh.#{BATCH_REF_UPDATES}.request")
            end

            # Initialize the command object that performs the side effects.
            command = Command.new(pull_requests:, repository: @repository)

            # Wrap the command and log invocations.
            command = Logging::Commands.new(delegate: command)

            result = begin
              # Only process valid requests
              Processor.new(
                command:,
                requests:,
                pull_request_ids: loader.pull_request_ids
              ).call
            rescue => exception # rubocop:todo Lint/RescueException
              exception
            end

            # Log the after state of the request.
            requests.each do |request|
              @logger.for(request.pull_request_id).append({
                actions: command.actions.logs_for_pull_request_id(request.pull_request_id)
              }, prefix: "gh.#{BATCH_REF_UPDATES}.request")
            end

            outcome = "unknown"
            ref_update = "unknown"

            begin
              case result
              when StandardError
                track_exception(exception: result)

                outcome = Result::Outcome::Error.serialize
                ref_update = "not_run"

                raise result
              when Result
                track_exception(exception:) if exception = result.exception

                outcome = result.outcome.serialize
                ref_update = begin
                  case result.ref_update
                  when nil then "not_run"
                  when ICommand::Result::Success then "success"
                  when ICommand::Result::Skipped then "skipped"
                  when ICommand::Result::Error   then "error"
                  end
                end

                return result
              else T.absurd(result)
              end
            ensure
              @logger.append({ outcome:, ref_update: }, prefix: "gh.#{BATCH_REF_UPDATES}")
              GitHub.dogstats.increment("pull_requests.#{BATCH_REF_UPDATES}.ref_update", tags: ["outcome:#{ref_update}"])
              GitHub.dogstats.increment("pull_requests.#{BATCH_REF_UPDATES}.outcome",    tags: ["outcome:#{outcome}"])
            end
          end
        ensure
          @logger.flush
        end

        private

        sig { params(counts: Integer).void }
        def track_counts(**counts)
          counts.each do |key, count|
            @logger.append({ "gh.#{BATCH_REF_UPDATES}.#{key}_count" => count })
            GitHub.dogstats.count("pull_requests.#{BATCH_REF_UPDATES}.#{key}_count", count)
          end
        end

        sig { params(exception: Exception).void }
        def track_exception(exception:)
          Failbot.report(exception)
          @logger.append_exception(exception, prefix: "gh.#{BATCH_REF_UPDATES}")
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
            repository_id: @repository.id
          )

          @logger.append({
            "code.namespace": "#{self.class.name}",
            "code.function": "call",
            "gh.merge_commits.uuid": @uuid,
            "gh.merge_commits.feature": "batch_ref_updates",
            "gh.#{BATCH_REF_UPDATES}.batch_size": @batch_size,
          })

          @logger.append_repository_context(@repository)

          GitHub.tracer.in_span(
            "pull_requests.#{BATCH_REF_UPDATES}.service",
            kind: :internal,
            attributes: {
              "repository_id" => @repository.id,
              "uuid" => @uuid
            }.compact,
          ) { GitHub.dogstats.distribution_time("pull_requests.#{BATCH_REF_UPDATES}.service.duration", &block) }
        end
      end
    end
  end
end
