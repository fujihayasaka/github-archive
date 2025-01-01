# typed: true
# frozen_string_literal: true

class Hook::Event::IssueEventEvent < Hook::Event
  # I know, I know... this is what we get for having events whose creation and deletion may
  # also make for _interesting_ events.
  #
  # Sorry.

  supports_targets Repository
  description "An issue event is created or deleted"

  event_attr :action, :event_name, :target_id, :actor_id, required: true
  event_attr :issue_id, :commit_id, :commit_repository_id, :referencing_issue_id, :performed_by_integration_id, :updated_at, :created_at

  def actor
    @actor ||= User.find_by(id: actor_id)
  end

  def target
    @target ||= IssueEvent.find_by(id: target_id)
  end

  def target_repository
    repository
  end

  def repository
    @repository ||= Repository.find_by(id: repository_id)
  end

  def commit_repository
    @commit_repository ||= if commit_repository_id.present?
      Repository.find_by(id: commit_repository_id)
    else
      repository
    end
  end

  def referencing_repository
    @referencing_repository ||= if commit_repository_id.present?
      Repository.find_by(id: commit_repository_id)
    else
      repository
    end
  end

  def issue
    args = { id: issue_id, repository_id: repository_id }.compact
    @issue ||= Issue.find_by(**args)
  end

  def referencing_issue
    @referencing_issue ||= Issue.find_by(id: referencing_issue_id)
  end

  # if we haven't enabled ELM webhooks, handle this as if it's feature flagged
  # if it's enabled, don't raise it as feature flagged so wildcard works
  def feature_flag_enabled?
    GitHub.elm_internal_webhooks_enabled?
  end

  # if ELM webhooks are enabled, this is visible.
  def self.visible_for?(user, target)
    GitHub.elm_internal_webhooks_enabled?
  end
end
