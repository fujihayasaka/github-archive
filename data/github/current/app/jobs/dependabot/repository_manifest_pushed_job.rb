# typed: true
# frozen_string_literal: true

# Builds any new fixes required after a Repository has pushed a diff containing
# manifest changes.
class Dependabot::RepositoryManifestPushedJob < ApplicationJob
  use_primaries ApplicationRecord::Notify

  queue_as :dependabot

  retry_on_dirty_exit

  # dependabot_install_time is not used and should be removed. Left in for now to avoid failing enqueued jobs with
  # that data already populated.
  def self.enqueue(repository)
    return unless vulnerability_updates_enabled?(repository)
    return if repository.dependabot_updates_paused?

    perform_later(repository.id)
  end

  def self.vulnerability_updates_enabled?(repository)
    # Dependabot should avoid creating RepositoryDependencyUpdate rows and dispatching
    # jobs to the service for spammy users as it is both a waste of resources and a
    # potential abuse vector
    return false if repository.owner&.spammy?

    repository.vulnerability_updates_enabled? ||
      RepositoryVulnerabilityAlertRules.new(repository: repository).enabled_update_rules.any?
  end

  def perform(repository_id)
    repository = Repository.find_by(id: repository_id)

    return unless repository
    return unless self.class.vulnerability_updates_enabled?(repository)

    # A manifest push can generate a large volume of RepositoryDependencyUpdate
    # rows, so lets throttle for safety.
    RepositoryDependencyUpdate.throttle do
      RepositoryDependencyUpdate.request_for_repository(repository, trigger: :push)
    end
  end
end
