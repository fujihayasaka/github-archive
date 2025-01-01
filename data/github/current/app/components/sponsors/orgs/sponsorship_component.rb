# typed: strict
# frozen_string_literal: true

module Sponsors
  module Orgs
    class SponsorshipComponent < ApplicationComponent
      extend T::Sig
      include SponsorsButtonsHelper

      # sponsorship - a Sponsorship record where the sponsor is an organization
      # viewer_can_manage_sponsorships - Boolean indicating if the current user can create and manage sponsorships for this organization
      # viewer_is_sponsoring - Boolean indicating if the current user is sponsoring the sponsorship's sponsorable;
      #                        only matters when viewer_is_sponsor_admin=false
      # is_sponsorable_for_viewer - Boolean indicating if the sponsorship's sponsorable is someone who the viewer
      #                             can start sponsoring; only matters when viewer_is_sponsor_admin=false
      sig do
        params(
          sponsorship: Sponsorship,
          viewer_can_manage_sponsorships: T::Boolean,
          viewer_is_sponsoring: T::Boolean,
          is_sponsorable_for_viewer: T::Boolean,
        ).void
      end
      def initialize(
        sponsorship:,
        viewer_can_manage_sponsorships:,
        viewer_is_sponsoring: false,
        is_sponsorable_for_viewer: false
      )
        @sponsorship = sponsorship
        @viewer_is_sponsoring = viewer_is_sponsoring
        @viewer_can_manage_sponsorships = viewer_can_manage_sponsorships
        @is_sponsorable_for_viewer = is_sponsorable_for_viewer
      end

      private

      sig { returns(Sponsorship) }
      attr_reader :sponsorship

      delegate :sponsors_listing, :sponsorable, :sponsorable_id, :sponsor_login, :tier, to: :sponsorship
      delegate :sponsorable_login, to: :sponsors_listing

      sig { returns(T::Boolean) }
      def viewer_is_sponsoring?
        @viewer_is_sponsoring
      end

      sig { returns(T::Boolean) }
      def viewer_can_manage_sponsorships?
        @viewer_can_manage_sponsorships
      end

      sig { returns(GitHubSponsors::Types::Sponsor) }
      memoize def sponsor
        T.must_because(sponsorship.sponsor) { "sponsorships must have a sponsor" }
      end

      sig { returns(T::Boolean) }
      def sponsorable_for_viewer?
        @is_sponsorable_for_viewer
      end

      sig { returns(Symbol) }
      def sponsor_button_location
        viewer_is_sponsoring? ? :PROFILE_SPONSORING_TAB_SPONSORING : :PROFILE_SPONSORING_TAB_SPONSOR
      end

      sig { returns(String) }
      def sponsor_button_id
        prefix = viewer_is_sponsoring? ? "sponsoring" : "sponsor"
        "#{prefix}-#{sponsorable_id}-button-profile-org"
      end

      sig { returns(String) }
      def tier_description
        "#{tier.name} #{tier_label}"
      end

      sig { returns(String) }
      def tier_label
        tier.custom? ? "(custom amount)" : "tier"
      end

      sig { returns(T.nilable(String)) }
      def sponsorship_end_date
        expiration = expiration_date

        if expiration.present?
          verb = expiration.past? ? "Expired" : "Expires"
          formatted_expiration_date = expiration.strftime("%b %-d, %Y")
          "#{verb} #{formatted_expiration_date}"
        elsif sponsorship.active?
          "Next payment due: #{sponsor.next_sponsors_billing_date.strftime('%b %-d, %Y')}"
        end
      end

      sig { returns(T.nilable(ActiveSupport::TimeWithZone)) }
      def expiration_date
        sponsorship.expires_at
      end

      sig { returns(String) }
      def sponsoring_text
        "#{sponsoring_verb} #{privacy_status} #{preposition} #{sponsorship_start_date}"
      end

      sig { returns(String) }
      def sponsoring_verb
        sponsorship.active? ? "Sponsoring" : "Sponsored"
      end

      sig { returns(T.nilable(String)) }
      def privacy_status
        return unless viewer_can_manage_sponsorships?

        if sponsorship.privacy_private?
          "privately"
        else
          "publicly"
        end
      end

      sig { returns(String) }
      def preposition
        sponsorship.active? ? "since" : "on"
      end

      sig { returns(String) }
      def sponsorship_start_date
        sponsorship.tier_selected_date.strftime("%b %-d, %Y")
      end
    end
  end
end
