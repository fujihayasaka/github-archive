# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Packages
  class VisibilityReindexJob < ApplicationJob
    queue_as :packages_visibility_reindex

    retry_on_dirty_exit

    def perform(repository_id)
      repository = if FeatureFlag.vexi.enabled?(:repos_by_id_jobs, default: false)
        Repositories.domain.by_id(repository_id)
      else
        Repository.find_by(id: repository_id)
      end
      T.cast(repository, Repository).packages.each(&:synchronize_search_index) if repository # rubocop:todo GitHub/AvoidCast
    end
  end
end
