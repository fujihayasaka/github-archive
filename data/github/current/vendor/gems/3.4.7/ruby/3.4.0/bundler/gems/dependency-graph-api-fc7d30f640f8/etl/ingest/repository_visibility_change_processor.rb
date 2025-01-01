# frozen_string_literal: true

module Ingest
  class RepositoryVisibilityChangeProcessor < Processor
    def initialize(name: "repo_visibility_change", debug: false)
      super
    end

    def consume_message(message)
      data = message.value.with_indifferent_access
      repo_id = data[:repository_id]
      is_public = data[:new_visibility] == :PUBLIC

      Repository.where(github_repository_id: repo_id).update_all(public: is_public)
    end

    def consume_debug_message(message)
      debug_message = {
        partition: message.partition,
        offset: message.offset,
        repo_id: message.value.with_indifferent_access[:repository_id],
        new_visibility: message.value.with_indifferent_access[:new_visibility]
      }

      puts debug_message
    end
  end
end
