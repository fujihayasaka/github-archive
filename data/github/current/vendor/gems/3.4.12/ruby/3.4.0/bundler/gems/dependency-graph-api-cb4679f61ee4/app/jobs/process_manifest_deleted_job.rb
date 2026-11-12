# frozen_string_literal: true

require_relative "../../lib/manifest_deleter"

class ProcessManifestDeletedJob < RetryJob
  include DependencyGraph::Tracing

  trace_method :delete_manifest, span_attribute_extractor: -> (_instance, *args, **_kwargs) { ProcessManifestDeletedJob.tags_for_message(args[0]) }

  queue_as { :manifest_deleted }

  def self.tags_for_message(message)
    {
      "gh.repo.id" => message.fetch(:repository_id, "UNKNOWN"),
      "gh.dependency_graph.manifest.path" => message.dig(:manifest_file, :path) || "UNKOWN",
      "gh.dependency_graph.manifest.filename" => message.dig(:manifest_file, :filename) || "UNKNOWN",
      "gh.repo.name_with_owner" => message.fetch(:repository_nwo, "UNKNOWN")
    }
  end

  def perform(manifest_deleted_message, log_context: {})
    log_tags = ProcessManifestDeletedJob.tags_for_message(manifest_deleted_message)
    DependencyGraph.logger.with_named_tags(log_tags.merge(log_context)) do
      DependencyGraph.logger.info("Attempting to delete manifests")

      begin
        Instrument.time("etl.repo_manifest_file_deleted.runtime") do
          delete_manifest(manifest_deleted_message)
        end

        DependencyGraph.logger.info("Deleted manifest")
      rescue ArgumentError => ae
        DependencyGraph.logger.error("ManifestDeleter failed to locate repo manifest",
          "gh.dependency_graph.error.message": "#{ae.message}")
      rescue StandardError => se
        # deleter should only ever throw ArgumentError, but unhandled errors
        # were observed while the ManifestDeleter lived in in the Hydro consumer,
        # so let's see if anything surfaces here. If not, we can narrow this rescue
        DependencyGraph.logger.error("Unexpected error while deleting manifest",
          "gh.dependency_graph.error.type": "#{se.class}",
          "gh.dependency_graph.error.message": "#{se.message}")
      end
    end
  end

  def delete_manifest(message)
    # perform best-effort manifest deletion and log errors
    delete_params = format_params(message)
    ManifestDeleter.run!(delete_params)
  end

  def format_params(job_params)
    {
      repository_id: job_params[:repository_id],
      manifest_file: {
        filename: job_params.dig(:manifest_file, :filename) || "UNKNOWN",
        path: job_params.dig(:manifest_file, :path) || "",
      }
    }
  end
end
