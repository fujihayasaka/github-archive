# typed: true
# frozen_string_literal: true

class Hook::Event::PageEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS
  description "Repository Page settings created, updated, or deleted."

  event_attr :action, :page_id, required: true
  event_attr :changes, :repository_id

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

  def page
    @page ||= Page.find_by(id: page_id)
  end

  def target_repository
    @target_repository ||= (repository_id ? Repository.find_by(id: repository_id) : page.repository)
  end

  # Because we're instrumenting the model, we may not have an actor; but Hook::Event requires one.
  def actor
    target_repository&.owner || User.ghost
  end

  def deliverable?
    target_repository.present?
  end

  def changes
    return unless changes_attr

    {}.tap do |hash|
      changes_attr.keys.each do |attr|
        hash[attr] = { from: changes_attr[attr].first }
      end
    end
  end

  private

  def changes_attr
    attributes.with_indifferent_access[:changes]
  end
end
