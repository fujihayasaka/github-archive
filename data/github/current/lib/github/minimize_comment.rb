# typed: false
# frozen_string_literal: true

module GitHub
  module MinimizeComment
    include AuditLogHelper

    ROLES = {
        minimized_by_author: 0,
        minimized_by_maintainer: 1,
        minimized_by_staff: 2
    }

    def set_minimized(actor, reason, classifier, author, staff = false)
      if actor.site_admin?
        # This flag is needed to allow staff to minimize a comment on a locked issue
        GitHub.context.push(staff_minimizing: true)
      end

      if staff && actor.site_admin?
        auditing_actor = GitHub.guarded_audit_log_staff_actor_entry(actor)
        instrument_key = "staff.minimize_comment"
        comment_hidden_by = ROLES[:minimized_by_staff]
      else
        if self.is_a? GistComment
          comment_hidden_by  = Gist.find_by_id(gist_id).pushable_by?(actor) ? ROLES[:minimized_by_maintainer] : ROLES[:minimized_by_author]
        else
          comment_hidden_by = repository.pushable_by?(actor) ? ROLES[:minimized_by_maintainer] : ROLES[:minimized_by_author]
        end

        auditing_actor = { actor: actor.display_login, actor_id: actor.id }
        instrument_key = "user.minimize_comment"
      end

      success = self.update(
          comment_hidden: true,
          comment_hidden_reason: reason,
          comment_hidden_classifier: classifier,
          comment_hidden_by: comment_hidden_by
      )

      return false unless success

      payload = auditing_actor.merge(
        comment_id: self.id,
        comment_type: self.class.name,
        minimized_reason: reason,
        classifier: classifier,
        user: author,
      )

      GitHub.dogstats.increment("minimized_comment")

      GlobalInstrumenter.instrument "comment.toggle_minimize", {
        actor: actor,
        actor_was_staff: staff && actor.site_admin?,
        event_type: "minimize",
        reason: reason,
        comment: self,
        comment_id: self.id,
        comment_type: self.class.name,
        classifier: classifier,
        user: author,
      }

      GitHub.instrument instrument_key, payload
      true
    end

    def set_unminimized(actor, reason, author, staff = false)
      success = self.update(
        comment_hidden: false,
        comment_hidden_reason: reason,
        comment_hidden_classifier: nil,
      )

      return false unless success

      if staff && actor.site_admin?
        auditing_actor = GitHub.guarded_audit_log_staff_actor_entry(actor)
        instrument_key = "staff.unminimize_comment"
      else
        auditing_actor = { actor: actor.display_login, actor_id: actor.id }
        instrument_key = "user.unminimize_comment"
      end
      payload = auditing_actor.merge(
        comment_id: self.id,
        comment_type: self.class.name,
        unminimized_reason: reason,
        user: author,
      )

      GlobalInstrumenter.instrument "comment.toggle_minimize", {
        actor: actor,
        actor_was_staff: staff && actor.site_admin?,
        event_type: "unminimize",
        reason: reason,
        comment_id: self.id,
        comment_type: self.class.name,
        user: author,
      }

      GitHub.dogstats.increment("unminimized_comment")
      GitHub.instrument instrument_key, payload
      true
    end

    def minimized?
      !!comment_hidden?
    end

    def minimized_by_staff?
      self.comment_hidden_by == ROLES[:minimized_by_staff]
    end

    def viewer_can_see?(current_user)
      allowed_viewers = current_user&.site_admin? || current_user == self.user

      if self.is_a?(GistComment)
        allowed_viewers ||= self.gist.user == current_user
      else
        allowed_viewers ||= self.repository.adminable_by?(current_user)
      end
      !minimized_by_staff? || minimized_by_staff? && allowed_viewers
    end

    def minimized_audit_log(current_user)
      phrase = "action:staff.minimize_comment data.comment_id:#{self.id}"
      if driftwood_ade_query?(current_user)
        phrase = <<~KQL
          webevents
          | where action == "staff.minimize_comment"
          | where data.comment_id == "#{self.id}"
        KQL
      end
      query = Audit::Driftwood::Query.new_stafftools_query(phrase: phrase)
      query.execute
    end

    def minimized_reason
      self.comment_hidden_classifier
    end

    def async_minimizable_by?(actor)
      raise NotImplementedError, "#{self.class.name} must implement #async_minimizable_by?"
    end

    # Internal: is the given actor attempting to minimize their own comment
    # *and* are they unrestricted by internal App policy?
    #
    # actor - The actor attempting to minimize their own comment
    #
    # Returns a Boolean.
    def unrestricted_actor_minimizing_own_comment?(actor)
      # Short-circuit for Internal GitHub Apps that have been restricted to
      # requiring fine-grained permission when modifying public resources.
      # https://github.com/github/ecosystem-apps/issues/581
      return false if actor.respond_to?(:integration) && Apps::Internal.capable?(
        :restricted_modification_of_public_resources,
        app: actor.integration,
      )

      # All other kinds of actors are unrestricted.
      user_id == actor.id
    end
  end
end
