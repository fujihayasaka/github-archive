# typed: strict
# frozen_string_literal: true

module User::InstrumentationDependency
  extend T::Helpers

  requires_ancestor { User }

  # Performs all tracking necessary for a plan change: creates a Transaction,
  # instruments and increments stats.  Take options to help provide more
  # context when instrumenting.
  #
  # actor     - User that initiated for the change
  # old_plan  - Plan before the change
  # opts      - (Optional) Takes some specific optional arguments and any other
  #             parameters to be included as part of the audit log entry
  #   :coupon                    - (Optional) Coupon that was redeemed in conjunction with the change
  #   :repository                - (Optional) Repository that was created in conjunction with the change
  #   :billing_transaction       - (Optional) BillingTransaction if there was a charge
  #   :old_subscription_provider - (Optional) The old subscription provider name
  #   :reason                    - (Optional) A String describing why the change was made.
  #   :force                     - (Optional) skips the plan equality check
  sig do
    params(
      actor: T.nilable(User),
      old_plan: T.nilable(GitHub::Plan),
      opts: T::Hash[Symbol, T.untyped]
    ).void
  end
  def track_plan_change(actor, old_plan, opts = {})
    opts = opts.dup
    old_plan = GitHub::Plan.default_plan if old_plan.nil?
    return if !opts.delete(:force) && old_plan == plan

    opts.reverse_merge!(old_plan: old_plan.name).reject! { |_k, v| v.nil? }

    # transaction
    transactions.create(
      old_plan: old_plan.name,
      billing_transaction: opts.delete(:billing_transaction)
    )

    old_seat_count = opts.delete(:old_seat_count)

    payload = plan_change_payload(actor)
    payload.merge!(opts)
    payload.update(coupon: opts.delete(:coupon).code) if opts[:coupon]
    payload.update(repository: opts.delete(:repository).full_name) if opts[:repository]

    GitHub.instrument("account.plan_change", payload)

    billing_plan_change_payload = {
      actor_id: actor&.id,
      user_id: id,
      old_plan_name: old_plan.name,
      new_plan_name: plan.name,
    }
    billing_plan_change_payload[:new_seat_count] = seats if plan.per_seat? || opts.key?(:filled_seats)
    billing_plan_change_payload[:old_seat_count] = old_seat_count if old_seat_count
    GlobalInstrumenter.instrument("billing.plan_change", billing_plan_change_payload)

    # stats
    if old_plan.cost <= plan.cost
      GitHub.dogstats.increment("user.plan", tags: ["action:upgrade"])
    else
      GitHub.dogstats.increment("user.plan", tags: ["action:downgrade"])
    end
  end

  # Create a Transaction to track billing cycle changes (plan_duration).
  #
  # actor              - User that initiated for the change.
  # old_plan_duration  - Plan duration before the change.
  sig { params(actor: T.nilable(User), old_plan_duration: String).void }
  def track_plan_duration_change(actor, old_plan_duration)
    return if old_plan_duration == plan_duration

    transactions.create(old_plan_duration: old_plan_duration)

    payload = plan_change_payload(actor)
    payload.update(old_plan_duration: old_plan_duration)

    GitHub.instrument("account.plan_change", payload)

    GitHub.dogstats.increment("user.billing.cycle_change",
      tags: ["plan_duration:#{plan_duration}"])
  end

  # Create a Transaction to track organization seat count changes
  #
  # actor   - User that initiated the change
  # options - Hash of additional options.
  #           :old_seats           - Seat count before the change.
  #           :billing_transaction - Associated BillingTransaction.
  #           :reason              - (Optional) A String describing why the change was made.
  sig { params(actor: T.nilable(User), options: T.nilable(T::Hash[Symbol, T.untyped])).void }
  def track_seat_change(actor, options = nil)
    options ||= {}
    old_seats = options[:old_seats].to_i
    return if old_seats == seats

    transactions.create \
      old_seats: old_seats,
      billing_transaction: options[:billing_transaction]

    payload = plan_change_payload(actor)
    payload.update(old_seats: old_seats)
    payload.update(reason: options[:reason]) if options[:reason]

    GitHub.instrument("account.plan_change", payload)
  end

  # Create a Transaction to track data pack count changes
  #
  # actor           - User that initiated the change.
  # old_data_packs - Integer Data packs before the change.
  sig { params(actor: T.nilable(User), old_data_packs: T.nilable(Integer)).void }
  def track_data_pack_change(actor, old_data_packs:)
    old_data_packs    = old_data_packs.to_i
    asset_packs_total = data_packs
    asset_packs_delta = asset_packs_total - old_data_packs
    return if asset_packs_delta == 0

    transactions.create \
      asset_packs_delta: asset_packs_delta,
      asset_packs_total: asset_packs_total

    payload = plan_change_payload(actor)
    payload.update(old_data_packs: old_data_packs)

    GitHub.instrument("account.plan_change", payload)
  end

  sig { params(actor: User, previous_plan_duration: T.nilable(String)).void }
  def track_subscription_item_change_for_user_duration_change(actor, previous_plan_duration: nil)
    subscription_items.not_subscribable_Billing_ProductUUID.find_each do |item|
      prefix = item.subscribable_SponsorsTier? ? "sponsorship" : "marketplace_purchase"

      GitHub.instrument "#{prefix}.changed",
        subscription_item_id: item.id,
        sender_id: actor.id,
        previous_plan_duration: previous_plan_duration
    end
  end

  sig { returns(T::Boolean) }
  def instrument_async_delete?
    true
  end

  private

  sig { params(actor: T.nilable(User)).returns(T::Hash[Symbol, T.untyped]) }
  def plan_change_payload(actor)
    payload = user? ? { user: self } : { org: self }
    payload.update \
      old_plan: plan.name,
      plan: plan.name,
      old_plan_duration: plan_duration,
      plan_duration: plan_duration,
      old_seats: seats,
      seats: seats,
      old_data_packs: data_packs,
      asset_packs: data_packs,
      tos_sha: TosAcceptance.current_sha

    if actor&.site_admin?
      payload.update GitHub.guarded_audit_log_staff_actor_entry(actor)
    else
      payload.update actor: actor
    end

    payload
  end
end
