# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class ModelIndexer

      # Public: Manually index models that aren't automatically indexed on
      # AR#save. If a searchable model is imported using the direct insert
      # method and never goes through AR callbacks it should be added here.
      def self.process(current_migration)
        options = { queue: "index_low", purge: true }

        current_migration.by_states(:imported).by_model_type("repository").find_each do |mr|
          Search.add_to_search_index("repository",         mr.model_id, options)
          Search.add_to_search_index("code",               mr.model_id, options)
          Search.add_to_search_index("commit",             mr.model_id, options)
          Search.add_to_search_index("bulk_issues",        mr.model_id, options)
          Search.add_to_search_index("bulk_pull_requests", mr.model_id, options)
        end

        current_migration.by_states(:imported).by_model_type("release").find_each do |mr|
          Search.add_to_search_index("release",           mr.model_id, options)
        end

        current_migration.by_states(:imported).by_model_type("project").find_each do |mr|
          Search.add_to_search_index("project",            mr.model_id, options)
        end
      end
    end
  end
end
