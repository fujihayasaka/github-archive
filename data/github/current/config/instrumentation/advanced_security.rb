# typed: strict
# frozen_string_literal: true

GitHub.subscribe(/\Abilling.subscription_item_cancelled\Z/) do |_name, _start, _ending, _transaction_id, payload|
  item = Billing::SubscriptionItem.find_by(id: payload[:subscription_item_id])
  next unless item.present?

  if item.product_uuid? &&
    item.subscribable.product_type == AdvancedSecurity::Public::Subscription::ADVANCED_SECURITY_MONTHLY_PRODUCT.product_type &&
    item.subscribable.product_key == AdvancedSecurity::Public::Subscription::ADVANCED_SECURITY_MONTHLY_PRODUCT.product_key

    # Even if the original actor was deleted, we still need to clear the GHAS subscription config setting since the
    # subscription item has already been cancelled.
    actor = User.find_by(id: payload[:actor_id]) || User.ghost

    billable_entity = T.cast(T.must(T.must(item.plan_subscription).billable_entity), ::Billing::Types::OrgOrBusiness)
    billable_entity.transaction do
      billable_entity.mark_advanced_security_as_not_purchased_for_entity(actor: actor)
    end

    if payload[:previously_on_free_trial]
      message = {
        enterprise_id: billable_entity.is_a?(Business) ? billable_entity.id : nil,
        organization_id: billable_entity.is_a?(Organization) ? billable_entity.id : nil,
        action: :ENDED,
        trial_sku: :ADVANCED_SECURITY,
        converted_to_paid: false,
        **billable_entity.advanced_security_usage_stats
      }
      GlobalInstrumenter.instrument("advanced_security_trial.toggled", message) if GitHub.flipper.enabled?(:advanced_security_trial_toggled_event)
    end
  end
end

GlobalInstrumenter.subscribe "billing.plan_change" do |_name, _start, _ending, _transaction_id, payload|
  org = Organization.find_by(id: payload[:user_id])
  next unless org

  old_plan = GitHub::Plan.find(payload[:old_plan_name])
  new_plan = GitHub::Plan.find(payload[:new_plan_name])

  # Ignore if billing is being removed
  next unless new_plan.present?

  # Either upgrading or downgrading
  next unless old_plan.try(:business?) || new_plan.try(:business?)

  if old_plan.business?
    # downgrade
    org.mark_advanced_security_as_not_purchased_for_entity(actor: User.ghost)
  elsif new_plan.business?
    # upgrade
    org.set_customer_to_split_metered_offering(actor: User.ghost)
    org.set_advanced_security_seats_for_entity(seats: 0, actor: User.ghost, is_stafftools_action: true)
  end
end

GitHub.subscribe("billing.unlock") do |_name, _start, _ending, _transaction_id, payload|
  # There could be an org or a user id in the payload. We should favor the org id
  # if it exists, otherwise we will use the user id
  user_id, org_id = payload.values_at(:user_id, :org_id)
  id = org_id ? org_id : user_id
  org = Organization.find_by(id: id)
  next unless org&.organization?

  # must be the GHAS billing entity
  next unless org.advanced_security_billable_entity?
  next if org.advanced_security_purchased_for_entity?

  org.set_customer_to_split_metered_offering(actor: User.ghost)
  org.set_advanced_security_seats_for_entity(seats: 0, actor: User.ghost, is_stafftools_action: true)
end
