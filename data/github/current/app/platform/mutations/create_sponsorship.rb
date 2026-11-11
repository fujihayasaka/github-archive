# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateSponsorship < Platform::Mutations::Base
      description "Start a new sponsorship of a maintainer in GitHub Sponsors, or reactivate a past sponsorship."

      sig do
        params(
          user_or_org_or_login: T.nilable(T.any(User, Organization, String))
        ).returns(Promise[T.nilable(User)])
      end
      def self.async_user_or_org(user_or_org_or_login)
        if user_or_org_or_login.is_a?(String)
          Loaders::ActiveRecord.load(::User, user_or_org_or_login, column: :login)
        else
          Promise.resolve(user_or_org_or_login)
        end
      end

      sig do
        params(
          permission: Platform::Authorization::Permission,
          inputs: T.untyped
        ).returns(Promise[T::Boolean])
      end
      def self.async_api_can_modify?(permission, **inputs)
        sponsorable_promise = async_user_or_org(inputs[:sponsorable] || inputs[:sponsorable_login])

        sponsorable_promise.then do |sponsorable|
          unless sponsorable
            raise Platform::Errors::Execution.new("`sponsorableId` or `sponsorableLogin` is required")
          end

          async_user_or_org(inputs[:sponsor] || inputs[:sponsor_login]).then do |sponsor|
            raise Platform::Errors::Execution.new("`sponsorId` or `sponsorLogin` is required") unless sponsor

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
      argument :tier_id, ID, "The ID of one of sponsorable's existing tiers to sponsor at. Required if amount " \
        "is not specified.", required: false, loads: Objects::SponsorsTier
      argument :amount, Integer, "The amount to pay to the sponsorable in US dollars. " \
        "Required if a tierId is not specified. Valid values: " \
        "1-#{::SponsorsTier::MAX_SPONSORSHIP_AMOUNT_IN_DOLLARS}.",
        required: false
      argument :is_recurring, Boolean, "Whether the sponsorship should happen monthly/yearly or " \
        "just this one time. Required if a tierId is not specified.", required: false
      argument :receive_emails, Boolean, "Whether the sponsor should receive email updates from the sponsorable.",
        required: false, default_value: true
      argument :privacy_level, Enums::SponsorshipPrivacy, "Specify whether others should be able to see that the " \
        "sponsor is sponsoring the sponsorable. Public visibility still does not reveal which tier is used.",
        required: false, default_value: "public"

      field :sponsorship, Objects::Sponsorship, "The sponsorship that was started.", null: true

      sig do
        params(
          receive_emails: T::Boolean,
          privacy_level: String,
          tier: T.nilable(SponsorsTier),
          amount: T.nilable(Integer),
          is_recurring: T.nilable(T::Boolean),
          sponsor: T.nilable(GitHubSponsors::Types::Sponsor),
          sponsorable: T.nilable(GitHubSponsors::Types::Sponsorable),
          sponsor_login: T.nilable(String),
          sponsorable_login: T.nilable(String),
        ).returns(Promise[T::Hash[Symbol, T.nilable(Sponsorship)]])
      end
      def resolve(receive_emails:, privacy_level:, tier: nil, amount: nil, is_recurring: nil, sponsor: nil, sponsorable: nil, sponsor_login: nil, sponsorable_login: nil)
        raise Errors::Unprocessable.new("GitHub Sponsors is not available") unless GitHub.sponsors_enabled?

        sponsor_promise = self.class.async_user_or_org(sponsor || sponsor_login)

        if tier.nil? && (amount.nil? || is_recurring.nil?)
          raise Errors::Unprocessable.new("Must specify either tierId or both amount and isRecurring.")
        elsif tier && (!amount.nil? || !is_recurring.nil?)
          raise Errors::Unprocessable.new("Please specify only 1) a tierId or 2) amount and isRecurring.")
        end

        if amount && amount <= 0
          raise Errors::Unprocessable.new("Please specify an amount between $1 and " \
            "#{::SponsorsTier::MAX_SPONSORSHIP_AMOUNT_HUMAN} USD")
        end

        sponsor_promise.then do |sponsor|
          viewer = context[:viewer]
          sponsor_id = sponsor&.id
          unless sponsor_id && viewer.potential_sponsor_ids.include?(sponsor_id)
            raise Errors::Forbidden.new("#{viewer.display_login} cannot create a sponsorship from #{sponsor}")
          end

          sponsorable_promise = self.class.async_user_or_org(sponsorable || sponsorable_login)
          sponsorable_promise.then do |sponsorable|
            sponsors_listing = sponsorable&.sponsors_listing

            raise Errors::Unprocessable.new("Must specify a sponsorable maintainer.") unless sponsors_listing

            tier_amount = amount || T.must(tier).monthly_price_in_dollars.to_i

            tier_is_recurring = is_recurring || T.must(tier).recurring?

            sponsorship_tier = if tier
              tier
            else
              parent_tier = ::SponsorsTier.closest_lesser_value_tier_for(sponsors_listing.id, amount: amount,
                is_recurring: is_recurring)
              begin
                ::Sponsors::CreateSponsorsTier.find_published_or_create_custom_tier(
                  sponsors_listing: sponsors_listing,
                  amount: tier_amount,
                  viewer: viewer,
                  sponsor: sponsor,
                  is_recurring: tier_is_recurring,
                  parent_tier_id: parent_tier&.id,
                )
              rescue ::Sponsors::CreateSponsorsTier::ForbiddenError => err
                raise Errors::Forbidden.new(err.message)
              rescue ::Sponsors::CreateSponsorsTier::UnprocessableError => err
                raise Errors::Unprocessable.new(err.message)
              end
            end

            is_public = privacy_level == "public"

            sponsorship = begin
              if sponsorship_tier.one_time?
                ::Sponsors::AddOneTimePayment.call(tier: sponsorship_tier, sponsor: sponsor, sponsorable: sponsorable,
                  viewer: viewer, is_public: is_public, email_opt_in: receive_emails)
              else
                skip_proration = sponsor.can_skip_sponsorship_proration?
                ::Sponsors::CreateRecurringSponsorship.call(tier: sponsorship_tier, sponsor: sponsor, sponsorable: sponsorable,
                  viewer: viewer, is_public: is_public, email_opt_in: receive_emails, pay_prorated: !skip_proration)
              end
            rescue ::Sponsors::CreateSponsorship::ForbiddenError => err
              raise Errors::Forbidden.new("Could not sponsor #{sponsorable} as #{sponsor}: #{err.message}")
            rescue ::Sponsors::CreateSponsorship::UnprocessableError,
                   ::Billing::CreateSubscriptionItem::UnprocessableError => err
              raise Errors::Unprocessable.new("Could not sponsor #{sponsorable} as #{sponsor}: #{err.message}")
            end

            { sponsorship: sponsorship }
          end
        end
      end
    end
  end
end
