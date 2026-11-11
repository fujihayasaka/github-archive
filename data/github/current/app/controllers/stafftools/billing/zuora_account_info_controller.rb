# typed: strict
# frozen_string_literal: true

class Stafftools::Billing::ZuoraAccountInfoController < StafftoolsController
  before_action :ensure_billing_enabled
  before_action :ensure_customer_exists

  sig { void }
  def update
    return unless customer.present?
    present_customer = T.must(customer)
    billable_entity = T.must(present_customer.billable_owner)
    plan_subscription = get_plan_subscription

    customer_updated, customer_errors = update_customer_fields
    subscription_updated, subscription_errors = update_subscription_fields(plan_subscription)

    if !customer_updated && !customer_errors && !subscription_updated && !subscription_errors
      flash[:warn] = "No changes were made to #{billable_entity.display_login}'s Zuora information."
      redirect_to :back and return
    end

    # Build success and error messages based on what was attempted and the results
    messages = []
    if customer_updated && !customer_errors
      messages << "Zuora account information successfully updated."
    elsif customer_errors
      messages << "Zuora account information update failed: #{customer_errors}"
    end

    if subscription_updated && !subscription_errors
      messages << "Zuora subscription information successfully updated."
    elsif subscription_errors
      messages << "Zuora subscription information update failed: #{subscription_errors}"
    end

    # Determine flash type: error if any failures, notice if all successes
    has_errors = customer_errors.present? || subscription_errors.present?
    has_successes = customer_updated || subscription_updated

    if has_errors && has_successes
      # Partial success/failure - show all messages
      flash[:warn] = messages.join("\n")
    elsif has_errors
      # All failures
      flash[:error] = messages.join("\n")
    elsif has_successes
      old_account_id = present_customer.zuora_account_id
      old_account_number = present_customer.zuora_account_number
      old_subscription_id = plan_subscription&.zuora_subscription_id
      old_subscription_number = plan_subscription&.zuora_subscription_number
      instrument_update(
        target: billable_entity,
        old_account_id: old_account_id,
        new_account_id: present_customer.zuora_account_id,
        old_account_number: old_account_number,
        new_account_number: present_customer.zuora_account_number,
        old_subscription_id: old_subscription_id,
        new_subscription_id: plan_subscription&.zuora_subscription_id,
        old_subscription_number: old_subscription_number,
        new_subscription_number: plan_subscription&.zuora_subscription_number
      )
      flash[:notice] = messages.join("\n")
    end

    redirect_to :back
  end

  private

  sig { void }
  def ensure_customer_exists
    return if customer.present?
    redirect_to :back, flash: { error: "Customer not found" }
  end

  sig { returns(T.nilable(Customer)) }
  memoize def customer
    Customer.find_by(id: params[:customer_id])
  end

  sig { returns(T.nilable(T.any(Billing::PlanSubscription, Billing::SalesServePlanSubscription))) }
  def get_plan_subscription
    return nil unless billable_entity = customer&.billable_owner
    if billable_entity.is_a?(Business) && billable_entity.invoiced?
      return billable_entity.sales_serve_plan_subscription
    end
    billable_entity.plan_subscription
  end

  sig { returns([T::Boolean, T.nilable(String)]) }
  def update_customer_fields
    customer = T.must(self.customer)
    return [false, nil] if customer.zuora_account_id.to_s == params[:zuora_account_id] && customer.zuora_account_number.to_s == params[:zuora_account_number]

    # It's possible for the information to be set to nil if an empty string is submitted
    customer.zuora_account_id = params[:zuora_account_id].presence
    customer.zuora_account_number = params[:zuora_account_number].presence

    return [true, nil] if customer.save
    [false, "Customer: #{customer.errors.full_messages.join(", ")}"]
  end

  sig { params(plan_subscription: T.nilable(T.any(Billing::PlanSubscription, Billing::SalesServePlanSubscription))).returns([T::Boolean, T.nilable(String)]) }
  def update_subscription_fields(plan_subscription)
    return [false, nil] unless plan_subscription
    return [false, nil] if plan_subscription.zuora_subscription_id.to_s == params[:zuora_subscription_id] && plan_subscription.zuora_subscription_number.to_s == params[:zuora_subscription_number]

    # It's possible for the information to be set to nil if an empty string is submitted
    plan_subscription.zuora_subscription_id = params[:zuora_subscription_id].presence
    plan_subscription.zuora_subscription_number = params[:zuora_subscription_number].presence

    return [true, nil] if plan_subscription.save
    [false, "Subscription: #{plan_subscription.errors.full_messages.join(", ")}"]
  end

  sig do
    params(
      target: T.any(User, Business),
      old_account_id: T.nilable(String),
      new_account_id: T.nilable(String),
      old_account_number: T.nilable(String),
      new_account_number: T.nilable(String),
      old_subscription_id: T.nilable(String),
      new_subscription_id: T.nilable(String),
      old_subscription_number: T.nilable(String),
      new_subscription_number: T.nilable(String)
    ).void
  end
  def instrument_update(target:, old_account_id:, new_account_id:, old_account_number:, new_account_number:,
                        old_subscription_id:, new_subscription_id:, old_subscription_number:, new_subscription_number:)
    event_data = {
      actor: current_user,
      old_zuora_account_id: old_account_id,
      new_zuora_account_id: new_account_id,
      old_zuora_account_number: old_account_number,
      new_zuora_account_number: new_account_number,
      old_zuora_subscription_id: old_subscription_id,
      new_zuora_subscription_id: new_subscription_id,
      old_zuora_subscription_number: old_subscription_number,
      new_zuora_subscription_number: new_subscription_number
    }.tap { |payload| payload[target.event_prefix] = target }

    GitHub.instrument("billing.update_zuora_account_info", event_data)
  end
end
