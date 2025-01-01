# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CancelSponsorship < Platform::Mutations::Base
      description "Cancel an active sponsorship."

      def self.async_user_or_org(user_or_org_or_login)
        if user_or_org_or_login.is_a?(String)
          Loaders::ActiveRecord.load(::User, user_or_org_or_login, column: :login)
        else
          Promise.resolve(user_or_org_or_login)
        end
      end

      def self.async_api_can_modify?(permission, **inputs)
        sponsorable_promise = async_user_or_org(inputs[:sponsorable] || inputs[:sponsorable_login])

        sponsorable_promise.then do |sponsorable|
          unless sponsorable
            raise Platform::Errors::Execution.new("`sponsorableId` or `sponsorableLogin` is required")
          end

          async_user_or_org(inputs[:sponsor] || inputs[:sponsor_login]).then do |sponsor|
            raise Platform::Errors::Execution.new("`sponsorId` or `sponsorLogin` is required") unless sponsor

            sponsorship = sponsor.sponsorship_as_sponsor_for(sponsorable)
            sponsoring_org = sponsor.organization? ? sponsor : nil

            permission.access_allowed?(:admin_sponsorship,
              resource: sponsor,
              sponsorship: sponsorship,
              current_org: sponsoring_org,
              current_repo: nil,
              allow_integrations: false,
              allow_user_via_granular_actor: false,
            )
          end
        end
      end

      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      minimum_accepted_scopes ["user", "admin:org"]

      argument :sponsor_id, ID, "The ID of the user or organization who is acting as the sponsor, " \
        "paying for the sponsorship. Required if sponsorLogin is not given.", required: false, loads: Unions::Sponsor
      argument :sponsor_login, String, "The username of the user or organization who is acting as the sponsor, " \
        "paying for the sponsorship. Required if sponsorId is not given.", required: false
      argument :sponsorable_id, ID, "The ID of the user or organization who is receiving the sponsorship. Required " \
        "if sponsorableLogin is not given.", required: false, loads: Interfaces::Sponsorable
      argument :sponsorable_login, String, "The username of the user or organization who is receiving the " \
        "sponsorship. Required if sponsorableId is not given.", required: false

      field :sponsors_tier, Objects::SponsorsTier, "The tier that was being used at the time of cancellation.",
        null: true

      def resolve(sponsor: nil, sponsorable: nil, sponsor_login: nil, sponsorable_login: nil)
        raise Errors::Unprocessable.new("GitHub Sponsors is not available") unless GitHub.sponsors_enabled?

        sponsor_promise = self.class.async_user_or_org(sponsor || sponsor_login)

        sponsor_promise.then do |sponsor|
          viewer = context[:viewer]

          sponsorable_promise = self.class.async_user_or_org(sponsorable || sponsorable_login)
          sponsorable_promise.then do |sponsorable|
            sponsorship = sponsor.sponsorship_as_sponsor_for(sponsorable)

            sponsorship_readability_promise = if sponsorship.nil?
              Promise.resolve(false)
            else
              sponsorship.async_sponsor_readable_by?(viewer)
            end

            sponsorship_readability_promise.then do |is_sponsorship_visible|
              raise Errors::NotFound.new("No such sponsorship exists") unless is_sponsorship_visible

              unless sponsorship.active?
                raise Errors::Unprocessable.new("@#{sponsor}'s sponsorship of @#{sponsorable} is not active")
              end

              unless sponsorship.adminable_by?(viewer)
                raise Errors::Forbidden.new("@#{viewer.display_login} cannot cancel @#{sponsor}'s sponsorship of @#{sponsorable}")
              end

              sponsors_tier = sponsorship.tier
              result = sponsorship.cancel(actor: viewer, reason: :SPONSOR_INITIATED)

              if !result.success
                error_message = result.errors.join(", ")
                raise Errors::Unprocessable.new("Could not cancel sponsorship: #{error_message}")
              end

              { sponsors_tier: sponsors_tier }
            end
          end
        end
      end
    end
  end
end
