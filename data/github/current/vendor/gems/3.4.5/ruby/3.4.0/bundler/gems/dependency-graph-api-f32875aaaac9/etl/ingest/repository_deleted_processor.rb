# frozen_string_literal: true

module Ingest
  class RepositoryDeletedProcessor < Processor
    def initialize(name: "repo_deleted", debug: false)
      super
    end

    def consume_message(message)
      github_repository_id = message.value.with_indifferent_access[:repository_id]
      repo_table_id = Repository.select(:id).find_by(github_repository_id: github_repository_id)&.id

      if repo_table_id.blank?
        DependencyGraph.logger.info(
          fn: :repository_deleted_processor,
          github_repository_id: github_repository_id,
          log_message: "Couldn't find Repository to delete based off of github_repository_id",
        )
      else
        Repository.destroy(repo_table_id)
      end
    end

    # Used by `script/etl/tail_repositories_delete`
    # Print just enough to debug, not enough to potentially expose PII.
    def consume_debug_message(message)
      github_repository_id = message.value.with_indifferent_access[:repository_id]
      puts "Repository #{github_repository_id} deleted."
    end
  end
end
