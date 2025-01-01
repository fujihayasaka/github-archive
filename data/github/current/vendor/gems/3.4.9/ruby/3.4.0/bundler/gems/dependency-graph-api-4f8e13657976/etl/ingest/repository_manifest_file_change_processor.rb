# Public: Merges manifests from the ETL pipeline into the dependency graph.
module Ingest
  class RepositoryManifestFileChangeProcessor < Processor
    def initialize(name: "repo_manifest_file_change", debug: false)
      super
    end

    def consume_message(hydro_message)
      ProcessManifestJob.perform_later(hydro_message.value.with_indifferent_access, log_context: get_logging_context(hydro_message))
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
