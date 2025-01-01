# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MarketplaceOrderPreview < Platform::Objects::Base
      model_name "Marketplace::OrderPreview"
      description "Saved data from a Marketplace order preview for a given user/listing."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, order_preview)
        order_preview.async_listing.then do |listing|
          permission.typed_can_access?("MarketplaceListing", listing)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      # Ability check for a Marketplace::OrderPreview object
      def self.async_viewer_can_see?(permission, object)
        if permission.viewer.present?
          permission.viewer.id == object.user_id
        else
          true # Internal requests from background jobs
        end
      end

      visibility :internal

      minimum_accepted_scopes ["repo"]

      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      global_id_field :id, description: "The Node ID of the MarketplaceOrderPreview object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      database_id_field
      field :user, User, method: :async_user, description: "The user who previewed the Marketplace order.", null: false
      field :listing, MarketplaceListing, method: :async_listing, description: "The listing that this order preview belongs to.", null: false
      field :quantity, Integer, description: "The quantity selected in the order preview.", null: false

      field :account, Platform::Unions::Account, description: "The target account selected in the order preview.", null: false

      def account
        @object.async_account.then do |account|
          account || @object.async_user
        end
      end

      field :listing_plan, MarketplaceListingPlan, description: "The listing plan selected in the order preview.", null: true

      def listing_plan
        @object.async_listing_plan.then do |listing_plan|
          @context[:permission].typed_can_see?("MarketplaceListingPlan", listing_plan).then do |listing_plan_readable|
            if listing_plan_readable
              listing_plan
            else
              @object.async_listing.then do |listing|
                listing.default_plan
              end
            end
          end
        end
      end
    end
  end
end
