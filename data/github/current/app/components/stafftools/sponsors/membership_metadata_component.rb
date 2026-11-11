# typed: true
# frozen_string_literal: true

module Stafftools
  module Sponsors
    class MembershipMetadataComponent < ApplicationComponent
      include SvgHelper

      DATE_FORMAT = "%b %-d, %Y"
      MATCH_ICON_CLASS = "color-fg-success"

      def initialize(sponsors_listing:)
        @listing = sponsors_listing
      end

      private

      attr_reader :listing

      delegate :stripe_transfers_enabled?, :banned?, :ignored?, :reviewed?, :sponsorable, :stafftools_metadata,
        to: :listing

      def render?
        listing.present?
      end

      memoize def sponsorable_profile
        sponsorable.profile
      end

      def join_date
        sponsorable.created_at.strftime(DATE_FORMAT)
      end

      def membership_accepted_date
        listing.accepted_at&.strftime(DATE_FORMAT)
      end

      memoize def sponsoring_others_component
        Stafftools::Sponsors::Members::SponsoringOthersComponent.new(
          sponsorable: sponsorable,
        )
      end

      def match_deadline_eligible?
        listing.joined_waitlist_before_match_deadline?
      end

      def has_stripe_account?
        stripe_connect_account.present?
      end

      def format_date(datetime)
        datetime.strftime(DATE_FORMAT)
      end

      def match_icon_class
        match_deadline_eligible? ? MATCH_ICON_CLASS : ""
      end

      def twitter_username
        "@#{sponsorable_profile.twitter_username}"
      end

      def twitter_url
        sponsorable_profile&.twitter_url
      end

      def sponsors_emails_options
        sponsorable.possible_sponsors_emails.pluck(:email, :id)
      end

      def billing_country_options
        Braintree::Address::CountryNames.map do |country_name, alpha2, _, _|
          [country_name, alpha2]
        end
      end

      def stripe_connect_account
        listing.active_stripe_connect_account
      end

      def parent_string_connect_account
        listing.active_parent_stripe_connect_account
      end

      def sponsors_count
        sponsorable.sponsorships_as_sponsorable.count
      end

      def stripe_balance_path
        stafftools_sponsors_member_stripe_connect_account_balance_partial_path(
          sponsorable,
          stripe_connect_account,
        )
      end

      def stripe_transfers_path
        login  = has_stripe_account? ? listing.sponsorable_login : listing.parent_sponsorable_login
        stripe = has_stripe_account? ? stripe_connect_account : parent_string_connect_account

        stafftools_sponsors_member_stripe_connect_account_transfers_path(login, stripe)
      end

      def audit_log_query
        if GitHub.driftwood_ade_queries_enabled?
          <<~KQL
            #{listing_kql_query}
            | where action startswith 'sponsors'
          KQL
        else
          "#{listing_log_query} action:sponsors*"
        end
      end

      def listing_log_query
        "(#{sponsorable.audit_log_query} OR data.sponsors_listing_id:#{listing.id})"
      end

      def listing_kql_query
        "#{sponsorable.audit_log_kql_query} or data.sponsors_listing_id == #{listing.id}"
      end
    end
  end
end
