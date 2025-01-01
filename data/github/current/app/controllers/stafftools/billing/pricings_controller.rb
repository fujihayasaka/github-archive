# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class PricingsController < StafftoolsController
      extend T::Sig
      include ReactHelper
      include ApplicationController::VerifiedFetchDependency
      include ApplicationController::JsonDependency

      # TODO: Create a proper serializer for this
      PRICING_KEYS = %i(sku product price meterType friendlyName azureMeterId freeForPublicRepos effectiveDatePrices unitType effectiveAt).freeze

      before_action :dotcom_required
      before_action :try_parse_json_params, only: [:create, :update]

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
      only: [:index, :show, :new, :edit]

      depends_on_clusters ApplicationRecord::Copilot,
        only: [:index, :show, :new, :edit],
        optional: true

      allow_verified_fetch only: [:create, :update]

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
          rescue StandardError => e # rubocop:todo Lint/GenericRescue
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
          ssr: true,
        )
      end

      sig { void }
      def new
        render_react_app(
          payload: {
            productId: params[:product_id],
          },
          title: "Create a New Metered Billing SKU",
          layout: "layouts/stafftools/react_stafftools",
          ssr: true,
        )
      end

      sig { void }
      def create
        sku = params[:sku]
        pricing_response = billing_client.get_pricing(sku:)
        if !pricing_response.is_a?(::Billing::Platform::Api::Error) && pricing_response[:pricing].present?
          return render json: { error: "A SKU pricing with this name already exists" }, status: 400
        end

        create_pricing_response = billing_client.create_or_update_pricing(pricing: upsert_pricing_body)
        if create_pricing_response.is_a?(::Billing::Platform::Api::Error)
          return render json: { error: "Unable to create SKU pricing" }, status: 500
        end

        GitHub.instrument("billing.sku_create", { sku: })
        render_react_app(payload: {}, ssr: true)
      end

      sig { void }
      def edit
        render_react_app(
          payload: {
            pricing: pricing_details,
          },
          title: "Update a Metered Billing SKU",
          layout: "layouts/stafftools/react_stafftools",
          ssr: true,
        )
      end

      sig { void }
      def update
        sku = upsert_pricing_body[:sku]
        update_pricing_response = billing_client.create_or_update_pricing(pricing: upsert_pricing_body)
        if update_pricing_response.is_a?(::Billing::Platform::Api::Error)
          return render json: { error: "Unable to update SKU pricing" }, status: 500
        end

        GitHub.instrument("billing.sku_update", { sku: })
        render_react_app(payload: {}, ssr: true)
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

      sig { returns Hash }
      def upsert_pricing_body
        {
          sku: params[:sku],
          friendlyName: params[:friendlyName],
          price: params[:price],
          meterType: params[:meterType],
          unitType: params[:unitType],
          freeForPublicRepos: params[:freeForPublicRepos],
          effectiveAt: params[:effectiveAt],
          product: params[:product],
          azureMeterId: params[:azureMeterId],
        }
      end
    end
  end
end
