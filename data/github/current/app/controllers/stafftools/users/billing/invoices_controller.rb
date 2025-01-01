# typed: true
# frozen_string_literal: true

class Stafftools::Users::Billing::InvoicesController < Stafftools::Users::BillingController
  include Stafftools::Users::ControllerLayoutMethods
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include Billing::Invoices

  layout :billing_layout

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  allow_verified_fetch only: [:create]
  before_action :parse_json_params, only: [:create]

  def self.react_bundle_name
    "billing-app"
  end

  def index
    render_invoices(this_entity: this_user)
  end

  def create
    respond_to do |format|
      format.json do
        generation_response = billing_platform_client.admin_trigger_invoice_generation(
          customer_id: customer_id,
          month: params[:month],
          year: params[:year],
        )

        if generation_response.is_a?(Billing::Platform::Api::Error)
          return render json: { error: generation_response.message }, status: 500
        end

        render json: { success: generation_response[:success] }, status: 200
      end
    end
  end

  private

  def customer_id
    this_user.customer.id
  end

  def entity_slug
    this_user.login
  end
end
