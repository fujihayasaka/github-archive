# typed: true
# frozen_string_literal: true

###### Individual (User) Level ######

# Event: a subscription item changed (e.g. a plan upgrade or downgrade).
# When the new product is Copilot, instrument a license/billable customer change
# so the Limiter's cache of the user's current plan is invalidated and quota
# reflects the updated subscription.
GitHub.subscribe("billing.subscription_item_changed") do |_name, _start, _ending, _transaction_id, payload|
  next unless payload[:new_product_type] == Copilot::PRODUCT_TYPE

  # user_id is optional on this event. Skip events that aren't scoped to a user.
  user_id = payload[:user_id]
  next unless user_id

  user = ::User.find_by(id: user_id)
  next unless user

  # Gate the new billing-driven license-change emission so it can be rolled out gradually.
  next unless user.feature_flag_enabled?(:copilot_billing_license_change_event, default: false)

  Copilot::Instrumenter.instrument_copilot_license_or_billable_customer_change(
    Copilot::Public::User.for(user),
    old_plan: Hydro::EntitySerializer.copilot_individual_plan(payload[:old_product_key]),
    new_plan: Hydro::EntitySerializer.copilot_individual_plan(payload[:new_product_key]),
  )
end
