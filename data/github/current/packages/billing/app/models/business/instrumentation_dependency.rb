# typed: strict
# frozen_string_literal: true

module Business::InstrumentationDependency
  extend T::Helpers

  requires_ancestor { Business }

  # Create an Audit Log to track business seat count changes
  #
  # actor   - User that initiated the change
  # options - Hash of additional options.
  #           :old_seats           - Seat count before the change.
  #           :reason              - (Optional) A String describing why the change was made.
  #           :coupon              - (Optional) Coupon that was redeemed in conjunction with the change
  # Returns payload
  # TODO: create a transaction to track seat count changes
  sig { params(actor: T.nilable(User), options: T.nilable(T::Hash[Symbol, T.untyped])).void }
  def track_seat_upgrade_change(actor, options = nil)
    options ||= {}
    old_seats = options[:old_seats].to_i
    return if old_seats == seats

    payload = seats_change_payload(actor)
    payload.update(old_seats: old_seats)
    payload.update(reason: options[:reason]) if options[:reason]
    payload.update(coupon: options.delete(:coupon).code) if options[:coupon]
    GitHub.instrument("account.plan_change", payload)
  end

  private

  sig { params(actor: T.nilable(User)).returns(T::Hash[Symbol, T.untyped]) }
  def seats_change_payload(actor)
    payload = { business: self }
    payload.update(
      plan: GitHub::Plan.business_plus.name.to_sym,
      old_plan: GitHub::Plan.business_plus.name.to_sym,
      old_plan_duration: plan_duration,
      plan_duration: plan_duration,
      old_seats: seats,
      seats: seats,
    )

    if actor&.site_admin?
      payload.update GitHub.guarded_audit_log_staff_actor_entry(actor)
    else
      payload.update actor: actor
    end

    payload
  end
end
