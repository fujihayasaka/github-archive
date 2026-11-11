# typed: strict
# frozen_string_literal: true

module PullRequests
  module Merge
    module Creation
      class Service
        include GitHub::Memoizer

        sig do
          params(
            pull_request: PullRequest,
            repository: Repository,
            actor: T.untyped,
            mode: Mode,
            commit_title: T.nilable(String),
            commit_message: T.nilable(String),
            commit_email_address: T.nilable(UserEmail),
            actor_ip_address: T.nilable(String),
            requested_at: Time,
          ).void
        end
        def initialize(pull_request:, repository:, actor:, mode:, commit_title:, commit_message:, commit_email_address:, actor_ip_address:, requested_at: Time.current)
          @pull_request = pull_request
          @repository = repository
          @actor = actor
          @mode = mode
          @commit_title = commit_title
          @commit_message = commit_message
          @commit_email_address = commit_email_address
          @actor_ip_address = actor_ip_address
          @requested_at = requested_at
        end

        sig { returns(T.any(Results::Created, Results::Error, Results::AlreadyEnqueued, Results::AlreadyMerged, Results::Invalid)) }
        def call
          with_telemetry do
            # An already existing AutoMergeRequest means we can early return.
            if auto_merge_request = @pull_request.auto_merge_request
              return Results::AlreadyEnqueued.new(auto_merge_request:)
            end

            # An already existing MergeQueueEntry for Queue mode means we can early return.
            case @mode
            when Mode::Queue
              if merge_queue_entry = @pull_request.merge_queue_entry
                return Results::AlreadyEnqueued.new(merge_queue_entry:)
              end
            end

            request = Request.new(
              mode: @mode,
              commit_title: @commit_title,
              commit_message: @commit_message,
              commit_email_address_id: @commit_email_address&.id,
              actor_ip_address: @actor_ip_address,
              requested_at: @requested_at
            )

            logger.append(request.serialize, prefix: "gh.merge.request")

            command = Logging::Commands.new(
              delegate: Command.new(
                pull_request: @pull_request,
                repository: @repository,
                actor: @actor,
                mode: @mode,
                runtime: Enums::Runtime::Creation
              )
            )

            processor = Processor.new(command:, request:).call

            result = case processor
            when ICommand::Result::Success
              if auto_merge_request = @pull_request.auto_merge_request
                Results::Created.new(auto_merge_request:)
              else
                Results::Error.new(message: "failed")
              end
            when ICommand::Result::DuplicateDatabaseRecord
              if auto_merge_request = AutoMergeRequest.find_by(pull_request: @pull_request)
                Results::AlreadyEnqueued.new(auto_merge_request:)
              else
                Results::Error.new(message: "failed")
              end
            when ICommand::Result::Error
              if exception = processor.exception
                logger.append_exception(exception, prefix: "gh.merge")
              end

              Results::Error.new(message: processor.message, exception:)
            when Results::Invalid, Results::AlreadyMerged
              processor
            else T.absurd(processor)
            end

            logger.append({ actions: command.actions.to_a }, prefix: "gh.merge")
            logger.append(result.serialize.merge(type: result.class.name), prefix: "gh.merge.result")

            result
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

          Audit.context.push(actor_ip: @actor_ip_address)

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
            mode: @mode.serialize,
            actor_id: @actor.id,
            actor_type: @actor.class,
          }, prefix: "gh.merge")

          logger.append_repository_context(@repository)

          if issue = @pull_request.issue
            logger.append_issue_context(issue)
          end

          GitHub.tracer.in_span(
            "pull_requests.merge.creation",
            kind: :internal,
            attributes: { "uuid" => uuid },
          ) { GitHub.dogstats.distribution_time("pull_requests.merge.creation.duration", &block) }
        end

        sig { returns(Shared::Logger) }
        memoize def logger = Shared::Logger.new
      end
    end
  end
end
