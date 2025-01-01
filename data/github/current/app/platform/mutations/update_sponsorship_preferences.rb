# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateSponsorshipPreferences < Platform::Mutations::Base
      description "Change visibility of your sponsorship and opt in or out of email updates from the maintainer."

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

            # Billing Managers are not members of an Organization. If the Org requires SAML, we need to allow for
            # Business level Auth, to allow Billing Managers to perform the action.
            business_promise = sponsoring_org&.async_business || Promise.resolve(nil)
            business_promise.then do |business|
              saml_scope_enabled = business&.feature_enabled?(:saml_scope_private_resources_to_org) || ::FeatureFlag.vexi.enabled?(:saml_scope_private_resources_to_org, default: false)
              resource = saml_scope_enabled ? Platform::InternalResource.new(resource: sponsor) : sponsor
              permission.access_allowed?(:admin_sponsorship,
                resource: resource,
                sponsorship: sponsorship,
                current_org: sponsoring_org,
                current_repo: nil,
                allow_integrations: false,
                allow_user_via_granular_actor: false,
              )
            end
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
      argument :receive_emails, Boolean, "Whether the sponsor should receive email updates from the sponsorable.",
        required: false, default_value: true
      argument :privacy_level, Enums::SponsorshipPrivacy, "Specify whether others should be able to see that the " \
        "sponsor is sponsoring the sponsorable. Public visibility still does not reveal which tier is used.",
        required: false, default_value: "public"

      field :sponsorship, Objects::Sponsorship, "The sponsorship that was updated.", null: true

      def resolve(receive_emails:, privacy_level:, sponsor: nil, sponsorable: nil, sponsor_login: nil, sponsorable_login: nil)
        raise Errors::Unprocessable.new("GitHub Sponsors is not available") unless GitHub.sponsors_enabled?

        viewer = context[:viewer]
        is_public = privacy_level == "public"

        self.class.async_user_or_org(sponsor || sponsor_login).then do |sponsor|
          self.class.async_user_or_org(sponsorable || sponsorable_login).then do |sponsorable|
            sponsorship = sponsor.sponsorship_as_sponsor_for(sponsorable)

            begin
              ::Sponsors::UpdateSponsorshipPreferences.call(
                sponsorship,
                viewer: viewer,
                is_public: is_public,
                email_opt_in: receive_emails
              )
            rescue ::Sponsors::UpdateSponsorship::UnprocessableError => error
              raise Errors::Unprocessable.new(error.message)
            rescue ::Sponsors::UpdateSponsorship::ForbiddenError => error
              raise Errors::Forbidden.new(error.message)
            end

            { sponsorship: sponsorship }
          end
        end
      end
    end
  end
end
