# Delete manifests and dependencies associated with 1 or more target Manifest-model filtering fields
# Originally implemented for go.sum cleanup as per https://github.com/github/dependency-graph/issues/655
# Dotcom usage: run in #dg-ops .transitions run <PR url> <environment> clear_manifest_data.rb [-r]

require "optparse"
require_relative "../../config/environment"

module Transitions
  class ClearManifestData
    MAX_ATTEMPTS = 5
    MANIFEST_BATCH_SIZE = 50
    DEPENDENCY_BATCH_SIZE = 500

    attr_reader :manifests_deleted, :dependencies_deleted

    def initialize(opts = {})
      @options = opts
      @max_attempts = @options[:max_attempts] || MAX_ATTEMPTS
      @manifest_batch_size = @options[:manifest_batch_size] || MANIFEST_BATCH_SIZE
      @dependency_batch_size = @options[:dependency_batch_size] || DEPENDENCY_BATCH_SIZE
      @manifests_deleted = 0
      @dependencies_deleted = 0
      @entries_deleted = 0
      @throttler = Freno::Throttler.new(client: Freno.client, app: :dependency_graph)
    end

    def execute
      filters = @options[:filters]
      raise "required option missing: filters (Hash)" if filters.nil? || filters.empty?

      log(message: "Starting cleanup of manifests filtered by #{filters} and associated dependencies...")
      begin
        ActiveRecord::Base.connected_to(role: :reading) do
          Manifest.where(filters).select(:id).in_batches(of: @manifest_batch_size).each do |batch|
            log(message: "Fetched batch of #{batch.count} manifest IDs to process")
            batch.distinct.each do |manifest|
              cleanup_manifest_and_dependencies(manifest.id)
            end
          end
        end

        log(message: "Completed cleanup of manifests filtered by #{filters} and associated dependencies")

      rescue => e
        log(error: e.class.to_s, message: "FATAL ERROR: shutting down", details: e.to_s)
        Failbot.report(e)
        raise e
      end
    end

    private

    def cleanup_manifest_and_dependencies(manifest_id)
      before_deps_delete_count = @dependencies_deleted

      (1..@max_attempts).each do |attempts|
        begin
          log(message: "processing manifest ID #{manifest_id}", attempt: attempts)

          attempt_cleanup_once(manifest_id, attempts)
          associated_deps_deleted = @dependencies_deleted - before_deps_delete_count

          log(message: "completed delete of manifest ID #{manifest_id} and #{associated_deps_deleted} associated dependency records")
          return # break loop

        rescue StandardError => se
          log(
            message: "Error while deleting data associated with manifest ID #{manifest_id}. #{attempts < @max_attempts ? "Retrying..." : "Aborting!"}",
            attempt: attempts,
            error: se.class.to_s,
            details: se.to_s)

          if attempts == @max_attempts
            raise se
          else
            sleep(0.5 * attempts)
          end
        end
      end
    end

    def attempt_cleanup_once(manifest_id, attempt_counter)
      ActiveRecord::Base.connected_to(role: :writing) do
        @throttler.throttle(:"dependency-graph") do
          # delete potentially large number of dependencies associated w/manifest in small batches
          ManifestDependency.where(manifest_id: manifest_id).in_batches(of: @dependency_batch_size).each do |batch|
            log(message: "deleting batch of #{batch.count} dependencies associated with manifest ID #{manifest_id}", attempt: attempt_counter)

            if !@options[:dry_run]
              @dependencies_deleted += batch.delete_all
            end
          end

          # delete ManifestEntries
          # @entries_deleted is updated here, but currently not read anywhere
          if DependencyGraph.use_normalized_tables? && ManifestEntry.table_exists?
            ManifestEntry.where(manifest_id: manifest_id).in_batches(of: @dependency_batch_size).each do |batch|
              log(message: "deleting batch of #{batch.count} ManifestEntries associated with manifest ID #{manifest_id}", attempt: attempt_counter)

              if !@options[:dry_run]
                @entries_deleted += batch.delete_all
              end
            end
          end

          # lastly, delete the parent manifest if this isn't a retry
          if Manifest.find(manifest_id)
            log(message: "deleting manifest ID #{manifest_id}", attempt: attempt_counter)

            if !@options[:dry_run]
              Manifest.delete(manifest_id)
              @manifests_deleted += 1
            end
          end
        end
      end
    end

    def log(**kvs)
      DependencyGraph.logger.info({
        "gh.dependency_graph.transition.name": self.class.to_s,
        "gh.dryrun": @options[:dry_run],
        "gh.dependency_graph.transition.manifests_deleted": @manifests_deleted,
        "gh.dependency_graph.transition.dependencies_deleted": @dependencies_deleted,
      }.merge!(kvs))
    end
  end
end
