# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   # First, run the transition in dry-run mode
#   $ gudo bin/safe-ruby lib/github/transitions/20220609193838_set_key_link_is_alphanumeric_to_false.rb --verbose | tee -a /tmp/set_key_link_is_alphanumeric_to_false.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20220609193838_set_key_link_is_alphanumeric_to_false.rb --verbose -w | tee -a /tmp/set_key_link_is_alphanumeric_to_false.log
#
module GitHub
  module Transitions
    class SetKeyLinkIsAlphanumericToFalse < Transition
      BATCH_SIZE = GitHub.enterprise? ? 10000 : 100

      def after_initialize
        min_id = @other_args[:start_id] || readonly do
          ApplicationRecord::Collab.github_sql
            .value("SELECT COALESCE(MIN(id), 0) FROM key_links")
        end
        max_id = @other_args[:end_id] || readonly do
          ApplicationRecord::Collab.github_sql
            .value("SELECT COALESCE(MAX(id), 0) FROM key_links")
        end
        batch_size = @other_args[:batch_size] || BATCH_SIZE

        @iterator = ApplicationRecord::Collab
          .github_sql_batched_between(start: min_id, finish: max_id, batch_size: batch_size)
        @iterator.add <<-SQL
          SELECT id FROM key_links
          WHERE id BETWEEN :start AND :last
        SQL
      end

      def perform
        GitHub::SQL::Readonly.new(@iterator.batches).each do |rows|
          process(rows)
        end
      end

      private

      def process(rows)
        log "Processing #{rows.count} rows" if verbose?
        return if rows.empty?
        ids = rows.flatten
        ids.each do |id|
          log "Processing row #{id}" if verbose?
          next if dry_run?
          ActiveRecord::Base.connected_to(role: :writing) do
            KeyLinks::Public::Throttler.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
              ApplicationRecord::Collab.github_sql.run(<<-SQL, id: id)
                UPDATE key_links k
                SET k.is_alphanumeric = 0
                WHERE k.id = :id
              SQL
            end
          end
          log "Done processing row #{id}" if verbose?
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: ruby #{__FILE__} [options]"

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
  transition = GitHub::Transitions::SetKeyLinkIsAlphanumericToFalse.new(**options)
  transition.run
end
