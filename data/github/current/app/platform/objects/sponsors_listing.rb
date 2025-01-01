# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class SponsorsListing < Platform::Objects::Base
      description "A GitHub Sponsors listing."

      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      sig do
        params(
          permission: Platform::Authorization::Permission,
          sponsors_listing: ::SponsorsListing
        ).returns(Promise[T::Boolean])
      end
      def self.async_api_can_access?(permission, sponsors_listing)
        sponsors_listing.async_sponsorable.then do |sponsorable|
          org = T.must(sponsorable).organization? ? sponsorable : nil
          permission.access_allowed?(:read_sponsors_listing,
            resource: sponsorable,
            sponsors_listing: sponsors_listing,
            current_org: org,
            current_repo: nil,
            allow_integrations: false,
            allow_user_via_granular_actor: false,
          )
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      # Ability check for a SponsorsListing object
      sig do
        params(
          permission: Platform::Authorization::Permission,
          sponsors_listing: ::SponsorsListing
        ).returns(Promise[T::Boolean])
      end
      def self.async_viewer_can_see?(permission, sponsors_listing)
        sponsors_listing.async_readable_by?(permission.viewer)
      end

      minimum_accepted_scopes ["read:user", "read:org"]

      implements_node templates: [[:usl, :user_id, :sponsors_listing_id], [:osl, :organization_id, :sponsors_listing_id]], as: "SL", ready_date: "2021-05-26" do |sponsors_listing|
        sponsors_listing.async_sponsorable.then do |sponsorable|
          if sponsorable.organization?
            {
              prefix: :osl,
              organization_id: sponsorable.id,
              sponsors_listing_id: sponsors_listing.id
            }
          else
            {
              prefix: :usl,
              user_id: sponsorable.id,
              sponsors_listing_id: sponsors_listing.id
            }
          end
        end
      end

      created_at_field

      url_fields description: "The HTTP URL for this Sponsors listing." do |sponsors_listing|
        template = Addressable::Template.new("/sponsors/{sponsorable_login}")
        template.expand sponsorable_login: sponsors_listing.sponsorable_login
      end

      url_fields(
        prefix: :dashboard,
        description: "The HTTP URL for the Sponsors dashboard for this Sponsors listing.",
      ) do |sponsors_listing|
        template = Addressable::Template.new("/sponsors/{sponsorable_login}/dashboard")
        template.expand sponsorable_login: sponsors_listing.sponsorable_login
      end

      field :slug, String, "The short name of the listing.", null: false
      field :name, String, "The listing's full name.", null: false
      field :short_description, String, "The short description of the listing.", null: false

      sig { returns String }
      def short_description
        @object.short_description || ""
      end

      field :full_description, String, "The full description of the listing.", null: false

      sig { returns String }
      def full_description
        @object.full_description || ""
      end

      field :full_description_html, Scalars::HTML, description: "The full description of the listing rendered to HTML.", null: false

      sig { returns String }
      def full_description_html
        Platform::Helpers::MarketplaceListingContent.html_for(
          @object, :full_description, { current_user: @context[:viewer] }
        )
      end

      field :active_goal, Objects::SponsorsGoal,
        description: "The current goal the maintainer is trying to reach with GitHub " \
          "Sponsors, if any.",
        null: true, method: :async_active_goal
      field :is_public, Boolean, "Whether this listing is publicly visible.", null: false, method: :approved?

      field :active_stripe_connect_account, Objects::StripeConnectAccount, null: true,
        description: "The Stripe Connect account currently in use for payouts for this Sponsors listing, if any. " \
          "Will only return a value when queried by the maintainer themselves, or by an admin of the sponsorable " \
          "organization."

      sig { returns Promise[T.nilable(Billing::StripeConnect::Account)] }
      def active_stripe_connect_account
        @object.async_adminable_by?(@context[:viewer]).then do |can_admin|
          # Intentionally not calling #active_stripe_account_for_self_or_fiscal_host here because that would be a
          # Stripe Connect account whose owner is someone other than the sponsorable:
          @object.async_active_stripe_connect_account if can_admin
        end
      end

      field :sponsorable, Interfaces::Sponsorable, method: :async_sponsorable,
        description: "The entity this listing represents who can be sponsored on GitHub Sponsors.", null: false

      field(:featured_items, [Objects::SponsorsListingFeaturedItem],
        description: "The records featured on the GitHub Sponsors profile.",
        null: false,
      ) do
        argument :featureable_types, [Enums::SponsorsListingFeaturedItemFeatureableType],
          "The types of featured items to return.", required: false, default_value: %w[Repository User]
      end

      sig { params(featureable_types: T::Array[String]).returns(ArrayWrapper) }
      def featured_items(featureable_types:)
        ArrayWrapper.new(@object.featured_items.where(featureable_type: featureable_types).ordered_by_position)
      end

      field :tiers, Connections.define(Objects::SponsorsTier),
        description: "The tiers for this GitHub Sponsors profile.",
        connection: true,
        null: true do
        argument :order_by, Inputs::SponsorsTierOrder,
          "Ordering options for Sponsors tiers returned from the connection.", required: false,
          default_value: { field: "monthly_price_in_cents", direction: "ASC" }
        argument :include_unpublished, Boolean, "Whether to include tiers that aren't published. Only admins of " \
          "the Sponsors listing can see draft tiers. Only admins of the Sponsors listing and viewers who are " \
          "currently sponsoring on a retired tier can see those retired tiers. Defaults to including only " \
          "published tiers, which are visible to anyone who can see the GitHub Sponsors profile.", required: false,
          default_value: false
      end

      sig do
        params(
          order_by: Platform::Inputs::SponsorsTierOrder,
          include_unpublished: T::Boolean
        ).returns(ActiveRecord::Relation)
      end
      def tiers(order_by:, include_unpublished: false)
        scope = @object.sponsors_tiers
        scope = if include_unpublished
          scope.visible_to(@context[:viewer])
        else
          scope.with_published_state
        end
        scope.order("sponsors_tiers.#{order_by[:field]} #{order_by[:direction]}")
      end

      field :next_payout_date, Scalars::Date,
        description: "A future date on which this listing is eligible to receive a payout.",
        null: true

      sig { returns Promise[T.nilable(Date)] }
      def next_payout_date
        @object.async_next_payout_date_for(@context[:viewer])
      end

      field :residence_country_or_region, String, null: true,
        description: "The name of the country or region where the maintainer resides. Will only return a value " \
          "when queried by the maintainer themselves, or by an admin of the sponsorable organization."

      sig { returns Promise[T.nilable(String)] }
      def residence_country_or_region
        @object.async_adminable_by?(@context[:viewer]).then do |can_admin|
          @object.country_of_residence_name if can_admin
        end
      end

      field :billing_country_or_region, String, null: true,
        description: "The name of the country or region with the maintainer's bank account or fiscal host. Will " \
          "only return a value when queried by the maintainer themselves, or by an admin of the sponsorable " \
          "organization."

      sig { returns Promise[T.nilable(String)] }
      def billing_country_or_region
        @object.async_adminable_by?(@context[:viewer]).then do |can_admin|
          @object.full_billing_country if can_admin
        end
      end

      field :fiscal_host, Organization, null: true,
        description: "The fiscal host used for payments, if any. Will only return a value when queried by the " \
          "maintainer themselves, or by an admin of the sponsorable organization."

      sig { returns Promise[T.nilable(::SponsorsListing)] }
      def fiscal_host
        @object.async_adminable_by?(@context[:viewer]).then do |can_admin|
          @object.async_parent_listing_sponsorable if can_admin
        end
      end

      field :contact_email_address, String, null: true,
        description: "The email address used by GitHub to contact the sponsorable " \
          "about their GitHub Sponsors profile. Will " \
          "only return a value when queried by the maintainer themselves, or by an admin of the sponsorable " \
          "organization."

      sig { returns Promise[T.nilable(String)] }
      def contact_email_address
        @object.async_adminable_by?(@context[:viewer]).then do |can_admin|
          @object.async_contact_email_address if can_admin
        end
      end
    end
  end
end
