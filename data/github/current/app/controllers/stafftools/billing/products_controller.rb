# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class ProductsController < StafftoolsController
      include ReactHelper
      include ApplicationController::VerifiedFetchDependency
      include ApplicationController::JsonDependency

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
        only: [:index, :show, :new, :edit], optional: true

      allow_verified_fetch only: [:create, :update]

      sig { returns(String) }
      def self.react_bundle_name
        "billing-app"
      end

      sig { void }
      def new
        render_react_app(
          payload: {},
          title: "Create a Metered Billing Product",
          layout: "layouts/stafftools/react_stafftools",
          ssr: true,
        )
      end

      sig { void }
      def create
        product_name = params[:name]
        product_exists = products.any? { |product| product[:name] == product_name }

        if product_exists
          return render json: { error: "A product with this name already exists" }, status: 400
        end

        response = billing_client.create_or_update_product({
          name: product_name,
          friendlyProductName: params[:friendlyProductName],
          zuoraUsageIdentifier: params[:zuoraUsageIdentifier]
        })

        if response.is_a?(::Billing::Platform::Api::Error)
          return render json: { error: "Unable to create product" }, status: 500
        end
        render_react_app payload: {}, ssr: true
      end

      sig { void }
      def index
        render_react_app(
          payload: {
            products: products,
          },
          title: "Metered Billing Products",
          layout: "layouts/stafftools/react_stafftools",
          ssr: true,
        )
      end

      sig { void }
      def show
        render_react_app(
          payload: {
            product: product_details,
          },
          title:  "Product Details",
          layout: "layouts/stafftools/react_stafftools",
          ssr: true,
        )
      end

      sig { void }
      def edit
        render_react_app(
          payload: {
            product: product_details,
          },
          title: "Update a Metered Billing Product",
          layout: "layouts/stafftools/react_stafftools",
          ssr: true,
        )
      end

      sig { void }
      def update
        response = billing_client.create_or_update_product({
          name: params[:name],
          friendlyProductName: params[:friendlyProductName],
          zuoraUsageIdentifier: params[:zuoraUsageIdentifier]
        })

        if response.is_a?(::Billing::Platform::Api::Error)
          return render json: { error: "Unable to update product" }, status: 500
        end
        render_react_app payload: {}, ssr: true
      end

      private

      sig { returns(::Billing::Platform::Api::Client) }
      memoize def billing_client
        ::Billing::Platform::Api::Client.new
      end

      sig { returns T::Array[Hash] }
      memoize def products
        products_response = billing_client.get_all_products
        products = if products_response.is_a?(::Billing::Platform::Api::Error)
          []
        else
          products_response[:products]
        end
        products
      end

      sig { returns T.nilable(Hash) }
      def product_details
        product_response = billing_client.get_product(params[:id])
        pricing_response = billing_client.get_pricings_by_product(product_name: params[:id])
        product_keys = [:name, :friendlyProductName, :zuoraUsageIdentifier]
        pricing_keys = [:sku, :friendlyName, :product, :meterType, :price, :azureMeterId, :freeForPublicRepos, :unitType, :effectiveAt]

        product = unless product_response.is_a?(::Billing::Platform::Api::Error)
          product_response[:product]&.select { |k, _| product_keys.include?(k) }
        end

        if product && !pricing_response.is_a?(::Billing::Platform::Api::Error)
          product[:pricings] = pricing_response[:pricings].map { |k| k.slice(*pricing_keys) }
        end

        product
      end
    end
  end
end
