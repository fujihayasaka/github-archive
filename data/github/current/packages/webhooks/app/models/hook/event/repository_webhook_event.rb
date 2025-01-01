# typed: true
# frozen_string_literal: true

class Hook::Event::RepositoryWebhookEvent < Hook::Event
  supports_targets Repository
  description "A hook is created, updated or deleted"

  event_attr :action, :hook_id, required: true

  # if we haven't enabled migration vnext webhooks, handle this as if it's feature flaggedAdd a comment on lines R11 to R15Add diff commentMarkdown input: edit mode selected.WritePreviewAdd a suggestionHeadingBoldItalicQuoteCodeLinkUnordered listNumbered listTask listMentionReferenceSaved repliesAdd FilesPaste, drop, or click to add filesCancelCommentStart a reviewReturn to code
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

  def hook
    @hook ||= Hook.find_by(id: hook_id)
  end

  def actor
    @actor ||= hook.creator
  end

  def target_repository
    hook.installation_target if hook.repo_hook?
  end

  def updated_at
    # in the case of an `:updated` action, we can't rely on the hook's `updated_at` field, which may not have serialized when
    # the event was created. So, we will use the later of the `event.triggered_at` and the hook's `updated_at` field.
    if action == :updated
      [triggered_at, hook&.updated_at].compact.max
    else
      hook&.updated_at
    end
  end

  # Events which need a mechanism for bailing out in certain cases should
  # define `deliverable?`. If it returns false, hooks won't be delivered
  # for this event.
  def deliverable?
    target_repository.present?
  end
end
