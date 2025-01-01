# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# For dotcom, run this transition directly (using gh-screen).
# The transition can be run in a few ways to perform verification of proper end-state:
#
#   $ cd /data/github/current
#
#   # 1. First, run the transition in dry-run mode
#   # This will do a pass over the data to see if any records in the new schema are missing or invalid
#   $ gudo bin/safe-ruby lib/github/transitions/20221026145312_two_factor_credential_normalization.rb --verbose | tee -a /tmp/two_factor_credential_normalization.log
#
#   # 2. Then, optionally, if there are any records that exist for a two_factor_credential record that are invalid, run the following command to clean those records up
#   # without writing any new records for two_factor_credential records that don't have a new schema record
#   $ gudo bin/safe-ruby lib/github/transitions/20221026145312_two_factor_credential_normalization.rb --verbose -w --cleanup_only | tee -a /tmp/two_factor_credential_normalization.log
#
#   # 3. Finally, to run the verifications, any potential cleanup, _and_ create new records for the normalized schema, run the following:
#   $ gudo bin/safe-ruby lib/github/transitions/20221026145312_two_factor_credential_normalization.rb --verbose -w | tee -a /tmp/two_factor_credential_normalization.log
#
#   # After running the transition to backfill the normalized schema, it'd be a good idea to run step 1 once more to
#   # verify there were no issues that may have occurred. You can use the output of the min/max IDs from previous runs to followup with quicker verifications using `start_id` and `end_id` flags
#
# For enterprise, the transition will be run during downtime, against newly created (empty) tables for the new schema.
module GitHub
  module Transitions
    class TwoFactorCredentialNormalizationTwoFactorCredential < ApplicationRecord::Domain::Users
      self.table_name = "two_factor_credentials"
      encrypts :secret

      def generate_recovery_secret!
        T.unsafe(self).encrypted_recovery_secret = Base64.strict_encode64(OpenSSL::Random.random_bytes(32))
        T.unsafe(self).recovery_used_bitfield = 0
        T.unsafe(self).recovery_codes_viewed = false
      end
    end

    class TwoFactorCredentialNormalization < Transition
      attr_reader :unverified_total

      # increase batch sizes to decrease transition run time
      # and maintenance window for GHES instance
      #
      # active replica lag isn't a concern during GHES maintenance/upgrade
      #
      PROCESS_BATCH_SIZE = GitHub.enterprise? ? 10000 : 100
      CREATE_BATCH_SIZE = GitHub.enterprise? ? 1000 : 1
      CLEANUP_BATCH_SIZE = GitHub.enterprise? ? 1000 : 100

      def after_initialize
        @min_id = @other_args[:start_id] || readonly do
          ApplicationRecord::Domain::Users.github_sql
            .value("SELECT COALESCE(MIN(id), 0) FROM two_factor_credentials")
        end
        @max_id = @other_args[:end_id] || readonly do
          ApplicationRecord::Domain::Users.github_sql
            .value("SELECT COALESCE(MAX(id), 0) FROM two_factor_credentials")
        end
        @process_batch_size = @other_args[:process_batch_size] || PROCESS_BATCH_SIZE
        @create_batch_size = @other_args[:create_batch_size] || CREATE_BATCH_SIZE
        @cleanup_batch_size = @other_args[:cleanup_batch_size] || CLEANUP_BATCH_SIZE

        @cleanup_only = @other_args[:cleanup_only]
        if @cleanup_only && dry_run?
          raise ArgumentError, "Cannot use --cleanup_only without --write"
        end
        @unverified_total = 0
      end

      # Returns nothing.
      def perform
        log "Starting transition with process batch size #{@process_batch_size} and min_id: #{@min_id} to max_id: #{@max_id}"
        readonly do
          batch_num = 1
          TwoFactorCredentialNormalizationTwoFactorCredential.in_batches(of: @process_batch_size, start: @min_id, finish: @max_id) do |rows|
            log ""
            log "Processing batch #{batch_num} of size #{rows.size}"
            process(rows)
            log "Finished processing batch #{batch_num}"
            batch_num += 1
          end
        end
        log "Finished transition for min_id: #{@min_id} to max_id: #{@max_id}"
        log "Total unverified rows found during transition: #{@unverified_total}"
      end

      private

      def process(rows)
        unverified_rows = run_registrations_verification(rows)
        log "Found #{unverified_rows.size} unverified rows"
        @unverified_total += unverified_rows.size
        return if dry_run? || unverified_rows.empty?

        run_registrations_cleanup(unverified_rows)
        return if @cleanup_only

        run_registrations_backfill(unverified_rows)
      end

      # verifies that the given two_factor_credential rows have expected sms_registration and totp_app_registration rows
      # returns unverified rows
      def run_registrations_verification(rows)
        rows.filter do |row|
          verified = RegistrationsVerifier.verify(row) do |log_message|
            log "[TwoFactorCredentialID: #{row.id}] #{log_message}" if verbose? # log specific verification messages if verbose logging enabled
          end
          log "[TwoFactorCredentialID: #{row.id}] Not verified" if !verified && verbose?
          !verified
        end
      end

      # deletes any sms_registration and totp_app_registration rows associated with the given two_factor_credential records
      # returns nothing
      def run_registrations_cleanup(rows)
        return if dry_run?
        log "Cleaning up any records for #{rows.size} unverified two_factor_credentials with batch size #{@cleanup_batch_size}"
        destroyed_count = 0
        rows.each_slice(@cleanup_batch_size) do |slice|
          TwoFactorCredentialNormalizationTwoFactorCredential.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
            user_ids = slice.map(&:user_id)
            destroyed_count += RegistrationCleaner.clean_registrations(user_ids) do |log_message|
              log log_message if verbose?
            end
          end
        end
        log "Destroyed #{destroyed_count} records"
      end

      # inserts new sms_registration and totp_app_registration rows for the given two_factor_credential records
      # returns nothing
      def run_registrations_backfill(rows)
        return if dry_run?
        log "Running normalization for #{rows.size} unverified two_factor_credentials with batch size #{@create_batch_size}"
        rows.each_slice(@create_batch_size) do |slice|
          TwoFactorCredentialNormalizationTwoFactorCredential.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
            RegistrationsBackfiller.backfill_registrations(slice) do |log_message|
              log log_message if verbose?
            end
          end
        end
      end

      class RegistrationsVerifier
        def self.verify(two_factor_credential)
          if two_factor_credential.delivery_method == "sms"
            self.verify_sms_registrations(two_factor_credential) do |log_message|
              yield log_message if block_given?
            end
          else
            verified_totp_app = self.verify_totp_app_registrations(two_factor_credential) do |log_message|
              yield log_message if block_given?
            end
            unless two_factor_credential.backup_sms_number.present?
              return verified_totp_app
            end
            verified_backup = self.verify_sms_backup_registration(two_factor_credential) do |log_message|
              yield log_message if block_given?
            end
            verified_totp_app && verified_backup
          end
        end

        # verifies the given two_factor_credential row has an sms_registration row with the expected values
        # returns true if verified, false otherwise
        def self.verify_sms_registrations(two_factor_credential)
          has_backup_sms_number = two_factor_credential.backup_sms_number.present?
          user_sms_registrations = SmsRegistration.where(user_id: two_factor_credential.user_id)
          expected_sms_registration_count = has_backup_sms_number ? 2 : 1

          if user_sms_registrations.size != expected_sms_registration_count
            yield "User #{two_factor_credential.user_id} has #{user_sms_registrations.size} sms registrations, expected #{expected_sms_registration_count}"
            return false
          end

          primary_sms_registration = user_sms_registrations.find { |reg| reg.is_primary }
          if primary_sms_registration.nil?
            yield "User #{two_factor_credential.user_id} has no primary sms registration"
            return false
          end

          return false unless verify_sms_registration(two_factor_credential.user_id, primary_sms_registration, two_factor_credential.sms_number, two_factor_credential.secret) do |log_message|
            yield log_message
          end

          if has_backup_sms_number
            backup_sms_registration = user_sms_registrations.find { |reg| !reg.is_primary }
            if backup_sms_registration.nil?
              yield "User #{two_factor_credential.user_id} has no backup sms registration"
              return false
            end
            return false unless verify_sms_registration(two_factor_credential.user_id, backup_sms_registration, two_factor_credential.backup_sms_number, two_factor_credential.secret) do |log_message|
              yield log_message
            end
          end
          true
        end

        # verifies the given two_factor_credential row has a backup sms_registration row
        # returns true if verified, false otherwise
        def self.verify_sms_backup_registration(two_factor_credential)
          user_sms_registrations = SmsRegistration.where(user_id: two_factor_credential.user_id)
          if user_sms_registrations.size != 1
            yield "User #{two_factor_credential.user_id} has #{user_sms_registrations.size} sms registrations, expected 1"
            return false
          end
          backup_sms_registration = user_sms_registrations.find { |reg| !reg.is_primary }
          if backup_sms_registration.nil?
            yield "User #{two_factor_credential.user_id} has no backup sms registration"
            return false
          end
          return false unless verify_sms_registration(two_factor_credential.user_id, backup_sms_registration, two_factor_credential.backup_sms_number, two_factor_credential.secret) do |log_message|
            yield log_message
          end
          true
        end

        # verifies the given two_factor_credential row has a totp_app_registration row with the expected values
        # returns true if verified, false otherwise
        def self.verify_totp_app_registrations(two_factor_credential)
          user_app_registrations = TotpAppRegistration.where(user_id: two_factor_credential.user_id)
          if user_app_registrations.size != 1
            yield "User #{two_factor_credential.user_id} has #{user_app_registrations.size} totp app registrations, expected 1"
            return false
          end

          user_app_registration = user_app_registrations.first
          if user_app_registration.encrypted_otp_secret != two_factor_credential.secret
            yield "User #{two_factor_credential.user_id} has totp app registration with secret that does not match"
            return false
          end
          true
        end

        # verifies the given sms_registration row has the expected values
        # returns true if the row is valid, false otherwise
        def self.verify_sms_registration(user_id, sms_registration, expected_sms_number, expected_secret)
          if sms_registration.sms_number != expected_sms_number
            yield "User #{user_id} has sms registration with sms_number #{sms_registration.sms_number}, expected #{expected_sms_number}"
            return false
          end
          if sms_registration.encrypted_otp_secret != expected_secret
            yield "User #{user_id} has sms registration with secret that does not match"
            return false
          end
          true
        end
      end

      class RegistrationCleaner
        # removes any sms_registration or totp_app_registration rows for the given user IDs
        # returns count of records destroyed
        def self.clean_registrations(user_ids)
          return 0 unless user_ids.present?

          ActiveRecord::Base.connected_to(role: :writing) do
            destroyed = SmsRegistration.destroy_by(user_id: user_ids)
            sms_registrations_destroyed_count = destroyed.size
            yield "Destroyed #{sms_registrations_destroyed_count} sms_registration rows" if sms_registrations_destroyed_count > 0 && block_given?
            destroyed = TotpAppRegistration.destroy_by(user_id: user_ids)
            totp_app_registrations_destroyed_count = destroyed.size
            yield "Destroyed #{totp_app_registrations_destroyed_count} totp_app_registration rows" if totp_app_registrations_destroyed_count > 0 && block_given?
            sms_registrations_destroyed_count + totp_app_registrations_destroyed_count
          end
        end
      end

      class RegistrationsBackfiller
        # inserts new sms_registration and totp_app_registration rows for the given two_factor_credential records
        # returns nothing
        def self.backfill_registrations(rows)
          sms_records_to_insert = []
          totp_app_records_to_insert = []
          rows.each do |two_factor_credential|
            if two_factor_credential.delivery_method == "sms"
              sms_records_to_insert << {
                is_primary: true,
                user_id: two_factor_credential.user_id,
                encrypted_otp_secret: two_factor_credential.secret,
                sms_number: two_factor_credential.sms_number,
                sms_provider: two_factor_credential.provider,
              }
            else
              totp_app_records_to_insert << {
                user_id: two_factor_credential.user_id,
                encrypted_otp_secret: two_factor_credential.secret,
              }
            end

            if two_factor_credential.backup_sms_number.present?
              sms_records_to_insert << {
                is_primary: false,
                user_id: two_factor_credential.user_id,
                encrypted_otp_secret: two_factor_credential.secret,
                sms_number: two_factor_credential.backup_sms_number,
                sms_provider: two_factor_credential.provider,
              }
            end
          end

          if sms_records_to_insert.size > 0
            yield "Inserting #{sms_records_to_insert.size} sms registration records" if block_given?
            ActiveRecord::Base.connected_to(role: :writing) do
              # note - insert_all does not perform AR model validations
              SmsRegistration.insert_all(sms_records_to_insert)
            end
          end

          if totp_app_records_to_insert.size > 0
            yield "Inserting #{totp_app_records_to_insert.size} totp app registration records" if block_given?
            ActiveRecord::Base.connected_to(role: :writing) do
              # note - insert_all does not perform AR model validations
              TotpAppRegistration.insert_all(totp_app_records_to_insert)
            end
          end
        end
      end
    end
  end
end

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

    opts.on("--process-batch-size SIZE", Integer, "Number of rows to process at a time") do |process_batch_size|
      options[:process_batch_size] = process_batch_size
    end

    opts.on("--create-batch-size SIZE", Integer, "Number of rows to create at a time") do |create_batch_size|
      options[:create_batch_size] = create_batch_size
    end

    opts.on("--cleanup-batch-size SIZE", Integer, "Number of rows to delete at a time") do |cleanup_batch_size|
      options[:cleanup_batch_size] = cleanup_batch_size
    end

    opts.on("--cleanup-only", "Only clean up the old data, do not migrate (--write required)") do |cleanup_only|
      options[:cleanup_only] = cleanup_only
    end
  end.parse!

  options[:dry_run] = !options[:write]

  transition = GitHub::Transitions::TwoFactorCredentialNormalization.new(**options)
  transition.run
end
