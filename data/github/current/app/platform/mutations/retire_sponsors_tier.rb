# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RetireSponsorsTier < Platform::Mutations::Base
      description "Retire a published payment tier from your GitHub Sponsors profile so it cannot be used to start " \
        "new sponsorships."

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

      argument :tier_id, ID, "The ID of the published tier to retire.", required: true, loads: Objects::SponsorsTier

      field :sponsors_tier, Objects::SponsorsTier, "The tier that was retired.", null: true

      def resolve(tier:)
        unless tier.retired?
          Sponsors::RetireSponsorsTier.call(tier: tier, viewer: context[:viewer])
        end
        { sponsors_tier: tier }
      rescue ::Sponsors::RetireSponsorsTier::ForbiddenError => err
        raise Errors::Forbidden.new(err.message)
      rescue ::Sponsors::RetireSponsorsTier::UnprocessableError => err
        raise Errors::Unprocessable.new(err.message)
      end
    end
  end
end
