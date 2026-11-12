# frozen_string_literal: true

module Rebaseable
  extend ActiveSupport::Concern

  def create_rebase_update_jobs(manual: false)
    raise "Invalid state" unless in_state?(:updating)

    # Ordering of the dependencies list is important for multi-dependency
    # PRs because the update checker uses it to determine which is the
    # "primary" dependency being updated.
    dependencies = updated_dependencies.order(:id)

    # Carry over `security_updates_only`, which is set when the update job
    # is in response to a security alert.
    security_updates_only = update_job&.security_updates_only || false

    # Carry over `github_request_id` so that the new rebase job has a link
    # to the `RepositoryDependencyUpdate` record in GitHub.
    github_request_id = update_job&.github_request_id

    update_job_ids = rebase_update_config_ids.each_with_index.map do |update_config_id, index|
      # link_to_transition is true only for the first job. This avoids issues with the
      # belongs_to/has_one relationship between UpdateJob and PullRequestTransition where
      # multiple jobs pointing to the same transition would cause lookup failures in
      # CombinePullRequestsAfterJobsCompletion.
      create_rebase_update_job(
        update_config_id:,
        dependencies:,
        security_updates_only:,
        github_request_id:,
        manual:,
        link_to_transition: index.zero?,
      )
    end
    UpdateJob.where(id: update_job_ids)
  end

  def rebase_update_config_ids
    return multi_ecosystem_config.update_configs.ids if multi_ecosystem_config_id?

    [update_config.id]
  end

  private

  def create_rebase_update_job(update_config_id:, dependencies:, security_updates_only:, github_request_id:, manual:,
                               link_to_transition: true)
    raise "Invalid state" unless in_state?(:updating)

    update_config = UpdateConfig.find(update_config_id)
    ecosystem_package_manager = update_config.package_manager
    ecosystem_dependencies = dependencies.select { |dep| dep.package_manager == ecosystem_package_manager }
    directories = determine_directories(ecosystem_dependencies, update_config)

    UpdateJob.create(
      command: :recreate,
      directories: directories,
      update_config_id: update_config_id,
      pull_request_transition_id: link_to_transition ? last_transition&.id : nil,
      dependencies: ecosystem_dependencies.map(&:name),
      github_request_id: github_request_id,
      pull_request_transition: link_to_transition ? last_transition : nil,
      security_updates_only: security_updates_only,
      trigger_type: manual ? "manual_rebase" : "rebase",
      enqueue_scheduled_update_id: enqueue_scheduled_update_id,
    )
  end

  def determine_directories(ecosystem_dependencies, update_config)
    if update_config.multi_ecosystem_config_id
      dirs = ecosystem_dependencies.map(&:directory).uniq
      return dirs unless dirs.empty?

      return update_config.manifest_directories.to_a
    end

    affected_directories
  end

  def enqueue_scheduled_update_id
    @enqueue_scheduled_update_id ||= SecureRandom.uuid
  end
end
