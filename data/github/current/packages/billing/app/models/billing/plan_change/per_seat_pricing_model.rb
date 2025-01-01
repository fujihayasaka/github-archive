# typed: true
# frozen_string_literal: true

module Billing
  # Models switching to or from a per seat pricing model, as well as providing
  # the ability to  perform the switch itself.
  class PlanChange::PerSeatPricingModel < PlanChange
    attr_accessor :organization, :old_plan, :old_seats, :seats, :plan_duration, :new_plan, :coupon

    MAXIMUM_SEATS_BEFORE_TALKING_TO_SALES = 300

    def initialize(organization, seats: nil, plan_duration: nil, new_plan: nil, coupon: nil, plan_effective_at: nil, plan_and_seat_cost_only: false)
      @new_plan = GitHub::Plan.find(new_plan, effective_at: plan_effective_at, account: organization)

      if @new_plan.blank?
        @new_plan = GitHub.billing_enabled? ? GitHub::Plan.business : GitHub::Plan.enterprise
      end

      @organization  = organization
      @old_plan      = organization.plan
      @old_seats     = organization.seats
      @seats         = initial_seats(seats)
      @plan_duration = plan_duration || organization.plan_duration
      @coupon        = coupon || organization.coupon
      @plan_and_seat_cost_only = plan_and_seat_cost_only

      old_subscription = Billing::Subscription.for_account(organization)
      new_subscription = Billing::Subscription.for_account \
        organization,
        seats: @seats,
        plan: @new_plan,
        duration_in_months: duration_in_months,
        coupon_discount: coupon_discount

      super(old_subscription, new_subscription, plan_and_seat_cost_only: plan_and_seat_cost_only)
    end

    # Public: Switch an organization to the per_seat plan. Any remaining credit
    # on their existing plan will be refunded.
    #
    # options - actor : User performing the switch
    #
    # Returns a Boolean whether the switch was successful
    def switch(actor:, payment_details: nil, business_owned: false, organization_details: nil, job_status_id: nil)
      return false if invoiced?(actor: actor)
      return false if payment_details.blank? && needs_payment_details?
      if payment_details.present? && !update_payment_details(payment_details, actor: actor)
        return false
      end
      return false if is_upgrade? && !purchases_allowed?(actor: actor)
      return false unless actor_can_change_plan?(new_plan, actor: actor)

      organization.process_zero_charge_transaction if final_price.zero?

      if !is_upgrade?
        schedule_pending_plan_change(actor: actor)
      else
        organization.seats = seats
        organization.plan = new_plan
        organization.plan_duration = plan_duration
        organization.clear_preloaded_batch_method_value(:plan_trial_active?, new_plan.name)
        rollback_plan = old_plan
        rollback_seats = old_seats

        return false unless organization.valid? # Checks seat count

        success = Organization.transaction do
          Billing::PlanTrial.transaction do
            # Skip the automatic external subscription update - for synchronous payments, the first
            # synchronization after the plan change must be run from CollectPaymentOnUpgradeJob.
            organization.skip_update_external_subscription = true

            # We need to update the pending plan change with any changes to the target's subscription
            update_existing_pending_cycle_change if organization.pending_cycle_change

            ensure_external_subscription_exists!(actor: actor)
            if business_owned
              upgrade_tos_to_corporate(actor: actor, company_name: organization_details[:company_name])
            end

            was_active = cloud_trial.active?
            if was_active
              rollback_plan = cloud_trial.fallback_plan || GitHub::Plan.free
              rollback_seats = cloud_trial.fallback_seats || 0
              cloud_trial.deactivate!
            end

            organization.save!

            if cloud_trial.ever_been_in_trial? && cloud_trial.expired_within?(Billing::EnterpriseCloudTrial::EXPIRATION_MESSAGE_DURATION)
              cloud_trial.log_plan_change(new_plan: organization.plan.name, user_initiated: true, active: was_active)
            end

            plan_change_opts = {
              filled_seats: organization.filled_seats,
              teams_count: organization.teams.size,
              public_repositories_count: organization.public_repositories.size,
              private_repositories_count: organization.private_repositories.size,
              had_active_cloud_trial: was_active,
              force: true
            }
            plan_change_opts[:old_seat_count] = old_seats if old_plan.per_seat?
            organization.track_plan_change(actor, old_plan, plan_change_opts)
            GitHub.dogstats.increment("organization.per_seat")

            true
          end
        end

        return false unless success

        # Start a job to synchronize and collect payment for the plan or seat change
        if organization.collect_payment_immediately_for_plan_or_seat_changes?
          Billing::JobStatus.find(job_status_id)&.queued!
          CollectPaymentForUpgradeJob.perform_later(
            billable_entity: organization,
            old_plan_name: rollback_plan.name,
            old_seat_count: rollback_seats,
            job_status_id: job_status_id,
            actor: actor,
          )
        else
          organization.plan_subscription&.synchronize_later
        end

        true
      end
    end

    def maximum_seats
      MAXIMUM_SEATS_BEFORE_TALKING_TO_SALES
    end

    def base_seats
      new_plan.base_units
    end

    def monthly_plan?
      plan_duration == User::BillingDependency::MONTHLY_PLAN
    end

    def yearly_plan?
      !monthly_plan?
    end

    def duration_in_months
      monthly_plan? ? 1 : 12
    end

    # Public: Price of additional seats
    #
    # Returns Money
    def additional_seats_price
      additional_seats * unit_price
    end

    def base_price
      if monthly_plan?
        Billing::Money.new(new_subscription.plan.cost * 100)
      else
        Billing::Money.new(new_subscription.plan.yearly_cost * 100)
      end
    end

    def total_seats_price
      base_price + additional_seats_price
    end

    # Public: String human unit price (per seat) for the new plan's duration.
    def human_unit_price
      "#{unit_price.format(no_cents: true)}/#{new_subscription.duration} each"
    end

    # Public: String human unit price (per seat) for the new plan's duration.
    def human_base_price
      "#{base_price.format(no_cents: true)}/#{new_subscription.duration} for the first #{base_seats} seats"
    end

    def error_messages
      organization.invalid? ? organization.errors.full_messages : [@error]
    end

    # Public: Money amount of final price. Only apply credit when there's a charge so that
    #         it does not return the credit amount when credit wasn't used. Only prorate
    #         price if updating an existing subscription.
    #
    # Returns Money
    def final_price(github_only: false, use_balance: false)
      price = if starting_new_subscription? || organization.past_due? || cloud_trial.active?
        renewal_price(github_only: github_only)
      else
        price_for_rest_of_billing_cycle(github_only: github_only) - price_of_remaining_service
      end

      if price.positive? && use_balance
        price -= Billing::Money.new(organization.credit * 100)
      end

      price
    end

    # Public: Money amount of remaining service in old subscription
    sig { returns(::Billing::Money) }
    def price_of_remaining_service
      @price_of_remaining_service ||= old_subscription.price_of_remaining_service
    end

    # Public: Money amount of remaining service in new subscription
    #
    # Returns Money
    def price_for_rest_of_billing_cycle(github_only: false)
      @price_for_rest_of_billing_cycle ||= if upgrading_from_free?
        # Account for the Subscription model not counting current day in
        # remaining service calculation, resulting in
        # service_percent_remaining < 100% when upgrading from free
        renewal_price(github_only: github_only)
      else
        new_subscription.price_of_remaining_service
      end
    end

    # Public: Amount of coupon discount or 0
    #
    # Returns Money
    def coupon_discount_for_duration
      Billing::Pricing.new(
        account: organization,
        plan: new_plan,
        seats: seats,
        plan_duration: plan_duration,
        coupon: coupon,
      ).discount
    end

    def data_pack_change
      # You can't currently change data packs while upgrading to
      # Business pricing, but you can change plan duration,
      # and it's useful to have the info about your data pack cost
      # available as a line item.
      @data_pack_change ||= PlanChange::DataPackChange.new \
        organization,
        total_packs: organization.data_packs,
        plan_duration: plan_duration
    end

    private

    def initial_seats(seats)
      seats.nil? ? organization.default_seats(new_plan: new_plan) : [seats.to_i, base_seats].max
    end

    def is_downgrade?
      downgrading_seats? || delayed_duration_change? || downgrading_plan?
    end

    def is_upgrade?
      (organization.plan.per_repository? && new_plan.per_seat? || !is_downgrade?) || cloud_trial.active?
    end

    def delayed_duration_change?
      changing_plan_duration? && organization.payment_amount > 0
    end

    def downgrading_seats?
      return false if organization.plan.free? && new_plan.paid?
      organization.seats > seats
    end

    def downgrading_plan?
      changing_plan? && organization.undiscounted_payment_difference(new_plan, seat_count: seats) < 0
    end

    def changing_plan?
      organization.plan != new_plan
    end

    # Private: Returns whether the plan duration is being changed.
    #
    # Returns a boolean
    def changing_plan_duration?
      plan_duration != organization.plan_duration
    end

    # Private: Transition this organization to an external subscription service,
    #          refunding any remaining credit for their GitHub-hosted subscription
    #
    # Return Boolean whether the transition was performed successfully
    def transition_to_external_subscription
      refunded = GitHub::Billing.find_and_refund_transactions_for_amount \
        organization,
        price_of_remaining_service.cents

      if refunded && refunded.failed?
        @error = refunded.error_message
        return false
      end

      organization.billed_on = GitHub::Billing.today

      # Perform the transition but skip the synchronization with Zuora - for synchronous payments,
      # the first synchronization after the plan change must be run from CollectPaymentOnUpgradeJob.
      !!::Billing::PlanSubscription::Transition.activate(organization, purpose: :general, skip_sync: true)
    end

    # Internal: Returns the discount that will be applied by the coupon for the new plan
    #
    # Returns Float
    def coupon_discount
      return Billing::Money.new(0) if changing_to_business_plus?
      coupon&.discount
    end

    def changing_to_business_plus?
      changing_plan? && @new_plan.business_plus?
    end

    def cloud_trial
      @_cloud_trial ||= Billing::EnterpriseCloudTrial.new(organization)
    end

    def invoiced?(actor:)
      if organization.invoiced? && !actor.site_admin?
        @error = "Your account is being invoiced. Please contact support to make plan changes."
        true
      else
        false
      end
    end

    def needs_payment_details?
      if organization.needs_valid_payment_method_to_switch_to_plan?(new_plan)
        @error = "must have a payment method on file"
        true
      else
        false
      end
    end

    def update_payment_details(payment_details, actor:)
      # Skipping synchronization on upgrade since it happens during the upgrade flow
      result = GitHub::Billing.create_or_update_customer(organization, payment_details,
        skip_synchronization: is_upgrade?, actor: actor)

      if result.failed?
        @error = result.error_message
        false
      else
        true
      end
    end

    def purchases_allowed?(actor:)
      disabled_due_to_payment_method_issue = organization.disabled? && organization.should_disable?(check_plan_limit: false)
      result = organization.validate_purchases_allowed(actor: actor, check_disabled: disabled_due_to_payment_method_issue)

      if result.failed?
        @error = result.error_message
        false
      else
        true
      end
    end

    def actor_can_change_plan?(new_plan, actor:)
      if !organization.can_change_plan_to?(new_plan, actor: actor)
        @error = "#{organization} cannot change to #{new_plan}"
        false
      else
        true
      end
    end

    def schedule_pending_plan_change(actor:)
      result = Billing::SchedulePlanChange.run \
        account: organization,
        actor: actor,
        seats: seats,
        plan: new_plan,
        plan_duration: plan_duration

      @error = result.error_message
      result.success?
    end

    def update_existing_pending_cycle_change
      organization.pending_cycle_change.seats = seats if seats
      organization.pending_cycle_change.plan_duration = plan_duration if plan_duration
      organization.pending_cycle_change.plan = new_plan if new_plan
      organization.pending_cycle_change.save
    end

    def ensure_external_subscription_exists!(actor:)
      if organization.has_valid_payment_method?(feature_type: :noncommercial) && !organization.external_subscription?
        transition_to_external_subscription
      else
        true
      end
    end

    def upgrade_tos_to_corporate(actor:, company_name:)
      organization.terms_of_service.update \
        type: "Corporate",
        actor: actor,
        company_name: company_name
    end
  end
end
