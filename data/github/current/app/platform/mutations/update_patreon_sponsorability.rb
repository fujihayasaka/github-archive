# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdatePatreonSponsorability < Platform::Mutations::Base
      description "Toggle the setting for your GitHub Sponsors profile that allows other GitHub accounts to " \
        "sponsor you on GitHub while paying for the sponsorship on Patreon. Only applicable when you have a " \
        "GitHub Sponsors profile and have connected your GitHub account with Patreon."

      def self.async_api_can_modify?(permission, **inputs)
        sponsorable_promise = if inputs[:sponsorable_login].present?
          Loaders::ActiveRecord.load(::User, inputs[:sponsorable_login], column: :login)
        else
          Promise.resolve(permission.viewer)
        end

        sponsorable_promise.then do |sponsorable|
          permission.access_allowed?(:admin_sponsors_listing,
            resource: sponsorable,
            current_org: sponsorable&.organization? ? sponsorable : nil,
            current_repo: nil,
            allow_integrations: false,
            allow_user_via_granular_actor: false,
          )
        end
      end

      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      minimum_accepted_scopes ["user", "admin:org"]

      argument :sponsorable_login, String, "The username of the organization with the GitHub Sponsors " \
        "profile, if any. Defaults to the GitHub Sponsors profile for the authenticated user " \
        "if omitted.", required: false
      argument :enable_patreon_sponsorships, Boolean, "Whether Patreon tiers should be shown on the GitHub " \
        "Sponsors profile page, allowing potential sponsors to make their payment through Patreon instead of GitHub.",
        required: true

      field :sponsors_listing, Objects::SponsorsListing, "The GitHub Sponsors profile.", null: true

      def resolve(enable_patreon_sponsorships:, sponsorable_login: nil)
        raise Errors::Unprocessable.new("GitHub Sponsors is not available") unless GitHub.sponsors_enabled?

        viewer = context[:viewer]
        sponsorable_promise = if sponsorable_login.present?
          Loaders::ActiveRecord.load(::User, sponsorable_login, column: :login)
        else
          Promise.resolve(viewer)
        end

        sponsorable_promise.then do |sponsorable|
          raise Errors::Forbidden.new("Invalid sponsorable") unless sponsorable

          sponsorable.async_sponsors_listing.then do |sponsors_listing|
            listing_permission_promise = (sponsors_listing || sponsorable).async_adminable_by?(viewer)
            listing_permission_promise.then do |viewer_has_admin_access|
              unless viewer_has_admin_access
                raise Errors::Forbidden.new("Authenticated viewer does not have permission to modify setting " \
                  "for @#{sponsorable}")
              end

              unless sponsors_listing
                raise Errors::Unprocessable.new("@#{sponsorable} does not have a GitHub Sponsors profile")
              end

              sponsorable.async_sponsors_patreon_user.then do |sponsors_patreon_user|
                unless sponsors_patreon_user
                  raise Errors::Unprocessable.new("@#{sponsorable} has not connected with Patreon")
                end

                unless sponsors_patreon_user.update(enabled_as_sponsorable: enable_patreon_sponsorships)
                  error = sponsors_patreon_user.errors.full_messages.to_sentence
                  raise Errors::Unprocessable.new("Could not update Patreon sponsorability setting: #{error}")
                end

                { sponsors_listing: sponsors_listing }
              end
            end
          end
        end
      end
    end
  end
end
