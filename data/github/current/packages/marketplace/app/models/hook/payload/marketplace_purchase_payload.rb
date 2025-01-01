# typed: true
# frozen_string_literal: true

class Hook::Payload::MarketplacePurchasePayload < Hook::Payload
  include Formatter

  delegate \
    :account,
    :action,
    :installation_account,
    :item,
    :subscribable,
    :previous_item,
    :previous_listing_plan,
    :previous_plan_duration,
    :previous_quantity,
    :previously_on_free_trial,
    :previous_free_trial_ends_on,
    :pending_subscription_item_change,
    :sender,
    to: :hook_event

  def to_payload_hash
    {
      action: action,
      effective_date: time(effective_date.to_datetime),
      sender: sender_hash,
    }.merge(purchase_payload)
  end

  def purchase_payload
    if [:pending_change, :pending_change_cancelled].include?(action.to_sym)
      return {
        marketplace_purchase: pending_marketplace_purchase,
        previous_marketplace_purchase: marketplace_purchase,
      }
    end

    if action.to_sym == :changed
      {
        marketplace_purchase: marketplace_purchase,
        previous_marketplace_purchase: previous_marketplace_purchase,
      }
    else
      { marketplace_purchase: marketplace_purchase }
    end
  end

  def pending_marketplace_purchase
    marketplace_purchase_hash.merge({
      billing_cycle: "#{item.plan_duration}ly",
      unit_count: pending_subscription_item_change.quantity,
      on_free_trial: pending_subscription_item_change.free_trial,
      free_trial_ends_on: time(item.free_trial_ends_on&.to_datetime),
      next_billing_date: time(item.next_billing_date&.to_datetime),
      plan: plan_hash_for(pending_subscription_item_change.subscribable),
    })
  end

  def marketplace_purchase
    marketplace_purchase_hash.merge({
      billing_cycle: "#{item.plan_duration}ly",
      unit_count: item.quantity,
      on_free_trial: item.on_free_trial?,
      free_trial_ends_on: time(item.free_trial_ends_on&.to_datetime),
      next_billing_date: time(item.next_billing_date&.to_datetime),
      plan: plan_hash_for(subscribable),
    })
  end

  def previous_marketplace_purchase
    marketplace_purchase_hash.merge({
      billing_cycle: "#{previous_plan_duration || item.plan_duration}ly",
      on_free_trial: previously_on_free_trial,
      free_trial_ends_on: time(previous_free_trial_ends_on&.to_datetime),
      unit_count: previous_unit_count,
      plan: plan_hash_for(previous_listing_plan || subscribable),
    })
  end

  def marketplace_purchase_hash
    {
      account: {
        type: installation_account.type,
        id: installation_account.id,
        node_id: installation_account.global_relay_id,
        login: installation_account.display_login,
        organization_billing_email: installation_account.organization_billing_email,
      },
    }
  end

  def plan_hash_for(plan)
    {
      id: plan.id,
      name: plan.name,
      description: plan.description,
      monthly_price_in_cents: plan.monthly_price_in_cents,
      yearly_price_in_cents: plan.yearly_price_in_cents,
      price_model: plan.price_model,
      has_free_trial: plan.has_free_trial?,
      unit_name: plan.unit_name,
      bullets: plan.bullets.pluck(:value),
    }
  end

  def effective_date
    if :pending_change == action.to_sym
      return pending_subscription_item_change.active_on
    end

    GitHub::Billing.today
  end

  def listing_plan_price
    subscribable.base_price * item.quantity
  end

  def previous_listing_plan_price
    previous_listing_plan.base_price * previous_unit_count
  end

  def previous_unit_count
    previous_quantity || item.quantity
  end

  def sender_hash
    api_serialize(:user_hash, sender).merge({ email: sender.email })
  end
end
