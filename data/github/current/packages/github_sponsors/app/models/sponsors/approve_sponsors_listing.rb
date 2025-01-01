# typed: true
# frozen_string_literal: true

module Sponsors
  # Public: A Plain Old Ruby Object (PORO) used for approving an existing Sponsors listing.
  class ApproveSponsorsListing
    # inputs - Hash containing attributes to approve a Sponsors listing.
    # inputs[:listing] - The SponsorsListing to approve.
    # inputs[:actor] - The User actor that is approving this listing.
    # inputs[:automated] - (optional) A Boolean indicating if this is an
    #                      automated acceptance, defaulting to false.
    def self.call(inputs)
      new(**inputs).call
    end

    def initialize(sponsors_listing:, actor:, automated: false)
      @sponsors_listing = sponsors_listing
      @actor            = actor
      @automated        = automated
    end

    def call
      if !automated && !actor.can_admin_sponsors_listings?
        error_message = "#{actor} does not have permission to approve the listing."

        return Result.failure(
          sponsors_listing: sponsors_listing,
          errors: [error_message],
        )
      end

      return Result.success(sponsors_listing: sponsors_listing) if sponsors_listing.approved?

      if !sponsors_listing.ready_for_approval?
        return Result.failure(
          sponsors_listing: sponsors_listing,
          errors: ["Listing is not ready for approval."],
        )
      end

      if automated && !sponsors_listing.auto_approvable?
        error_message = "Listing is not auto approvable."

        return Result.failure(
          sponsors_listing: sponsors_listing,
          errors: [error_message],
        )
      end

      unless sponsors_listing.can_approve?
        error_message = "Listing cannot be approved."

        return Result.failure(
          sponsors_listing: sponsors_listing,
          errors: [error_message],
        )
      end

      approve_sponsors_listing
    end

    private

    attr_accessor :sponsors_listing, :actor, :automated

    def approve_sponsors_listing
      sponsors_listing.actor = actor
      if sponsors_listing.approve!(automated: automated)
        Result.success(sponsors_listing: sponsors_listing)
      else
        error_message = sponsors_listing.halted_because

        Result.failure(
          sponsors_listing: sponsors_listing,
          errors: [error_message],
        )
      end
    end

    class Result
      attr_reader :sponsors_listing, :success, :errors
      alias_method :success?, :success

      # sponsors_listing - The SponsorsListing that is being approved.
      # success - A Boolean indicating if approving the listing was successful.
      # errors - An Array of any errors that occured when approving the listing.
      def initialize(sponsors_listing:, success:, errors:)
        @sponsors_listing = sponsors_listing
        @success = success
        @errors = errors
      end

      def self.success(sponsors_listing:)
        new(
          sponsors_listing: sponsors_listing,
          success: true,
          errors: [],
        )
      end

      def self.failure(sponsors_listing:, errors:)
        new(
          sponsors_listing: sponsors_listing,
          success: false,
          errors: errors,
        )
      end
    end
  end
end
