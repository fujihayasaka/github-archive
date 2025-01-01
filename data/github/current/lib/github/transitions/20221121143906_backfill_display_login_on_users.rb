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
#   $ gudo bin/safe-ruby lib/github/transitions/20221121143906_backfill_display_login_on_users.rb --verbose | tee -a /tmp/backfill_display_login_on_users.dry_run.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20221121143906_backfill_display_login_on_users.rb --verbose -w | tee -a /tmp/backfill_display_login_on_users.write_run.log
module GitHub
  module Transitions
    class BackfillDisplayLoginOnUsers < Transition
      BATCH_READ_SIZE = GitHub.enterprise? ? 10000 : 100
      BATCH_UPDATE_SIZE = GitHub.enterprise? ? 1000 : 20

      def after_initialize
        @total_updated_users = 0
        @phrasing = dry_run? ? "Would have updated" : "Updating"

        @max_biz_id = readonly { ApplicationRecord::Domain::Users.github_sql.value("SELECT COALESCE(MAX(id), 0) FROM businesses") }
        @start_id = @other_args[:start_id] || readonly { ApplicationRecord::Domain::Users.github_sql.value("SELECT COALESCE(MIN(id), 0) FROM users") }
        @end_id = @other_args[:end_id] || readonly { ApplicationRecord::Domain::Users.github_sql.value("SELECT COALESCE(MAX(id), 0) FROM users") }

        @iterator = ApplicationRecord::Domain::Users.github_sql_batched_between(
          batch_size: batch_read_size,
          start: @start_id,
          finish: @end_id
        )
        @iterator.add <<-SQL
          SELECT id, login
          FROM users
          WHERE id BETWEEN :start AND :last
          AND display_login IS NULL
          AND business_id = 0
          ORDER BY id
        SQL
      end

      def perform
        # Process all users without a business_id (across all environments)
        log "Processing users with display_login equivalent to login"
        GitHub::SQL::Readonly.new(@iterator.batches).each do |rows|
          process_copy_display_login(rows)
        end

        # then handle business_id != 0 users on Proxima only
        return unless GitHub.multi_tenant_enterprise?
        log "Processing users with display_login distinct from login (Proxima EMUs). Max business_id is #{@max_biz_id}" if verbose?

        readonly do
          Business.select(:id, :shortcode).each do |biz|
            log "Processing Business id: #{biz.id}" if verbose?

            User.unscoped.where(business_id: biz.id, display_login: nil)
            .select(:id, :login)
            .find_in_batches(batch_size: batch_read_size, start: @start_id, finish: @end_id) do |batch|
              process_new_display_login(batch, shortcode: biz.shortcode)
            end
          end
        end
      end

      def process_copy_display_login(rows)
        return if rows.empty?
        user_ids = rows.map(&:first)
        log "processing users between ids #{user_ids.first} and #{user_ids.last}" if verbose?

        run_batch_display_login_copy(user_ids) unless dry_run?

        @total_updated_users += user_ids.size
        log "#{@phrasing} #{@total_updated_users} so far" if verbose?
      end

      def run_batch_display_login_copy(user_ids)
        user_ids.each_slice(batch_update_size).each do |user_ids_slice|
          ActiveRecord::Base.connected_to(role: :writing) do
            User.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
              User.github_sql.run <<~SQL, user_ids: user_ids_slice
                UPDATE users
                SET display_login = login
                WHERE id IN :user_ids
                AND display_login IS NULL
                AND business_id = 0
              SQL
            end
          end
        end
      end

      def process_new_display_login(rows, shortcode:)
        return if rows.empty?
        user_ids = rows.map(&:id)
        log "processing users between ids #{user_ids.first} and #{user_ids.last}" if verbose?

        insert_rows = rows.map do |row|
          login = row.login
          display_login = row.login.chomp("_#{shortcode}")

          [login, display_login]
        end

        run_batch_display_login_insert(insert_rows) unless dry_run?

        @total_updated_users += user_ids.size
        log "#{@phrasing} #{@total_updated_users} so far" if verbose?
      end

      def run_batch_display_login_insert(rows)
        rows.each_slice(batch_update_size).each do |rows_slice|
          ActiveRecord::Base.connected_to(role: :writing) do
            User.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
              User.github_sql.run <<~SQL, rows: GitHub::SQL::ROWS(rows_slice)
                INSERT INTO users (login, display_login)
                VALUES :rows
                ON DUPLICATE KEY UPDATE display_login = VALUES(display_login)
              SQL
            end
          end
        end
      end

      def batch_read_size
        other_args[:batch_read_size] || BATCH_READ_SIZE
      end

      def batch_update_size
        other_args[:batch_update_size] || BATCH_UPDATE_SIZE
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

    opts.on("--batch-read-size SIZE", Integer, "Number of rows to read at a time") do |size|
      options[:batch_read_size] = size
    end

    opts.on("--batch-update-size SIZE", Integer, "Number of rows to update at a time") do |size|
      options[:batch_update_size] = size
    end

    opts.on("--no-rollback", "Do not write a rollback file; this may speed up your transition or dry run.") do
      options[:no_rollback] = true
    end

    opts.on("-n", "--workers COUNT", Integer, "Worker count") do |count|
      options[:workers] = count
    end
  end.parse!

  options[:dry_run] = !options[:write]
  options[:workers] ||= 1

  # If choosing to run this transition as a single process, uncomment the below commands:
  transition = GitHub::Transitions::BackfillDisplayLoginOnUsers.new(**options)
  transition.run

  # If choosing to use Divvy and run this transition as a multithreaded process
  # uncomment the below commands to pass the transition to Divvy, as well as an
  # option for worker count:
  # transition = GitHub::Transitions::BackfillDisplayLoginOnUsers.new(**options)
  # divvy = Divvy::Master.new(transition, options[:workers], options[:verbose])
  # divvy.run
end
