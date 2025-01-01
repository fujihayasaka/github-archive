# typed: strict
# frozen_string_literal: true

require "divvy"

module GitHub
  module Transitions
    # Base class for transitions using iterators.
    #
    # This class is used for any type of transition. It is optimized for
    # the iteration use case where the transition is about iterating over
    # a small or large number of items. For that use case, different iterators
    # can be used or implement to support different sources of items (e.g.
    # MySQL database tables, Cosmos DB collections, CSV files, etc).
    #
    # Example for basic, minimal transition:
    #
    #    class SomeRandomTransition < Base
    #      def perform
    #        # do my thing, possibly using `arguments` (to process
    #        # CLI arguments) and `write_to` (to write to MySQL tables)
    #      end
    #    end
    #
    # The most common use case is to iterate over MySQL database tables.
    # Here's an example how to use the database table iterator:
    #
    # Example to backfill a column for some records on the same table:
    #
    #    class SomeExampleTransition < Base
    #      class SomeModel < ApplicationRecord::Domain::SomeDomain
    #        self.table_name = :some_table
    #      end
    #
    #      iterate_over :database_table, params: {
    #        model_class: SomeModel,
    #        conditions: "`some_old_column` IS NOT NULL"
    #      }
    #
    #      def process_batch(items)
    #        ids = items.keys
    #
    #        if dry_run?
    #          log "would update #{ids.size} records"
    #        else
    #          write_to(model_class: SomeModel) do
    #            SomeModel.where(id: ids).update_all(
    #              some_new_column: Arel.sql("some_old_column")
    #            )
    #          end
    #        end
    #      end
    #    end
    #
    # Example to backfill a column for some records on a different table:
    #
    #    class SomeExampleTransition < Base
    #      class SomeModel < ApplicationRecord::Domain::SomeDomain
    #        self.table_name = :some_table
    #      end
    #
    #      iterate_over :database_table, params: {
    #        model_class: SomeModel,
    #        conditions: "`some_old_column` IS NOT NULL"
    #      }
    #
    #      class AnotherModel < ApplicationRecord::Domain::SomeDomain
    #        self.table_name = :another_table
    #      end
    #
    #      def process_batch(items)
    #        ids = items.keys
    #
    #        scope = AnotherModel.where(some_model_id: ids)
    #        scope = scope.joins(<<~SQL)
    #          INNER JOIN `some_table`
    #            ON `another_table`.`some_model_id` = `some_table`.`id`
    #        SQL
    #
    #        if dry_run?
    #          log "would update #{ids.size} records"
    #        else
    #          write_to(model_class: AnotherModel) do
    #            scope.update_all(<<~SQL)
    #              `another_table`.`some_new_column` = `some_table`.`some_old_column`
    #            SQL
    #          end
    #        end
    #      end
    #    end
    #
    # A Rubocop linter will make sure all writes are using the `write_to`
    # method. This ensures that throttling and connection switching is applied
    # correctly.
    #
    # Next to using methods like `verbose?` and `dry_run?`, a transition
    # subclass can overwrite `after_initialize` to do internal setup or
    # validation of arguments.
    #
    # Arguments are available via the `arguments` accessor, returning an
    # instance of `Arguments` containing parsed CLI input. The way to use
    # arguments like this:
    #
    #    arguments = GitHub::Transitions::Arguments.parse(ARGV)
    #    GitHub::Transitions::SomeRandomTransition.new(arguments).run
    #
    # See the documentation of the `Arguments` class for more details.
    class Base
      extend T::Helpers

      include Divvy::Parallelizable

      abstract!

      sig { returns(T.nilable(Iterators::Base)) }
      attr_reader :iterator
      class_attribute :_iterator

      sig { returns(Arguments) }
      attr_reader :arguments

      sig do
        params(
          iterator_type_or_class: T.any(Symbol, T.class_of(Iterators::Base)),
          params: T::Hash[Symbol, T.untyped]
        ).void
      end
      def self.iterate_over(iterator_type_or_class, params: {})
        iterator_class = if iterator_type_or_class.is_a?(Symbol)
          class_name = iterator_type_or_class.to_s.classify
          full_class_name = "GitHub::Transitions::Iterators::#{class_name}"
          T.cast(full_class_name.constantize, T.class_of(Iterators::Base))
        else
          iterator_type_or_class
        end

        self._iterator = iterator_class.new(**params)
      end

      sig { params(arguments: Arguments).void }
      def initialize(arguments = Arguments.new)
        @arguments = T.let(arguments, Arguments)
        @iterator = T.let(self._iterator, T.nilable(Iterators::Base))

        iterator&.transition = self
        iterator&.arguments = arguments

        init_context

        wrap { after_initialize }

        iterator&.validate_arguments

        log "transition=#{name} created"
        log "arguments=#{arguments}"
      end

      sig { overridable.void }
      def after_initialize; end

      sig { void }
      def run
        log "transition running"

        wrap(with_executor: !parallel?) do
          perform
        end

        log "transition finished"
      end

      sig { overridable.void }
      def perform
        log "configuration dry-run=#{dry_run?} parallel=#{parallel?} workers=#{worker_count}"

        if parallel?
          Divvy::Master.new(self, worker_count, false).run
        else
          dispatch { |identifiers| process(identifiers) }
        end
      end

      # Method required by Divvy::Parallelizable
      sig do
        params(
          block: T.proc.params(identifiers: Iterators::Identifiers).void
        ).void
      end
      def dispatch(&block)
        iterator = T.must_because(self.iterator) { "no iterator set" }

        ActiveRecord::Base.connected_to(role: :reading) do
          iterator.each_identifiers_batch do |identifiers|
            yield identifiers
          end
        end
      end

      # Method required by Divvy::Parallelizable
      sig { params(worker: Divvy::Worker).void }
      def before_fork(worker)
        iterator = T.must_because(self.iterator) { "no iterator set" }
        iterator.prepare_iteration
      end

      # Method required by Divvy::Parallelizable
      sig { params(worker: Divvy::Worker).void }
      def after_fork(worker)
        iterator = T.must_because(self.iterator) { "no iterator set" }
        iterator.prepare_worker
      end

      # Method required by Divvy::Parallelizable
      sig { params(identifiers: Iterators::Identifiers).void }
      def process(identifiers)
        iterator = T.must_because(self.iterator) { "no iterator set" }

        wrap do
          items = iterator.build_items_for_batch(identifiers)
          process_batch(items)
        end
      end

      sig { overridable.params(items: Iterators::Items).void }
      def process_batch(items); end

      sig { returns(T::Boolean) }
      def dry_run?
        arguments[:dry_run]
      end

      sig { returns(T::Boolean) }
      def verbose?
        arguments[:verbose]
      end

      sig { returns(T::Boolean) }
      def parallel?
        worker_count > 1
      end

      sig { returns(Integer) }
      def worker_count
        iterator&.worker_count || 1
      end

      sig do
        params(
          message: String,
          payload: T::Hash[T.any(Symbol, String), T.untyped]
        ).void
      end
      def log(message, payload = {})
        return if GitHub::AppEnvironment.test?

        logger.tagged("transition" => name) do
          GitHub.logger.info(message, payload)
        end
      end

      sig { returns(String) }
      def name
        # uses the first parameter passed to `script/run-automated-transition`
        File.basename($0, ".rb")
      end

      # Returns the Migration ID (ActiveRecord ID) of the transition.
      # The transition ID is derived from the filename of the transition class. For example, 20220101000000_some_transition.rb will return 20220101000000.
      # This method is primarily used in GitHub::Transitions::Iterators::DatabaseTable.ghes_worker_count
      sig { returns(T.nilable(Integer)) }
      def migration_id
        path = T.must(Object.const_source_location(self.class.to_s)).first
        return if path.blank?

        match = path.match(/(\d+)_\S+\.rb\z/)
        return if match.nil?
        match[1].to_i
      end

      protected

      # Helper method for writing to the database. It switches to the writing
      # connection for the given `model_class`, enables throttling with retries,
      # and yields to the block.
      sig do
        params(
          model_class: T.class_of(ApplicationRecord::Base),
          block: T.proc.void
        ).void
      end
      def write_to(model_class:, &block)
        raise "do not write in dry-run mode" if dry_run?
        if ActiveRecord::Base.single_database_cluster?
          ActiveRecord::Base.connected_to(role: :writing) do
            model_class.throttle_with_retry(
              max_retry_count: 5
            ) do
              yield
            end
          end
        else
          model_class.connection_class_for_self.connected_to(role: :writing) do
            model_class.throttle_with_retry(
              max_retry_count: 5
            ) do
              yield
            end
          end
        end
      end

      private

      sig { void }
      def init_context
        context = {
          app: "github-transitions",
          transition: name,
        }

        Failbot.push context
        GitHub.context.push context
        Audit.context.push context

        class_name = self.class.name&.underscore

        GitHub.context.push(remote_call_source_datadog_tags: [
          "source_type:transition",
          "transition:#{class_name}",
          "source:transition-#{class_name}",
        ])
      end

      sig { returns(SemanticLogger::Logger) }
      def logger
        GitHub.logger
      end

      # Helper method for wrapping "user" code from subclasses
      sig { params(with_executor: T::Boolean, block: T.proc.void).void }
      def wrap(with_executor: true, &block)
        wrapped = lambda do
          GH::Context.enabled do
            logger.tagged("transition" => name) do
              ActiveRecord::Base.connected_to(role: :reading) do
                enforce_read_only_if_dry_run do
                  yield
                end
              end
            end
          end
        end

        if with_executor
          Rails.application.executor.wrap(&wrapped)
        else
          wrapped.call
        end
      end

      sig { params(block: T.proc.void).void }
      def enforce_read_only_if_dry_run(&block)
        if dry_run? && @original_read_only.nil?
          @original_read_only = T.let(GitHub.read_only?, T.nilable(T::Boolean))
          GitHub.read_only = true
        end

        yield
      ensure
        if !@original_read_only.nil?
          GitHub.read_only = @original_read_only
        end
      end
    end
  end
end
