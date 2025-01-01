# typed: strict
# frozen_string_literal: true

module Sponsors
  # Public: A Plain Old Ruby Object (PORO) used for retiring an existing Sponsors tier.
  class RetireSponsorsTier
    class UnprocessableError < StandardError; end
    class ForbiddenError < StandardError; end

    sig { params(tier: SponsorsTier, viewer: T.nilable(User)).void }
    def self.call(tier:, viewer:)
      new(tier: tier, viewer: viewer).call
    end

    sig { params(tier: SponsorsTier, viewer: T.nilable(User)).void }
    def initialize(tier:, viewer:)
      @tier = tier
      @viewer = viewer
    end

    sig { void }
    def call
      validate
      tier.retire!
      tier
    end

    private

    sig { returns SponsorsTier }
    attr_reader :tier

    sig { returns T.nilable(User) }
    attr_reader :viewer

    sig { returns T.nilable(SponsorsListing) }
    def sponsors_listing
      tier.sponsors_listing
    end

    sig { void }
    def validate
      validate_sponsors_enabled
      validate_not_yet_retired
      validate_non_custom_tier
      validate_tier_can_be_edited
      validate_accepted_sponsors_listing
      validate_tier_can_be_retired
    end

    sig { void }
    def validate_sponsors_enabled
      raise UnprocessableError.new("GitHub Sponsors is not available.") unless GitHub.sponsors_enabled?
    end

    sig { void }
    def validate_not_yet_retired
      raise UnprocessableError.new("Can't change the state of a retired tier.") if tier.retired?
    end

    sig { void }
    def validate_non_custom_tier
      raise UnprocessableError.new("Cannot retire a custom tier.") if tier.custom?
    end

    sig { void }
    def validate_tier_can_be_edited
      return if tier.editable_by?(viewer)
      raise ForbiddenError.new("#{viewer} does not have permission to change the tier.")
    end

    sig { void }
    def validate_accepted_sponsors_listing
      return if sponsors_listing&.accepted_into_sponsors?
      raise ForbiddenError.new("Tiers for this Sponsors profile cannot be retired at this time.")
    end

    sig { void }
    def validate_tier_can_be_retired
      raise UnprocessableError.new("This tier cannot be retired.") unless tier.can_retire?
    end
  end
end
