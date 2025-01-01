# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    # Execution and glue layer of the Merge Commit Request process.
    class Service
      extend T::Sig

      sig { params(repository: Repository).void }
      def initialize(repository:)
        @repository = repository
      end

      sig { void }
      def call
        with_logging_context do
          loader = Loader.new(repository: @repository)

          requests, invalid_requests = loader.requests
          loaded_requests = requests + invalid_requests

          # Early return to prevent unnecessary database and git operations.
          return if loaded_requests.empty?

          configuration = loader.configuration
          pull_requests = loader.pull_requests

          # Initialize the command object that performs the side effects.
          command = Command.new(pull_requests:, repository: @repository)

          # Wrap the command and log invocations.
          command = Logging::Commands.new(delegate: command)

          begin
            Processor.new(command:, configuration:, requests:, invalid_requests:).call
          ensure
            GitHub.dogstats.count("pull_requests.merge_commits.loaded_requests_count", loaded_requests.count)

            context = configuration.to_logging_h.merge!({
              "gh.merge_commits.loaded_requests_count": loaded_requests.count,
              "gh.merge_commits.valid_requests": requests.length,
              "gh.merge_commits.invalid_requests": invalid_requests.length,
              "gh.repo.advisory_repository": @repository.advisory_workspace?,
            })

            GitHub.logger.with_named_tags(context) do
              GitHub.dogstats.count("pull_requests.merge_commits.request.processed", loaded_requests.count)

              loaded_requests.each do |request|
                GitHub.logger.info(request.to_logging_h.merge(
                  "gh.merge_commits.request.actions": command.actions.logs_for_pull_request_id(request.pull_request_id),
                ))

                request.to_stats_h.each do |stat_name_key, tags|
                  GitHub.dogstats.increment(stat_name_key, tags: [tags])
                end

                request.to_timing_stats_h.each do |stat_name_key, timing|
                  GitHub.dogstats.distribution(stat_name_key, timing)
                end
              end
            end
          end
        end
      end

      private

      # Adds logging context that can be used to aggregate exeuctions of the Merge Commit Request process.
      sig { params(block: T.proc.void).void }
      def with_logging_context(&block)
        uuid = SecureRandom.uuid
        repository_id = @repository.id

        sensitive_context = {
          repository: @repository.name_with_display_owner,
        }

        # Ensure we can connect the logs of this system with our exception tracking logs.
        Failbot.push(merge_commits_uuid: uuid, repository_id:)
        Failbot.push_sensitive(repository: @repository.name_with_display_owner)

        GitHub.tracer.in_span("merge_commits.service", kind: :internal, attributes: { "repository_id" => @repository.id, "uuid" => uuid }) do
          GitHub.logger.with_named_tags(
            "code.namespace": "#{self.class.name}",
            "code.function": "call",
            "gh.repo.id": repository_id,
            "gh.merge_commits.uuid": uuid,
            &block
          )
        end
      end
    end
  end
end
