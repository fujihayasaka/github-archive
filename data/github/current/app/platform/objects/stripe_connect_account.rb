# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class StripeConnectAccount < Platform::Objects::Base
      description "A Stripe Connect account for receiving sponsorship funds from GitHub Sponsors."

      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, stripe_connect_account)
        stripe_connect_account.async_sponsors_listing.then do |sponsors_listing|
          sponsors_listing.async_sponsorable.then do |sponsorable|
            org = sponsorable.organization? ? sponsorable : nil
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
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      # Ability check for a SponsorsListing object
      def self.async_viewer_can_see?(permission, stripe_connect_account)
        stripe_connect_account.async_adminable_by?(permission.viewer)
      end

      minimum_accepted_scopes ["read:user", "read:org"]

      field :account_id, String, null: false, method: :stripe_account_id,
        description: "The account number used to identify this Stripe Connect account."

      field :is_active, Boolean, null: false, method: :active?,
        description: "Whether this Stripe Connect account is currently in use for the associated GitHub Sponsors " \
          "profile."

      field :sponsors_listing, Objects::SponsorsListing, null: false, method: :async_sponsors_listing,
        description: "The GitHub Sponsors profile associated with this Stripe Connect account."

      field :stripe_dashboard_url, Scalars::URI, null: false, description: "The URL to access this Stripe Connect " \
        "account on Stripe's website."

      field :country_or_region, String, null: true, method: :country_name,
        description: "The name of the country or region of the Stripe Connect account. Will only return a value " \
          "when queried by the maintainer of the associated GitHub Sponsors profile themselves, or by an admin " \
          "of the sponsorable organization."

      field :billing_country_or_region, String, null: true, method: :billing_country_name,
        description: "The name of the country or region of an external account, such as a bank account, tied to " \
          "the Stripe Connect account. Will only return a value when queried by the maintainer of the associated " \
          "GitHub Sponsors profile themselves, or by an admin of the sponsorable organization."
    end
  end
end
