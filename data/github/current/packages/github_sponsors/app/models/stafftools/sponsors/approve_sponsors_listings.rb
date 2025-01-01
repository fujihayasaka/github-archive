# typed: true
# frozen_string_literal: true

module Stafftools
  module Sponsors
    class ApproveSponsorsListings
      class Result
        def self.success(total_approved:)
          new(success: true, total_failed: 0, total_approved: total_approved, error: nil)
        end

        def self.error(error)
          new(success: false, total_failed: 0, total_approved: 0, error: error)
        end

        def self.failure(total_failed:, total_approved:)
          new(success: false, total_failed: total_failed, total_approved: total_approved, error: nil)
        end

        def initialize(success:, total_approved:, total_failed:, error:)
          @success = success
          @total_approved = total_approved
          @total_failed = total_failed
          @error = error
        end

        # Public: Were all the specified maintainers approved to have a public GitHub Sponsors profile?
        #
        # Returns a Boolean.
        def success?
          @success
        end

        # Public: Get a description of what was done and what failed.
        #
        # Returns a String.
        def message
          return @error if @error
          return @message if @message

          success_message = if @total_approved > 0
            "Approved #{@total_approved} GitHub Sponsors #{"maintainer".pluralize(@total_approved)}."
          end
          failure_message = if @total_failed > 0
            "Failed to approve #{@total_failed} GitHub Sponsors #{"maintainer".pluralize(@total_failed)}."
          end

          @message = [failure_message, success_message].compact.join(" ")
        end
      end

      MAX_SPONSORABLES = 100

      # Public: Approve multiple GitHub Sponsors profiles at once.
      #
      # sponsorable_logins - an Array of User and Organization logins (Strings) of the maintainers to approve
      # actor - the currently authenticated User doing the approving
      #
      # Returns a Stafftools::Sponsors::ApproveSponsorsListings::Result.
      def self.call(sponsorable_logins:, actor:)
        new(sponsorable_logins: sponsorable_logins, actor: actor).call
      end

      def initialize(sponsorable_logins:, actor:)
        @sponsorable_logins = sponsorable_logins
        @actor = actor
        @total_approved = 0
        @total_failed = 0
        @called = false
        @error = nil
      end

      # Public: Attempts to approve the specified GitHub Sponsors members.
      #
      # Returns a Stafftools::Sponsors::ApproveSponsorsListings::Result.
      def call
        return Result.error(error) unless valid?

        sponsors_listings_to_approve.each do |sponsors_listing|
          approve_sponsors_listing(sponsors_listing)
        end

        if total_failed.zero?
          Result.success(total_approved: total_approved)
        else
          Result.failure(total_approved: total_approved, total_failed: total_failed)
        end
      end

      private

      attr_reader :total_approved, :total_failed, :sponsorable_logins, :actor, :error

      def valid?
        sponsors_enabled? && any_sponsorables_specified? && within_max_sponsorable_limit? &&
          any_sponsors_listings_to_approve?
      end

      def sponsors_enabled?
        return true if GitHub.sponsors_enabled?
        @error = "GitHub Sponsors is not enabled."
        false
      end

      def any_sponsorables_specified?
        return true if sponsorable_logins.present?
        @error = "Please specify at least one GitHub Sponsors member to approve."
        false
      end

      def within_max_sponsorable_limit?
        return true if sponsorable_logins.size <= MAX_SPONSORABLES
        @error = "Please specify #{MAX_SPONSORABLES} maintainers or fewer to approve at a time."
        false
      end

      def any_sponsors_listings_to_approve?
        return true if sponsors_listings_to_approve.any?
        @error = "No GitHub Sponsors members were found that are not already approved."
        false
      end

      def approve_sponsors_listing(sponsors_listing)
        result = ::Sponsors::ApproveSponsorsListing.call(sponsors_listing: sponsors_listing, actor: actor)

        if result.success?
          @total_approved += 1
        else
          @total_failed += 1
        end
      end

      def sponsors_listings_to_approve
        @sponsors_listings_to_approve ||= SponsorsListing
          .with_sponsorable_logins(sponsorable_logins)
          .without_approved_state
          .limit(MAX_SPONSORABLES)
          .to_a
      end
    end
  end
end
