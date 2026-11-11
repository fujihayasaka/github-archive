# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

module GitHub
  module Transitions
    class MultipleUserTwoFactorCredentialRepairRollback < Transition
      def perform
        CSV.foreach(rollback_filename, headers: false) { |row| roll_back_row(row) }
      end

      def roll_back_row(row)
        cred = JSON.parse row[0]
        log "#{dry_run? ? "Would recreate" : "Recreating"} #{cred}"
        ActiveRecord::Base.connected_to(role: :writing) do
          GitHub::Transitions::MultipleUserTwoFactorCredentialRepairTwoFactorCredential.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
            if !dry_run? && User.find_by(id: cred["user_id"])
              cred = GitHub::Transitions::MultipleUserTwoFactorCredentialRepairTwoFactorCredential.new(cred)
              cred.save(validate: false) # we need to skip validations so that we are "allowed" to create multiple creds for a user during a rollback scenario
            end
          end
        end
      end

      private

      def rollback_filename
        @other_args[:data_file]
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
      options[:dry_run] = false
    end

    opts.on("-v", "--verbose", "Log verbose output") do
      options[:verbose] = true
    end

    opts.on("-data_file=FILE", String, "Path to a file containing rollback data") do |file|
      options[:data_file] = file
    end
  end.parse!

  options[:dry_run] ||= true

  transition = GitHub::Transitions::MultipleUserTwoFactorCredentialRepairRollback.new(**options)
  transition.run
end
