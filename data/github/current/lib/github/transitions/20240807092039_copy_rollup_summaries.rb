# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    # This transition copies records from rollup_summaries into notification_summaries.
    # The main difference between the two is that notification_summaries has timestamp columns,
    # apart of that they have the same data.
    #
    # It doesn't copy all existing rollup summaries, only those that are referenced from the
    # tables notification_entries and saved_notification_entries.
    class CopyRollupSummaries < Base
      # Minimum version of the old RollupSummary model. This is used by the
      # transition to read data and copy it to NotificationSummary
      class RollupSummary < ApplicationRecord::Domain::Notifications
        class Coder < Coders::Base
          extend T::Sig
          extend T::Helpers

          data_accessors :authors,
            :items,
            :title,
            :creator_id,
            :issue_state,
            :issue_number,
            :number,
            :milestone_slug,
            :is_pull_request,
            :release_tag,
            :check_suite_conclusion,
            :updated_at,
            :is_draft

          sig { params(options: T::Hash[T.untyped, T.untyped]).void }
          def initialize(options = {})
            super options

            data[:authors] ||= {}
            data[:items] ||= {}
            data[:is_pull_request] ||= false
          end

          sig { returns(T.nilable(Time)) }
          def updated_at
            time data[:updated_at]
          end

          sig { returns(T::Boolean) }
          def is_pull_request
            data[:is_pull_request].to_s.match?(/(1|true)/)
          end
        end

        include Coders::CodableColumn
        serialize_with_coder :raw_data, Coder
      end

      # This transition uses a custom iterator because it needs to iterate over two tables,
      # notification_entries and saved_notification_entries, and it iterates not over the main ID
      # but the reference ID: :summary_id
      # Apart of that it uses the same logic as GitHub::Transitions::Iterators::DatabaseTable to
      # define parallelization and batch size
      class CustomIterator < GitHub::Transitions::Iterators::Base
        extend T::Sig
        extend T::Helpers

        # Default number of workers to use for parallelization. Intends to
        # be a safe default for most transitions.
        DEFAULT_WORKER_COUNT = T.let(4, Integer)

        # Maximum number of workers to use for parallelization. Intends to
        # match the number of unicorn workers, configured via
        # `GH_UNICORN_WORKER_COUNT`.
        MAX_WORKER_COUNT = T.let(16, Integer)

        # Default number of rows to read at a time.
        DEFAULT_READ_BATCH_SIZE = T.let(
          GitHub.enterprise? ? 10000 : 100, Integer
        )

        # Maximum number of rows to read at a time. This is limited
        # to a maximum of 16KB per batch. That limit is coming form
        # Divvy's limitation to pass more from the main to the worker
        # processes. We are passing `Integer` values as identifiers,
        # which are 8 bytes each. So we can pass 2048 identifiers.
        # We leave some buffer and limit it to 1800.
        MAX_READ_BATCH_SIZE = T.let(
          GitHub.enterprise? ? 10000 : 1800, Integer
        )

        # Default number of rows to process at a time.
        DEFAULT_PROCESS_BATCH_SIZE = T.let(
          GitHub.enterprise? ? 1000 : 10, Integer
        )

        # Maximum number of rows to process at a time.
        MAX_PROCESS_BATCH_SIZE = T.let(
          GitHub.enterprise? ? 1000 : 100, Integer
        )

        sig { override.void }
        def prepare_iteration
          ActiveRecord::Base.connection_handler.clear_all_connections!(:all)
        end

        sig { override.void }
        def prepare_worker
          ActiveRecord::Base.connection_handler.clear_all_connections!(:all)
        end

        sig do
          override.params(
            block: T.proc.params(items: GitHub::Transitions::Iterators::Identifiers).void
          ).void
        end
        def each_identifiers_batch(&block)
          min_id = load_min_id
          max_id = load_max_id
          iteration_count = 0
          rows_count = 0

          log "iterating with min_id=#{min_id} max_id=#{max_id} read_batch_size=#{read_batch_size} process_batch_size=#{process_batch_size}"

          iterators = [
            build_iterator(table: Newsies::NotificationEntry.table_name, start: min_id, finish: max_id),
            build_iterator(table: Newsies::SavedNotificationEntry.table_name, start: min_id, finish: max_id),
          ].each do |iterator|
            last_id = T.let(0, T.nilable(Numeric))
            iterator.each do |batch|
              batch.each_slice(process_batch_size) do |ids|
                yield ids
              end

              iteration_count += 1
              rows_count += batch.size
              last_id = batch.last
              # Log every 10 * read_batch_size iterations, so we don't log
              # too much. With the default read batch size, this means
              # we log every 1000th iteration, which is every 100k rows.
              if iteration_count % (read_batch_size * 10) == 0
                log "progress iterations=#{iteration_count} rows=#{rows_count} last_id=#{last_id}"
              end
            end

            log "complete total_iterations=#{iteration_count} total_rows=#{rows_count} last_id=#{last_id}"
          end
        end

        sig do
          override
            .params(identifiers: GitHub::Transitions::Iterators::Identifiers)
            .returns(GitHub::Transitions::Iterators::Items)
        end
        def build_items_for_batch(identifiers)
          records = ActiveRecord::Base.connected_to(role: :reading) do
            RollupSummary.where(id: identifiers).pluck(:id, :list_type, :list_id, :thread_key, :raw_data).map do |values|
              # associate each value with its attribute name in a Hash
              Hash[[:id, :list_type, :list_id, :thread_key, :raw_data].zip(values)]
            end
          end

          records.reduce({}) do |items, record|
            items[record[:id]] = record
            items
          end
        end

        sig { override.returns(Integer) }
        def worker_count
          if GitHub.enterprise?
            1
          else
            value = arguments[:workers] || DEFAULT_WORKER_COUNT
            [value, MAX_WORKER_COUNT].min
          end
        end

        private

        sig { returns(Integer) }
        def load_min_id
          start_id || ActiveRecord::Base.connected_to(role: :reading) do
            RollupSummary.minimum(:id) || 0
          end
        end

        sig { returns(Integer) }
        def load_max_id
          end_id || ActiveRecord::Base.connected_to(role: :reading) do
            RollupSummary.maximum(:id) || 0
          end
        end

        sig { params(table: String, start: Numeric, finish: Numeric).returns(GitHub::QueryBatching::IteratorBuilder[T::Array[Numeric]]) }
        def build_iterator(table:, start:, finish:)
          GitHub::QueryBatching::IteratorBuilder[T::Array[Numeric]].new(start: start, finish: finish, batch_size: read_batch_size) do |iteration|
            results = ActiveRecord::Base.connected_to(role: :reading) do
              arel_bindings = iteration.cursor.arel_bindings.merge(table: Arel.sql(table))
              ApplicationRecord::Domain::NotificationsEntries.connection.select_rows(Arel.sql(<<~SQL, **arel_bindings))
                SELECT DISTINCT(en.summary_id)
                FROM :table AS en
                WHERE en.summary_id BETWEEN :lower_id AND :upper_id
                ORDER BY en.summary_id
                LIMIT :limit
              SQL
            end

            iteration << results.flatten
          end
        end

        # Returns the ID of the rollup summary to start processing.
        sig { returns(T.nilable(Integer)) }
        def start_id
          arguments[:start_id]
        end

        # Returns the ID of the rollup summary to end processing.
        sig { returns(T.nilable(Integer)) }
        def end_id
          arguments[:end_id]
        end

        # Returns the number of rows to read at a time.
        sig { returns(Integer) }
        def read_batch_size
          value = arguments[:read_batch_size] || DEFAULT_READ_BATCH_SIZE
          [value, MAX_READ_BATCH_SIZE].min
        end

        # Returns the number of rows to process at a time.
        sig { returns(Integer) }
        def process_batch_size
          value = arguments[:process_batch_size] || DEFAULT_PROCESS_BATCH_SIZE
          [value, MAX_PROCESS_BATCH_SIZE].min
        end
      end

      iterate_over CustomIterator

      sig { override.void }
      def perform
        return unless GitHub.multi_tenant_enterprise? || GitHub.enterprise?
        super
      end

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        existing_records = ActiveRecord::Base.connected_to(role: :reading) do
          Set.new(NotificationSummary.where(id: items.keys).pluck(:id).flatten)
        end

        inserts = items.reject { |key, _| existing_records.member?(key) }

        log "creating records in notification_summaries inserts=#{inserts.size} batch_size=#{items.size} dry_run=#{dry_run?}"

        return if dry_run?

        write_to(model_class: NotificationSummary) do
          # We are only inserting new records
          # but just in case there is a race condition we keep #upsert_all
          NotificationSummary.upsert_all(inserts.values) # rubocop:disable GitHub/UpsertAll
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV)

  GitHub::Transitions::CopyRollupSummaries.new(args).run
end
