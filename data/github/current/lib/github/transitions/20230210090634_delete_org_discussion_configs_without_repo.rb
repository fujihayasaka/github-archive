# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition, checkout the relevant documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/running/
module GitHub
  module Transitions
    class DeleteOrgDiscussionConfigsWithoutRepo < Transition

      READ_BATCH_SIZE = GitHub.enterprise? ? 10000 : 100
      WRITE_BATCH_SIZE = GitHub.enterprise? ? 1000 : 10

      attr_reader :iterator
      attr_reader :total_updated

      def read_batch_size
        @other_args[:read_batch_size] || READ_BATCH_SIZE
      end

      def write_batch_size
        @other_args[:write_batch_size] || WRITE_BATCH_SIZE
      end

      def after_initialize
        min_id = @other_args[:start_id] || readonly do
          ApplicationRecord::Domain::Discussions.github_sql
            .value("SELECT COALESCE(MIN(id), 0) FROM organization_discussion_repositories")
        end
        max_id = @other_args[:end_id] || readonly do
          ApplicationRecord::Domain::Discussions.github_sql
            .value("SELECT COALESCE(MAX(id), 0) FROM organization_discussion_repositories")
        end

        @total_updated = 0

        @iterator = readonly do
          ApplicationRecord::Domain::Discussions
            .github_sql_batched_between(start: min_id, finish: max_id, batch_size: read_batch_size)
        end
        @iterator.add <<-SQL
          SELECT id, repository_id FROM organization_discussion_repositories
          WHERE id BETWEEN :start AND :last
          ORDER BY id ASC
        SQL
      end

      # Returns nothing.
      def perform
        dispatch { |rows| process(rows) }
      end

      def dispatch
        GitHub::SQL::Readonly.new(iterator.batches).each do |rows|
          yield rows
        end
      end

      private

      def process(rows)
        rows.each_slice(write_batch_size) do |slice|
          config_ids = slice.map { |row| row[0] }
          repo_ids = slice.map { |row| row[1] }
          config_ids_to_delete = []

          readonly do
            configs = OrganizationDiscussionConfig.where(id: config_ids)
            repos = Repository.where(id: repo_ids)

            configs.each do |config|
              config_ids_to_delete << config.id unless repos.include?(config.repository)
            end
          end

          @total_updated += run_batch_delete(config_ids_to_delete) if config_ids_to_delete.any?

          log "#{dry_run? ? "Would delete" : "Deleted"} #{total_updated} OrganizationDiscussionConfig records" if verbose?
        end
      end

      def run_batch_delete(rows)
        return rows.size if dry_run?

        ApplicationRecord::Domain::Discussions.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES, low_priority: true) do
          query = "DELETE FROM organization_discussion_repositories WHERE id IN (#{rows.join(", ")})"
          sql = ApplicationRecord::Domain::Discussions.github_sql.new query
          sql.run
          sql.affected_rows
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  options = {}
  OptionParser.new do |opts|
    opts.on("-w", "--write", "Enable writes for the transition - this defaults to false (i.e. a dry_run mode) for safety.") do |write|
      options[:write] = write
    end

    opts.on("-v", "--verbose", "Log verbose output") do |verbose|
      options[:verbose] = verbose
    end

    opts.on("--start_id ID", Integer, "ID to start processing") do |start_id|
      options[:start_id] = start_id
    end

    opts.on("--end_id ID", Integer, "ID to end processing") do |end_id|
      options[:end_id] = end_id
    end

    opts.on("--read_batch_size SIZE", Integer, "Number of rows to read at a time") do |read_batch_size|
      options[:read_batch_size] = read_batch_size
    end

    opts.on("--write_batch_size SIZE", Integer, "Number of rows to write at a time") do |write_batch_size|
      options[:write_batch_size] = write_batch_size
    end
  end.parse!

  options[:dry_run] = !options[:write]

  transition = GitHub::Transitions::DeleteOrgDiscussionConfigsWithoutRepo.new(**options)
  transition.run
end
