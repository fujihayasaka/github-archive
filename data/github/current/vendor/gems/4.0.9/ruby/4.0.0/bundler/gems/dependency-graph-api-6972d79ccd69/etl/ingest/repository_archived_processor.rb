# frozen_string_literal: true

module Ingest
  class RepositoryArchivedProcessor < Processor
    def initialize(name: "repo_archived_status_change", debug: false)
      super
    end

    def consume_message(message)
      data = message.value

      if data[:is_archived]
        repo = Repository.find_by(github_repository_id: data[:repository_id])
        DependencyGraph.logger.info("Deleting archived repository",
          "gh.repo.id" => data[:repo_id],
          "gh.dependency_graph.dg_repo_id" => repo&.id
        )
        Repository.destroy(repo.id) unless repo.blank?
      end
    end

    def consume_debug_message(message)
      debug_message = {
        partition: message.partition,
        offset: message.offset,
        repository_id: message.value[:repository_id],
        is_archived: message.value[:is_archived]
      }

      puts debug_message
    end
  end
end
