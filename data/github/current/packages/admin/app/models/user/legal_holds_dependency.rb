# typed: true
# frozen_string_literal: true

module User::LegalHoldsDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  requires_ancestor { User }

  # Public: place a legal hold on this user so we don't purge their deleted
  # repositories.
  #
  # actor - The user that is placing this legal hold.
  #
  # Returns a Boolean.
  def place_legal_hold(actor:)
    return false if legal_hold?

    hold = build_legal_hold

    if hold.save
      auditing_actor = GitHub.guarded_audit_log_staff_actor_entry(actor)
      GitHub.instrument "staff.place_legal_hold", event_context.merge(auditing_actor)
      true
    else
      false
    end
  end

  # Public: clear a legal hold on this user. Their deleted repositories will be
  # eligible for pruning.
  #
  # actor - The user that is placing this legal hold.
  #
  # Returns a Boolean.
  def clear_legal_hold(actor:)
    return false unless legal_hold?

    if legal_hold&.destroy
      auditing_actor = GitHub.guarded_audit_log_staff_actor_entry(actor)
      GitHub.instrument "staff.clear_legal_hold", event_context.merge(auditing_actor)
      true
    else
      false
    end
  end
end
