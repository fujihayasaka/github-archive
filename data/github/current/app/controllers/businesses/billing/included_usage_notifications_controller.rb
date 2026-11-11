# typed: strict
# frozen_string_literal: true

class Businesses::Billing::IncludedUsageNotificationsController < Businesses::BillingsController
  include ApplicationController::VerifiedFetchDependency
  include Billing::Platform::Api::Utils

  allow_verified_fetch only: [:update]

  sig { void }
  def update
    return render_404 unless FeatureFlag.vexi.enabled?(:billing_discount_threshold_notification, this_business, default: false)

    if customer_id.blank?
      render json: { error: "Customer not found" }, status: 422
      return
    end

    raw_body = request.body.read
    body = if raw_body.blank?
      {}
    else
      begin
        JSON.parse(raw_body)
      rescue JSON::ParserError
        {}
      end
    end
    value = (body["value"] || params[:value]).to_s

    unless %w[enabled disabled].include?(value)
      render json: { error: "Invalid value. Must be 'enabled' or 'disabled'" }, status: 422
      return
    end

    response = billing_platform_client.add_key_value(
      customer_id: customer_id,
      key: "included_usage_notification_customer",
      value: value
    )

    if response.is_a?(Billing::Platform::Api::Error)
      render json: { error: "Unable to update notification setting" }, status: 500
    else
      render json: { success: true, value: value }, status: 200
    end
  end

  private

  sig { returns(Billing::Platform::Api::Client) }
  def billing_platform_client
    Billing::Platform::Api::Client.new
  end

  sig { returns(String) }
  def customer_id
    this_business.customer_id.to_s
  end
end
