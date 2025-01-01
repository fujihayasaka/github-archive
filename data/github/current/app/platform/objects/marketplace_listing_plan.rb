# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MarketplaceListingPlan < Platform::Objects::Base
      model_name "Marketplace::ListingPlan"
      description "A payment plan for a listing in the GitHub Marketplace."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      # Ability check for a Marketplace::ListingPlan object
      #
      # See https://github.com/github/marketplace/blob/master/docs/graphql-permissions.md for
      # more context around this implementation.
      def self.async_viewer_can_see?(permission, object)
        object.async_listing.then do |listing|
          if object.published? && listing&.publicly_listed?
            true
          elsif listing && permission.authenticating_as_app?
            if listing.listable_is_integration?
              listing.listable_id == permission.integration.id
            elsif listing.listable_is_oauth_application?
              listing.listable_id == permission.oauth_app.id
            end
          else
            object.async_can_user_see?(permission.viewer)
          end
        end
      end

      visibility :internal

      minimum_accepted_scopes ["repo"]

      implements_node templates: [[:mlp, :id]], as: "MLP", ready_date: "2021-03-18" do |marketplace_listing_plan|
        {
          prefix: :mlp,
          id: marketplace_listing_plan.id,
        }
      end

      database_id_field

      field :name, String, "The name.", null: false
      field :description, String, "A description.", null: false
      field :monthly_price_in_cents, Integer, "How much this costs per month in cents.", null: false
      field :yearly_price_in_cents, Integer, "How much this costs annually in cents.", null: false
      field :monthly_price_in_dollars, Integer, "How much this costs per month in dollars.", null: false
      field :yearly_price_in_dollars, Integer, "How much this costs annually in dollars.", null: false
      field :can_publish, Boolean, "Can this be published?", method: :can_publish?, null: false
      field :can_be_retired, Boolean, "Can this be retired?", method: :can_be_retired?, null: false
      field :can_change_pricing, Boolean, "Can pricing on this be changed?", method: :can_change_pricing?, null: false
      field :can_be_installed, Boolean, "Can plan can be installed?", method: :can_be_installed?, null: false
      field :description_html, Scalars::HTML, description: "The description rendered to HTML", null: false

      def description_html
        Platform::Helpers::MarketplaceListingContent.html_for(
          @object, :description, { current_user: @context[:viewer] }
        )
      end

      field :number, Integer, "The plan's number.", null: false
      field :are_prices_allowed, Boolean, "Can prices be set for this plan?", method: :prices_allowed?, null: false, visibility: :internal
      field :is_per_unit, Boolean, "Is this plan charged per unit?", method: :per_unit, null: false
      field :is_unit_allowed, Boolean, "Can a unit be set for this plan?", method: :unit_allowed?, null: false, visibility: :internal
      field :unit_name, String, "The name of the unit if this plan is per-unit.", null: true
      field :is_paid, Boolean, "Is this a paid plan or free?", method: :paid?, null: false
      field :is_direct_billing, Boolean, "Is this a direct billing plan?", method: :direct_billing?, null: false, visibility: :internal
      field :price_model, Enums::MarketplaceListingPlanPriceModel, "The pricing model for this plan", null: false
      field :remaining_bullet_count, Integer, "How many more bullet points can be added to this plan.", null: false
      field :has_free_trial, Boolean, "Does this plan have a free trial", method: :has_free_trial?, null: false
      field :is_free_trial_allowed, Boolean, "Can a free trial be set for this plan?", method: :free_trial_allowed?, null: false, visibility: :internal
      field :for_users_only, Boolean, "Is this plan for personal user accounts only?", null: false, method: :for_users_only?
      field :for_organizations_only, Boolean, "Is this plan for organization accounts only?", null: false, method: :for_organizations_only?

      field :state, Enums::MarketplaceListingPlanState, description: "The current state of the listing plan", null: false

      def state
        @object.current_state.name
      end

      field :can_change_name, Boolean, description: "Can the name on this plan be changed?", null: false

      def can_change_name
        @object.async_listing.then do
          @object.can_change_name?
        end
      end

      field :listing, MarketplaceListing, method: :async_listing, description: "The listing that this plan belongs to.", null: true

      field :bullets, Connections.define(Objects::MarketplaceListingPlanBullet), description: "A list of bullet points describing this plan.", null: false, connection: true

      def bullets
        @object.bullets.order(:id).scoped
      end

      field :subscription_items, Connections::SubscriptionItem, visibility: :internal, description: "A list of the subscription items associated with this plan.", null: true, numeric_pagination_enabled: true do
        T.bind(self, GraphQL::Schema::Member::HasArguments)
        argument :account_id, ID, "Filter the subscription items for a given account", required: false
        argument :order_by, Inputs::SubscriptionItemOrder, "Ordering options for the returned subscription items.", required: false
      end

      def subscription_items(**arguments)
        scope = @object.subscription_items.order(:id)

        if arguments[:account_id]
          account = Platform::Helpers::NodeIdentification.typed_object_from_id([Objects::User, Objects::Organization], arguments[:account_id], @context)
          raise Platform::Errors::NotFound.new("Unable to find account") unless account
          scope = account.business&.self_serve_payment? ? scope.where(organization_id: account.id) : scope.joins(:plan_subscription).where(plan_subscriptions: { user_id: account.id })
        end

        if arguments[:order_by]
          field = arguments[:order_by][:field]
          direction = arguments[:order_by][:direction]
          scope = scope.reorder("subscription_items.#{field} #{direction}")
        end

        scope.active.scoped
      end

      def self.load_from_global_id(id)
        Loaders::ActiveRecord.load(::Marketplace::ListingPlan, id.to_i).then do |plan|
          if plan
            plan.async_listing.then { plan }
          end
        end
      end
    end
  end
end
