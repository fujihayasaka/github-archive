# typed: true
# frozen_string_literal: true

module Codespaces
  # background job to clean up orphaned prebuild templates and configurations
  class WatchOrphanedPrebuildTemplatesJob < CodespacesJob
    locked_by timeout: 1.hour, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC
    retry_on_dirty_exit

    schedule interval: 1.day, condition: -> { !GitHub.enterprise? }

    BATCH_SIZE = 100

    def perform
      # Loop through all prebuild configs
      repos_ids_cleaned_up = T.let([], T::Array[Integer])
      Codespaces::PrebuildConfiguration.select(:repository_id).where(state: :enabled).distinct.in_batches do |relation|
        repos_ids_cleaned_up += clean_up_repos(relation)
      end

      # Loop through all prebuild templates
      # Exclude any repos that were cleaned up in the previous step
      Codespaces::PrebuildTemplate.select(:repository_id).where.not(repository_id: repos_ids_cleaned_up).distinct.in_batches do |relation|
        clean_up_repos(relation)
      end

    rescue Aqueduct::Worker::JobKilled => e
      GitHub.dogstats.increment("codespaces.clean_up_prebuild_templates_by_repo_job.dirty_exit")
      raise
    end

    def disabled_for_org?(owner)
      owner&.organization? && !Codespaces::OrgPolicy.enabled_by_organization?(owner)
    end

    # sig {params(relation: ActiveRecord::Relation).returns(T::Array[Integer])}
    def clean_up_repos(relation)
      repository_ids_found = []
      repository_ids_with_orphaned_templates = []
      repository_ids = relation.pluck(:repository_id)
      Repository.where(id: repository_ids).find_each do |repository|
        repository_ids_found.push(repository.id)
        next unless repository.deleted? || disabled_for_org?(repository.owner)

        repository_ids_with_orphaned_templates.push(repository.id)
        GitHub.dogstats.increment("codespaces.clean_up_prebuild_templates_by_repo_job.clean_up")
        Codespaces::DeletePrebuildsForRepoJob.perform_later(repository_id: repository.id)
      end

      # clean up any repos no longer found in the DB
      hard_deleted_repo_ids = repository_ids - repository_ids_found
      hard_delete_prebuild_configurations(hard_deleted_repo_ids)
      repository_ids_with_orphaned_templates + hard_deleted_repo_ids
    end

    def hard_delete_prebuild_configurations(hard_deleted_repo_ids)
      hard_deleted_repo_ids.each do |hard_deleted_repo_id|
        GitHub.dogstats.increment("codespaces.clean_up_prebuild_templates_by_repo_job.hard_delete_clean_up")
        Codespaces::DeletePrebuildsForRepoJob.perform_later(repository_id: hard_deleted_repo_id, disable_prebuild_configurations: false, hard_delete_configurations: true)
      end
    end
  end
end
