# frozen_string_literal: true

require "json"

class CreateSecurityUpdateJob < ApplicationJob
  queue_as :default
  default_retries_for_idempotent_jobs

  attr_reader :update_config, :dependency_update, :advisory, :dependencies, :feature_flags, :directories

  def perform(update_config:, dependency_update:, advisory:, dependencies: nil, feature_flags: [], directories: nil)
    Dependabot::Exceptions.push(
      "gh.ghsa_id": advisory.ghsa_id,
      "gh.owner.id": update_config.repo.account.github_id,
      "gh.repo.id": update_config.repo.github_id,
    )

    @update_config = update_config
    @dependency_update = dependency_update
    @advisory = advisory
    @feature_flags = feature_flags
    @dependencies = dependencies
    @directories = directories

    return if already_processing_for_ghsa?

    job = create_update_job
    enqueue_update_job(job)
  end

  private

  def grouped_security_updates_requested?
    # NOTE: This is NOT a dependabot-api feature flag. It's a field on the hydro message.
    feature_flags.include?("grouped_security_updates") ||
      update_config.dependency_groups.any?(&:applies_to_security_updates?)
  end

  def dependencies_targeted_by_alert
    if grouped_security_updates_requested?
      dependencies
    else
      [advisory.dependency_name]
    end
  end

  def create_update_job
    dependencies = dependencies_targeted_by_alert

    update_config.update_jobs.create!(
      command: :security,
      github_request_id: dependency_update.id,
      triggered_at: dependency_update.triggered_at,
      dependencies: dependencies,
      directories: directories,
      security_updates_only: true,
      trigger_type: dependency_update.trigger,
      triggered_by_ghsa_id: advisory.ghsa_id,
      dry_run: dependency_update.dry_run?,
    ).tap do |update_job|
      update_job.increment_metric("security_update.triggered")
    end
  end

  def already_processing_for_ghsa?
    update_config.update_jobs.security_updates.where(dependencies: dependencies_targeted_by_alert).any? do |job|
      job.in_state?(:pending, :enqueued, :processing)
    end
  end

  def enqueue_update_job(job)
    PrioritizedJobs::StartUpdateJob.perform_later(job)
  end
end
