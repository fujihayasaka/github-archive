# typed: true
# frozen_string_literal: true

class Businesses::Billing::ProductsController < Businesses::BillingsController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    respond_to do |format|
      format.json do
        begin
          products_response = billing_platform_client.get_all_products
        rescue => e # rubocop:todo Lint/RescueException
          return render json: { error: "Unable to query products", products: [] }, status: 500
        end

        if products_response.is_a?(Billing::Platform::Api::Error)
          return render json: { error: "An unknown error occured", products: [] }, status: 500
        end

        # Filtering only relevant fields
        result = products_response[:products]
        unless result.empty?
          result.map! do |r|
            {
              name: r[:name],
              friendlyProductName: r[:friendlyProductName]
            }
          end
        end

        render json: {
          products: result
        }, status: 200
      end
      format.html do
        head :no_content
      end
    end
  end
end
