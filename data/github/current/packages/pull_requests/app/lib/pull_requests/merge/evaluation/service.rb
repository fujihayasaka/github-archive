# typed: strict
# frozen_string_literal: true

module PullRequests
  module Merge
    module Evaluation
      class Service
        include GitHub::Memoizer

        sig do
          params(
            pull_request: PullRequest,
            repository: Repository,
            auto_merge_request: AutoMergeRequest,
            actor: T.untyped,
          ).void
        end
        def initialize(pull_request:, repository:, auto_merge_request:, actor:)
          @pull_request = pull_request
          @repository = repository
          @auto_merge_request = auto_merge_request
          @actor = actor
        end

        sig { returns(Enums::Signal) }
        def call
          with_telemetry do
            mode = Mode.deserialize(
              @auto_merge_request.mode,
              @auto_merge_request.mode_configuration
            )

            request = Request.new(
              mode:,
              commit_title: @auto_merge_request.commit_title,
              commit_message: @auto_merge_request.commit_message,
              commit_email_address_id: @auto_merge_request.commit_email_address&.id,
              actor_ip_address: @auto_merge_request.actor_ip_address,
              merge_commit_sha: @pull_request.merge_commit_sha,
              requested_at: @auto_merge_request.created_at,
            )

            logger.append(request.serialize, prefix: "gh.merge.request")

            command = Logging::Commands.new(
              delegate: Command.new(
                pull_request: @pull_request,
                repository: @repository,
                actor: @actor,
                mode:,
                runtime: Enums::Runtime::Evaluation,
                auto_merge_request: @auto_merge_request,
              )
            )

            signal = case mode
            when Mode::Queue
              Queue.new(command:, request:, mode:).call
            when Mode::Wait
              Wait.new(command:, request:, mode:).call
            when Mode::Now
              Now.new(command:, request:, mode:).call
            when Mode::Bypass, Mode::StackedQueue, Mode::StackedWait
              raise "TODO: Not supported."
            else T.absurd(mode)
            end

            logger.append({
              actions: command.actions.to_a,
              signal: signal.serialize
            }, prefix: "gh.merge")

            # TODO: Expand return value to include additional context of outcomes, rule state, etc. It should be returned
            # from the Processor classes, keeping this return value to just the Signal for the to-be-added background job.

            signal
          end
        ensure
          logger.flush
        end

        private

        sig do
          type_parameters(:U).params(
            block: T.proc.returns(T.type_parameter(:U))
          ).returns(T.type_parameter(:U))
        end
        def with_telemetry(&block)
          uuid = SecureRandom.hex(16)

          Failbot.push(
            merge_uuid: uuid,
            pull_request_id: @pull_request.id,
            pull_request_number: @pull_request.number,
            repository_id: @repository.id
          )

          logger.append({
            "code.namespace": "#{self.class.name}",
            "code.function": "call",
          })

          logger.append({
            auto_merge_request_id: @auto_merge_request.id,
            auto_merge_request_merge_method: @auto_merge_request.merge_method,
            auto_merge_request_merge_error: @auto_merge_request.merge_error,
            actor_id: @actor.id,
            actor_type: @actor.class,
          }, prefix: "gh.merge")

          logger.append_repository_context(@repository)

          if issue = @pull_request.issue
            logger.append_issue_context(issue)
          end

          GitHub.tracer.in_span(
            "pull_requests.merge.evaluation",
            kind: :internal,
            attributes: { "uuid" => uuid },
          ) { GitHub.dogstats.distribution_time("pull_requests.merge.evaluation.duration", &block) }
        end

        sig { returns(Shared::Logger) }
        memoize def logger = Shared::Logger.new
      end
    end
  end
end
