# typed: true
# frozen_string_literal: true

class Hook::Event::DependabotAlertEvent < Hook::Event
  include GitHub::Memoizer

  ACTIONS = %w[
    auto_dismissed
    auto_reopened
    created
    dismissed
    reopened
    fixed
    reintroduced
  ]

  supports_targets *DEFAULT_TARGETS
  description "Dependabot alert #{ACTIONS.to_sentence(two_words_connector: " or ", last_word_connector: ", or ")}."

  event_attr :action, :alert_id, required: true

  delegate :repository, :vulnerability, :vulnerable_version_range, to: :alert, allow_nil: true
  alias_method :target_repository, :repository

  # On dotcom, this will always return true.
  # On GHES, this will only return false if Dependabot Alerts is not enabled for the instance.
  # Returning false disables Dependabot Alert webhooks and removes Dependabot Alerts as an option when adding a new webhook.
  def self.visible_for?(_user, _target)
    SecurityProduct::VulnerabilityAlerts.enabled_for_instance?
  end

  memoize def alert
    RepositoryVulnerabilityAlert.find_by(id: alert_id)
  end

  memoize def actor
    if alert&.last_state_change_actor_id?
      alert.last_state_change_actor || User.ghost
    else
      GitHub.trusted_oauth_apps_owner
    end
  end

  memoize def deliverable?
    ACTIONS.include?(action.to_s) &&
      alert.present? &&
      alert.active? &&
      repository.present? &&
      vulnerability.present? &&
      vulnerable_version_range.present?
  end
end
