# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module CreateStackedCommits
      class Service
        CREATE_COMMITS = CreateCommits::Service::CREATE_COMMITS

        sig { params(stack: PullRequests::Stack, logger: Shared::Logger, priority: Integer, requested_at: Time).void }
        def initialize(stack:, logger: Shared::Logger.new, priority: 0, requested_at: Time.current)
          @stack = stack
          @logger = logger
          @priority = priority
          @uuid = T.let(SecureRandom.uuid, String)
          @requested_at = requested_at
        end

        sig { returns(CreateCommits::Results) }
        def call
          with_telemetry do
            unless repository = T.cast(@stack.repository, T.nilable(Repository)) # rubocop:disable GitHub/AvoidCast
              return CreateCommits::Results.empty
            end

            loader = Loader.new(
              stack: @stack,
              repository:,
              priority: @priority,
            )

            logger.append_repository_context(repository)

            requests = loader.requests

            return CreateCommits::Results.empty if requests.empty?

            loader.pull_requests.each { logger.for(_1.id).append_pull_request_context(_1) }

            command = Logging::Commands.new(
              delegate: Command.new(
                repository:,
                pull_requests: loader.pull_requests,
              )
            )

            requests.each_with_index do |request, index|
              pull_request_id = request.pull_request_id

              logger.for(pull_request_id) do |child|
                child.append({
                  pull_request_id:,
                  position: index + 1,
                  total: requests.size,
                }, prefix: "gh.#{CREATE_COMMITS}")

                child.append(
                  request.serialize.without("merge_commit", "rebase_commit"),
                  prefix: "gh.#{CREATE_COMMITS}.request"
                )

                child.append(
                  Logging::Commits.to_hash(request.merge_commit),
                  prefix: "gh.#{CREATE_COMMITS}.request.merge_commit"
                )

                child.append(
                  Logging::Commits.to_hash(request.rebase_commit),
                  prefix: "gh.#{CREATE_COMMITS}.request.rebase_commit"
                )
              end
            end

            results = CreateCommits::Processor.new(
              command:,
              requests:,
              rebase_timeout: loader.rebase_timeout,
              requested_at: @requested_at,
            ).call

            requests.zip(results).each do |(request, result)|
              pull_request_id = request.pull_request_id

              logger.for(pull_request_id) do |child|
                if result
                  child.append(
                    Logging::Commits.to_hash(result.merge_commit),
                    prefix: "gh.#{CREATE_COMMITS}.merge_commit"
                  )

                  child.append(
                    Logging::Commits.to_hash(result.rebase_commit),
                    prefix: "gh.#{CREATE_COMMITS}.rebase_commit"
                  )

                  child.append({
                    outcome: result.outcome.serialize,
                    actions: command.actions.logs_for_pull_request_id(pull_request_id),
                  }, prefix: "gh.#{CREATE_COMMITS}")

                  if exception = result.exception
                    Failbot.report(exception)
                    child.append_exception(exception, prefix: "gh.#{CREATE_COMMITS}")
                  end
                else
                  child.append({
                    outcome: "not_processed",
                  }, prefix: "gh.#{CREATE_COMMITS}")
                end
              end
            end

            results
          end
        ensure
          logger.flush
        end

        private

        sig { returns(Shared::Logger) }
        attr_reader :logger

        sig { type_parameters(:T).params(block: T.proc.returns(T.type_parameter(:T))).returns(T.type_parameter(:T)) }
        def with_telemetry(&block)
          Failbot.push(
            merge_commits_uuid: @uuid,
            stack_id: @stack.id,
          )

          logger.append({
            "code.namespace": "#{self.class.name}",
            "code.function": "call",
            "gh.merge_commits.uuid": @uuid,
            "gh.merge_commits.feature": "create_commits",
            "gh.merge_commits.stacked": true,
          })

          GitHub.tracer.in_span(
            "pull_requests.#{CREATE_COMMITS}.service",
            kind: :internal,
            attributes: {
              "stack" => true,
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
