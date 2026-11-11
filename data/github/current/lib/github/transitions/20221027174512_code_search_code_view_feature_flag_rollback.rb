# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

module GitHub
  module Transitions
    class CodeSearchCodeViewFeatureFlagRollback < Transition

      MAX_THROTTLE_RETRIES = 4

      def perform
        log "No rollback logic has been implemented for CodeSearchCodeViewFeatureFlag"
        CSV.foreach(rollback_filename, headers: false) { |row| roll_back_row(row) }
      end

      def roll_back_row(row)
        class_name, id = row
        action = dry_run? ? "Updates" : "Updated"
        ActiveRecord::Base.connected_to(role: :writing) do
          actor = class_name.constantize.find_by(id: id)
          if actor.present?
            log "#{action} #{actor.class} #{actor.id} feature flag"
            FeatureFlag.vexi_management.remove_feature_flag_actors(:code_search_code_view, [actor]) unless dry_run? # rubocop:disable GitHub/FeatureManagement/NoVexiManagementUsage
          else
            log "Could not find #{class_name} with id #{id}, skipping"
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
      options[:write] = true
    end

    opts.on("-v", "--verbose", "Log verbose output") do
      options[:verbose] = true
    end

    opts.on("--data_file FILE", "Path to a file containing rollback data") do |file|
      options[:data_file] = file
    end

    opts.on("--start_id ID", Integer, "ID to start processing") do |id|
      options[:start_id] = id
    end

    opts.on("--end_id ID", Integer, "ID to end processing") do |id|
      options[:end_id] = id
    end
  end.parse!

  options[:dry_run] = !options[:write]

  transition = GitHub::Transitions::CodeSearchCodeViewFeatureFlagRollback.new(**options)
  transition.run
end
