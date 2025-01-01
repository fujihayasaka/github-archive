# typed: true
# frozen_string_literal: true

# This background job deletes all packages for a given repository in the background to prevent timeouts
# for users with lots of packages.
#
# It is only triggered via Staff Tools for now.

module Packages
  class DeletePackagesForRepositoryJob < ApplicationJob
    default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

    queue_as :delete_packages_for_repository

    retry_on_dirty_exit
    discard_on ActiveRecord::RecordNotFound

    def perform(repository_id:)
      return if GitHub.enterprise?

      repository = Repositories::Public.find_active!(repository_id)
      packages = repository.packages.includes(:package_versions)
      packages.destroy_all
    end
  end
end
