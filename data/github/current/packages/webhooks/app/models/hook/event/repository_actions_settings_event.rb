# typed: true
# frozen_string_literal: true

class Hook::Event::RepositoryActionsSettingsEvent < Hook::Event
  supports_targets Repository

  event_attr :action, :actor_id, :repo_id, required: true

  event_attr :old_policy,
    :new_policy,
    :updated_access_policy,
    :updated_allowed_types,
    :updated_github_owned_allowed,
    :updated_sha_pinning_required,
    :updated_verified_allowed,
    :updated_patterns,

  def self.feature_flagged?
    !GitHub.elm_internal_webhooks_enabled?
  end

  def self.visible_for?(user, target)
    GitHub.elm_internal_webhooks_enabled?
  end

  def feature_flag_enabled?
    GitHub.elm_internal_webhooks_enabled?
  end

  def target_repository
    Repository.find_by(id: repo_id)
  end

  def actor
    @actor ||= User.find_by(id: actor_id) || User.ghost
  end

  def deliverable?
    target_repository.present?
  end
end
