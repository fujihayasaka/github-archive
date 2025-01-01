# typed: strict
# frozen_string_literal: true

module Sponsors
  class ReviewPendingSponsorsListing
    extend T::Sig
    include GitHub::Memoizer

    MINIMUM_ACTIVITY_SCORE = 4

    sig { returns(SponsorsListing) }
    attr_reader :sponsors_listing

    sig { params(sponsors_listing: SponsorsListing).returns(Sponsors::ReviewPendingSponsorsListing::Result) }
    def self.call(sponsors_listing:)
      new(sponsors_listing: sponsors_listing).call
    end

    private_class_method :new

    sig { params(sponsors_listing: SponsorsListing).void }
    def initialize(sponsors_listing:)
      @sponsors_listing = sponsors_listing
    end

    sig { returns(Sponsors::ReviewPendingSponsorsListing::Result) }
    def call
      unless sponsors_listing.stripe_verified? && sponsors_listing.stripe_w8_or_w9_verified?
        return Result.reject(
          sponsors_listing: sponsors_listing, error: "Stripe connect account is missing or unverified."
        )
      end

      if calculated_activity_score >= MINIMUM_ACTIVITY_SCORE
        return Result.approve(sponsors_listing: sponsors_listing)
      end

      Result.reject(
        sponsors_listing: sponsors_listing, error: "Listing does not meet the minimum requirements."
      )
    end

    private

    sig { returns(Integer) }
    def calculated_activity_score
      [
        trust_level_score,
        public_contributions_score,
        sponsors_tiers_score,
        public_repos_score,
        sponsorships_score,
        abuse_reports_score
      ].sum
    end

    # This is essentially a proxy for account age but can be overidden by staff
    sig { returns(Integer) }
    def trust_level_score
      trust_level = T.must(sponsors_listing.sponsorable).trust_level_as_sponsorable

      return 2 if trust_level.trusted?

      return 1 if trust_level.neutral?

      0
    end

    # Does the sponsorable have a significant number of public contributions?
    # see https://github.com/github/sponsors/issues/6034 for more context
    sig { returns(Integer) }
    def public_contributions_score
      public_contributions_count = sponsors_listing.public_contribution_count

      return 2 if public_contributions_count >= 250

      return 1 if public_contributions_count >= 25

      0
    end

    # Has the sponsorable published any sponsors tiers?
    sig { returns(Integer) }
    def sponsors_tiers_score
      return 1 if sponsors_listing.has_published_tier?

      0
    end

    # Does the sponsorable have any public non-fork repositories?
    sig { returns(Integer) }
    def public_repos_score
      return 1 if T.must(sponsors_listing.sponsorable).public_repositories.where(parent_id: nil).any?

      0
    end

    # Has the sponsorable funded any other users?
    sig { returns(Integer) }
    def sponsorships_score
      return 1 if T.must(sponsors_listing.sponsorable).sponsorships_as_sponsor.any?

      0
    end

    # Has the sponsorable received any abuse reports?
    sig { returns(Integer) }
    def abuse_reports_score
      return -1 if sponsors_listing.sponsorable_has_received_abuse_report?

      0
    end

    class Result
      extend T::Sig

      sig { returns(SponsorsListing) }
      attr_reader :sponsors_listing

      sig { returns(T.nilable(String)) }
      attr_reader :error

      sig { returns(T::Boolean) }
      attr_reader :approve
      alias_method(:approve?, :approve)

      sig { params(sponsors_listing: SponsorsListing, approve: T::Boolean, error: T.nilable(String)).void }
      def initialize(sponsors_listing:, approve:, error:)
        @sponsors_listing = sponsors_listing
        @approve = approve
        @error = error
      end

      sig { params(sponsors_listing: SponsorsListing).returns(T.attached_class) }
      def self.approve(sponsors_listing:)
        new(sponsors_listing: sponsors_listing, approve: true, error: nil)
      end

      sig { params(sponsors_listing: SponsorsListing, error: String).returns(T.attached_class) }
      def self.reject(sponsors_listing:, error:)
        new(sponsors_listing: sponsors_listing, approve: false, error: error)
      end
    end
  end
end
