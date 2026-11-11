# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition, checkout the relevant documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/running/
module GitHub
  module Transitions
    class Populate2FaPreferenceFromAuthenticatedDevices < Transition
      READ_BATCH_SIZE = GitHub.enterprise? ? 10000 : 1000
      WRITE_BATCH_SIZE = GitHub.enterprise? ? 1000 : 100

      OLD_WEBAUTHN_VALUE = 1
      OLD_MOBILE_VALUE = 2
      OLD_TOTP_VALUE = 3
      NEW_SMS_VALUE = 1
      NEW_APP_VALUE = 2
      NEW_MOBILE_VALUE = 3
      NEW_WEBAUTHN_VALUE = 4

      attr_reader :total_updated

      def read_batch_size
        @other_args[:read_batch_size] || READ_BATCH_SIZE
      end

      def write_batch_size
        @other_args[:write_batch_size] || WRITE_BATCH_SIZE
      end

      def after_initialize
        min_id = @other_args[:start_id] || readonly do
          AuthenticatedDevice.github_sql
            .value("SELECT COALESCE(MIN(id), 0) FROM authenticated_devices")
        end
        max_id = @other_args[:end_id] || readonly do
          AuthenticatedDevice.github_sql
            .value("SELECT COALESCE(MAX(id), 0) FROM authenticated_devices")
        end
        @total_updated = 0
        @iterator = readonly do
          AuthenticatedDevice
            .github_sql_batched_between(start: min_id, finish: max_id, batch_size: read_batch_size)
        end
        @iterator.add <<-SQL
          SELECT id, user_id, two_factor_preference FROM authenticated_devices
          WHERE id BETWEEN :start AND :last
          AND two_factor_preference IS NOT NULL
        SQL
      end

      # Returns nothing.
      def perform
        log "Starting transition with batch size #{read_batch_size} and min_id: #{@min_id} to max_id: #{@max_id}"
        readonly do
          batch_num = 1
          GitHub::SQL::Readonly.new(@iterator.batches).each do |rows|
            mapped_rows = rows.map { |row| { id: row[0], user_id: row[1], two_factor_preference: row[2] } }
            log ""
            log "Processing batch #{batch_num} of size #{mapped_rows.size}"
            process(mapped_rows)
            log "Finished processing batch #{batch_num}"
            batch_num += 1
          end
        end
        log "Transition finished, updated #{@total_updated} rows"
      end

      private

      def process(rows)
        return if rows.empty?

        log "processing #{rows.size} authenticated_device records between ids #{rows.first[:id]} and #{rows.last[:id]}" if verbose?
        user_pref_map = determine_user_preference(rows)
        log "mapped to #{user_pref_map.size} users"
        run_batch_update(user_pref_map) unless dry_run?
      end

      def determine_user_preference(rows)
        results = {}
        rows.each do |device|
          user_id = device[:user_id]
          two_factor_preference = AuthenticatedDevice.github_sql.value "SELECT two_factor_preference FROM authenticated_devices WHERE user_id = #{user_id} AND two_factor_preference IS NOT NULL ORDER BY updated_at DESC LIMIT 1"

          next if two_factor_preference.nil?

          new_pref = nil
          if two_factor_preference == OLD_TOTP_VALUE
            if TotpAppRegistration.where(user_id: user_id).size > 0
              new_pref = NEW_APP_VALUE
            elsif SmsRegistration.where(user_id: user_id).size > 0
              new_pref = NEW_SMS_VALUE
            else
              next
            end
          elsif two_factor_preference == OLD_MOBILE_VALUE
            new_pref = NEW_MOBILE_VALUE
          elsif two_factor_preference == OLD_WEBAUTHN_VALUE
            new_pref = NEW_WEBAUTHN_VALUE
          end

          results[user_id] = new_pref if !new_pref.nil?
        end
        results
      end

      def run_batch_update(user_pref_map)
        return user_pref_map.size if dry_run?

        ActiveRecord::Base.connected_to(role: :writing) do
          user_pref_map.each do |user_id, two_factor_preference|
            TwoFactorCredential.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
              sql = ApplicationRecord::Domain::Users.github_sql.new "UPDATE two_factor_credentials SET login_preference = #{two_factor_preference}"
              sql.add " WHERE user_id = #{user_id}"
              sql.add " AND login_preference IS NULL"
              sql.run
              log "Rows affected: #{sql.affected_rows}"
              @total_updated += sql.affected_rows
            end
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
  end.parse!

  options[:dry_run] = !options[:write]

  transition = GitHub::Transitions::Populate2FaPreferenceFromAuthenticatedDevices.new(**options)
  transition.run
end
