# typed: false
# frozen_string_literal: true

require "application_record/base/github_sql_builder"

module GHES
  module DB
    module ParallelMigrator
      MIGRATION_SUCCESSFUL = 0
      MIGRATION_DEPENDENCY_UNMET = 1
      MIGRATION_ERROR = 2

      @@error_mutex = Mutex.new
      @@migration_errors = {}
      @@debug = false

      def self.run(metadata_json, worker_count, debug = false)
        puts "Running migrations with a worker count of #{worker_count}}"
        @@debug = debug

        instructions = InstructionSerializer.build_migration_instructions(metadata_json)

        if @debug
          puts "** Migration Metadata Start **"
          puts instructions
          puts "** Migration Metadata End **"
        end

        # get the current state of the migrations according to active record
        migration_map = get_active_record_migration_state

        root = deserialize_instructions(instructions, migration_map)
        root.completed = true

        migration_threads = []
        migration_queue = Queue.new
        result_queue = Queue.new
        result_queue.push({
                            migration_id: root.name,
                            node: root,
                            status: MIGRATION_SUCCESSFUL,
                            thread_id: 0,
                          })

        thread_specific_execution_logs = []
        (1..worker_count).each do |thread_num|
          migration_threads << Thread.new do # rubocop:disable GitHub/ThreadUse
            puts ">> Thread #{thread_num} starting"
            execution_log = WorkerThreadExecutionLog.new(thread_num)
            thread_specific_execution_logs << execution_log
            migration_worker(thread_num, migration_queue, result_queue, execution_log)
          end
        end
        puts ">> Migration threads started"

        feeder_thread = Thread.new do # rubocop:disable GitHub/ThreadUse
          feeder_worker(migration_queue, result_queue, migration_map)
        end
        puts ">> Feeder thread started"

        migration_threads.each(&:join)
        puts ">> Migration threads joined"
        feeder_thread.exit
        puts ">> Feeder thread stopped"

        thread_specific_execution_logs.each do |execution_log|
          execution_log.output_execution_log
        end

        # Call record_environment_once at the end to set the environment key in the internal_metadata table
        CustomMigrationContext.new(Rails.root.join("db", "migrate")).record_environment_once

        # check to see if any errors were encountered during the migration process
        if !@@migration_errors.empty?
          raise "Migrations failed with errors: #{@@migration_errors}"
        end
      end

      def self.deserialize_instructions(instructions, migration_map)
        # Build a map of migration IDs that we have metadata for
        # Later we will validate that all "down" state migrations have an entry in this map if not we will refuse to run the job
        migration_metadata_entries = {}
        nodes = {}

        instructions.each do |node_definition|
          children = node_definition[:children]
          dependencies = node_definition[:dependencies]
          kind = node_definition[:kind]
          migration_id = node_definition[:id]

          # add the migration id to the metadata entry map
          migration_metadata_entries[migration_id] = true

          # Fetch, or create, the node for processing.
          if nodes.has_key?(migration_id)
            node = nodes[migration_id]
          else
            node = Node.new(migration_id, kind)
            nodes[migration_id] = node
          end

          # Link the dependencies. Create them if needed.
          dependencies&.each do |dependency|
            if nodes.has_key?(dependency)
              dependency_node = nodes[dependency]
            else
              dependency_node = Node.new(dependency, "")
              nodes[dependency] = dependency_node
            end

            # if the dependency is in an up state, mark it as completed
            # if the dependency was not returned from active record it will be nil, this means we have instructions for a migration that was likely removed
            dependancy_state = migration_map[dependency_node.name]
            if dependancy_state.nil? || dependancy_state == "up"
              dependency_node.completed = true
            end
            node.add_dependency(dependency_node)
          end

          # Link the children. Create them if needed.
          children&.each do |child|
            if nodes.has_key?(child)
              child_node = nodes[child]
            else
              child_node = Node.new(child, "")
              nodes[child] = child_node
            end

            # if the child is in an up state, mark it as completed
            # if the child was not returned from active record it will be nil, this means we have instructions for a migration that was likely removed
            child_state = migration_map[child_node.name]
            if child_state.nil? || child_state == "up"
              child_node.completed = true
            end
            node.add_next(child_node)
          end
        end

        if !nodes.has_key?("root")
          raise "No root node found in instructions"
        end

        down_migrations_missing_metadata = []
        migration_map.each do |key, value|
          if value == "down" && !migration_metadata_entries.has_key?(key)
            down_migrations_missing_metadata << key
          end
        end

        if down_migrations_missing_metadata.length > 0
          migration_ids = down_migrations_missing_metadata.join(", ")
          raise "Migration(s) #{migration_ids} are in a down state but have no metadata entry"
        end

        nodes["root"]
      end

      def self.get_active_record_migration_state
        # Build a map from the current state of the migrations
        migration_context = CustomMigrationContext.new(Rails.root.join("db", "migrate"))
        mig_stats = migration_context.migrations_status

        # build a map of migrations and their current state according to active record
        # this will be used later to decide what migrations should be marked as complete
        migration_map = {}
        mig_stats.each do |migration|
          migration_id = migration[1].to_i
          migration_status = migration[0]
          migration_map[migration_id] = migration_status
        end

        if @@debug
          pp migration_map
        end

        migration_map
      end

      def self.feeder_worker(migration_queue, result_queue, migration_map)
        loop do
          # When there are no more migrations in a "down" state, we are done. Close the queues and break
          if !migration_map.has_value?("down")
            puts "all expected migrations have been run - closing queues and finishing"
            migration_queue.close
            result_queue.close
            break
          end

          result = result_queue.pop

          case result[:status]
          when MIGRATION_SUCCESSFUL
            puts ">> INFO: Thread #{result[:thread_id]} successfully performed migration ID #{result[:migration_id]}"
            puts ">> #{result.except(:node)}" if @@debug

            # mark the migration as now being in an "up" state since we ran it succesfully.
            migration_map[result[:migration_id]] = "up"

            if !result[:node].next.empty?
              result[:node].next.each do |child|
                if !child.has_been_queued?
                  puts ">> DEBUG: Pushing #{child.name}, child of #{result[:migration_id]}, into migration queue" if @@debug
                  child.has_been_queued = true
                  migration_queue.push(child)
                end
              end
            end
          when MIGRATION_DEPENDENCY_UNMET
            puts ">> WARN: Thread #{result[:thread_id]} could not performed migration ID #{result[:migration_id]} due to unmet dependencies" if @@debug
            migration_queue.push(result[:node])
          when MIGRATION_ERROR
            puts ">> ERROR: Thread #{result[:thread_id]} failed to perform migration ID #{result[:migration_id]}"
            migration_queue.close
            result_queue.close
            break
          end
        end
      end

      def self.migration_worker(thread_id, migration_queue, result_queue, execution_log, always_log: false, migration_context: CustomMigrationContext.new(Rails.root.join("db", "migrate")))

        loop do
          if migration_queue.empty? && migration_queue.closed?
            puts ">> DEBUG: Thread #{thread_id} exiting due to closed queue." if @@debug
            break
          end

          thread_wait_start_time = Time.now
          t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          migration = migration_queue.pop
          if migration.nil?
            puts ">> DEBUG: Thread #{thread_id} caught nil. Migration queue likely closed." if @@debug
            next
          end
          thread_wait_end_time = Time.now
          t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          # If the total time spent waiting for a job from the queue is greater than a second add it as a log entry
          thread_wait_total_time = t1 - t0
          if thread_wait_total_time > 1.0 || always_log
            execution_log.add_execution_detail("blocked", thread_wait_start_time, thread_wait_end_time, thread_wait_total_time)
          end

          puts ">> DEBUG: Thread #{thread_id} processing ID #{migration.name}" if @@debug

          dependencies_met = true
          migration.dependencies.each do |dependency|
            if !dependency.completed?
              puts ">> DEBUG: Migration #{migration.name} has incomplete dependency #{dependency.name}. Will not process yet." if @@debug
              dependencies_met = false
              result_queue.push({
                                  migration_id: migration.name,
                                  node: migration,
                                  status: MIGRATION_DEPENDENCY_UNMET,
                                  thread_id: thread_id,
                                })
            end
          end
          next if !dependencies_met

          migration_status = MIGRATION_SUCCESSFUL
          migration_start_time = Time.now
          t3 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          begin
            # If a migration in our queue is already in an "up" state, skip it here and treat it as a success case.
            if !migration.completed?
              puts "Running Migration Name: #{migration.name}"
              migration_context.run(:up, migration.name)
            end
          rescue => e
            # check to see if the error is due to a missing migration. If so, let's bury it and continue
            if e.message.include?("No migration with version number")
              puts ">> WARN: #{migration.name} is being skipped because it was not found - moving on"
              migration_status = MIGRATION_SUCCESSFUL
              migration.completed = true
            else
              add_migration_error(migration.name, e.message)
              migration_status = MIGRATION_ERROR
            end
          else
            migration.completed = true
          end
          migration_end_time = Time.now
          t4 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          execution_time = t4 - t3
          execution_log.add_execution_detail(migration.name, thread_wait_start_time, thread_wait_end_time, thread_wait_total_time)

          result_queue.push({
                              migration_id: migration.name,
                              migration_time: execution_time,
                              node: migration,
                              status: migration_status,
                              thread_id: thread_id,
                            })
        end
      end

      def self.add_migration_error(migration_name, error_message)
        @@error_mutex.synchronize do
          @@migration_errors[migration_name] = error_message
        end
      end

      class Node
        attr_reader :dependencies, :kind, :name, :next

        def initialize(name, kind)
          @completed = false
          @completed_mutex = Mutex.new
          @has_been_queued = false
          @has_been_queued_mutex = Mutex.new
          @dependencies = []
          @kind = kind
          @name = name
          @next = []
        end

        def add_dependency(node)
          @dependencies.push(node)
        end

        def add_next(node)
          @next.push(node)
        end

        def completed?
          @completed_mutex.synchronize do
            return @completed
          end
        end

        def completed=(bool)
          @completed_mutex.synchronize do
            @completed = bool
          end
        end

        def has_been_queued?
          @has_been_queued_mutex.synchronize do
            return @has_been_queued
          end
        end

        def has_been_queued=(bool)
          @has_been_queued_mutex.synchronize do
            @has_been_queued = bool
          end
        end
      end

      class WorkerThreadExecutionLog
        def initialize(thread_id)
          @thread_id = thread_id
          @records = []
        end

        attr_reader :records

        def add_execution_detail(operation_name, start_time, end_time, total_time)
          record = { thread_id: @thread_id, operation: operation_name, start_time: start_time, end_time: end_time, total_time: total_time }
          @records << record
        end

        def output_execution_log
          if !@records.empty?
            puts ""
            puts "Thread #{@thread_id} Execution Log"
            puts "Operation | Start Time | End Time | Duration"
            @records.each do |record|
              puts "#{record[:operation]} | #{record[:start_time]} | #{record[:end_time]} | #{sprintf("%.6f", record[:total_time])}"
            end
            puts ""
          end
        end
      end

      # For db:migrate:parallel we want to avoid writing to the internal_metadata table multiple times,
      # because with each thread writing to the table, we could end up with multiple entries.
      #
      # ActiveRecord::Migrator#record_environment is the method that writes to the internal_metadata table. (It adds the environment key to the internal_metadata table)
      # ActiveRecord::Migrator#run_without_lock calls ActiveRecord::Migrator#record_environment so we are overriding it.
      #
      # The existing code flow in rails/rails is as follows:
      # ActiveRecord::MigrationContext#run -> ActiveRecord::Migrator#run -> (PRIVATE) ActiveRecord::Migrator#run_without_lock -> (PRIVATE) ActiveRecord::Migrator#record_environment
      #
      # Below we are overriding the ActiveRecord::Migrator#run_without_lock method so that we can avoid calling ActiveRecord::Migrator#record_environment method.

      # Overriding the default ActiveRecord::MigrationContext#run method so that we can call our custom Migrator class with overridden run_without_lock method
      class CustomMigrationContext < ActiveRecord::MigrationContext
        def run(direction, target_version)
          puts "**Running CustomMigrationContext#run"
          CustomMigrator.new(direction, migrations, schema_migration, internal_metadata, target_version).run
        end

        # This is replacement for ActiveRecord::Migrator#record_environment, which will be called in self.run method once after running all migrations.
        # Below in CustomMigrator#run_without_lock we not calling record_environment method.
        def record_environment_once
          puts "**Running CustomMigrationContext#record_environment_once"
          internal_metadata.create_table
          internal_metadata[:environment] = ActiveRecord::Tasks::DatabaseTasks.migration_connection.pool.db_config.env_name
        end
      end

      class CustomMigrator < ActiveRecord::Migrator
        def run_without_lock
          puts "**Running custom run_without_lock"
          migration = migrations.detect { |m| m.version == @target_version }
          raise ActiveRecord::UnknownMigrationVersionError.new(@target_version) if migration.nil?

          ## The commented part is the original code that we are overriding
          # record_environment

          execute_migration_in_transaction(migration)
        end

        private :run_without_lock
      end
    end
  end
end
