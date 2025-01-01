# typed: strict
# frozen_string_literal: true

# Public: A Plain Old Ruby Object (PORO) used for creating a Sponsors tier
module Sponsors
  class CreateSponsorsTier
    extend T::Sig

    class UnprocessableError < StandardError; end
    class ForbiddenError < StandardError; end

    # Public: Find an existing published tier with the specified amount and frequency, or create a new custom tier
    # for that amount and frequency.
    #
    # sponsors_listing - the SponsorsListing the tier is for
    # amount - amount in US dollars for the tier, e.g, 1 for $1
    # is_recurring - Boolean indicating whether the tier should be recurring versus one-time
    # viewer - the currently authenticated User to use when creating the custom tier, if necessary
    # parent_tier_id - optional ID for a published SponsorsTier that has the closest dollar value to the custom amount
    #                  without going over; only applicable when creating a custom tier, will not be used when a
    #                  published tier of the same frequency and amount exists for `sponsors_listing`
    #
    # Returns a SponsorsTier or raises one of UnprocessableError or ForbiddenError.
    sig do
      params(
        sponsors_listing: SponsorsListing,
        amount: Integer,
        is_recurring: T::Boolean,
        viewer: T.nilable(User),
        sponsor: T.nilable(T.any(User, Organization)),
        parent_tier_id: T.nilable(T.any(Integer, String)),
      ).returns(SponsorsTier)
    end
    def self.find_published_or_create_custom_tier(sponsors_listing:, amount:, is_recurring:, viewer: nil, sponsor: nil, parent_tier_id: nil)
      colliding_published_tier = sponsors_listing.colliding_published_tier(amount: amount,
        is_recurring: is_recurring)
      return colliding_published_tier if colliding_published_tier

      call(
        custom: true,
        description: nil,
        sponsors_listing: sponsors_listing,
        amount: amount,
        viewer: viewer,
        sponsor: sponsor,
        is_recurring: is_recurring,
        parent_tier_id: parent_tier_id,
      )
    end

    # inputs - Hash containing attributes to create a sponsors tier
    # inputs[:sponsors_listing] - the SponsorsListing the tier is for
    # inputs[:description] - A short description of the tier.
    # inputs[:amount] - amount in US dollars for the tier, e.g, 1 for $1
    # inputs[:viewer] - Current viewer from GraphQL context.
    # inputs[:custom] - Whether this should be a custom tier meant for use with one
    #                   sponsorship or not.
    # inputs[:is_recurring] - Boolean indicating whether the tier should be recurring versus one-time
    # inputs[:welcome_message] - An optional welcome message for new sponsors of this tier.
    # inputs[:repository_id] - An optional Repository ID to associate with the tier, to indicate all sponsors who use
    #                          this tier should be granted access to the repository.
    # inputs[:parent_tier_id] - optional ID for a published SponsorsTier that has the closest dollar value to the
    #                           custom amount without going over; only applicable when custom=true
    sig { params(inputs: T::Hash[Symbol, T.untyped]).returns(SponsorsTier) }
    def self.call(inputs)
      new(**T.unsafe(inputs)).call
    end

    sig do
      params(
        sponsors_listing: SponsorsListing,
        description: T.nilable(String),
        amount: Integer,
        viewer: T.nilable(User),
        custom: T::Boolean,
        is_recurring: T::Boolean,
        welcome_message: T.nilable(String),
        repository_id: T.nilable(T.any(Integer, String)),
        require_repository: T.nilable(T::Boolean),
        parent_tier_id: T.nilable(T.any(Integer, String)),
        sponsor: T.nilable(T.any(User, Organization)),
      ).void
    end
    def initialize(sponsors_listing:, description:, amount:,
                   viewer:, custom:, is_recurring:,
                   welcome_message: nil, repository_id: nil, require_repository: false,
                   parent_tier_id: nil, sponsor: nil)
      @sponsors_listing = sponsors_listing
      @description = description
      @amount = amount
      @viewer = viewer
      @sponsor = sponsor
      @custom = custom
      @is_recurring = is_recurring
      @welcome_message = welcome_message
      @repository_id = T.let(repository_id ? repository_id.to_i : nil, T.nilable(Integer))
      @require_repository = T.let(!!require_repository, T::Boolean)
      @parent_tier_id = T.let(parent_tier_id ? parent_tier_id.to_i : nil, T.nilable(Integer))
    end

    sig { returns(SponsorsTier) }
    def call
      validate_not_banned

      tier = SponsorsTier.new(
        sponsors_listing: sponsors_listing,
        state: new_tier_state,
        creator: viewer,
      )
      validate_tier_permission(tier)

      tier.description = description || ""
      tier.monthly_price_in_cents = monthly_price_in_cents
      tier.yearly_price_in_cents = yearly_price_in_cents
      tier.frequency = frequency
      tier.name = tier.generate_name
      tier.welcome_message = welcome_message
      tier.require_repository = require_repository
      tier.repository_id = repository_id
      tier.parent_tier_id = parent_tier_id
      tier.skip_max_amount_validation = sponsor&.sponsors_invoiced?

      if tier.save
        tier
      else
        errors = tier.errors.full_messages.join(", ")
        raise UnprocessableError.new("Could not create new Sponsors tier: #{errors}")
      end
    end

    private

    sig { returns(SponsorsListing) }
    attr_reader :sponsors_listing

    sig { returns(T.nilable(String)) }
    attr_reader :description

    sig { returns(Integer) }
    attr_reader :amount

    sig { returns(T.nilable(Integer)) }
    attr_reader :repository_id

    sig { returns(T::Boolean) }
    attr_reader :require_repository

    sig { returns(T.nilable(User)) }
    attr_reader :viewer

    sig { returns(T.nilable(T.any(User, Organization))) }
    attr_reader :sponsor

    sig { returns(T.nilable(String)) }
    attr_reader :welcome_message

    sig { returns(T.nilable(Integer)) }
    attr_reader :parent_tier_id

    sig { params(tier: SponsorsTier).void }
    def validate_tier_permission(tier)
      unless tier.editable_by?(viewer)
        raise ForbiddenError.new("#{viewer} does not have permission to create a Sponsors " \
          "tier for #{sponsors_listing.sponsorable_login}.")
      end
    end

    sig { void }
    def validate_not_banned
      if sponsors_listing.banned?
        raise ForbiddenError.new("Cannot create a Sponsors tier for #{sponsors_listing.sponsorable_login} " \
          "at this time.")
      end
    end

    sig { returns(Symbol) }
    def frequency
      @is_recurring ? :recurring : :one_time
    end

    sig { returns(Integer) }
    def monthly_price_in_cents
      amount * 100
    end

    sig { returns(Integer) }
    def yearly_price_in_cents
      if @is_recurring
        monthly_price_in_cents * 12
      else
        monthly_price_in_cents
      end
    end

    sig { returns(Symbol) }
    def new_tier_state
      @custom ? :custom : :draft
    end
  end
end
