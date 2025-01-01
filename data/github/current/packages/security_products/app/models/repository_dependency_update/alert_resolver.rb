# typed: true
# frozen_string_literal: true

# Acts as a factory class to produce correctly configured RepositoryDependencyUpdate
# objects given a RepositoryVulnerabilityAlert and trigger type.
#
# This class is considered internal to RepositoryDependencyUpdate and should not be
# used directly.
class RepositoryDependencyUpdate::AlertResolver
  attr_reader :alert, :trigger

  FORCE_CREATE_TRIGGERS = %w(
    manual
  )

  MAX_RETRIES = 3

  def initialize(alert, trigger:)
    @alert = alert
    @trigger = trigger.to_s
  end

  def create_update
    # Our app installation will fail on Spammy users but in the event
    # a workflow gets as far as creating a RepositoryDependencyUpdate
    # we should suppress it to avoid distracting noise in our metrics
    # and cleanup process.
    return false if owner_is_spammy?
    return false if repository_inaccessible? || alert_blocked? || update_blocked?

    if retries_count > 0
      GitHub.logger.info(
        "Attempting to create update for alert that previously failed",
        "code.namespace": self.class.name,
        "code.function": "create_update",
        "gh.repo.id": alert.repository.id,
        "gh.security_alerts.id": alert.id,
        "gh.dependabot_updates.attempts_last_30d": retries_count + 1,
        "gh.dependabot_updates.trigger_type": trigger
      )
    end

    create_dependency_update
  end

  private

  def create_dependency_update
    alert.repository.dependency_updates.create!(
      repository_vulnerability_alert: alert,
      manifest_path: alert.vulnerable_manifest_path,
      package_name: alert.vulnerable_version_range.affects,
      reason: :vulnerability,
      trigger_type: trigger,
      dry_run: false,
    )
  end

  def owner_is_spammy?
    alert.repository.owner.spammy?
  end

  # If a repository is not accessible via the API, we shouldn't create a
  # RepositoryDependencyUpdate as Dependabot will not be able to resolve it.
  def repository_inaccessible?
    alert.repository.access.disabled? ||
      alert.repository.owner.has_any_trade_restrictions?
  end

  # We have a very small number of alerts that have a blank vulnerable_manifest_path
  # which breaks our validation rules.
  #
  # Alerts are deliberately created without validation in a long-running batch job
  # so we cannot guarantee to eliminate this problem by adding a validation rule
  # on the alert itself.
  #
  # Given the miniscule number of lifetime occurences we should just block the update
  # and track the event.
  def alert_blocked?
    if alert.vulnerable_manifest_path.blank?
      GitHub.logger.info(
        "manifest-path-missing",
        "code.namespace": "RepositoryDependencyUpdate",
        "code.function": "blocked",
        "gh.dependabot.alert.id": alert.id
      )
      GitHub.dogstats.increment("repository_dependency_update.blocked",
                                tags: [
                                  "trigger:#{trigger}",
                                  "reason:manifest_path_missing",
                                ])
      return true
    end

    repository_alerts_disabled? ||
      alert_not_resolvable? ||
          manifest_path_unsupported?
  end

  def repository_alerts_disabled?
    !alert.repository.vulnerability_alerts_enabled?
  end

  def alert_not_resolvable?
    alert.dismissed? || alert.vulnerable_version_range.fixed_in.blank?
  end

  def manifest_path_unsupported?
    !RepositoryDependencyUpdate.manifest_path_supported?(alert.vulnerable_manifest_path)
  end

  def update_blocked?
    return true unless dependabot_enabled?
    return true unless ecosystem_supported?
    return false if overwrite_allowed?

    work_in_progress? || retries_exceeded?
  end

  # Dependabot is always considered enabled for manual requests as they are
  # explicitly requested by the user, otherwise we defer to Repository config
  # or the user-defined vulnerability alert rules.
  def dependabot_enabled?
    return true if trigger == "manual"

    alert.repository.vulnerability_updates_enabled? || alert.candidate_for_pull_request?
  end

  def overwrite_allowed?
    FORCE_CREATE_TRIGGERS.include? trigger
  end

  def ecosystem_supported?
    Dependabot.security_updates_supported?(package_ecosystem: alert.vulnerable_version_range.ecosystem)
  end

  def work_in_progress?
    previous_alert_updates.where.not(state: :error).any?
  end

  def retries_exceeded?
    retries_count >= MAX_RETRIES
  end

  def retries_count
    previous_alert_updates.where("created_at > ?", 30.days.ago).count
  end

  def previous_alert_updates
    alert.repository_dependency_updates.visible
  end
end
