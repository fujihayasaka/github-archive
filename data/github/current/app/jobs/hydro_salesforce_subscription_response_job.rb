# typed: true
# frozen_string_literal: true

class HydroSalesforceSubscriptionResponseJob < HydroMessageJob

  queue_as :hydro_salesforce_subscription_response
  retry_on_dirty_exit

  # Public: process a Hydro message
  sig { void }
  def perform
    request = Billing::SalesServeSubscriptionChangeRequest.find_by(request_uuid: message[:request_id])
    if request.nil?
      raise "Request is not found for #{message[:request_id]} in the database"
    end

    actor = User.staff_user
    GitHub.context.push(actor: actor)

    change_request_item_for_ghas_provision = T.let(nil, T.nilable(Billing::SalesServeSubscriptionChangeRequestItem))

    # if request_uuid is present, update the table
    message[:product_responses].each do |product_response|
      request_items = request.items
      if product_response[:product_rate_plan_charge_id].present?
        request_items = request_items.where(product_rate_plan_charge_id: product_response[:product_rate_plan_charge_id])
        if request_items.empty?
          GitHub.logger.info("request item is not found for #{request.request_uuid} - #{product_response[:product_rate_plan_charge_id]}")
          next
        end
      end

      request_items = request_items.where(change_type: translate_type(product_response[:type]))
      if request_items.empty?
        GitHub.logger.info("request item is not found for #{request.request_uuid} - #{product_response[:type]}")
        next
      end

      request_items.map do |item|
        status = translate_status(product_response[:status])
        with_write do
          item_updated = item.update(status: status)
          if !item_updated
            GitHub.logger.info("#{item.id} is not updated due to #{item.errors} ")
            next
          end
        end

        change_request_item_for_ghas_provision ||= item if item.status_complete? && GitHub.zuora_sales_serve_ghas_product_charge_ids.include?(item.product_rate_plan_charge_id)
      end
    end

    if change_request_item_for_ghas_provision &&
      (seats = change_request_item_for_ghas_provision.quantity) &&
      (business = request.customer&.business)
      provision_ghas(business:, seats:)
    end
  end

  sig { params(status: Symbol).returns(Symbol) }
  def translate_status(status)
    case status
    when :COMPLETE
      :complete
    when :ERROR
      :error
    when :PENDING
      :pending
    else
      :unknown
    end
  end

  sig { params(type: Symbol).returns(Symbol) }
  def translate_type(type)
    case type
    when :UPDATE
      :update
    when :RENEWAL
      :renewal
    else
      raise "type - #{type} is not valid"
    end
  end

  sig { params(business: T.nilable(Business), seats: Integer).void }
  def provision_ghas(business:, seats:)
    return unless business
    enabled = seats > 0

    # dotcom ghas provisioning
    actor = User.staff_user
    with_write do
      if enabled
        business.mark_advanced_security_as_purchased_for_entity(actor:)
      else
        business.mark_advanced_security_as_not_purchased_for_entity(actor:)
      end
      business.set_advanced_security_seats_for_entity(actor:, seats:)
    end

    # enterprise-web ghas provisioning
    return unless business.enterprise_web_business_id.present?
    return unless subscription_id = business.active_plan_subscription&.zuora_subscription_id
    return unless subscription = Billing::Zuora::SalesManagedSubscription.fetch_by_subscription_id(subscription_id)
    return unless license_number = subscription.license_number
    return unless license_number.present?

    payload = {
      advanced_security_enabled: enabled,
      advanced_security_seats: seats,
    }
    GitHub::EnterpriseWeb::License.update(business.enterprise_web_business_id, license_number, payload)
  end
end
