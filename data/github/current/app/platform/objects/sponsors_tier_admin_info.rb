# typed: strict
# frozen_string_literal: true

module Platform
  module Objects
    class SponsorsTierAdminInfo < Platform::Objects::Base
      extend T::Sig

      description "SponsorsTier information only visible to users that can administer the " \
        "associated Sponsors listing."
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      sig do
        params(
          permission: Authorization::Permission,
          tier_admin_info: Models::SponsorsTierAdminInfo
        ).returns(T.any(Promise[T::Boolean], T::Boolean))
      end
      def self.async_api_can_access?(permission, tier_admin_info)
        sponsors_tier = tier_admin_info.tier
        sponsors_tier.async_sponsorable.then do |sponsorable|
          org = sponsorable.organization? ? sponsorable : nil
          permission.access_allowed?(:read_sponsors_tier_admin_info,
            resource: sponsorable,
            sponsors_tier: sponsors_tier,
            current_org: org,
            current_repo: nil,
            allow_integrations: false,
            allow_user_via_granular_actor: false,
          )
        end
      end

      sig do
        params(
          permission: Authorization::Permission,
          tier_admin_info: Models::SponsorsTierAdminInfo
        ).returns(T.any(Promise[T::Boolean], Promise[FalseClass], Promise[TrueClass], T::Boolean))
      end
      def self.async_viewer_can_see?(permission, tier_admin_info)
        viewer = permission.viewer
        return Promise.resolve(false) unless viewer.present?
        return Promise.resolve(true) if viewer.can_admin_sponsors_listings?

        tier_admin_info.tier.async_adminable_by?(viewer)
      end

      minimum_accepted_scopes ["read:user", "read:org"]

      field :is_published, Boolean, null: false, description: "Indicates whether this tier is published to the " \
        "associated GitHub Sponsors profile. Published tiers are visible to anyone who can see the GitHub Sponsors " \
        "profile, and are available for use in sponsorships if the GitHub Sponsors profile is publicly visible.",
        method: :published?

      field :is_retired, Boolean, null: false, description: "Indicates whether this tier has been retired from the " \
        "associated GitHub Sponsors profile. Retired tiers are no longer shown on the GitHub Sponsors profile and " \
        "cannot be chosen for new sponsorships. Existing sponsorships may still use retired tiers if the sponsor " \
        "selected the tier before it was retired.", method: :retired?

      field :is_draft, Boolean, null: false, description: "Indicates whether this tier is still a work in progress " \
        "by the sponsorable and not yet published to the associated GitHub Sponsors profile. Draft tiers cannot be " \
        "used for new sponsorships and will not be in use on existing sponsorships. Draft tiers cannot be seen by " \
        "anyone but the admins of the GitHub Sponsors profile.", method: :draft?

      field :sponsorships, Connections.define(Objects::Sponsorship), connection: true,
        description: "The sponsorships using this tier.", null: false do
        argument :include_private, Boolean, "Whether or not to return private sponsorships using this tier. " \
          "Defaults to only returning public sponsorships on this tier.", required: false, default_value: false
        argument :order_by, Inputs::SponsorshipOrder,
          "Ordering options for sponsorships returned from this connection. If left blank, the " \
          "sponsorships will be ordered based on relevancy to the viewer.", required: false
      end

      sig do
        params(
          include_private: T::Boolean,
          order_by: T.nilable(Inputs::SponsorshipOrder)
        ).returns(Promise[T::Array[::Sponsorship]])
      end
      def sponsorships(include_private:, order_by: nil)
        object.tier.async_sponsors_listing.then do |sponsors_listing|
          Loaders::SponsorshipsAsSponsorable.load(
            sponsors_listing.sponsorable_id,
            viewer: context[:viewer],
            include_private: include_private,
            order_by: order_by,
            tier: object.tier
          ).then do |sponsorships|
            sponsorships ||= []
            ArrayWrapper.new(sponsorships)
          end
        end
      end
    end
  end
end
