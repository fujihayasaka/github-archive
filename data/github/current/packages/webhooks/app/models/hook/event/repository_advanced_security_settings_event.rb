# typed: true
# frozen_string_literal: true

class Hook::Event::RepositoryAdvancedSecuritySettingsEvent < Hook::Event
  supports_targets Business, *DEFAULT_TARGETS

  description "Repository advanced security settings edited."

  event_attr :action, :actor_id, :repository_id, required: true
  event_attr :changes

  # if we haven't enabled migration vnext webhooks, handle this as if it's feature flagged
  # if it's enabled, don't raise it as feature flagged so wildcard works
  def self.feature_flagged?
    !GitHub.elm_internal_webhooks_enabled?
  end

  # if migration vnext webhooks are enabled, this is visible
  def self.visible_for?(user, target)
    GitHub.elm_internal_webhooks_enabled?
  end

  def feature_flag_enabled?
    GitHub.elm_internal_webhooks_enabled?
  end

  def target_repository
    # this includes both active and deleted repositories
    @target_repository ||= Repositories.domain.by_id(repository_id)
  end

  def actor
    @actor ||= User.find_by(id: actor_id) || User.ghost
  end

  def deliverable?
    target_repository.present?
  end

  def changes
    return unless changes_attr

    {}.tap do |hash|
      if is_edited_action?
        [:vulnerability_alerts_enabled, :dependency_graph_enabled].each do |attr|
          if changes_attr.has_key?(attr)
            new_value = changes_attr[attr]
            hash[attr] = { to: new_value }
          end
        end
      end
    end
  end

  private

  def changes_attr
    attributes.with_indifferent_access[:changes]
  end

  def is_edited_action?
    action.to_sym == :edited
  end
end
