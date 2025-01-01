# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"
require "divvy"

# To run this transition, checkout the relevant documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/running/
module GitHub
  module Transitions
    class BackfillIssueEditCompressedDiff < Transition
      include Divvy::Parallelizable

      READ_BATCH_SIZE = GitHub.enterprise? ? 100 : 100
      WRITE_BATCH_SIZE = GitHub.enterprise? ? 10 : 1
      MAX_RETRY_COUNT = 8

      attr_accessor :total, :progress

      def read_batch_size
        @other_args[:read_batch_size] || READ_BATCH_SIZE
      end

      def write_batch_size
        @other_args[:write_batch_size] || WRITE_BATCH_SIZE
      end

      def after_initialize
        @min_id = @other_args[:start_id] || readonly { IssueEdit.order(id: :asc).pick(:id) } || 0
        @max_id = @other_args[:end_id] || readonly { IssueEdit.order(id: :desc).pick(:id) } || 0

        @iterator = readonly do
          ApplicationRecord::Domain::IssuesPullRequests.github_sql_batched_between(
            start: @min_id,
            finish: @max_id,
            batch_size: read_batch_size,
          )
        end

        @iterator.add <<-SQL
          SELECT issue_edits.id
          FROM issue_edits
          WHERE issue_edits.id BETWEEN :start AND :last
            AND issue_edits.compressed_diff IS NULL
            AND issue_edits.diff IS NOT NULL
          ORDER BY issue_edits.id
        SQL

        @total =
          if @max_id == @min_id
            @max_id > 0 ? 1 : 0
          else
            @max_id - @min_id + 1 # think IDs 1-11, that's 11 rows.
          end

        @progress = @min_id
      end

      # Returns nothing.
      def perform
        dispatch { |ids| process(ids) }
      end

      def dispatch
        log "Starting transition #{self.class.to_s.underscore} - #{@total} (approx) issue_edits rows."

        @iterator.batches.each do |rows|
          ids = rows.flatten
          next if ids.empty?

          yield ids

          # approximate approach to estimate progress.
          @progress = [@progress, ids.last - @min_id + 1].max
          log "Current progress: #{@progress} / #{@total}" if verbose?
        end

        log "Finished transition #{self.class.to_s.underscore}"
      end

      def process(ids)
        # need to query for the diff inside the Divvy worker, since messages passed between Divvy workers
        # have a cap.
        rows = read_diffs(ids)

        rows.each_slice(write_batch_size).each do |items|
          next if items.empty?

          log "updating next #{items.size} issue edits after id=#{items.first.first}" if verbose?

          ApplicationRecord::Domain::IssuesPullRequests.throttle_with_retry(max_retry_count: MAX_RETRY_COUNT, low_priority: true) do
            next if dry_run?

            # For GHES - we are offline during schema migration - so we can just update the rows.
            if GitHub.enterprise?
              items = map_issue_edit_id_to_compressed_diff(items)

              ActiveRecord::Base.connected_to(role: :writing) do
                sql = Arel.sql(<<-SQL)
                  UPDATE issue_edits
                  SET compressed_diff = CASE
                SQL

                items.each do |(id, compressed_diff)|
                  sql += Arel.sql("WHEN id = :id THEN :compressed_diff", id: id, compressed_diff: GitHub::SQL::ArelLiterals.binary(compressed_diff))
                end

                sql += Arel.sql("END WHERE id IN (:ids)", ids: items.map(&:first))

                ApplicationRecord::Domain::IssuesPullRequests.connection.update(sql)
              end
            else
              # For dotcom or proxima, we are online. Hence we need to ensure that the diff doesn't get deleted in the meanwhile by comparing
              # the read diff with the current diff. If this would fail, i.e. the `compressed_diff` is not updated, then we will re-run the
              # transition.
              items.each do |(id, diff)|
                IssueEdit.where(id: id).where("SHA2(diff, 256) = ?", Digest::SHA256.hexdigest(diff)).update_all(compressed_diff: diff)
              end
            end
          end
        end
      end

      def read_diffs(ids)
        ApplicationRecord::Domain::IssuesPullRequests.throttle_with_retry(max_retry_count: MAX_RETRY_COUNT, low_priority: true) do
          ActiveRecord::Base.connected_to(role: :reading) do
            sql = Arel.sql("SELECT id, diff from issue_edits where id in (:ids)", ids: ids)

            ApplicationRecord::Domain::IssuesPullRequests.connection.select_rows(sql)
          end
        end
      end

      def map_issue_edit_id_to_compressed_diff(items)
        items.map { |id, diff| [id, CompressedString.new("IssueEdit", "diff").serialize(diff).to_s] }
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

    opts.on("-n", "--workers COUNT", Integer, "Worker count") do |count|
      options[:workers] = count
    end
  end.parse!

  options[:dry_run] = !options[:write]

  # If choosing to run this transition as a single process, uncomment the below commands:
  # transition = GitHub::Transitions::BackfillIssueEditCompressedDiff.new(**options)
  # transition.run

  # If choosing to use Divvy and run this transition as a multithreaded process
  # uncomment the below commands to pass the transition to Divvy, as well as an
  # option for worker count:
  transition = GitHub::Transitions::BackfillIssueEditCompressedDiff.new(**options)
  divvy = Divvy::Master.new(transition, options[:workers], options[:verbose])
  divvy.run
end
