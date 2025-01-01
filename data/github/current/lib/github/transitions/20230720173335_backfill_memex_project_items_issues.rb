# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"
# Uncomment if you want to use Divvy
# require "divvy"

# To run this transition, checkout the relevant documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/running/
module GitHub
  module Transitions
    class BackfillMemexProjectItemsIssues < Transition

      class MemexProjectItems < ApplicationRecord::Domain::Memexes
        self.table_name = "memex_project_items"
      end

      # include Divvy::Parallelizable

      READ_BATCH_SIZE = GitHub.enterprise? ? 10000 : 50
      WRITE_BATCH_SIZE = GitHub.enterprise? ? 1000 : 1

      attr_reader :iterator
      attr_reader :total_updated
      attr_reader :max_id

      def read_batch_size
        @other_args[:read_batch_size] || READ_BATCH_SIZE
      end

      def write_batch_size
        @other_args[:write_batch_size] || WRITE_BATCH_SIZE
      end

      def after_initialize
        min_id = @other_args[:start_id] || readonly do
          MemexProjectItems.connection.select_value(
            Arel.sql("SELECT COALESCE(MIN(id), 0) FROM memex_project_items")
          )
        end
        @max_id = @other_args[:end_id] || readonly do
          MemexProjectItems.connection.select_value(
            Arel.sql("SELECT COALESCE(MAX(id), 0) FROM memex_project_items")
          )
        end

        @total_updated = 0

        @iterator = readonly do
          MemexProjectItems.github_sql_batched_between(
            start: min_id,
            finish: max_id,
            batch_size: read_batch_size
          )
        end

        @iterator.add <<-SQL
          -- id must go first for batched between to work properly
          SELECT id, issue_id FROM memex_project_items
          WHERE id BETWEEN :start AND :last
          AND (content_type = "PullRequest" OR content_type = "Issue")
          AND issue_created_at IS NULL
        SQL
      end

      # def dispatch
      #   GitHub::SQL::Readonly.new(iterator.batches).each do |rows|
      #     yield rows
      #   end
      # end

      def perform
        # dispatch { |rows| process(rows) }

        GitHub::SQL::Readonly.new(iterator.batches).each do |rows|
          process(rows)
        end

        verb = dry_run? ? "Would have updated" : "Updated"
        log("#{verb} #{total_updated} records")
      end

      private

      def process(rows)
        rows.each_slice(write_batch_size) do |slice|
          log "doing something with #{slice.map { |item| item[0] }}" if verbose?
          run_batch_update(slice)
          log "Did something through id #{slice.last[0]}. Still need to do something up to id #{max_id.to_i}" if verbose?
        end
      end

      def run_batch_update(rows)
        if verbose?
          verb = dry_run? ? "Would update" : "Updating"
          first_id = rows.first[0]
          last_id = rows.last[0]
          if first_id == last_id
            log("#{verb} row #{first_id}...")
          else
            log("#{verb} rows #{first_id} - #{last_id}...")
          end
        end

        updated = 0
        issue_ids = rows.map { |row| row[1] }
        log("Start running get_issues") if verbose?
        issues = get_issues(issue_ids)
        log("Finished running get_issues") if verbose?

        update_ids = []
        update_sql = Arel.sql("UPDATE memex_project_items SET")
        created_at_sql = Arel.sql("issue_created_at = CASE")
        closed_at_sql = Arel.sql("issue_closed_at = CASE")
        state_sql = Arel.sql("state = CASE")
        state_reason_sql = Arel.sql("state_reason = CASE")

        rows.each do |(id, issue_id)|
          issue = issues.find { |issue| issue[0] == issue_id }
          break unless issue

          update_ids.append(id)
          created_at_sql += Arel.sql("WHEN id = :id THEN :issue_created_at", id: id, issue_created_at: issue[2])
          closed_at_sql += Arel.sql("WHEN id = :id THEN :issue_closed_at", id: id, issue_closed_at: issue[1])
          state_sql += Arel.sql("WHEN id = :id THEN :state", id: id, state: issue[3])
          state_reason_sql += Arel.sql("WHEN id = :id THEN :state_reason", id: id, state_reason: issue[4])

          updated += 1
        end
        @total_updated += updated
        # exit early if there are no records to update in batch
        return if updated <= 0
        return if dry_run?

        created_at_sql += Arel.sql("END, ")
        closed_at_sql += Arel.sql("END, ")
        state_sql += Arel.sql("END, ")

        update_sql += created_at_sql
        update_sql += closed_at_sql
        update_sql += state_sql
        update_sql += state_reason_sql
        update_sql += Arel.sql("END WHERE id IN (:ids)", ids: update_ids)

        MemexProjectItem.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
          ActiveRecord::Base.connected_to(role: :writing) do
            ApplicationRecord::Domain::Memexes.connection.update(update_sql)
          end
        end
      end

      def get_issues(ids)
        ActiveRecord::Base.connected_to(role: :reading) do
          sql = Arel.sql("SELECT id, closed_at, created_at, state, state_reason from issues where id in (:ids)", ids: ids)

          log("Getting issues for ids: #{ids}") if verbose?
          ApplicationRecord::Domain::IssuesPullRequests.connection.select_rows(sql)
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

    opts.on("--read_batch_size SIZE", Integer, "Number of rows to read at a time") do |size|
      options[:read_batch_size] = size
    end

    opts.on("--write_batch_size SIZE", Integer, "Number of rows to write at a time") do |size|
      options[:write_batch_size] = size
    end

    opts.on("-n", "--workers COUNT", Integer, "Worker count (only applicable if using Divvy)") do |count|
      options[:workers] = count
    end
  end.parse!

  options[:workers] ||= 1
  options[:dry_run] = !options[:write]

  # If choosing to run this transition as a single process, uncomment the below commands:
  transition = GitHub::Transitions::BackfillMemexProjectItemsIssues.new(**options)
  transition.run

  # If choosing to use Divvy and run this transition as a multithreaded process
  # uncomment the below commands to pass the transition to Divvy, as well as an
  # option for worker count:
  # transition = GitHub::Transitions::BackfillMemexProjectItemsIssues.new(**options)
  # divvy = Divvy::Master.new(transition, options[:workers], options[:verbose])
  # divvy.run
end
