# typed: true
# frozen_string_literal: true

class Customers::Billing::DiscountsController < Customers::BillingController
  include Billing::Platform::Api::Utils
  include ApplicationController::VerifiedFetchDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:index]

  def index
    respond_to do |format|
      format.json do
        year = params.has_key?(:year) ? params[:year].to_i : Time.now.utc.year
        month = params.has_key?(:month) ? params[:month].to_i : Time.now.utc.month

        customer_id = this_organization.customer.id

        begin
          discount_states_responses = Billing::Platform::Api::Client.new.get_all_discount_states(customer_id: customer_id, year: year, month: month)
        rescue => e # rubocop:todo Lint/GenericRescue
          Rails.logger.error "Error querying discounts for customer #{customer_id} for #{month}/#{year}: #{e.message}"
          return render json: { error: "Unable to query discounts", discounts: [] }, status: 500
        end

        if discount_states_responses.is_a?(Billing::Platform::Api::Error)
          Rails.logger.error "API returned error for discounts retrieval for customer #{customer_id} for #{month}/#{year}: #{discount_states_responses.message}"
          return render json: { error: "Unable to retrieve discounts", discounts: [] }, status: 500
        end

        discounts = discount_states_responses[:discounts].map(&:to_hash)

        render json: { discounts: discounts }
      end
    end
  end
end
