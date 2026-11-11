# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   # First, run the transition in dry-run mode
#   $ gudo bin/safe-ruby lib/github/transitions/20211103181137_backfill_token_scan_result_first_location.rb --verbose | tee -a /tmp/backfill_token_scan_result_first_location.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20211103181137_backfill_token_scan_result_first_location.rb --verbose -w | tee -a /tmp/backfill_token_scan_result_first_location.log
#
module GitHub
  module Transitions
    class BackfillTokenScanResultFirstLocation < Transition
      BATCH_SIZE = GitHub.enterprise? ? 1000 : 100

      def after_initialize

        @batch_size = readonly { @other_args[:batch_size] || BATCH_SIZE }
        @start_id = readonly { @other_args[:start_id] || 0 }
        @last_id = readonly { @other_args[:end_id] || ApplicationRecord::TokenScanningService.github_sql.value("SELECT COALESCE(MAX(id), 0) FROM token_scan_results") }

      end

      def perform
        # We are using a different style of batching here than is recommended in
        # https://thehub.github.com/engineering/products-and-services/dotcom/migrations-and-transitions/transitions/#use-deterministic-small-queries-for-updates
        # mostly because, afaik, we use row changed replication not statement based replication - so using in(...) for the update on the master doesn't
        # change what or how the rows are replicated.
        start_transition = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        batch_start_id = @start_id
        batch_end_id = batch_start_id + @batch_size
        if batch_end_id > @last_id
          batch_end_id = @last_id
        end

        current_batch = 1
        total_rows = 0

        log "starting transition with start_id #{@start_id} through last_id #{@last_id}"
        while batch_start_id <= @last_id
          total_rows += process(batch_start_id, batch_end_id)
          log "finished batch #{current_batch}... from #{batch_start_id} to #{batch_end_id}; updated #{total_rows} so far"

          # move cursor to next batch
          current_batch += 1
          batch_start_id = batch_end_id + 1
          batch_end_id = batch_start_id + @batch_size - 1
          if batch_end_id > @last_id
            batch_end_id = @last_id
          end

        end
        finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        log "transition complete; took #{(finish - start_transition) / 60.0} minutes to update #{total_rows} row(s) in #{current_batch} batche(s)"
      end

      private

      def process(start_id, end_id)
        return 0 if dry_run?
        rc = T.let(0, T.untyped)
        TokenScanResult.throttle_writes_with_retry(max_retry_count: 3) do
          # rows which fail the nested loop inner join will remain null/false, which is the behavior we want.
          sql = <<-SQL
          UPDATE token_scan_results tsr
          INNER JOIN (
            SELECT
              token_scan_result_id,
              MIN(l.id) AS first_location
            FROM token_scan_result_locations_v2 l
            WHERE l.ignore_token = 0
            AND l.token_scan_result_id >= ? AND l.token_scan_result_id <= ?
            GROUP BY token_scan_result_id
            ORDER BY token_scan_result_id
          ) as tsrl ON tsrl.token_scan_result_id = tsr.id
          SET tsr.first_location_id = tsrl.first_location,
            tsr.has_valid_locations = true
          WHERE tsr.id >= ? AND tsr.id <= ?
          SQL
          sql = ActiveRecord::Base::sanitize_sql([sql, start_id, end_id, start_id, end_id])
          rc = TokenScanResult.connection.update(sql)
        end
        rc
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
  end.parse!

  options[:dry_run] = !options[:write]

  transition = GitHub::Transitions::BackfillTokenScanResultFirstLocation.new(**options)
  transition.run

end
