# typed: true
# frozen_string_literal: true

class Businesses::Billing::SkusController < Businesses::BillingsController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    respond_to do |format|
      format.json do
        begin
          skus_response = billing_platform_client.get_all_pricing
        rescue => e # rubocop:todo Lint/RescueException
          return render json: { error: "Unable to query SKUs", skus: [] }, status: 500
        end

        if skus_response.is_a?(Billing::Platform::Api::Error)
          return render json: { error: "An unknown error occured", skus: [] }, status: 500
        end

        # Filtering only relevant fields
        result = skus_response[:pricings]
        unless result.empty?
          # Filtering out SKUs that are not yet effective
          result.delete_if do |r|
            Time.at(r[:effectiveAt]) > Time.now.utc
          end

          result.map! do |r|
            {
              sku: r[:sku],
              product: r[:product]
            }
          end
        end

        render json: {
          skus: result
        }, status: 200
      end
      format.html do
        head :no_content
      end
    end
  end
end
