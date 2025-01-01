# typed: true
# frozen_string_literal: true

# This background job will look up all repositories for an owner
# and enqueue `DockerMigrationResetBillingRepositoryJob` for each repository
# that was found.
#
# For now, this job is invoked manually via the Rails console but there will
# be a mechanism to run it automatically in the future.

module Packages
  class DockerMigrationResetBillingOwnerJob < ApplicationJob
    queue_as :packages_docker_migration_reset_billing_owner

    retry_on_dirty_exit
    discard_on ActiveRecord::RecordNotFound

    def perform(owner_id:)
      return unless GitHub.billing_enabled?

      user = User.find(owner_id)

      find_docker_repositories(user: user) do |repository_id|
        Packages::DockerMigrationResetBillingRepositoryJob.perform_later(repository_id: repository_id)
      end
    end

    private

    def find_docker_repositories(user:)
      user
        .repositories
        .joins(:packages)
        .merge(Registry::Package.not_deleted.docker)
        .in_batches do |repositories_relation|
          repositories_relation.pluck(:id).each do |repository_id|
            yield(repository_id)
          end
        end
    end
  end
end
