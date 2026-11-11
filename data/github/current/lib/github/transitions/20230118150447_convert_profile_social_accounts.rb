# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"
require "divvy"

# To run this transition, checkout the relevant documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/running/
module GitHub
  module Transitions
    class ConvertProfileSocialAccounts < Transition
      include Divvy::Parallelizable

      # Recommended batch size number, but you can modify for your use case
      #
      # Consider increasing *_BATCH_SIZE to decrease transition run time
      # and maintenance window for GHES instance. Replication lag isn't a
      # concern during GHES maintenance/upgrades.
      #
      READ_BATCH_SIZE = GitHub.enterprise? ? 10000 : 100
      WRITE_BATCH_SIZE = GitHub.enterprise? ? 1000 : 10

      # attr_reader :iterator
      # attr_reader :total_updated

      def read_batch_size
        @other_args[:read_batch_size] || READ_BATCH_SIZE
      end

      def write_batch_size
        @other_args[:write_batch_size] || WRITE_BATCH_SIZE
      end

      attr_reader :iterator, :total_updated

      def after_initialize
        min_id = @other_args[:start_id] || readonly do
          Profile.github_sql.value("SELECT COALESCE(MIN(id), 0) FROM profiles")
        end
        max_id = @other_args[:end_id] || readonly do
          Profile.github_sql.value("SELECT COALESCE(MAX(id), 0) FROM profiles")
        end
        log "min_id=#{min_id} max_id=#{max_id} read_batch_size=#{read_batch_size} write_batch_size=#{write_batch_size}"

        @total_updated = 0

        @iterator = readonly do
          Profile.github_sql_batched_between(start: min_id, finish: max_id, batch_size: read_batch_size)
        end
        @iterator.add <<-SQL
          SELECT id, twitter_username
          FROM profiles
          WHERE id BETWEEN :start AND :last
          AND twitter_username IS NOT NULL
          AND encoded_social_accounts IS NULL
          ORDER BY id
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

      def process(rows)
        log "Processing batch of #{rows.size} profile(s)" if verbose?
        return if rows.empty?

        updates = rows.filter_map do |(id, twitter_username)|
          # We shouldn't have any "" usernames in the database, but nevertheless
          next unless twitter_username.present?

          encoded = [{ "key" => "twitter", "url" => "https://twitter.com/#{twitter_username}" }]
          [id, encoded]
        end

        log "Updating profile(s): #{updates.map(&:first).join(", ")}" if verbose?
        updates.each_slice(write_batch_size) do |slice|
          @total_updated += run_batch_update(slice)
          log "#{dry_run? ? "Would update" : "Updated"} #{@total_updated} profile(s)" if verbose?
        end
        log "Finished profile: #{rows.map(&:first).max}"
      end

      private

      def run_batch_update(updates)
        return updates.size if dry_run?

        ActiveRecord::Base.connected_to(role: :writing) do
          Profile.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
            sql = Profile.github_sql.new "UPDATE profiles SET encoded_social_accounts = CASE"
            updates.each do |(id, encoded_social_accounts)|
              sql.add <<~SQL, id:, encoded_social_accounts: encoded_social_accounts.to_json
                WHEN id = :id THEN :encoded_social_accounts
              SQL
            end
            sql.add "END WHERE id IN :ids", ids: updates.map(&:first)
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
  options[:workers] ||= 1

  transition = GitHub::Transitions::ConvertProfileSocialAccounts.new(**options)
  divvy = Divvy::Master.new(transition, options[:workers] || 1, options[:verbose])
  divvy.run

  transition = GitHub::Transitions::ConvertProfileSocialAccounts.new(**options)
  divvy = Divvy::Master.new(transition, options[:workers], options[:verbose])
  divvy.run
end
