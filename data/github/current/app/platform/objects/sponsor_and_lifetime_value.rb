# typed: strict
# frozen_string_literal: true

module Platform
  module Objects
    class SponsorAndLifetimeValue < Platform::Objects::Base
      extend T::Sig

      description "A GitHub account and the total amount in USD they've paid for sponsorships to a particular " \
        "maintainer. Does not include payments made via Patreon."
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      sig do
        params(
          permission: Platform::Authorization::Permission,
          object: Platform::Models::SponsorAndLifetimeValue
        ).returns(T.any(T::Boolean, Promise[T::Boolean]))
      end
      def self.async_api_can_access?(permission, object)
        object.sponsorable.async_sponsors_listing.then do
          permission.access_allowed?(:admin_sponsors_listing,
            resource: object.sponsorable,
            current_org: object.sponsorable.organization? ? object.sponsorable : nil,
            current_repo: nil,
            allow_integrations: false,
            allow_user_via_granular_actor: false,
          )
        end
      end

      # Determine whether the viewer can see this object (called internally).
      sig do
        params(
          permission: Platform::Authorization::Permission,
          object: Platform::Models::SponsorAndLifetimeValue
        ).returns(T.any(T::Boolean, Promise[T::Boolean]))
      end
      def self.async_viewer_can_see?(permission, object)
        return Promise.resolve(T.let(false, T::Boolean)) unless GitHub.sponsors_enabled?
        object.sponsorable.async_adminable_by?(permission.viewer).then do |sponsorable_is_adminable|
          next false unless sponsorable_is_adminable
          object.async_hide_from_user?(permission.viewer).then do |hide_from_viewer|
            !hide_from_viewer
          end
        end
      end

      field :amount_in_cents, Integer, null: false, description: "The amount in cents."
      field :formatted_amount, String, null: false, description: "The amount in USD, formatted as a string."
      field :sponsor, Interfaces::Sponsorable, null: false, description: "The sponsor's GitHub account.",
        method: :async_sponsor
      field :sponsorable, Interfaces::Sponsorable, null: false, description: "The maintainer's GitHub account."
    end
  end
end
