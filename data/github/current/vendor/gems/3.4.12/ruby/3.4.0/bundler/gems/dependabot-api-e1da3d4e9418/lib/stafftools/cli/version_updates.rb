# frozen_string_literal: true

require "thor"

module Stafftools
  module Cli
    class VersionUpdates < Thor
      desc "bump NWO PACKAGE_MANAGER", "Trigger a single version update job."
      option :trigger, type: :string, default: "schedule", desc: "The version update event trigger to use"
      # rubocop:disable Metrics/MethodLength
      def bump(nwo, package_manager)
        _, repo = Util.find(nwo)
        Util.validate_package_manager(package_manager)

        update_config = repo.update_configs.active.find_by(package_manager: package_manager)

        unless update_config
          say "#{nwo} does not have any active update configs for #{package_manager}.", :red
          exit 1
        end

        unless update_config.version_updates_enabled?
          say "#{nwo} does not have version updates enabled for #{package_manager}.", :red
          exit 1
        end

        unless UpdateJob::SCHEDULED_TRIGGER_TYPES.include?(options[:trigger])
          say "Invalid trigger: #{options[:trigger]}", :red
          say "Must be one of #{UpdateJob::SCHEDULED_TRIGGER_TYPES.join(', ')}"
          exit 1
        end

        job = UpdateJob.create!(
          update_config_id: update_config.id,
          trigger_type: options[:trigger]
        )

        PrioritizedJobs::StartUpdateJob.perform_now(job)

        say "Job #{job.id} created.", :green
      end
      # rubocop:enable Metrics/MethodLength
    end
  end
end
