# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   # First, run the transition in dry-run mode
#   $ gudo bin/safe-ruby lib/github/transitions/20221114143945_multiple_user_two_factor_credential_repair.rb --verbose | tee -a /tmp/multiple_user_two_factor_credential_repair.dry_run.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20221114143945_multiple_user_two_factor_credential_repair.rb --verbose -w | tee -a /tmp/multiple_user_two_factor_credential_repair.write_run.log
module GitHub
  module Transitions
    class MultipleUserTwoFactorCredentialRepairTwoFactorCredential < ApplicationRecord::Domain::Users
      self.table_name = "two_factor_credentials"

      def self.generate_secret
        Base64.strict_encode64(OpenSSL::Random.random_bytes(32))
      end

      def generate_recovery_secret!
        T.unsafe(self).encrypted_recovery_secret = self.class.generate_secret
        T.unsafe(self).recovery_used_bitfield = 0
        T.unsafe(self).recovery_codes_viewed = false
      end
    end

    class MultipleUserTwoFactorCredentialRepair < Transition
      attr_reader :total_users_repaired, :total_two_factor_credentials_deleted, :total_user_ids_skipped, :rollback_filename

      DELETE_BATCH_SIZE = GitHub.enterprise? ? 1000 : 1

      def after_initialize
        @total_users_repaired = 0
        @total_two_factor_credentials_deleted = 0
        @total_user_ids_skipped = 0

        unless @other_args[:no_rollback]
          @rollback_out_dir = Pathname.new("/").relative_path_from(Pathname.new(__dir__)).to_s + "/tmp"
          @rollback_data_rows = []
          @rollback_filename = @other_args[:rollback] || File.join(
            @rollback_out_dir, "rollback-#{T.unsafe(self).class.name.demodulize.underscore}.#{Time.now.to_i}.csv"
          )
        end

        if !@other_args[:user_ids_json] && !GitHub.enterprise?
          log "Must provide a user_ids_json file path for non-enterprise" if verbose?
          return
        end

        if Rails.env.test?
          @user_ids = JSON.parse(@other_args[:user_ids_json]) if @other_args[:user_ids_json]
        else
          @user_ids = JSON.parse(File.read(@other_args[:user_ids_json])) if @other_args[:user_ids_json]
        end
      end

      # Returns nothing.
      def perform
        if GitHub.enterprise? && !Rails.env.test?
          sql = ApplicationRecord::Domain::Users.github_sql.new
          sql.add <<-SQL
            SELECT DISTINCT(t.user_id)
            FROM two_factor_credentials t
            WHERE EXISTS
                (SELECT 1
                FROM two_factor_credentials t2
                WHERE t2.user_id = t.user_id
                  AND t2.id <> t.id)
          SQL
          @user_ids = sql.results.flatten
        end

        log "No user ids to process" if verbose? && !@user_ids
        log "Processing #{@user_ids.size} user ids" if verbose? && @user_ids
        readonly do
          process(@user_ids)
        end

        log "Skipped #{@total_user_ids_skipped} user ids" if verbose?
        log "#{dry_run? ? "Would have repaired" : "Repaired"} #{@total_users_repaired} users" if verbose?
        log "#{dry_run? ? "Would have deleted" : "Deleted"} #{@total_two_factor_credentials_deleted} two_factor_credentials" if verbose?
      ensure
        write_rollback_data
      end

      def process(user_ids)
        return unless user_ids && user_ids.size > 0
        groupings, @total_user_ids_skipped = MultipleTwoFactorCredentialGrouper.group(user_ids)
        process_user_ids(user_ids_from_group(groupings[:identical]), identical: true) if groupings[:identical].size > 0
        process_user_ids(user_ids_from_group(groupings[:rest])) if groupings[:rest].size > 0
      end

      def process_user_ids(user_ids, identical: false)
        log "Processing #{user_ids.size} users with #{identical ? "identical" : "different"} two_factor_credentials" if verbose?

        # keep the one that is closest to how the code would resolve it (e.g. user.two_factor_credential)
        total = 0
        dupe_two_factor_credential_ids = user_ids.map do |user_id|
          cred_id_keeping = User.find_by(id: user_id)&.two_factor_credential&.id
          all_ids_for_user = MultipleUserTwoFactorCredentialRepairTwoFactorCredential.where(user_id: user_id).pluck(:id)
          total += all_ids_for_user.size
          removing = all_ids_for_user - [cred_id_keeping]
          log "Removing IDs #{removing} for user #{user_id} and keeping ID #{cred_id_keeping}" if verbose?
          removing
        end.flatten.uniq
        log "Found #{dupe_two_factor_credential_ids.size} dupe two_factor_credential IDs out of #{total} two_factor_credential IDs" if verbose?

        dupe_two_factor_credential_ids.each_slice(DELETE_BATCH_SIZE) do |id_slice|
          rollback_data = MultipleUserTwoFactorCredentialRepairTwoFactorCredential.where(id: id_slice).to_a
          MultipleUserTwoFactorCredentialRepairTwoFactorCredential.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
            @total_two_factor_credentials_deleted += run_batch_delete(id_slice)
          end
          rollback_data.each { |d| @rollback_data_rows << [d.attributes.to_json] if write_rollback_data? }
        end

        if !dry_run? && !identical
          log "Marking users as repaired under non identical circumstances" if verbose?
          ActiveRecord::Base.connected_to(role: :writing) do
            user_ids.each do |user_id|
              # rubocop:todo GitHub/DoNotUseGlobalKv
              GitHub.kv.set("multiple_user_two_factor_credential_repair.#{user_id}", "true")
              # rubocop:enable GitHub/DoNotUseGlobalKv
            end
          end
        end

        @total_users_repaired += user_ids.size
      end

      def write_rollback_data?
        !@other_args[:no_rollback]
      end

      def write_rollback_data
        return if !@rollback_data_rows || @rollback_data_rows.size == 0

        # Writes out all preserved data to a CSV.
        unless write_rollback_data?
          log "Operator skipped rollback data write."
          return
        end

        CSV.open(@rollback_filename, "w") do |csv|
          @rollback_data_rows.each do |row|
            csv << row
          end
        end
        log "Rollback data (#{@rollback_data_rows.count} rows) written to #{@rollback_filename}"
        if dry_run?
          log "You should spot check this data to make sure it represents the data you expect to be updated!"
        else
          log "If you need to roll back this transition, re-run with `--rollback=#{@rollback_filename}`"
          log "bin/safe-ruby lib/github/transitions/20221114143945_multiple_user_two_factor_credential_repair_rollback.rb --verbose -w --data_file #{@rollback_filename} | tee -a /tmp/multiple_user_two_factor_credential_repair_rollback.log"
        end
      end

      def run_batch_delete(rows)
        # if in dry run, mimic the DELETE query as best as possible to return
        # the amount of rows that would be deleted
        sql = T.cast(nil, T.untyped)
        if dry_run?
          sql = ApplicationRecord::Domain::Users.github_sql.new "SELECT COUNT(*) FROM two_factor_credentials"
          sql.add <<-SQL, ids: rows
            WHERE id IN :ids
          SQL
          return sql.value
        end

        log "Deleting two_factor_credential records #{rows}" if verbose?
        ActiveRecord::Base.connected_to(role: :writing) do
          sql = ApplicationRecord::Domain::Users.github_sql.new "DELETE FROM two_factor_credentials"
          sql.add <<-SQL, ids: rows
            WHERE id IN :ids
          SQL
          sql.run
          sql.affected_rows
        end
      end

      def user_ids_from_group(group)
        group.map { |g| g[:users] }.flatten.uniq
      end
    end

    class MultipleTwoFactorCredentialGrouper
      # returns groupings of user_ids that have multiple two_factor_credentials that are identical or different
      # skips any user_ids that do not exist or do not have multiple two_factor_credential records
      def self.group(user_ids)
        deltas, skipped = group_deltas(user_ids)
        delta_groups = {
          identical: [],
          rest: [],
        }
        deltas.each do |delta|
          if delta[:grouping] == {} || delta[:grouping] == { created_at: true } || delta[:grouping] == { updated_at: true } || delta[:grouping] == { created_at: true, updated_at: true }
            delta_groups[:identical] << delta
          else
            delta_groups[:rest] << delta
          end
        end
        [delta_groups, skipped]
      end

      # returns an array of hashes with the following format:
      # [ { users: [id, id2], grouping: { secret: true } }]
      # the above example would mean that users with ids id and id2 have two_factor_credential records that have different secrets
      def self.group_deltas(user_ids)
        skipped = 0

        users_with_multiple = user_ids.map do |user_id|
          [user_id, MultipleUserTwoFactorCredentialRepairTwoFactorCredential.where(user_id: user_id)]
        end.filter do |_, two_factor_credentials|
          if two_factor_credentials.size <= 1
            skipped += 1 # if we couldn't find a two_factor_credential or multiple two_factor_credentials for the user_id given, skip it
            false
          else
            true
          end
        end
        return [[], skipped] if users_with_multiple.size == 0

        deltas = users_with_multiple.map do |user_id, two_factor_credentials|
          find_deltas_for_two_factor_credentials(user_id, two_factor_credentials.map { |c| c.attributes })
        end
        grouped = deltas.group_by { |_, d| d }.values
        groups = []
        grouped.each do |g|
          users = []
          g.each do |u, _|
            users << u
          end
          groups << { users: users, grouping: g.first[1] }
        end
        [groups, skipped]
      end
      private_class_method :group_deltas

      # returns attributes for multiple two_factor_credentials that have different values
      # ex: { secret: true } means that there were different secrets for the two_factor_credentials given
      def self.find_deltas_for_two_factor_credentials(user_id, two_factor_credentials)
        delta = {}
        delta[:secret] = true if two_factor_credentials.pluck("secret").uniq.size > 1
        delta[:delivery_method] = true if two_factor_credentials.pluck("delivery_method").uniq.size > 1
        delta[:sms_number] = true if two_factor_credentials.pluck("sms_number").uniq.size > 1
        delta[:backup_sms_number] = true if two_factor_credentials.pluck("backup_sms_number").uniq.size > 1
        delta[:recovery_codes_viewed] = true if two_factor_credentials.pluck("recovery_codes_viewed").uniq.size > 1
        delta[:recovery_used_bitfield] = true if two_factor_credentials.pluck("recovery_used_bitfield").uniq.size > 1
        delta[:encrypted_recovery_secret] = true if two_factor_credentials.pluck("encrypted_recovery_secret").uniq.size > 1
        delta[:created_at] = true if two_factor_credentials.pluck("created_at").uniq.size > 1
        delta[:updated_at] = true if two_factor_credentials.pluck("updated_at").uniq.size > 1
        [user_id, delta]
      end
      private_class_method :find_deltas_for_two_factor_credentials
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

    opts.on("--no-rollback", "Do not write a rollback file; this may speed up your transition or dry run.") do
      options[:no_rollback] = true
    end

    opts.on("--user-ids-json PATH", String, "Path to JSON file with user ids.") do |path|
      options[:user_ids_json] = path
    end
  end.parse!

  options[:dry_run] = !options[:write]

  # If choosing to run this transition as a single process, uncomment the below commands:
  transition = GitHub::Transitions::MultipleUserTwoFactorCredentialRepair.new(**options)
  transition.run
end
