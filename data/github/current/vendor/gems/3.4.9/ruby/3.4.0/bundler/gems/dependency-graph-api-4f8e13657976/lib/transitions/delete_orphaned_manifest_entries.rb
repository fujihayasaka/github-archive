#!/usr/bin/env ruby

require "csv"

require_relative "../../config/environment"

module Transitions
  class DeleteOrphanedManifestEntries
    include DependencyGraph::Tracing

    DEFAULT_DATA_DIR = "script/transitions/orphaned-manifest-entries-data"
    LOG_KVP_PREFIX = "gh.dependency_graph.delete_orphaned_manifest_entries"

    attr_reader :batch_size, :data_directory, :csv_name, :dry_run, :progress, :deleted, :throttler

    def initialize(batch_size:, csv_name:, dry_run: true, data_directory: DEFAULT_DATA_DIR)
      @batch_size = batch_size
      @data_directory = data_directory
      @csv_name = csv_name
      @dry_run = dry_run
      @progress = 0
      @deleted = 0
      @throttler = DependencyGraph.throttler
    end

    trace_method :execute
    def execute
      start_time = Time.now
      DependencyGraph.logger.with_named_tags(
        "#{LOG_KVP_PREFIX}.batch_size": batch_size,
        "#{LOG_KVP_PREFIX}.csv_name": csv_name,
        "#{LOG_KVP_PREFIX}.dry_run": dry_run,
        "#{LOG_KVP_PREFIX}.progress": progress,
        "#{LOG_KVP_PREFIX}.deleted": deleted) do

        # Read the orphaned manifest IDs from the CSV file
        orphaned_manifest_entries_ids = CSV.read(File.join(Rails.root, data_directory, csv_name), headers: false).flatten.map(&:to_i)
        DependencyGraph.logger.info(
          "Read #{orphaned_manifest_entries_ids.size} orphaned manifest entries IDs from CSV file",
          "#{LOG_KVP_PREFIX}.elapsed": Time.now - start_time
        )
        return if orphaned_manifest_entries_ids.empty?

        orphaned_manifest_entries_ids.each_slice(batch_size) do |manifest_entries_ids|
          process_manifest_entries_batch(manifest_entries_ids)
        end

        DependencyGraph.logger.info(
          "Completed processing orphaned manifest entries",
          "#{LOG_KVP_PREFIX}.elapsed": Time.now - start_time
        )
      end
    end

    def process_manifest_entries_batch(manifest_entries_ids)
      batch_started_at = Time.now
      retries = 0
      max_retries = 3

      begin
        truly_orphaned = filtered_manifest_entries_ids(manifest_entries_ids)

        if truly_orphaned.any? && !dry_run
          @deleted += delete_orphaned_manifest_entries(truly_orphaned)
        end

        @progress += manifest_entries_ids.size
        DependencyGraph.logger.info(
          "Processed batch of #{manifest_entries_ids.size} orphaned manifest entries",
          "#{LOG_KVP_PREFIX}.elapsed": Time.now - batch_started_at,
        )
        return
      rescue ActiveRecord::StatementInvalid, Freno::Throttler::WaitedTooLong, Freno::Throttler::ClientError => e
        Failbot.report(e)
        DependencyGraph.logger.error(
          "Error processing batch of orphaned manifest entries: #{e.class} - #{e.message}",
          "#{LOG_KVP_PREFIX}.error": e.class.to_s,
          "#{LOG_KVP_PREFIX}.message": e.message,
          "#{LOG_KVP_PREFIX}.retries": retries,
          "#{LOG_KVP_PREFIX}.retrying": retries < 3,
        )
        retries += 1
        retry if retries < max_retries
      end
    end

    def filtered_manifest_entries_ids(manifest_entries_ids)
      filtering_started_at = Time.now
      orphaned_manifest_entries_ids = ManifestEntry
        .left_joins(:manifest)
        .where(id: manifest_entries_ids, manifest: { id: nil })
        .pluck(:id)

      DependencyGraph.logger.info(
        "Found #{orphaned_manifest_entries_ids.size} from #{manifest_entries_ids.size} to be truly orphaned manifest entries in batch",
        "#{LOG_KVP_PREFIX}.elapsed": Time.now - filtering_started_at
      )

      Instrument.count("transition.delete_orphaned_manifest_entries.skipped", manifest_entries_ids.size - orphaned_manifest_entries_ids.size)

      orphaned_manifest_entries_ids
    end

    def delete_orphaned_manifest_entries(manifest_entries_ids)
      delete_started_at = Time.now
      throttler.throttle(:"dependency-graph") do
        num_deleted_manifest_entries = ManifestEntry.where(id: manifest_entries_ids).delete_all

        DependencyGraph.logger.info(
          "Deleted #{num_deleted_manifest_entries} from #{manifest_entries_ids.size} orphaned manifest entries in batch",
          "#{LOG_KVP_PREFIX}.elapsed": Time.now - delete_started_at
        )

        Instrument.count("transition.delete_orphaned_manifest_entries.processed", manifest_entries_ids.size)
        Instrument.count("transition.delete_orphaned_manifest_entries.deleted", num_deleted_manifest_entries)

        return num_deleted_manifest_entries
      end
    end
  end
end
