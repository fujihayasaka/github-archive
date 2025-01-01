# typed: true
# frozen_string_literal: true

# this handles autolink events based on packages/repositories/app/models/key_link
class Hook::Event::AutolinkEvent < Hook::Event
  supports_targets Repository
  description "An autolink reference is created or deleted"

  event_attr :action, :autolink_id, :key_prefix, :url_template, :repository_id, required: true
  event_attr :is_alphanumeric

  # if we haven't enabled elm migration webhooks, handle this as if it's feature flagged
  # if it's enabled, don't raise it as feature flagged so wildcard works
  def self.feature_flagged?
    !GitHub.elm_internal_webhooks_enabled?
  end

  # if elm migration webhooks are enabled, this is visible
  def self.visible_for?(user, target)
    GitHub.elm_internal_webhooks_enabled?
  end

  def feature_flag_enabled?
    GitHub.elm_internal_webhooks_enabled?
  end

  def autolink
    @autolink ||= Repositories.domain.key_links.by_id(autolink_id, repo_id: repository_id)
  end

  def actor
    nil # Autolinks don't have an associated actor
  end

  def target_repository
    # For deletion events, the autolink may no longer exist in the database
    if autolink
      autolink.owner if autolink.owner.is_a?(Repository)
    elsif repository_id
      Repositories.domain.by_id(repository_id)
    else
      nil
    end
  end

  def target_organization
    target_repository&.owner if target_repository&.owner.is_a?(Organization)
  end

  # Events which need a mechanism for bailing out in certain cases should
  # define `deliverable?`. If it returns false, hooks won't be delivered
  # for this event.
  def deliverable?
    target_repository.present?
  end
end
