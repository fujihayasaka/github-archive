# frozen_string_literal: true

require_relative "../advisory_db/config/sources"

ADVISORY_VEA_UPDATE_BATCH_SIZE = 100

namespace :advisory_db do
  namespace :import do
    config = Module.new.extend(AdvisoryDB::Config::Sources)

    desc "Enqueue an ImportJob for each of Advisory DB's sources"
    task all: :environment do
      config.importer_sources.each do |source|
        if ApplicationImporter.importer_for_source(source).auto_import?
          ImportJob.perform_later(source)
        end
      end
    end

    config.importer_sources.each do |source|
      desc %(Enqueue an ImportJob for the "#{source}" source)
      task source => :parse_importer_options do
        if @options.present?
          puts %(Enqueueing "#{source}" import with options: #{@options.inspect})
          ImportJob.perform_later(source, **@options)
        else
          ImportJob.perform_later(source)
        end
      end
    end

    task parse_importer_options: :environment do
      require "optparse"

      parser = OptionParser.new
      parser.banner = "Usage: bin/rake advisory_db:import:<source> -- {options}"

      parser.separator ""

      parser.separator "General importer options:"
      parser.on "--limit=LIMIT", Integer, "Limit the number of feed entries imported"
      parser.on "--[no-]report-to-slack", "Report progress to Slack"

      parser.separator ""

      parser.separator "Specific importer options:"
      parser.on "--cve-id=ID", "NVDImporter", "CVE ID to import"
      parser.on "--cve-review-id=ID", Integer, "CVEReviewImporter", "Database ID of the CVE review to import"
      parser.on "--feed-entries-directory=[DIR]", "BackfillImporter", %(Path to directory containing YAML files to backfill (defaults to "backfill"))
      parser.on "--feed-name=[NAME]", "NVDImporter", %(Optional feed name to import (defaults to "modified"))
      parser.on "--specific-advisory-path=[PATH]", "FriendsOfPHPImporter, GoImporter, RubysecImporter, RustsecImporter, PypaAdvisoryImporter", "Optional path to a specific advisory to import"

      parser.separator ""

      parser.on("--help", "Show this help message") do
        puts parser
        exit
      end

      args = parser.order!(ARGV) do |arg|
        # Ignore non-option arguments
      end

      options = {}
      parser.parse!(args, into: options)
      options.transform_keys! { |key| key.to_s.underscore.to_sym }
      @options = options
    end
  end

  desc "Reserve CVEs if running low on available CVEs"
  task reserve_cves: :environment do
    if AdvisoryDB.cve_automatic_reservation_enabled?
      ReserveCVEJob.perform_later
    end
  end

  desc "Sync older advisory data externally"
  task sync_advisory_data: :environment do
    # resync with dotcom
    AdvisorySyncState.batched_advisory_ids_to_sync(scope: :stale).each do |advisory_id_batch|
      Advisory.where(id: advisory_id_batch).find_each do |advisory|
        PublishAdvisoryToHydroJob.set(queue: :default).perform_later(advisory)
      end
    end

    # resync with repo
    PushAdvisoriesToRepoJob.set(queue: :default).perform_later(scope: :stale) if ENV["FEATURE_FLAG_RUN_PUSH_ADVISORIES_TO_REPO_JOB"] == "true"
  end

  desc "Start a process to control the rate of GitHub API calls"
  task throttle_github: :environment do
    require "github_throttle"
    GitHubThrottle.print_tickets
  end

  desc "Start the primary hydro processor which handles various hydro messages"
  task primary_hydro_processor: [:environment, :create_kafka_topics_for_dev] do
    GitHub::Telemetry::Logs.logger.info "Starting Primary Hydro Processor"
    begin
      AdvisoryDB.primary_hydro_executor.run
      GitHub::Telemetry::Logs.logger.info "Primary Hydro Processor has stopped"
    rescue StandardError => error
      GitHub::Telemetry::Logs.logger.error(
        "There was an error running the hydro_primary_hydro_executor",
        exception: error,
      )
      raise error
    end
  end

  desc "Create the topic for AdvisoryPrediction hydro messages (dev environment only)"
  task create_kafka_topics_for_dev: :environment do
    AdvisoryDB.create_kafka_topics_for_dev
  end

  desc "Run job to calculate and deliver stats on various review queue depths"
  task send_curation_queue_stats: :environment do
    SendCurationQueueStatsJob.perform_later
  end
end
