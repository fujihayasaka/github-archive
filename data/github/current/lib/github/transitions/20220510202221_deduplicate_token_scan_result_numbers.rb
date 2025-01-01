# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"
# Uncomment if you want to use Divvy
# require "divvy"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   # First, run the transition in dry-run mode
#   $ gudo bin/safe-ruby lib/github/transitions/20220510202221_deduplicate_token_scan_result_numbers.rb --verbose | tee -a /tmp/deduplicate_token_scan_result_numbers.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20220510202221_deduplicate_token_scan_result_numbers.rb --verbose -w | tee -a /tmp/deduplicate_token_scan_result_numbers.log
#
module GitHub
  module Transitions
    class DeduplicateTokenScanResultNumbers < Transition
      BATCH_NUM_DUPLICATES = GitHub.enterprise? ? 10000 : 100
      BATCH_UPDATE_SIZE = 100

      attr_reader :repo_id

      def after_initialize
        @repo_id = @other_args[:repo_id] || -1
      end

      def perform
        readonly do
          repo_ids = []
          if @repo_id > 0
            repo_ids << @repo_id
          else
            repo_ids = load_repositories
          end
          break if repo_ids.empty?

          repo_ids.each do |repo_id|
            log "Processing repository #{repo_id}"
            process_repository(repo_id)
            log "Done processing repository #{repo_id}"
          end
        end
      end

      private

      def load_repositories
        sql = ApplicationRecord::TokenScanningService.github_sql.new <<~SQL
          SELECT distinct repository_id
          FROM (
            SELECT repository_id
            FROM token_scan_results
            GROUP BY repository_id, number HAVING count(*) > 1
          ) AS _dupes;
        SQL

        sql.results.flatten
      end

      # We process repositories by batching 100 distinct & duplicated sequence numbers.
      # For each batch we:
      #  1. Load all duplicated token_scan_result ids
      #  2. In a further batch size of 50
      #    2a. Pre-allocate 50 sequence numbers
      #    2b. Calculate new sequence numbers
      #  3. Batch update those token_scan_result ids
      def process_repository(repo_id)
        loop do
          # Fetch batch of duplicated sequence numbers
          sql = TokenScanResult.github_sql.new <<~SQL
            SELECT number, count(*)
            FROM token_scan_results
            WHERE repository_id = #{repo_id}
            GROUP BY number
            HAVING count(*) > 1
            LIMIT #{BATCH_NUM_DUPLICATES};
          SQL
          dupes = sql.results
          break if dupes.empty?

          numbers = dupes.map { |(number, _count)| number }

          id_numbers = fetch_ids(repo_id, numbers)
          ids_by_number = {}
          id_numbers.each do |(id, number)|
            ids_by_number[number] ||= []
            ids_by_number[number] << id

            log "Duplicate token_scan_result #{id} with number #{number}" if verbose?
          end
          break if ids_by_number.empty?

          log "[#{repo_id}] For batch of #{BATCH_NUM_DUPLICATES} numbers, found #{ids_by_number.size} duplicates"

          ids_to_update = []
          numbers.each do |number|
            ids = ids_by_number[number]

            if number <= 0
              # these records are 'corrupted' and we're going to reset _ALL_ of them
              ids_to_update.concat(ids)
            else
              # leave the first id alone; they get to keep their sequence number
              ids_to_update.concat(ids.slice(1, ids.length))
            end
          end
          log "Going to update #{ids_to_update.size} token_scan_results: #{ids_to_update}" if verbose?

          ids_to_update.each_slice(BATCH_UPDATE_SIZE) do |ids|
            updates = []
            increment = ids.length
            # In dry-run, we're going to make a bunch of fake updates
            last_inserted_id = dry_run? ? 0 : preallocate_sequence_number(repo_id, increment)

            if last_inserted_id == -1
              log "Failed to pre-allocate sequence numbers for repository #{repo_id}"
              return
            end

            # the last inserted ID is the last reserved sequence number. To get the starting
            # sequence number, we need to work backwards a bit.
            start_number = last_inserted_id - increment + 1

            ids.each do |id|
              log "Updating #{id} to #{start_number}" if verbose?
              updates << [id, start_number]
              start_number += 1
            end

            run_batch_update(updates)
          end

          # Only process one batch in dry run mode, otherwise this runs indefinitely
          break if dry_run?

          # We want to avoid a read-after-write replication lag. Our cluster's replication lag
          # hardly ever goes above 50ms, so 1 second is plenty of time in between batches.
          sleep(1)
        end
      end

      def fetch_ids(repo_id, numbers)
        id_numbers = []
        numbers.each_slice(50) do |nums|
          nums = nums.join(",")

          sql = TokenScanResult.github_sql.new <<~SQL
            SELECT id, number
            FROM token_scan_results
            WHERE repository_id = #{repo_id}
            AND number IN (#{nums})
          SQL
          id_numbers.append(*sql.results)
        end

        id_numbers
      end

      def purge_token_scan_results(repo_id)
        log "[#{repo_id}] purging token scan results"
        ApplicationRecord::TokenScanningService.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
          next if dry_run?

          ActiveRecord::Base.connected_to(role: :writing) do
            sql = TokenScanResultSequence.connection.execute <<~SQL
              DELETE from token_scan_results
              WHERE repository_id = #{repo_id}
              AND number <= 0
            SQL
          end
        end
      end

      # Attempts to reserve a set of sequence numbers for the transition to assign to duplicated ids
      def preallocate_sequence_number(repo_id, increment)
        ApplicationRecord::TokenScanningService.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
          next if dry_run?

          ActiveRecord::Base.connected_to(role: :writing) do
            sql = TokenScanResultSequence.connection.execute <<~SQL
              INSERT INTO token_scan_result_sequences (repository_id, number, created_at, updated_at)
              VALUES (#{repo_id}, #{increment}, NOW(), NOW())
              ON DUPLICATE KEY UPDATE
              number = LAST_INSERT_ID(number + #{increment}), updated_at=NOW()
            SQL

            # Per MySQL documentation:https://dev.mysql.com/doc/refman/5.7/en/insert-on-duplicate.html
            # With ON DUPLICATE KEY UPDATE, the affected-rows value per row is:
            #   1 if the row is inserted as a new row
            #   2 if an existing row is updated
            #   0 if an existing row is set to its current values
            case sql.affected_rows
            when 0
              # this should never happen with "LAST_INSERT_ID"
              return -1
            when 1
              return increment
            when 2
              return sql.last_insert_id
            else
              return -1
            end
          end
        end

        -1
      end

      def run_batch_update(rows)
        ApplicationRecord::TokenScanningService.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
          next if dry_run?

          ActiveRecord::Base.connected_to(role: :writing) do
            sql = TokenScanResult.github_sql.new "UPDATE token_scan_results SET number = CASE"
            updates = rows.each do |(id, number)|
              sql.add <<~SQL, id: id, number: number
                WHEN id = :id THEN :number
              SQL
            end
            sql.add "END, updated_at=NOW() WHERE id IN :ids", ids: rows.map { |item| item[0] }
            sql.run
            sql.affected_rows
          end
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

    opts.on("--repo_id=ID", Integer, "Repository ID to process") do |id|
      options[:repo_id] = id
    end
  end.parse!

  options[:dry_run] = !options[:write]

  # If choosing to run this transition as a single process, uncomment the below commands:
  transition = GitHub::Transitions::DeduplicateTokenScanResultNumbers.new(**options)
  transition.run
end
