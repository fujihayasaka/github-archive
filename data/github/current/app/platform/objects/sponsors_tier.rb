# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class SponsorsTier < Platform::Objects::Base
      description "A GitHub Sponsors tier associated with a GitHub Sponsors listing."

      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, sponsors_tier)
        sponsors_tier.async_sponsorable.then do |sponsorable|
          org = sponsorable.organization? ? sponsorable : nil
          permission.access_allowed?(:read_sponsors_tier,
            resource: sponsorable,
            sponsors_tier: sponsors_tier,
            current_org: org,
            current_repo: nil,
            allow_integrations: false,
            allow_user_via_granular_actor: false,
          )
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      # Ability check for a SponsorsTier object
      #
      # Adapted from MarketplaceListingPlan GraphQL object.
      def self.async_viewer_can_see?(permission, object)
        object.async_readable_by?(permission.viewer)
      end

      minimum_accepted_scopes ["read:user", "read:org"]

      implements_node templates: [
        [:ust, :user_id, :sponsors_tier_id],
        [:ost, :organization_id, :sponsors_tier_id]
      ], as: "ST", ready_date: "2021-06-04" do |sponsors_tier|
        sponsors_tier.async_sponsors_listing.then do |sponsors_listing|
          sponsors_listing.async_sponsorable.then do |sponsorable|
            if sponsorable.organization?
              {
                prefix: :ost,
                organization_id: sponsorable.id,
                sponsors_tier_id: sponsors_tier.id
              }
            else
              {
                prefix: :ust,
                user_id: sponsorable.id,
                sponsors_tier_id: sponsors_tier.id
              }
            end
          end
        end
      end

      created_at_field
      updated_at_field

      field :sponsors_listing, Objects::SponsorsListing, method: :async_sponsors_listing,
        description: "The sponsors listing that this tier belongs to.", null: false
      field :name, String, "The name of the tier.", null: false

      field :closest_lesser_value_tier, Objects::SponsorsTier,
        description: "Get a different tier for this tier's maintainer that is at the same " \
          "frequency as this tier but with an equal or lesser cost. Returns the published tier with the " \
          "monthly price closest to this tier's without going over.", null: true

      def closest_lesser_value_tier
        tier = @object.closest_lesser_value_tier
        return unless tier

        tier.async_readable_by?(@context[:viewer]).then do |is_readable|
          tier if is_readable
        end
      end

      field :description, String, "The description of the tier.", null: false

      def description
        @object.async_description_readable_by?(@context[:viewer]).then do |is_readable|
          if is_readable
            @object.description
          else
            ""
          end
        end
      end

      field :monthly_price_in_cents, Integer, "How much this tier costs per month in cents.",
        null: false
      field :monthly_price_in_dollars, Integer, "How much this tier costs per month in USD.",
        null: false
      field :is_one_time, Boolean, "Whether this tier is only for use with one-time sponsorships.",
        null: false, method: :one_time?
      field :is_custom_amount, Boolean, "Whether this tier was chosen at checkout time by the " \
        "sponsor rather than defined ahead of time by the maintainer who manages the Sponsors " \
        "listing.", method: :custom?, null: false

      field :description_html, Scalars::HTML, description: "The tier description rendered to HTML",
        null: false

      def description_html
        @object.async_description_readable_by?(@context[:viewer]).then do |is_readable|
          if is_readable
            @object.async_description_html
          else
            Scalars::HTML.coerce_input("", @context)
          end
        end
      end

      field :admin_info, Objects::SponsorsTierAdminInfo,
        description: "SponsorsTier information only visible to users that can administer the associated Sponsors listing.",
        null: true

      def admin_info
        @object.async_sponsors_listing.then do |listing|
          listing.async_adminable_by?(@context[:viewer]).then do |adminable_by|
            next if !adminable_by && !@context[:viewer]&.can_admin_sponsors_listings?
            Models::SponsorsTierAdminInfo.new(@object)
          end
        end
      end
    end
  end
end
