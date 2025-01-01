# typed: true
# frozen_string_literal: true

# This is a background job that is usually only triggered by `DockerMigrationResetBillingOwnerJob`.
#
# Since Docker usage data has been inherently unreliable in the past, its purpose is to query
# knowable usage data and infer the amount of Docker usage contained in the usage reported by billing.
#
# Once the assumed Docker usage is calculated, it will submit the difference to billing in order to
# take Docker usage out of the equation for now.

module Packages
  class DockerMigrationResetBillingRepositoryJob < ApplicationJob
    default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

    queue_as :packages_docker_migration_reset_billing_repository

    # In case of an error, wait long enough for hydro to process messages until we try again
    def self.retry_on_dirty_exit_with_wait
      wait_time = 5.minutes

      retry_on Aqueduct::Worker::JobKilled, wait: wait_time
    end

    retry_on_dirty_exit_with_wait
    discard_on ActiveRecord::RecordNotFound

    def perform(repository_id:)
      repository = Repositories::Public.get_active_or_deleted!(repository_id)
      docker_usage = calculate_docker_usage(repository)

      submit_corrected_values(repository, docker_usage)
    end

    private

    def calculate_docker_usage(repository)
      storage_usage = Registry::StorageUsage.new(owner: repository.owner, repository: repository)

      combined_usage = storage_usage.billing_combined_usage
      actions_usage = storage_usage.billing_actions_usage
      non_docker_usage = storage_usage.packages_non_docker_usage
      docker_usage = combined_usage - actions_usage - non_docker_usage

      GitHub.logger.info(
        "code.function" => __method__,
        "code.namespace" => self.class.name,
        "gh.container-registry.owner_name" => repository.owner.name,
        "gh.container-registry.repository_name" => repository.name,
        "gh.container-registry.combined_usage" => combined_usage,
        "gh.container-registry.actions_usage" => actions_usage,
        "gh.container-registry.non_docker_usage" => non_docker_usage,
        "gh.container-registry.docker_usage" => docker_usage,
      )

      docker_usage
    end

    def submit_corrected_values(repository, docker_usage)
      return if docker_usage == 0

      if docker_usage > 0
        correct_positive_usage(repository, docker_usage)
      else
        correct_negative_usage(repository, docker_usage)
      end
    end

    def correct_positive_usage(repository, docker_usage)
      fake_package, fake_version = fake_data_for_events(repository)

      delete_package_version_data = {
        actor: nil,
        package: fake_package,
        version: fake_version,
        size: docker_usage,
        files_count: 1,
        deleted_at: Time.now,
        storage_service: "AWS_S3",
        user_agent: nil,
        via_actions: false,
      }

      GitHub.logger.info(
        "code.function" => __method__,
        "code.namespace" => self.class.name,
        "gh.container-registry.owner_name" => repository.owner.name,
        "gh.container-registry.repository_name" => repository.name,
        "gh.container-registry.size" => docker_usage,
      )

      GlobalInstrumenter.instrument("package_registry.package_version_deleted", delete_package_version_data)
    end

    def correct_negative_usage(repository, docker_usage)
      fake_package, fake_version = fake_data_for_events(repository)
      size = docker_usage.abs

      file_published_data = {
        actor: nil,
        package: fake_package,
        version: fake_version,
        size: size,
        files_count: 1,
        published_at: Time.now,
        storage_service: "AWS_S3",
        user_agent: nil,
        via_actions: false,
        file: nil,
      }

      GitHub.logger.info(
        "code.function" => __method__,
        "code.namespace" => self.class.name,
        "gh.container-registry.owner_name" => repository.owner.name,
        "gh.container-registry.repository_name" => repository.name,
        "gh.container-registry.size" => size,
      )

      GlobalInstrumenter.instrument("package_registry.package_file_published", file_published_data)
    end

    def fake_data_for_events(repository)
      fake_package = Registry::Package.new(
        id: 0, # some ID value is required for populating the global_id field in a hydro payload
        name: "DockerMigrationDelete",
        owner: repository.owner,
        repository: repository,
        package_type: :docker,
        # Message serializers depend on this timestamp to be there
        created_at: Time.now.utc,
        updated_at: Time.now.utc,
      )

      fake_version = Registry::PackageVersion.new(
        id: 0, # some ID value is required for populating the global_id field in a hydro payload
        package: fake_package,
        version: "1.3.3.7-docker-migration",
        author: repository.owner,
        # Message serializers depend on this timestamp to be there
        created_at: Time.now.utc,
        updated_at: Time.now.utc,
      )

      [fake_package, fake_version]
    end
  end
end
