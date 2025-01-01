# frozen_string_literal: true
require_relative "../../lib/manifest_deleter"


module Ingest
  class RepositoryManifestFileDeletedProcessor < Processor
    def initialize(name: "repo_manifest_file_deleted", debug: false)
      super
    end

    def consume_message(hydro_message)
      message = hydro_message.value.with_indifferent_access
      manifest_tag_value = message.dig(:manifest_file, :filename) || "UNKNOWN"

      DependencyGraph.logger.with_named_tags({
        "gh.repo.id" => message.fetch(:repository_id, "UNKNOWN"),
        "gh.dependency_graph.manifest.path" => message.dig(:manifest_file, :path) || "UNKOWN",
        "gh.dependency_graph.manifest.filename" => message.dig(:manifest_file, :filename) || "UNKNOWN",
        "gh.repo.name_with_owner" => message.fetch(:repository_nwo, "UNKNOWN") }) do

        enqueued = ProcessManifestDeletedJob.perform_later(message, log_context: get_logging_context(hydro_message))
        if enqueued.nil?
          Instrument.increment("etl.repo_manifest_file_deleted.job_submitted",
            manifest: manifest_tag_value,
            result: "failed")
        else
          Instrument.increment("etl.repo_manifest_file_deleted.job_submitted",
            manifest: manifest_tag_value,
            result: "success")
          DependencyGraph.logger.info("Enqueue static manifest deletion job",
             "gh.active_job_id" => enqueued.job_id,
             "gh.aqueduct.queue.name" => enqueued.queue_name)
        end

        if snapshots_enabled_for?(message)
          enqueued = DeleteManifestSnapshotJob.perform_later(message, get_logging_context(hydro_message))
          unless enqueued.nil?
            DependencyGraph.logger.info("enqueued snapshot manifest deletion job",
              "gh.active_job_id" => enqueued.job_id,
              "gh.aqueduct.queue.name" => enqueued.queue_name)
          end
        end
      end
    end

    def consume_debug_message(hydro_message)
      debug_message = {
        :partition => hydro_message.partition,
        :offset => hydro_message.offset,
        "gh.dependency_graph.manifest.path" => message.dig(:manifest_file, :path) || "UNKNOWN",
        :repo_id => hydro_message.value.with_indifferent_access.fetch(:repository_id, "UNKNOWN"),
        :filename => hydro_message.value.with_indifferent_access.dig(:manifest_file, :filename) || "UNKNOWN",
      }

      puts debug_message
    end

    def get_processor_specific_logging_context(hydro_message)
      message = hydro_message.value.with_indifferent_access
      {
        "gh.dependency_graph.manifest.path" => message.dig(:manifest_file, :path) || "UNKNOWN",
        "gh.dependency_graph.manifest.filename" => message.dig(:manifest_file, :filename) || "UNKNOWN",
        "gh.repo.id" => message.fetch(:repository_id, "UNKNOWN"),
        "gh.repo.name_with_owner" => message.fetch(:repository_nwo, "UNKNOWN"),
      }
    end

  end
end
