# typed: false
# frozen_string_literal: true

# Shared persistence + audit/instrumentation helpers for hiding the *body* of
# a top-level content object (an Issue, a Gist, etc.) as an admin moderation
# action.
#
# Mirrors `GitHub::MinimizeComment`, but writes to `TrustSafety::KV.store`
# instead of dedicated columns on the model. Per platform-health#5888 we
# start with a KV-backed implementation so we can ship without a schema
# migration on hot tables; we can promote to columns later if query-time
# filtering becomes the bottleneck.
#
# Storage layout:
#   content_hidden:<subject>:<id>      = "true"
#   content_hidden_meta:<subject>:<id> = JSON({reason, classifier, hidden_by})
#
# Including classes must define:
#   * #async_hideable_by?(actor)
#   * #async_unhideable_by?(actor)
#   * #actor_is_maintainer?(actor)
# and may override:
#   * #instrument_subject  (defaults to underscored class name)
#   * #kv_subject          (defaults to #instrument_subject)
module TrustSafety
  module HideContent
    ROLES = {
      hidden_by_author: 0,
      hidden_by_maintainer: 1,
      hidden_by_staff: 2,
    }

    KEY_PREFIX      = "content_hidden"
    META_KEY_PREFIX = "content_hidden_meta"

    def set_hidden(actor, reason, classifier, author, staff = false)
      current = current_hidden_metadata
      if current && current["reason"] == reason && current["classifier"] == classifier
        return true
      end

      if staff && actor.site_admin?
        auditing_actor  = GitHub.guarded_audit_log_staff_actor_entry(actor)
        instrument_key  = "staff.hide_#{instrument_subject}"
        hidden_by_value = ROLES[:hidden_by_staff]
      else
        hidden_by_value = actor_is_maintainer?(actor) ? ROLES[:hidden_by_maintainer] : ROLES[:hidden_by_author]
        auditing_actor  = { actor: actor.display_login, actor_id: actor.id }
        instrument_key  = "user.hide_#{instrument_subject}"
      end

      meta = {
        "reason" => reason,
        "classifier" => classifier,
        "hidden_by" => hidden_by_value,
      }

      kv_store.set(content_hidden_meta_key, JSON.dump(meta))
      kv_store.set(content_hidden_key, "true")
      @hidden_cached = true
      @content_hidden_meta = meta

      enqueue_hide_content_side_effects(:hide)

      payload = auditing_actor.merge(
        subject_id: self.id,
        subject_type: self.class.name,
        hidden_reason: reason,
        classifier: classifier,
        user: author,
      )

      GitHub.dogstats.increment("hidden_#{instrument_subject}")

      GlobalInstrumenter.instrument "content.toggle_hidden", {
        actor: actor,
        actor_was_staff: staff && actor.site_admin?,
        event_type: "hide",
        reason: reason,
        subject: self,
        subject_id: self.id,
        subject_type: self.class.name,
        classifier: classifier,
        user: author,
      }

      GitHub.instrument instrument_key, payload
      true
    rescue ::GitHub::KV::UnavailableError => e
      GitHub.dogstats.increment("hide_content.kv_unavailable", tags: ["subject:#{instrument_subject}", "action:hide"])
      Failbot.report(e, app: "github")
      false
    end

    def set_unhidden(actor, reason, author, staff = false)
      return true unless hidden?

      kv_store.del(content_hidden_key)
      kv_store.del(content_hidden_meta_key)
      @hidden_cached = false
      @content_hidden_meta = nil

      enqueue_hide_content_side_effects(:unhide)

      if staff && actor.site_admin?
        auditing_actor = GitHub.guarded_audit_log_staff_actor_entry(actor)
        instrument_key = "staff.unhide_#{instrument_subject}"
      else
        auditing_actor = { actor: actor.display_login, actor_id: actor.id }
        instrument_key = "user.unhide_#{instrument_subject}"
      end

      payload = auditing_actor.merge(
        subject_id: self.id,
        subject_type: self.class.name,
        unhidden_reason: reason,
        user: author,
      )

      GlobalInstrumenter.instrument "content.toggle_hidden", {
        actor: actor,
        actor_was_staff: staff && actor.site_admin?,
        event_type: "unhide",
        reason: reason,
        subject_id: self.id,
        subject_type: self.class.name,
        user: author,
      }

      GitHub.dogstats.increment("unhidden_#{instrument_subject}")
      GitHub.instrument instrument_key, payload
      true
    rescue ::GitHub::KV::UnavailableError => e
      GitHub.dogstats.increment("hide_content.kv_unavailable", tags: ["subject:#{instrument_subject}", "action:unhide"])
      Failbot.report(e, app: "github")
      false
    end

    def hidden? # rubocop:disable GitHub/ControllersShouldUseMemoizeForMemoization
      return @hidden_cached if defined?(@hidden_cached) && !@hidden_cached.nil?
      @hidden_cached = kv_store.get(content_hidden_key).value { nil }.present?
    end

    def hidden_reason
      current_hidden_metadata&.dig("reason")
    end

    def hidden_classifier
      current_hidden_metadata&.dig("classifier")
    end

    def hidden_by
      current_hidden_metadata&.dig("hidden_by")
    end

    def hidden_by_staff?
      hidden_by == ROLES[:hidden_by_staff]
    end

    def hidden_by_maintainer?
      hidden_by == ROLES[:hidden_by_maintainer]
    end

    def hidden_by_author?
      hidden_by == ROLES[:hidden_by_author]
    end

    # Clears the per-instance cache of the KV-backed hidden state. Hook this
    # into AR's reload chain so callers see fresh values after KV writes from
    # other code paths.
    def clear_hidden_state_cache
      remove_instance_variable(:@hidden_cached) if defined?(@hidden_cached)
      remove_instance_variable(:@content_hidden_meta) if defined?(@content_hidden_meta)
    end

    def reload(*args)
      clear_hidden_state_cache
      super
    end

    def async_hideable_by?(actor)
      raise NotImplementedError, "#{self.class.name} must implement #async_hideable_by?"
    end

    def async_unhideable_by?(actor)
      raise NotImplementedError, "#{self.class.name} must implement #async_unhideable_by?"
    end

    # Including classes must define this to disambiguate the non-staff hide
    # path (maintainer-vs-author bookkeeping in `hidden_by`).
    def actor_is_maintainer?(actor)
      raise NotImplementedError, "#{self.class.name} must implement #actor_is_maintainer?"
    end

    private

    def instrument_subject
      self.class.name.to_s.underscore
    end

    # Namespace segment under the content_hidden KV key. Defaults to
    # instrument_subject; override if multiple model classes should share a
    # single logical key namespace.
    def kv_subject
      instrument_subject
    end

    def content_hidden_key
      "#{KEY_PREFIX}:#{kv_subject}:#{id}"
    end

    def content_hidden_meta_key
      "#{META_KEY_PREFIX}:#{kv_subject}:#{id}"
    end

    def kv_store
      ::TrustSafety::KV.store
    end

    def current_hidden_metadata # rubocop:disable GitHub/ControllersShouldUseMemoizeForMemoization
      return @content_hidden_meta if defined?(@content_hidden_meta) && @content_hidden_meta
      raw = kv_store.get(content_hidden_meta_key).value { nil }
      @content_hidden_meta = raw && JSON.parse(raw)
    end

    # Phase 2 hook: an out-of-band job will unindex (action=:hide) or
    # restore (action=:unhide) this record from search, notifications, feeds,
    # etc. For Phase 1 we only instrument so we can observe call volume
    # before wiring up the actual purge/restore jobs.
    def enqueue_hide_content_side_effects(action)
      GitHub.dogstats.increment(
        "hide_content.side_effect_enqueued",
        tags: ["subject:#{instrument_subject}", "action:#{action}"],
      )
    end
  end
end
