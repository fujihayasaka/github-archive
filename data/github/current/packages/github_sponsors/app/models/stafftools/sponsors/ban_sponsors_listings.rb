# typed: true
# frozen_string_literal: true

module Stafftools
  module Sponsors
    class BanSponsorsListings
      class Result
        def self.success(total_banned:)
          new(success: true, total_banned: total_banned, error: nil)
        end

        def self.error(error)
          new(success: false, total_banned: 0, error: error)
        end

        def initialize(success:, total_banned:, error:)
          @success = success
          @total_banned = total_banned
          @error = error
        end

        # Public: Were all the specified maintainers banned from GitHub Sponsors?
        #
        # Returns a Boolean.
        def success?
          @success
        end

        # Public: Get a description of what was done.
        #
        # Returns a String.
        def message
          return @error if @error
          return @message if @message

          success_message = if @total_banned > 0
            "Scheduled #{@total_banned} GitHub Sponsors #{"maintainer".pluralize(@total_banned)} to be banned soon."
          end

          @message = [success_message].compact.join(" ")
        end
      end

      MAX_SPONSORABLES = 100

      # Public: Ban multiple maintainers from GitHub Sponsors at once.
      #
      # sponsorable_logins - an Array of User and Organization logins (Strings) for the maintainers to ban from
      #                      GitHub Sponsors
      # actor - the currently authenticated User doing the banning
      # ban_reason - a String description of why these maintainers are being banned
      #
      # Returns a Stafftools::Sponsors::BanSponsorsListings::Result.
      def self.call(sponsorable_logins:, actor:, ban_reason:)
        new(sponsorable_logins: sponsorable_logins, actor: actor, ban_reason: ban_reason).call
      end

      def initialize(sponsorable_logins:, actor:, ban_reason:)
        @sponsorable_logins = sponsorable_logins
        @actor = actor
        @ban_reason = ban_reason
        @total_banned = 0
        @called = false
        @error = nil
      end

      # Public: Attempts to ban the specified GitHub Sponsors members.
      #
      # Returns a Stafftools::Sponsors::BanSponsorsListings::Result.
      def call
        return Result.error(error) unless valid?

        sponsors_listings_to_ban.each do |sponsors_listing|
          ban_sponsors_listing(sponsors_listing)
        end

        Result.success(total_banned: total_banned)
      end

      private

      attr_reader :total_banned, :sponsorable_logins, :actor, :error, :ban_reason

      def valid?
        sponsors_enabled? && any_sponsorables_specified? && within_max_sponsorable_limit? && ban_reason_provided? &&
          any_sponsors_listings_to_ban?
      end

      def sponsors_enabled?
        return true if GitHub.sponsors_enabled?
        @error = "GitHub Sponsors is not enabled."
        false
      end

      def any_sponsorables_specified?
        return true if sponsorable_logins.present?
        @error = "Please specify at least one GitHub Sponsors member to ban."
        false
      end

      def within_max_sponsorable_limit?
        return true if sponsorable_logins.size <= MAX_SPONSORABLES
        @error = "Please specify #{MAX_SPONSORABLES} maintainers or fewer to ban at a time."
        false
      end

      def any_sponsors_listings_to_ban?
        return true if sponsors_listings_to_ban.any?
        @error = "No GitHub Sponsors members were found that are not already banned."
        false
      end

      def ban_reason_provided?
        return true if ban_reason.present?
        @error = "Please specify a reason these GitHub Sponsors members are being banned."
        false
      end

      def ban_sponsors_listing(sponsors_listing)
        BanSponsorsListingJob.perform_later(sponsors_listing: sponsors_listing, actor: actor, ban_reason: ban_reason)
        @total_banned += 1
      end

      def sponsors_listings_to_ban
        @sponsors_listings_to_ban ||= SponsorsListing
          .with_sponsorable_logins(sponsorable_logins)
          .without_banned_state
          .limit(MAX_SPONSORABLES)
          .to_a
      end
    end
  end
end
