# typed: true
# frozen_string_literal: true

module Sponsors
  # Public: A Plain Old Ruby Object (PORO) used for accepting a Sponsors membership.
  class AcceptSponsorsMembership
    # inputs - Hash containing attributes to accept a membership.
    # inputs[:sponsorable] - The User or Organization whose membership into Sponsors is
    #                        being accepted.
    # inputs[:actor] - The User that is accepting this membership.
    # inputs[:automated] - (optional) A Boolean indicating if this is an
    #                      automated acceptance, defaulting to false.
    # inputs[:send_acceptance_email] - (optional) A Boolean indicating if we should
    #                                  notify the sponsorable via email on acceptance,
    #                                  defaulting to true.
    def self.call(inputs)
      new(**inputs).call
    end

    def initialize(sponsorable:, actor:, automated: false, send_acceptance_email: true)
      @sponsorable = sponsorable
      @listing = @sponsorable&.sponsors_listing
      @actor = actor
      @automated = automated
      @send_acceptance_email = send_acceptance_email
    end

    def call
      if !automated && !actor&.can_admin_sponsors_listings?
        return Result.failure(
          sponsorable: sponsorable,
          errors: ["Actor is not authorized to accept this membership"],
        )
      end

      unless sponsorable && listing
        return Result.failure(
          sponsorable: sponsorable,
          errors: ["Given sponsorable has not joined the Sponsors waitlist"]
        )
      end

      if already_accepted?
        return Result.success(sponsorable: sponsorable)
      end

      if automated && !listing.auto_acceptable?
        return Result.failure(
          sponsorable: sponsorable,
          errors: ["Membership is not auto acceptable"],
        )
      end

      begin
        listing.actor = actor
        if listing.accept!(automated: automated, send_acceptance_email: @send_acceptance_email)
          Result.success(sponsorable: sponsorable)
        else
          Result.failure(
            sponsorable: sponsorable,
            errors: [listing.halted_because],
          )
        end
      rescue Workflow::NoTransitionAllowed => error
        Result.failure(
          sponsorable: sponsorable,
          errors: [error.message],
        )
      end
    end

    private

    attr_accessor :sponsorable, :actor, :automated, :listing

    def already_accepted?
      if listing
        listing.accepted_into_sponsors?
      else
        false
      end
    end

    class Result
      attr_reader :sponsorable, :success, :errors
      alias_method :success?, :success

      # sponsorable - The User or Organization who is being accepted
      # success - A Boolean indicating if accepting the membership was successful
      # errors - An Array of any errors that occured when accepting a membership
      def initialize(sponsorable:, success:, errors:)
        @sponsorable = sponsorable
        @success = success
        @errors = errors
      end

      def self.success(sponsorable:)
        new(
          sponsorable: sponsorable,
          success: true,
          errors: [],
        )
      end

      def self.failure(sponsorable:, errors:)
        new(
          sponsorable: sponsorable,
          success: false,
          errors: errors,
        )
      end
    end
  end
end
