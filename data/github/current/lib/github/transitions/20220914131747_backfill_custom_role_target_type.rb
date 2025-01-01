# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   # First, run the transition in dry-run mode
#   $ gudo bin/safe-ruby lib/github/transitions/20220914131747_backfill_custom_role_target_type.rb --verbose | tee -a /tmp/backfill_custom_role_target_type.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20220914131747_backfill_custom_role_target_type.rb --verbose -w | tee -a /tmp/backfill_custom_role_target_type.log
#
module GitHub
  module Transitions
    class BackfillCustomRoleTargetType < Transition
      BATCH_SIZE = GitHub.enterprise? ? 10000 : 100

      attr_reader :iterator

      def after_initialize
        min_id = @other_args[:start_id] || readonly do
          ApplicationRecord::Domain::Iam.github_sql
            .value("SELECT COALESCE(MIN(id), 0) FROM roles WHERE target_type IS NULL AND base_role_id IS NOT NULL AND owner_id IS NOT NULL")
        end

        max_id = @other_args[:end_id] || readonly do
          ApplicationRecord::Domain::Iam.github_sql
            .value("SELECT COALESCE(MAX(id), 0) FROM roles WHERE target_type IS NULL AND base_role_id IS NOT NULL AND owner_id IS NOT NULL")
        end

        batch_size = @other_args[:batch_size] || BATCH_SIZE

        @iterator = ApplicationRecord::Domain::Iam
          .github_sql_batched_between(start: min_id, finish: max_id, batch_size: batch_size)
        @iterator.add <<-SQL
          -- id must go first for batched between to work properly
          SELECT id FROM roles
          WHERE id BETWEEN :start AND :last
          AND owner_id IS NOT NULL
          AND base_role_id IS NOT NULL
          AND target_type IS NULL
        SQL
      end

      # Returns nothing.
      def perform
        GitHub::SQL::Readonly.new(iterator.batches).each do |rows|
          process(rows)
        end
      end

      private

      def process(rows)
        log "processing #{rows.count}" if verbose?

        rows.each_slice(BATCH_SIZE) do |slice|
          Role.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
            log "adding target_type `Repository` to #{slice.map { |item| item[0] }}" if verbose?
            run_batch_update slice unless dry_run?
          end
        end
      end

      def run_batch_update(rows)
        ActiveRecord::Base.connected_to(role: :writing) do

          sql = ApplicationRecord::Domain::Iam.github_sql.new "UPDATE roles SET target_type = 'Repository'"
          sql.add "WHERE id IN :ids", ids: rows.map { |item| item[0] }
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

    opts.on("--batch_size SIZE", Integer, "Number of rows to process at a time") do |size|
      options[:batch_size] = size
    end

    opts.on("-n", "--workers COUNT", Integer, "Worker count") do |count|
      options[:workers] = count
    end
  end.parse!

  options[:dry_run] = !options[:write]
  options[:workers] ||= 1

  # If choosing to run this transition as a single process, uncomment the below commands:
  transition = GitHub::Transitions::BackfillCustomRoleTargetType.new(**options)
  transition.run
end
