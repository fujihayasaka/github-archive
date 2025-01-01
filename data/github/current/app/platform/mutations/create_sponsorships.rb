# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateSponsorships < Platform::Mutations::Base
      description "Make many sponsorships for different sponsorable users or organizations at once. " \
        "Can only sponsor those who have a public GitHub Sponsors profile."

      def self.async_user_or_org(user_or_org_or_login)
        if user_or_org_or_login.is_a?(String)
          Loaders::ActiveRecord.load(::User, user_or_org_or_login, column: :login)
        else
          Promise.resolve(user_or_org_or_login)
        end
      end

      def self.async_api_can_modify?(permission, **inputs)
        Loaders::ActiveRecord.load(::User, inputs[:sponsor_login], column: :login).then do |sponsor|
          # Return a NotFound error for API requests, instead of a generic permission error message, so it
          # is more clear to the user that the sponsor login is incorrect
          raise Errors::NotFound.new("Could not find sponsor with login: #{inputs[:sponsor_login]}") unless sponsor

          sponsoring_org = sponsor.organization? ? sponsor : nil

          permission.access_allowed?(:admin_sponsorship,
            resource: sponsor,
            sponsorship: nil,
            current_org: sponsoring_org,
            current_repo: nil,
            allow_integrations: false,
            allow_user_via_granular_actor: false,
          )
        end
      end

      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      minimum_accepted_scopes ["user", "admin:org"]

      argument :sponsor_login, String, "The username of the user or organization who is acting as the sponsor, " \
        "paying for the sponsorships.", required: true
      argument :sponsorships, [Inputs::BulkSponsorship], "The list of maintainers to sponsor and " \
        "for how much apiece.", required: true
      argument :receive_emails, Boolean, "Whether the sponsor should receive email updates from the sponsorables.",
        required: false, default_value: false
      argument :privacy_level, Enums::SponsorshipPrivacy, "Specify whether others should be able to see that the " \
        "sponsor is sponsoring the sponsorables. Public visibility still does not reveal the dollar value of the " \
        "sponsorship.", required: false, default_value: "public"
      argument :recurring, Boolean, "Whether the sponsorships created should continue each billing cycle for " \
        "the sponsor (monthly or annually), versus lasting only a single month. Defaults to one-time sponsorships.",
        required: false, default_value: false

      field :sponsorables, [Interfaces::Sponsorable], "The users and organizations who received a sponsorship.",
        null: true

      def resolve(sponsor_login:, sponsorships:, receive_emails: false, privacy_level: "public", recurring: false)
        raise Errors::Unprocessable.new("GitHub Sponsors is not available") unless GitHub.sponsors_enabled?

        amounts_by_sponsorable_login = {}

        sponsorships.each do |sponsorship_data|
          amount = sponsorship_data.amount
          sponsorable = sponsorship_data.sponsorable
          sponsorable_login = sponsorship_data.sponsorable_login.presence&.downcase

          if amount <= 0
            raise Errors::Unprocessable.new("Please specify an amount between $1 and " \
              "#{::SponsorsTier::MAX_SPONSORSHIP_AMOUNT_HUMAN} USD")
          end

          if sponsorable.nil? && sponsorable_login.blank?
            raise Errors::Unprocessable.new("Must specify either sponsorableId or sponsorableLogin.")
          elsif sponsorable && sponsorable_login.present?
            raise Errors::Unprocessable.new("Please specify only sponsorableId or sponsorableLogin.")
          end

          if amounts_by_sponsorable_login.key?(sponsorable_login)
            raise Errors::Unprocessable.new("Please specify each maintainer only once.")
          end

          sponsorable_login ||= sponsorable.login.downcase
          amounts_by_sponsorable_login[sponsorable_login] = amount
        end

        Loaders::ActiveRecord.load(::User, sponsor_login, column: :login).then do |sponsor|
          raise Errors::NotFound.new("Could not find sponsor with login: #{sponsor_login}") unless sponsor

          viewer = context[:viewer]
          unless viewer.potential_sponsor_ids.include?(sponsor.id)
            raise Errors::Forbidden.new("#{viewer.display_login} cannot create a sponsorship from #{sponsor}")
          end

          result = if recurring
            ::Sponsors::CreateRecurringSponsorships.call(
              sponsor: sponsor,
              actor: viewer,
              amounts_by_sponsorable_login: amounts_by_sponsorable_login,
              receive_email: receive_emails,
              privacy_level: privacy_level,
            )
          else
            ::Sponsors::AddOneTimePayments.call(
              sponsor: sponsor,
              actor: viewer,
              amounts_by_sponsorable_login: amounts_by_sponsorable_login,
              receive_email: receive_emails,
              privacy_level: privacy_level,
            )
          end

          if result.success?
            { sponsorables: result.sponsorables }
          else
            raise Errors::Unprocessable.new(result.errors.join(", "))
          end
        end
      end
    end
  end
end
