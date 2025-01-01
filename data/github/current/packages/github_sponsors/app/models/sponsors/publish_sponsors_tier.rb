# typed: true
# frozen_string_literal: true

module Sponsors

  # Public: A Plain Old Ruby Object (PORO) used for publishing an existing Sponsors tier.
  class PublishSponsorsTier
    class UnprocessableError < StandardError; end
    class ForbiddenError < StandardError; end

    # Public: Publish a Sponsors tier, making it publicly visible on the sponsorable's GitHub Sponsors profile page.
    #
    # inputs - Hash containing attributes to publish a sponsors tier
    # inputs[:tier] - The SponsorsTier to publish.
    # inputs[:viewer] - Current viewer from GraphQL context.
    #
    # Returns the SponsorsTier or raises Sponsors::PublishSponsorsTier::UnprocessableError or
    # Sponsors::PublishSponsorsTier::ForbiddenError.
    def self.call(inputs)
      new(**inputs).call
    end

    def initialize(tier:, viewer:)
      @tier = tier
      @viewer = viewer
    end

    def call
      validate
      tier.publish!
      tier.instrument_publish(actor: viewer)
      tier
    end

    private

    attr_accessor :tier, :viewer

    delegate :sponsors_listing, to: :tier

    def validate
      validate_sponsors_enabled
      validate_viewer_can_admin_tier
      validate_listing_not_banned
      validate_not_yet_published
      validate_not_retired
      validate_within_published_tier_limit
      validate_publishable_tier
    end

    def validate_sponsors_enabled
      raise UnprocessableError.new("GitHub Sponsors is not available.") unless GitHub.sponsors_enabled?
    end

    def validate_viewer_can_admin_tier
      return if tier.adminable_by?(viewer)
      raise ForbiddenError.new("#{viewer} does not have permission to change the tier.")
    end

    def validate_listing_not_banned
      if sponsors_listing.banned?
        raise ForbiddenError.new("Tiers for this Sponsors profile cannot be published at this time.")
      end
    end

    def validate_not_yet_published
      raise UnprocessableError.new("This tier has already been published.") if tier.published?
    end

    def validate_not_retired
      raise UnprocessableError.new("This tier has been retired.") if tier.retired?
    end

    def validate_within_published_tier_limit
      if sponsors_listing.reached_maximum_tier_count?(recurring: tier.recurring?)
        raise UnprocessableError.new("The Sponsors profile has reached the limit of published, " \
          "#{tier.frequency_adjective} tiers.")
      end
    end

    def validate_publishable_tier
      raise UnprocessableError.new("This tier cannot be published.") unless tier.draft? && tier.can_publish?
    end
  end
end
