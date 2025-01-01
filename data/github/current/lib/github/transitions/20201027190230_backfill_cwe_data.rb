# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   # First, run the transition in dry-run mode
#   $ gudo bin/safe-ruby lib/github/transitions/20201027190230_backfill_cwe_data.rb --verbose | tee -a /tmp/backfill_cwe_data.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20201027190230_backfill_cwe_data.rb --verbose -w | tee -a /tmp/backfill_cwe_data.log
#
module GitHub
  module Transitions
    class BackfillCWEData < Transition
      # Returns nothing.
      def perform
        cwe_path = Rails.root.join("config", "cwe-data.json")
        cwe_content = File.read(cwe_path)
        cwes = JSON.parse(cwe_content).with_indifferent_access

        added = 0
        updated = 0

        cwes.each do |key, value|
          CWE.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
            cwe_id = "CWE-#{key}"
            entry = CWE.find_by(cwe_id: cwe_id) || CWE.new(cwe_id: cwe_id)
            entry.name = value[:name]
            entry.description = value[:description]

            if entry.new_record?
              added += 1
              log "Creating #{cwe_id}" if verbose?
            elsif entry.changed?
              updated += 1
              log "Updating #{cwe_id}" if verbose?
            end

            entry.save! unless dry_run?
          end
        end

        log "Updated: #{updated}, Added: #{added}"
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

  transition = GitHub::Transitions::BackfillCWEData.new(**options)
  transition.run
end
