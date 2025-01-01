# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::InvoicesController < Stafftools::Businesses::BillingController
  extend T::Sig

  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include ReactHelper

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing, only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  allow_verified_fetch only: [:create]

  before_action :parse_json_params, only: [:create]

  def self.react_bundle_name
    "billing-app"
  end

  def index
    respond_to do |format|
      format.json do
        invoices_response = billing_platform_client.get_invoices(customer_id: params[:customer_id])
        if invoices_response.is_a?(Billing::Platform::Api::Error)
          return render json: { error: invoices_response.message, invoices: [] }, status: 500
        end

        render json: { invoices: invoices_response[:invoices] }, status: 200
      end

      format.html do
        render_invoices_react_app(payload: { customerSelections: usage_customer_selections(this_business) })
      end
    end

  end

  def create
    if params[:customerId].blank?
      return render json: { error: "invalid customer id" }, status: 400
    end

    if params[:customerId] != this_business.customer_id.to_s
      # check customerId belongs to a cost center within the enterprise
      allowed_cost_centers = usage_customer_selections(this_business)
      if allowed_cost_centers.none? { |cc| cc[:id] == params[:customerId] }
        return render json: { error: "invalid customer id" }, status: 400
      end
    end

    generation_response = billing_platform_client.admin_trigger_invoice_generation(
      customer_id: params[:customerId],
      month: params[:month],
      year: params[:year],
    )

    if generation_response.is_a?(Billing::Platform::Api::Error)
      return render json: { error: generation_response.message }, status: 500
    end

    render json: { success: generation_response[:success] }, status: 200
  end

  private

  def render_invoices_react_app(payload:)
    payload = {
      slug: this_business.slug,
    }.merge!(payload)

    render_react_app(
      payload: payload,
      page_data: { selected_link: :business_billing_settings },
      title: "#{this_business.name} | Invoices",
      ssr: true,
    )
  end
end
