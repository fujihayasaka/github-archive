# typed: true
# frozen_string_literal: true

class Businesses::Billing::DiscountsController < Businesses::BillingsController
  include Billing::Platform::Api::Utils
  include ApplicationController::VerifiedFetchDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:index]

  def index
    respond_to do |format|
      format.json do
        discounts = []

        year = params[:year].to_i
        month = params[:month].to_i

        discount_states_responses = billing_platform_client.get_all_discount_states(customer_id: this_business.customer_id.to_s, year: year, month: month)

        if discount_states_responses.is_a?(Billing::Platform::Api::Error)
          return render json: { error: "Unable to retrieve discounts", discounts: [] }, status: 500
        end

        discounts = discount_states_responses[:discounts].map { |discount| discount.to_hash }
        return render json: { discounts: discounts }, status: 200
      end
      format.html do
        head :no_content
      end
    end
  end
end
