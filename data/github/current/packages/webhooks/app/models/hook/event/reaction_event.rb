# typed: true
# frozen_string_literal: true

# this handles reaction events based of packages/releases/app/models/reaction
class Hook::Event::ReactionEvent < Hook::Event
  supports_targets Repository
  description "A reaction is created or deleted"

  event_attr :action, :reaction_id, :reacted_at, :actor_id, :subject_id, :subject_type, :content, required: true

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

  def subject
    Reaction.find_subject(subject_id, subject_type)
  end

  def actor
    @actor ||= User.find_by(id: actor_id)
  end

  def target_repository
    subject.try(:repository)
  end

  def target_organization
    subject.try(:organization)
  end

  # Events which need a mechanism for bailing out in certain cases should
  # define `deliverable?`. If it returns false, hooks won't be delivered
  # for this event.
  def deliverable?
    target_repository.present?
  end
end
