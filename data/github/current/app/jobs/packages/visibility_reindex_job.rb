# typed: true
# frozen_string_literal: true

module Packages
  class VisibilityReindexJob < ApplicationJob
    default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

    queue_as :packages_visibility_reindex

    retry_on_dirty_exit

    def perform(repository_id)
      repository = Repository.find_by(id: repository_id)
      repository.packages.each(&:synchronize_search_index) if repository
    end
  end
end
