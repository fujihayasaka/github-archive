# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class PublishSponsorsTier < Platform::Mutations::Base
      description "Publish an existing sponsorship tier that is currently still a draft to a GitHub Sponsors profile."

      def self.async_api_can_modify?(permission, **inputs)
        inputs[:tier].async_sponsorable.then do |sponsorable|
          next false unless sponsorable

          permission.access_allowed?(:admin_sponsors_listing,
            resource: sponsorable,
            current_org: sponsorable.organization? ? sponsorable : nil,
            current_repo: nil,
            allow_integrations: false,
            allow_user_via_granular_actor: false,
          )
        end
      end

      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      minimum_accepted_scopes ["user", "admin:org"]

      argument :tier_id, ID, "The ID of the draft tier to publish.", required: true, loads: Objects::SponsorsTier

      field :sponsors_tier, Objects::SponsorsTier, "The tier that was published.", null: true

      def resolve(tier:)
        unless tier.published?
          Sponsors::PublishSponsorsTier.call(tier: tier, viewer: context[:viewer])
        end
        { sponsors_tier: tier }
      rescue ::Sponsors::PublishSponsorsTier::ForbiddenError => err
        raise Errors::Forbidden.new(err.message)
      rescue ::Sponsors::PublishSponsorsTier::UnprocessableError => err
        raise Errors::Unprocessable.new(err.message)
      end
    end
  end
end
