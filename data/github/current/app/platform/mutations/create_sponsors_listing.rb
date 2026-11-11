# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateSponsorsListing < Platform::Mutations::Base
      description "Create a GitHub Sponsors profile to allow others to sponsor you or your organization."

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

      argument :sponsorable_login, String, "The username of the organization to create a GitHub Sponsors " \
        "profile for, if desired. Defaults to creating a GitHub Sponsors profile for the authenticated user " \
        "if omitted.", required: false
      argument :fiscal_host_login, String, "The username of the supported fiscal host's GitHub organization, if " \
        "you want to receive sponsorship payouts through a fiscal host rather than directly to a bank account. For " \
        "example, 'Open-Source-Collective' for Open Source Collective or 'numfocus' for numFOCUS. Case " \
        "insensitive. See https://docs.github.com/sponsors/receiving-sponsorships-through-github-sponsors/" \
        "using-a-fiscal-host-to-receive-github-sponsors-payouts for more information.", required: false
      argument :fiscally_hosted_project_profile_url, String, "The URL for your profile page on the fiscal host's " \
        "website, e.g., https://opencollective.com/babel or https://numfocus.org/project/bokeh. Required if " \
        "fiscalHostLogin is specified.", required: false
      argument :billing_country_or_region_code, Enums::SponsorsCountryOrRegionCode,
        "The country or region where the sponsorable's bank account is located. Required if fiscalHostLogin is " \
        "not specified, ignored when fiscalHostLogin is specified.", required: false
      argument :residence_country_or_region_code, Enums::SponsorsCountryOrRegionCode,
        "The country or region where the sponsorable resides. This is for tax purposes. Required if the " \
        "sponsorable is yourself, ignored when sponsorableLogin specifies an organization.", required: false
      argument :contact_email, String, "The email address we should use to contact you about the GitHub Sponsors " \
        "profile being created. This will not be shared publicly. Must be a verified email address already on " \
        "your GitHub account. Only relevant when the sponsorable is yourself. Defaults to your primary " \
        "email address on file if omitted.", required: false
      argument :full_description, String, "Provide an introduction to serve as the main focus that appears on your " \
        "GitHub Sponsors profile. It's a great opportunity to help potential sponsors learn more about you, your " \
        "work, and why their sponsorship is important to you. GitHub-flavored Markdown is supported.", required: false

      field :sponsors_listing, Objects::SponsorsListing, "The new GitHub Sponsors profile.", null: true

      def resolve(sponsorable_login: nil, fiscal_host_login: nil, fiscally_hosted_project_profile_url: nil, billing_country_or_region_code: nil, residence_country_or_region_code: nil, contact_email: nil, full_description: nil)
        raise Errors::Unprocessable.new("GitHub Sponsors is not available") unless GitHub.sponsors_enabled?

        viewer = context[:viewer]
        sponsorable_promise = if sponsorable_login.present?
          Loaders::ActiveRecord.load(::User, sponsorable_login, column: :login)
        else
          Promise.resolve(viewer)
        end
        parent_listing_id_promise = if fiscal_host_login.present?
          Loaders::ActiveRecord.load(::User, fiscal_host_login, column: :login).then do |fiscal_host|
            T.must(fiscal_host).async_sponsors_listing.then do |sponsors_listing|
              sponsors_listing.id if sponsors_listing&.fiscal_host?
            end
          end
        else
          Promise.resolve(nil)
        end

        sponsorable_promise.then do |sponsorable|
          raise Errors::Forbidden.new("Invalid sponsorable") unless sponsorable

          user_email = if sponsorable.user?
            if contact_email.present?
              sponsorable.possible_sponsors_emails.where(email: contact_email).first
            else
              sponsorable.primary_user_email
            end
          end

          parent_listing_id_promise.then do |parent_listing_id|
            if fiscal_host_login.present? && parent_listing_id.nil?
              valid_fiscal_hosts = SponsorsListing.fiscal_hosts_visible_for_signup.order(:slug)
                .map(&:sponsorable_login).to_sentence
              error_message = "The specified fiscal host, #{fiscal_host_login}, is not supported."
              error_message += " Valid options: #{valid_fiscal_hosts}" if valid_fiscal_hosts.present?
              raise Errors::Unprocessable.new(error_message)
            end

            survey = (
              sponsorable.organization? ? ::Sponsors::OrganizationWaitlistSurvey : ::Sponsors::UserWaitlistSurvey
            ).find_or_create_survey
            sponsors_listing = nil
            create_attrs = {
              sponsorable: sponsorable,
              country_of_residence: residence_country_or_region_code,
              contact_email_id: user_email&.id,
              actor: viewer,
              survey: survey,
              full_description: full_description,
            }

            begin
              sponsors_listing = if parent_listing_id
                Sponsors::CreateSponsorsListing.with_fiscal_host(create_attrs.merge(
                  parent_listing_id: parent_listing_id,
                  fiscally_hosted_project_profile_url: fiscally_hosted_project_profile_url,
                ))
              else
                Sponsors::CreateSponsorsListing.with_bank(create_attrs.merge(
                  billing_country: billing_country_or_region_code,
                ))
              end
            rescue ::Sponsors::CreateSponsorsListing::UnprocessableError => err
              raise Errors::Unprocessable.new(err.message)
            rescue ::Sponsors::CreateSponsorsListing::ForbiddenError => err
              raise Errors::Forbidden.new(err.message)
            end

            { sponsors_listing: sponsors_listing }
          end
        end
      end
    end
  end
end
