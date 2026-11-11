# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class PricingsController < StafftoolsController
      include ApplicationController::VerifiedFetchDependency
      include ApplicationController::JsonDependency

      # TODO: Create a proper serializer for this
      PRICING_KEYS = %i(sku product price meterType friendlyName azureMeterId freeForPublicRepos effectiveDatePrices unitType effectiveAt).freeze

      before_action :dotcom_required

      depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Mysql5,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Billing,
      ApplicationRecord::Ballast,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Repositories,
      ApplicationRecord::Configurations,
      only: [:index, :show]

      depends_on_clusters ApplicationRecord::Copilot,
        only: [:index, :show],
        optional: true

      sig { returns(String) }
      def self.react_bundle_name
        "billing-app"
      end

      sig { void }
      def index
        respond_to do |format|
          format.json do
            pricing_response = billing_client.get_all_pricing

            if pricing_response.is_a?(::Billing::Platform::Api::Error)
              return render json: { error: "An unknown error occurred" }, status: 500
            end

            pricings = pricing_response[:pricings]&.map { |pricing| pricing.slice(*PRICING_KEYS) }

            render json: pricings, status: 200
          rescue StandardError => e
            render json: { error: "Unable to query pricing" }, status: 500
          end
        end
      end

      sig { void }
      def show
        render_react_app(
          payload: {
            pricing: pricing_details,
          },
          title:  "Pricing Details",
          layout: "layouts/stafftools/react_stafftools",
        )
      end

      private

      sig { returns(::Billing::Platform::Api::Client) }
      memoize def billing_client
        ::Billing::Platform::Api::Client.new
      end

      sig { returns T.nilable(Hash) }
      def pricing_details
        pricing_response = billing_client.get_pricing(sku: params[:id])

        pricing = unless pricing_response.is_a?(::Billing::Platform::Api::Error)
          pricing_response[:pricing]&.slice(*PRICING_KEYS)
        end

        pricing
      end
    end
  end
end
