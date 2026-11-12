# typed: false
# frozen_string_literal: true

require_relative "../../../config/environment"
require "slop"
require "dependabot/transition"

#
# Transitions are orchestrated by the GitHub transitions service and are run
# via chatops:
#
#   .transitions run <pr-url> <environment> <arguments>
#
# A pull request is required to run a transition, so the first step is to
# create one for the transition files.
#
# To run a transition in a particular stamp, specify the stamp as the
# <environment>, e.g., prod-weu-01. To run a transition in all stamps,
# specify * as the <environment>.
#
# Before running a transition you should lock dependabot-api deployments.
#
# To run this transition in dry-run mode, issue the following chatop in the
# #dependabot-ops channel:
#
#   .transitions run <pr-url> <environment> 20251230042641_backfill_current_state_values.rb -v
#
# To run this transition in write mode, issue the following chatop in the
# #dependabot-ops channel:
#
#   .transitions run <pr-url> <environment> 20251230042641_backfill_current_state_values.rb -v -w
#
# Once the transition is complete, merge the pull request.
#
module Dependabot
  module Transitions
    class BackfillCurrentStateValues < Dependabot::Transition
      extend T::Sig

      # Transitions provide an alternative to running arbitrary code in
      # production without code review.
      #
      # When designing a transition, favor an approach that can be run in small
      # batches and ensure your script is idempotent and safe to resume/re-run.
      #
      # Database connections default to writing, so be sure to test dry runs
      # thoroughly.

      # Recommended batch size number, but you can modify for your use case
      READ_BATCH_SIZE = 1000
      WRITE_BATCH_SIZE = 100

      # Freno db cluster to throttle for writes.
      FRENO_CLUSTER = :dependabot
      RETRY_COUNT = 6
      RETRY_WAIT = 1 # seconds

      BACKFILL_TYPES = [
        [Account, AccountTransition, AccountStateMachine],
        [UpdateConfig, UpdateConfigTransition, UpdateConfigStateMachine],
        [UpdateJob, UpdateJobTransition, UpdateJobStateMachine],
        [PullRequest, PullRequestTransition, PullRequestStateMachine],
        [PendingPullRequest, PendingPullRequestTransition, PendingPullRequestStateMachine],
      ].freeze

      # Returns nothing.
      def perform
        BACKFILL_TYPES.each do |record_type, transition_type, state_machine_type|
          process_type(record_type, transition_type, state_machine_type)
        end
      end

      def process_type(record_type, transition_type, state_machine_type)
        log "Starting to process #{record_type}"
        return if dry_run?

        batch = 0
        updated_count = 0

        # fetch records in batched reads and update their current_state in batched writes
        process_batches(record_type, transition_type, state_machine_type) do |ids_by_state|
          # log progress every 50 batches / 5000 records if verbose
          batch += 1
          if verbose? && (batch % 50).zero?
            log "Processing #{record_type.name} batch #{batch}, #{updated_count} total rows updated"
          end

          updated_count += ids_by_state.sum do |state, ids|
            update_with_retries(record_type, ids, state)
          end
        end
      rescue StandardError => e
        log "Error processing #{record_type}. #{e.detailed_message}"
        raise
      ensure
        log "Finished processing #{record_type}, #{updated_count} total rows updated"
      end

      sig { params(record_type: T.class_of(ActiveRecord::Base), ids: T::Array[Integer], current_state: String).returns(Integer) }
      def update_with_retries(record_type, ids, current_state)
        retry_wait = other_args.fetch(:retry_wait, RETRY_WAIT)
        batch_size = other_args.fetch(:write_batch_size, WRITE_BATCH_SIZE)
        retry_count = 0

        # write records in batches of max size WRITE_BATCH_SIZE, and return
        # the sum count of all records updated
        ids.each_slice(batch_size).sum do |batch_ids|
          Dependabot.freno_throttler.throttle(FRENO_CLUSTER) do
            record_type.where(id: batch_ids, current_state: nil).update_all(current_state: current_state)
          end
        rescue Freno::Throttler::Error, *Dependabot::Exceptions::RECOVERABLE_DATABASE_EXCEPTION_CLASSES
          retry_count += 1
          raise if retry_count > RETRY_COUNT

          sleep(retry_wait * retry_count)
          retry
        end
      end

      sig do
        params(
          record_type: T.class_of(ActiveRecord::Base),
          transition_type: T.class_of(ActiveRecord::Base),
          state_machine_type: T.class_of(Object),
          blk: T.proc.params(grouped_ids: T::Hash[String, T::Array[Integer]]).void
        ).void
      end
      # rubocop:disable Naming/BlockForwarding, Lint/UnusedMethodArgument
      def process_batches(record_type, transition_type, state_machine_type, &blk) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/PerceivedComplexity
        # rubocop:enable Naming/BlockForwarding, Lint/UnusedMethodArgument
        retry_wait = other_args.fetch(:retry_wait, RETRY_WAIT)
        batch_size = other_args.fetch(:read_batch_size, READ_BATCH_SIZE)

        min_id = 0
        max_id = record_type.maximum(:id)
        return if max_id.nil?

        # fetch records in batches of size READ_BATCH_SIZE until there are no more
        # to process.  fetched records will be yielded to the caller as a hash like
        # { "state1" => [id1, id2], "state2" => [id3, id4] }
        while min_id <= max_id
          retry_count = 0

          # set an upper bound on the batch fetch to avoid scanning the entire table
          batch_max_id = min_id + 1_000_000
          ids_and_states = ActiveRecord::Base.connected_to(role: :reading) do
            record_type.where(id: min_id..batch_max_id, current_state: nil).
              joins(record_type.most_recent_transition_join).
              order(id: :asc).
              limit(batch_size).
              pluck(:id, current_state_sql(transition_type, state_machine_type))
          rescue *Dependabot::Exceptions::RECOVERABLE_DATABASE_EXCEPTION_CLASSES
            retry_count += 1
            raise if retry_count > RETRY_COUNT

            sleep(retry_wait * retry_count)
            retry
          end

          if ids_and_states.any?
            # yield grouped ids by state
            yield ids_and_states.each_with_object({}) { |(id, state), agg| (agg[state] ||= []) << id }

            # set min_id for next batch to the last processed id + 1
            min_id = ids_and_states.last.first + 1
          else
            # nothing to process in this batch, set min_id to batch_max_id + 1
            min_id = batch_max_id + 1
          end
        end
      end

      def current_state_sql(transition_type, state_machine_type)
        most_recent_join_alias = "most_recent_#{transition_type.name.underscore}"
        Arel.sql(
          "COALESCE(#{most_recent_join_alias}.to_state, '#{state_machine_type.initial_state}')"
        )
      end
    end
  end
end

# Run as a single process if this script is run directly
if $PROGRAM_NAME == __FILE__
  slop = Slop.parse(help: true, strict: true) do |options|
    options.bool "-w",
                 "--write",
                 "Enable writes - this defaults to false for safety.",
                 default: false

    options.bool "-v",
                 "--verbose",
                 "Log verbose output"
  end

  options = slop.to_hash
  options = options.merge(dry_run: !options[:write])

  transition = Dependabot::Transitions::BackfillCurrentStateValues.new(**options)
  transition.run
end
