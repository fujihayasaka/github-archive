# typed: strict
# frozen_string_literal: true

module Platform
  module Objects
    class Sponsorship < Platform::Objects::Base
      description "A sponsorship relationship between a sponsor and a maintainer"
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      sig do
        params(
          permission: Authorization::Permission,
          sponsorship: ::Sponsorship
        ).returns(T.any(Promise[T::Boolean], T::Boolean))
      end
      def self.async_api_can_access?(permission, sponsorship)
        # A public sponsorship is publicly accessible data, no special permissions required:
        return true if sponsorship.privacy_public?

        Promise.all([
          sponsorship.async_sponsors_listing,
          sponsorship.async_sponsor,
        ]).then do |sponsors_listing, sponsor|
          sponsoring_org = sponsor.organization? ? sponsor : nil
          sponsors_listing.async_sponsorable.then do |sponsorable|
            # Billing Managers are not members of an Organization. If the Org requires SAML, we need to allow for
            # Business level Auth, to allow Billing Managers to perform the action.
            business_promise = sponsoring_org&.async_business || Promise.resolve(nil)
            business_promise.then do |business|
              saml_scope_enabled = business&.feature_enabled?(:saml_scope_private_resources_to_org) || GitHub.flipper[:saml_scope_private_resources_to_org].enabled?
              resource = saml_scope_enabled ? Platform::InternalResource.new(resource: sponsorable) : sponsorable
              permission.access_allowed?(:read_sponsors_listing,
                resource: resource,
                sponsors_listing: sponsors_listing,
                current_org: sponsoring_org,
                current_repo: nil,
                allow_integrations: false,
                allow_user_via_granular_actor: false,
              )
            end
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      sig do
        params(
          permission: Authorization::Permission,
          sponsorship: ::Sponsorship
        ).returns(T.any(Promise[T::Boolean], T::Boolean))
      end
      def self.async_viewer_can_see?(permission, sponsorship)
        # Anyone can see the sponsorship, provided it isn't from or to a spammer, it's just
        # the sponsor part that gets restricted based on privacy and viewer
        sponsorship.async_hide_from_user?(permission.viewer).then do |hide_from_user|
          !hide_from_user
        end
      end

      minimum_accepted_scopes ["read:user"]

      implements_node templates: [
        [:us, :user_id, :sponsorship_id],
        [:os, :organization_id, :sponsorship_id]
      ], as: "S", ready_date: "2021-06-02" do |sponsorship|
        sponsorship.async_sponsorable.then do |sponsorable|
          if sponsorable.organization?
            {
              prefix: :os,
              organization_id: sponsorable.id,
              sponsorship_id: sponsorship.id
            }
          else
            {
              prefix: :us,
              user_id: sponsorable.id,
              sponsorship_id: sponsorship.id
            }
          end
        end
      end

      created_at_field

      field :tier_selected_at, Platform::Scalars::DateTime, null: true,
        description: "Identifies the date and time when the current tier was " \
          "chosen for this sponsorship.", method: :subscribable_selected_at

      field :is_sponsor_opted_into_email, Boolean, visibility: {
        internal: { environments: [:enterprise] },
        public: { environments: [:dotcom] },
      }, description: "Whether the sponsor has chosen to receive sponsorship update emails sent from the " \
        "sponsorable. Only returns a non-null value when the viewer has permission to know this.", null: true

      sig { returns(Promise[T::Boolean]) }
      def is_sponsor_opted_into_email
        object.async_is_sponsor_opted_into_email_for(context[:viewer])
      end

      field :privacy_level, Enums::SponsorshipPrivacy, description: "The privacy level for this sponsorship.",
        null: false

      field :is_active, Boolean, description: "Whether the sponsorship is active. False implies the sponsor is a " \
        "past sponsor of the maintainer, while true implies they are a current sponsor.", method: :active?,
        null: false

      field :maintainer, Objects::User, "The entity that is being sponsored", null: false do
        deprecated(
          start_date: Date.new(2019, 12, 17),
          reason: "`Sponsorship.maintainer` will be removed.",
          superseded_by: "Use `Sponsorship.sponsorable` instead.",
          owner: "antn",
        )
      end

      sig { returns(Promise[GitHubSponsors::Types::Sponsorable]) }
      def maintainer
        if Rails.env.development?
          raise Platform::Errors::Unprocessable, "Sponsorship.maintainer is deprecated, please use Sponsorship.sponsorable"
        end

        object.async_sponsorable
      end

      field :sponsorable, Interfaces::Sponsorable, "The entity that is being sponsored", null: false, method: :async_sponsorable
      field :sponsor, Objects::User, "The user that is sponsoring. Returns null if the sponsorship is private or if sponsor is not a user.", null: true do
        deprecated(
          start_date: Date.new(2020, 04, 27),
          reason: "`Sponsorship.sponsor` will be removed.",
          superseded_by: "Use `Sponsorship.sponsorEntity` instead.",
          owner: "nholden",
        )
      end

      sig { returns(Promise[GitHubSponsors::Types::Sponsor]) }
      def sponsor
        sponsor_entity.then do |entity|
          # We only want the `sponsor` field to return `User` sponsors. We must
          # inspect `entity.class` here because `entity.is_a?(::User)` will
          # return `true` for subclasses of `User`, including `Organization`.
          entity if entity.class == ::User
        end
      end

      field :sponsor_entity, Unions::Sponsor,
        "The user or organization that is sponsoring, if you have permission to view them.", null: true

      sig { returns(Promise[GitHubSponsors::Types::Sponsor]) }
      def sponsor_entity
        object.async_sponsor_entity(viewer: context[:viewer])
      end

      field :payment_source, Enums::SponsorshipPaymentSource,
        description: "The platform that was most recently used to pay for the sponsorship.", null: true

      sig { returns(Promise[T.nilable(Enums::SponsorshipPaymentSource)]) }
      def payment_source
        object.async_amount_readable_by?(context[:viewer]).then do |viewer_can_read_amount|
          next object.payment_source if viewer_can_read_amount
        end
      end

      field :tier, Objects::SponsorsTier, description: "The associated sponsorship tier", null: true

      sig { returns(Promise[T.nilable(SponsorsTier)]) }
      def tier
        object.async_subscription_item.then do |subscription_item|
          if subscription_item
            subscription_item.async_viewable_by?(context[:viewer]).then do |viewable_by|
              subscription_item.async_subscribable if viewable_by
            end
          else
            # there is no subscription item for invoiced sponsorship
            object.async_invoiced_sponsorship_transfer.then do |transfer|
              if transfer
                object.async_tier.then do |tier|
                  tier.async_readable_by?(context[:viewer]).then do |is_tier_readable|
                    tier if is_tier_readable
                  end
                end
              end
            end
          end
        end
      end

      field :is_one_time_payment, Boolean,
        "Whether this sponsorship represents a one-time payment versus a recurring sponsorship.",
        method: :async_one_time_payment?, null: false
    end
  end
end
