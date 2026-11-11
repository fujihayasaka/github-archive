# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition, checkout the relevant documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/running/
module GitHub
  module Transitions
    class RemoveOrphanedMemexTemplateRows < Transition
      class MemexTemplate < ApplicationRecord::Domain::Memexes
        self.table_name = "memex_templates"
      end

      READ_BATCH_SIZE = GitHub.enterprise? ? 10000 : 100
      WRITE_BATCH_SIZE = GitHub.enterprise? ? 1000 : 10

      attr_reader :iterator
      attr_reader :total_deleted
      attr_reader :max_id

      def read_batch_size
        @other_args[:read_batch_size] || READ_BATCH_SIZE
      end

      def write_batch_size
        @other_args[:write_batch_size] || WRITE_BATCH_SIZE
      end

      def after_initialize
        min_id = @other_args[:start_id] || readonly do
          ApplicationRecord::Domain::Memexes.connection
            .select_value(Arel.sql("SELECT COALESCE(MIN(id), 0) FROM memex_templates"))
        end
        @max_id = @other_args[:end_id] || readonly do
          ApplicationRecord::Domain::Memexes.connection
            .select_value(Arel.sql("SELECT COALESCE(MAX(id), 0) FROM memex_templates"))
        end

        @total_deleted = 0
        @iterator = readonly do
          ApplicationRecord::Domain::Memexes.github_sql_batched_between(
            start: min_id,
            finish: max_id,
            batch_size: read_batch_size,
          )
        end
        @iterator.add <<-SQL
          SELECT memex_templates.id
          FROM memex_templates
          LEFT JOIN memex_projects ON memex_templates.memex_project_id = memex_projects.id
          WHERE memex_templates.id BETWEEN :start AND :last
          AND memex_projects.id IS NULL
        SQL
      end

      # Returns nothing.
      def perform
        GitHub::SQL::Readonly.new(iterator.batches).each do |rows|
          process(rows)
        end

        verb = dry_run? ? "Would have deleted" : "Deleted"
        log("#{verb} #{total_deleted} records")
      end

      private

      def process(rows)
        rows.each_slice(write_batch_size) do |slice|
          MemexTemplate.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
            log "doing something with #{slice.map { |item| item[0] }}" if verbose?
            @total_deleted += run_batch_delete(slice)
            log "Did something through id #{slice.last[0]}. Still need to do something up to id #{max_id.to_i}" if verbose?
          end
        end
      end

      def run_batch_delete(rows)
        if verbose?
          verb = dry_run? ? "Would delete" : "Deleting"
          first_id = rows.first[0]
          last_id = rows.last[0]
          if first_id == last_id
            log("#{verb} row #{first_id}...")
          else
            log("#{verb} rows #{first_id} - #{last_id}...")
          end
        end

        return rows.size if dry_run?

        sql = Arel.sql("DELETE FROM memex_templates WHERE id IN (:ids)", ids: rows.map { |row| row[0] })

        ActiveRecord::Base.connected_to(role: :writing) do
          ApplicationRecord::Domain::Memexes.connection.delete(sql)
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  options = {}
  OptionParser.new do |opts|
    opts.on("-w", "--write", "Enable writes for the transition - this defaults to false (i.e. a dry_run mode) for safety.") do
      options[:write] = true
    end

    opts.on("-v", "--verbose", "Log verbose output") do
      options[:verbose] = true
    end

    opts.on("--start_id ID", Integer, "ID to start processing") do |id|
      options[:start_id] = id
    end

    opts.on("--end_id ID", Integer, "ID to end processing") do |id|
      options[:end_id] = id
    end

    opts.on("--read_batch_size SIZE", Integer, "Number of rows to read at a time") do |size|
      options[:read_batch_size] = size
    end

    opts.on("--write_batch_size SIZE", Integer, "Number of rows to write at a time") do |size|
      options[:write_batch_size] = size
    end
  end.parse!

  options[:dry_run] = !options[:write]

  transition = GitHub::Transitions::RemoveOrphanedMemexTemplateRows.new(**options)
  transition.run
end
