#!/usr/bin/env ruby

require "csv"

require_relative "../../config/environment"

module Transitions
  class DestroyOrphanedManifests
    include DependencyGraph::Tracing

    DEFAULT_DATA_DIR = "script/transitions/orphaned-manifests-data"
    LOG_KVP_PREFIX = "gh.dependency_graph.destroy_orphaned_manifests"

    attr_reader :batch_size, :data_directory, :csv_name, :dry_run, :progress, :destroyed, :throttler

    def initialize(batch_size:, csv_name:, dry_run: true, data_directory: DEFAULT_DATA_DIR)
      @batch_size = batch_size
      @data_directory = data_directory
      @csv_name = csv_name
      @dry_run = dry_run
      @progress = 0
      @destroyed = 0
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
        "#{LOG_KVP_PREFIX}.destroyed": destroyed) do

        # Read the orphaned manifest IDs from the CSV file
        orphaned_manifest_ids = CSV.read(File.join(Rails.root, data_directory, csv_name), headers: false).flatten.map(&:to_i)
        DependencyGraph.logger.info(
          "Read #{orphaned_manifest_ids.size} orphaned manifest IDs from CSV file",
          "#{LOG_KVP_PREFIX}.elapsed": Time.now - start_time
        )
        return if orphaned_manifest_ids.empty?

        orphaned_manifest_ids.each_slice(batch_size) do |manifest_ids|
          process_manifests_batch(manifest_ids)
        end

        DependencyGraph.logger.info(
          "Completed processing orphaned manifests",
          "#{LOG_KVP_PREFIX}.elapsed": Time.now - start_time
        )
      end
    end

    def process_manifests_batch(manifest_ids)
      batch_started_at = Time.now
      retries = 0
      max_retries = 3

      begin
        truly_orphaned = filtered_manifest_ids(manifest_ids)

        if truly_orphaned.any? && !dry_run
          @destroyed += destroy_orphaned_manifests(truly_orphaned)
        end

        @progress += manifest_ids.size
        DependencyGraph.logger.info(
          "Processed batch of #{manifest_ids.size} orphaned manifests",
          "#{LOG_KVP_PREFIX}.elapsed": Time.now - batch_started_at,
        )
        return
      rescue ActiveRecord::StatementInvalid, Freno::Throttler::WaitedTooLong, Freno::Throttler::ClientError => e
        Failbot.report(e)
        DependencyGraph.logger.error(
          "Error processing batch of orphaned manifests: #{e.class} - #{e.message}",
          "#{LOG_KVP_PREFIX}.error": e.class.to_s,
          "#{LOG_KVP_PREFIX}.message": e.message,
          "#{LOG_KVP_PREFIX}.retries": retries,
          "#{LOG_KVP_PREFIX}.retrying": retries < 3,
        )
        retries += 1
        retry if retries < max_retries
      end
    end

    def filtered_manifest_ids(manifest_ids)
      filtering_started_at = Time.now
      orphaned_manifest_ids = Manifest
        .left_joins(:repository)
        .where(id: manifest_ids, repository: { id: nil })
        .pluck(:id)

      DependencyGraph.logger.info(
        "Found #{orphaned_manifest_ids.size} from #{manifest_ids.size} to be truly orphaned manifests in batch",
        "#{LOG_KVP_PREFIX}.elapsed": Time.now - filtering_started_at
      )

      Instrument.count("transition.destroy_orphaned_manifests.skipped", manifest_ids.size - orphaned_manifest_ids.size)

      orphaned_manifest_ids
    end

    def destroy_orphaned_manifests(manifest_ids)
      destroy_started_at = Time.now
      throttler.throttle(:"dependency-graph") do
        destroyed_manifests = Manifest.where(id: manifest_ids).destroy_all

        DependencyGraph.logger.info(
          "Destroyed #{destroyed_manifests.size} from #{manifest_ids.size} orphaned manifests in batch",
          "#{LOG_KVP_PREFIX}.elapsed": Time.now - destroy_started_at
        )

        Instrument.count("transition.destroy_orphaned_manifests.processed", manifest_ids.size)
        Instrument.count("transition.destroy_orphaned_manifests.destroyed", destroyed_manifests.size)

        return destroyed_manifests.size
      end
    end
  end
end
