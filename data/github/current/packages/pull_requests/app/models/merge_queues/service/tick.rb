# typed: strict
# frozen_string_literal: true

module MergeQueues
  module Service
    # Primary entry point for executing the core code loop of the MergeQueue. This class is idempotent and
    # is designed to run the execution loop as many times as necessary.
    #
    # Called by MergeQueueJob
    class Tick < Base
      MAX_ITERATIONS = T.let(5, Integer)

      sig { returns(DecisionEngine::Result) }
      def call
        stats_start_time = GitHub::Dogstats.monotonic_time

        with_logging do
          if @merge_queue.nil?
            GitHub.logger.info("no_such_queue")
            return DecisionEngine::Result::Done
          end

          # Check to see if the Merge Queue feature has been disabled. If it has, clear the queue and return.
          if !@repository.merge_queue_enabled?
            GitHub.logger.info(
              "gh.merge_queue.result": "queue_disabled",
              "gh.merge_queue.feature_flag": @repository.feature_flag_enabled_or_raise?(:merge_queue), # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
              "gh.merge_queue.plan_support": @repository.plan_supports?(:merge_queue),
              "gh.merge_queue.github_owned": @repository.github_owned?
            )

            return DecisionEngine::Result::Disabled
          end

          if @merge_queue.wait_for_branch_rename?
            GitHub.logger.info("branch_rename_in_progress")
            return DecisionEngine::Result::Waiting
          end

          # Track the total sum of actions performed across multiple engine invocations.
          actions = T.let([], T::Array[MergeQueues::CommandActionLogger::Action])

          # The most recent engine result.
          engine_result = T.let(DecisionEngine::Result::Done, DecisionEngine::Result)

          # Hold a mutex while we load DB & Git state.
          # After that we are operating on in-memory state, and a synchronous
          # merge via GraphQL can happen safely.
          begin
            models, branch_sha = with_merge_mutex do
              [
                factory.merge_queue_entry_models,
                @repository.ref_to_sha(@branch)
              ]
            end
          rescue GitHub::Redis::Mutex::LockError
            GitHub.logger.info("synchronous_merge_in_progress")
            return DecisionEngine::Result::Waiting
          end

          if branch_sha.nil?
            GitHub.logger.info("gh.merge_queue.result": "base_branch_missing")
            return DecisionEngine::Result::Done
          end

          entries = factory.to_entry_list

          # Preemptively notify the websockets to update.
          notify_websockets!

          log_entries(entries, suffix: :before)

          GitHub.logger.info("gh.merge_queue.configuration": JSON.dump(configuration_for_logs))

          # Count each tick as a single iteration.
          iteration = 0

          # Ensure the variable is accessible in the ensure block.
          exception = T.let(nil, T.nilable(StandardError))

          command = command_with_status_check_models

          # Repeatedly execute the decision engine until we no longer have any actions being performed.
          # This is an optimization to deal with order of operation quirks for failure scenarios.
          decision_engine = DecisionEngine.new(
            entries:,
            command:,
            branch_sha:,
            configuration:,
            require_checks: factory.require_checks?,
          )

          begin
            while iteration < MAX_ITERATIONS
              if entries.empty?
                # We have nothing to evaluate.
                break
              end

              begin
                engine_result = decision_engine.call
              rescue => exception # rubocop:todo Lint/RescueException
                # Make sure we're dumping the events that occurred, even if we failed.
                actions.concat(command.actions)
                # Exception is captured so that it will be present in the ensure block
                raise
              end

              actions_performed = command.actions
                .reject { |action| action.name == CommandActionLogger::Action::Name::RecalculatePositions }
                .any?

              # Pattern matching on the various return statements. Retry if we performed any actions in the previous loop.
              case [engine_result, actions_performed]
              in [DecisionEngine::Result::Done, _] | [DecisionEngine::Result::Waiting, false]
                break
              else
                iteration += 1
                actions.concat(command.actions)
                command.actions.clear
              end
            end

            ids = actions.map(&:merge_queue_entry_id)

            notify_websockets!(
              models.filter { |entry| ids.include?(entry.id) }
            )

            return engine_result
          ensure
            result = exception.nil? ? "success" : "error"
            GitHub.dogstats.distribution_timing_since(
              "merge_queue.evaluate.time",
              stats_start_time,
              tags: ["single_job", result],
            )

            if @repository.feature_flag_enabled_or_raise?(:merge_queue_logging_filter) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
              actions = actions.reject { |action| action.name == CommandActionLogger::Action::Name::RecalculatePositions }
            end

            # These need to be split up as they often contain large amounts of data that overflow the limits.
            GitHub.logger.info("gh.merge_queue.result": result, "exception.message": exception)
            GitHub.logger.info("gh.merge_queue.iteration_count": iteration + 1)
            GitHub.logger.info("gh.merge_queue.actions": JSON.dump(actions.map(&:to_s)))
            log_entries(entries, suffix: :after)
          end
        end
      end

      private

      sig { params(entries: EntryList, suffix: Symbol).void }
      def log_entries(entries, suffix:)
        # Short array of strings for easier reading.
        GitHub.logger.info("gh.merge_queue.entries_#{suffix}": entries.map(&:to_logging_s))

        # Split each entry to its own line to deal with larger data related to checks.
        entries.to_a.each.with_index(1) do |entry, position|
          log_data = JSON.dump({ position:, state: entry.to_state_s }.merge(entry.serialize.with_indifferent_access.without(:required_checks, :state)))
          GitHub.logger.info("gh.merge_queue.entry_#{suffix}": log_data)
        end
      end

      sig { params(block: T.proc.returns(DecisionEngine::Result)).returns(DecisionEngine::Result) }
      def with_logging(&block)
        context = {
          mq_uuid: SecureRandom.uuid,
          fn: "MergeQueues::Service#tick!"
        }

        sensitive_context = {
          repository: @repository.nwo,
          branch: @branch,
        }

        # Ensure we can connect the logs of this system with our exception tracking logs.
        Failbot.push(**context)
        Failbot.push_sensitive(**sensitive_context)

        GitHub.logger.with_named_tags(
          "code.namespace": "MergeQueues::Service:Tick",
          "code.function": "call",
          "gh.repo.id": @repository.id,
          "gh.merge_queue.uuid": context[:mq_uuid],
          "gh.merge_queue.branch": @branch,
          &block
        )
      end
    end
  end
end
