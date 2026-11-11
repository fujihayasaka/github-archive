# typed: strict
# frozen_string_literal: true

class Stafftools::Sponsors::RetryOneTimeSubscriptionItemsController < StafftoolsController
  before_action :sponsors_required
  before_action :ensure_one_time_sponsorship_subscription_items
  before_action :ensure_total_subscription_items_within_limit
  before_action :ensure_subscription_items_are_not_billable
  before_action :ensure_subscription_items_are_active
  before_action :ensure_subscription_items_have_one_plan_subscription

  MAX_SUBSCRIPTION_ITEMS = 50
  WRITE_BATCH_SIZE = 10

  sig { void }
  def create
    touch_subscription_items
    plan_subscription.synchronize_later

    which_account = billable_entity ? "#{billable_entity}'s" : "The"
    units = if subscription_items.size == 1
      "the payment"
    else
      "payment for #{subscription_items.size} subscription items"
    end

    flash[:notice] = "#{which_account} #{subscription_description} will be synchronized to retry #{units}."
    redirect_to_payment_history
  end

  private

  sig { void }
  def touch_subscription_items
    subscription_item_ids.each_slice(WRITE_BATCH_SIZE) do |sub_item_ids_in_batch|
      Billing::SubscriptionItem.where(id: sub_item_ids_in_batch).update_all(updated_at: Time.now)
    end
  end

  sig { returns T.nilable(T.any(User, Business)) }
  def billable_entity
    plan_subscription.billable_entity
  end

  sig { returns Billing::PlanSubscription }
  memoize def plan_subscription
    subscription_item = T.must_because(subscription_items.first) do
      "#ensure_one_time_sponsorship_subscription_items ensures non-nil"
    end
    T.must_because(subscription_item.plan_subscription) do
      "#ensure_subscription_item_has_plan_subscription ensures non-nil"
    end
  end

  sig { returns String }
  def subscription_description
    subscription_number = plan_subscription.zuora_subscription_number
    subscription_number ? "#{subscription_number} subscription" : "subscription"
  end

  sig { returns T::Array[T.any(String, Integer)] }
  memoize def subscription_item_ids
    (params[:subscription_item_ids] || []).compact
  end

  sig { returns T::Array[Billing::SubscriptionItem] }
  memoize def subscription_items
    Billing::SubscriptionItem.where(id: subscription_item_ids).to_a
  end

  sig { void }
  def ensure_one_time_sponsorship_subscription_items
    if subscription_item_ids.empty? || subscription_items.empty?
      flash[:error] = "You must specify at least one subscription item to retry."
      redirect_to_billing_mismatches
      return
    end

    invalid_subscription_items = subscription_items.reject(&:one_time_sponsorship?)
    return if invalid_subscription_items.empty?

    flash[:error] = "Only one-time sponsorship subscription items can be retried."
    redirect_to_billing_mismatches
  end

  sig { void }
  def ensure_total_subscription_items_within_limit
    if subscription_item_ids.size > MAX_SUBSCRIPTION_ITEMS
      flash[:error] = "You can only retry up to #{MAX_SUBSCRIPTION_ITEMS} subscription items at a time."
      redirect_to_billing_mismatches
    end
  end

  sig { void }
  def ensure_subscription_items_are_not_billable
    invalid_subscription_items = subscription_items.select(&:billable?)
    return if invalid_subscription_items.empty?

    flash[:error] = "Some subscription items are currently billable and cannot be retried yet."
    redirect_to_billing_mismatches
  end

  sig { void }
  def ensure_subscription_items_are_active
    invalid_subscription_items = subscription_items.reject(&:active?)
    return if invalid_subscription_items.empty?

    flash[:error] = "Some subscription items have been cancelled and thus cannot be retried."
    redirect_to_billing_mismatches
  end

  sig { void }
  def ensure_subscription_items_have_one_plan_subscription
    invalid_subscription_items = subscription_items.select { |sub_item| sub_item.plan_subscription.nil? }
    if invalid_subscription_items.present?
      flash[:error] = "Not all subscription items have a plan subscription, so no synchronization can " \
        "happen to retry payment."
      redirect_to_billing_mismatches
      return
    end

    plan_subscriptions = subscription_items.map(&:plan_subscription).uniq
    if plan_subscriptions.size > 1
      flash[:error] = "Only subscription items for the same subscription can be retried together."
      redirect_to_billing_mismatches
    end
  end

  sig { void }
  def redirect_to_payment_history
    return redirect_to_billing_mismatches unless billable_entity

    if billable_entity.is_a?(Business)
      redirect_to stafftools_enterprise_billing_payment_history_path(billable_entity)
    else
      redirect_to stafftools_user_billing_history_path(billable_entity)
    end
  end

  sig { void }
  def redirect_to_billing_mismatches
    account = subscription_items.first&.account
    sponsor_login = if account&.is_a?(User)
      account.login
    end
    redirect_to stafftools_sponsors_billing_mismatches_path(sponsor_login: sponsor_login)
  end
end
