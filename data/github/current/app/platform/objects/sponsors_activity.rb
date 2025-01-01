# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class SponsorsActivity < Platform::Objects::Base
      description "An event related to sponsorship activity."

      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, sponsors_activity)
        Promise.all([
          sponsors_activity.async_sponsorable,
          sponsors_activity.async_sponsor,
        ]).then do |sponsorable, sponsor|
          relevant_org = if sponsor&.organization?
            sponsor
          elsif sponsorable.organization?
            sponsorable
          end
          permission.access_allowed?(:read_sponsors_activity,
            resource: sponsor,
            sponsors_activity: sponsors_activity,
            current_org: relevant_org,
            current_repo: nil,
            allow_integrations: false,
            allow_user_via_granular_actor: false,
          )
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      # Ability check for a SponsorsActivity object
      #
      # Maintainers may see their own activity, and sponsors admins may
      # see all activity.
      def self.async_viewer_can_see?(permission, sponsors_activity)
        sponsors_activity.async_readable_by?(permission.viewer)
      end

      minimum_accepted_scopes ["read:user", "read:org"]

      implements_node templates: [
        [:usa, :user_id, :sponsors_activity_id],
        [:osa, :organization_id, :sponsors_activity_id]
      ], as: "SA", ready_date: "2021-06-01" do |sponsors_activity|
        sponsors_activity.async_sponsorable.then do |sponsorable|
          if sponsorable.organization?
            {
              prefix: :osa,
              organization_id: sponsorable.id,
              sponsors_activity_id: sponsors_activity.id
            }
          else
            {
              prefix: :usa,
              user_id: sponsorable.id,
              sponsors_activity_id: sponsors_activity.id
            }
          end
        end
      end

      field :action, Enums::SponsorsActivityAction,
        "What action this activity indicates took place.", null: false
      field :timestamp, Scalars::DateTime, description: "The timestamp of this event.", null: true
      field :sponsorable, Interfaces::Sponsorable,
        description: "The user or organization that is being sponsored, the maintainer.",
        null: false, method: :async_sponsorable

      field :via_bulk_sponsorship, Boolean, null: false, visibility: {
        public: { environments: [:dotcom] },
        internal: { environments: [:enterprise] },
      }, description: "Was this sponsorship made alongside other sponsorships at the same time from the same sponsor?"

      field :sponsor, Unions::Sponsor,
        description: "The user or organization who triggered this activity and was/is sponsoring the sponsorable.",
        null: true

      def sponsor
        @object.async_linked_or_direct_sponsor.then do |sponsor|
          if sponsor
            next sponsor unless sponsor.hide_from_user?(context[:viewer])
          end
        end
      end

      field :payment_source, Enums::SponsorshipPaymentSource,
        description: "The platform that was used to pay for the sponsorship.", null: true
      field :sponsors_tier, Objects::SponsorsTier, description: "The associated sponsorship tier.", null: true,
        method: :async_sponsors_tier
      field :previous_sponsors_tier, Objects::SponsorsTier, method: :async_old_sponsors_tier,
        description: "The tier that the sponsorship used to use, for tier change events.", null: true
      field :current_privacy_level, Enums::SponsorshipPrivacy, method: :async_current_privacy_level,
        description: "The sponsor's current privacy level.", null: true
    end
  end
end
