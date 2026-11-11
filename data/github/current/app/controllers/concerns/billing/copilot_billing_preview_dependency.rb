# typed: strict
# frozen_string_literal: true

module Billing::CopilotBillingPreviewDependency
  include Billing::Platform::Api::Utils
  include Billing::ProductsDependency
  extend ActiveSupport::Concern

  extend T::Helpers

  requires_ancestor { ApplicationController }

  abstract!

  PREMIUM_REQUEST_UNIT_PRICE = 0.04
  AI_CREDIT_UNIT_PRICE = 0.01

  sig { params(this_entity: ::Billing::Types::Account, is_stafftools_route: T::Boolean).void }
  def render_billing_preview(this_entity:, is_stafftools_route: false)
    respond_to do |format|
      format.json do
        # Stafftools routes bypass the bill preview eligibility check so staff can always
        # access billing previews, even when the feature flag or Copilot access requirements
        # are not met for the entity.
        if !is_stafftools_route && !bill_preview_enabled?(this_entity)
          return render json: { error: "Feature not available" }, status: :not_found
        end

        customer = this_entity.customer
        return render json: { error: "Customer not found" }, status: :unprocessable_entity if customer.nil?

        today = Time.now.utc.to_date
        if today.year == 2026 && (today.month == 4 || today.month == 5)
          # During April and May 2026, always show April 2026 data for the TBB preview launch window
          month = 4
          year = 2026
        else
          month = params[:month].present? ? params[:month].to_i : today.month
          year = params[:year].present? ? params[:year].to_i : today.year
        end

        begin
          preview_response = billing_platform_client.get_copilot_billing_preview(
            customer_id: customer.id.to_s,
            year: year,
            month: month,
            billing_period: BillingPlatform::Base::BillingPeriod::Monthly,
          )
        rescue => e
          Failbot.report(e, app: "billing-platform")
          return render json: { error: "Unable to query billing preview" }, status: 500
        end

        if preview_response.is_a?(Billing::Platform::Api::Error)
          return render json: { error: "An unknown error occurred" }, status: 500
        end

        premium_request_amount = preview_response[:premium_request_amount].to_f
        ai_credit_amount = preview_response[:ai_credit_amount].to_f

        response_data = {
          premiumRequestAmount: premium_request_amount,
          aiCreditAmount: ai_credit_amount,
          premiumRequestQuantity: (premium_request_amount / PREMIUM_REQUEST_UNIT_PRICE).round,
          aiCreditQuantity: (ai_credit_amount / AI_CREDIT_UNIT_PRICE).round,
          premiumRequestUnitPrice: PREMIUM_REQUEST_UNIT_PRICE,
          aiCreditUnitPrice: AI_CREDIT_UNIT_PRICE,
          billingMonth: month,
          billingYear: year,
        }

        render json: response_data, status: 200
      end
    end
  end

  protected

  sig { abstract.returns(Billing::Platform::Api::Client) }
  def billing_platform_client; end
end
