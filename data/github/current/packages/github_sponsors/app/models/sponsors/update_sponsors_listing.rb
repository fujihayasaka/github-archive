# typed: true
# frozen_string_literal: true

module Sponsors
  # Public: A Plain Old Ruby Object (PORO) used for updating an existing Sponsors listing.
  class UpdateSponsorsListing
    class UnprocessableError < StandardError; end
    class ForbiddenError < StandardError; end

    # inputs - Hash containing attributes to update a Sponsors listing
    # inputs[:viewer] - Current viewer from GraphQL context.
    # inputs[:slug] - The slug of the listing (SponsorsListing) to update.
    # inputs[:short_description] - (optional) The listing's short description.
    # inputs[:full_description] - (optional) The listing's full description.
    # inputs[:featured_state] - (optional) Whether the listing should be featured. Choose from
    #                           "disabled", "allowed", or "active".
    # inputs[:hide_past_sponsorships] - (optional Boolean) Whether the listing should hide past sponsorships.
    # inputs[:enable_featured_sponsorships] - (optional Boolean) Whether the listing should enable featured sponsorships.
    # inputs[:automate_featured_sponsorships] - (optional Boolean) Whether the listing should automate featured sponsorships.
    sig { params(inputs: T::Hash[Symbol, T.any(String, User, T::Boolean, Symbol)]).returns(SponsorsListing) }
    def self.call(inputs)
      new(**T.unsafe(inputs)).call
    end

    sig do
      params(
        viewer: T.nilable(User),
        slug: String,
        short_description: T.nilable(String),
        full_description: T.nilable(String),
        featured_state: T.nilable(T.any(String, Symbol)),
        hide_past_sponsorships: T.nilable(T::Boolean),
        enable_featured_sponsorships: T::Boolean,
        automate_featured_sponsorships: T::Boolean,
      ).void
    end
    def initialize(
      viewer:,
      slug:,
      short_description: nil,
      full_description: nil,
      featured_state: nil,
      hide_past_sponsorships: false,
      enable_featured_sponsorships: false,
      automate_featured_sponsorships: false
    )
      @sponsors_listing = SponsorsListing.find_by!(slug: slug)
      @sponsors_listing.actor = viewer
      @short_description = T.let(short_description || @sponsors_listing.short_description, T.nilable(String))
      @full_description = full_description
      @viewer = viewer
      @featured_state = T.let(featured_state || @sponsors_listing.featured_state, T.nilable(T.any(Symbol, String)))
      @hide_past_sponsorships = hide_past_sponsorships
      @enable_featured_sponsorships = enable_featured_sponsorships
      @automate_featured_sponsorships = automate_featured_sponsorships
    end

    sig { returns SponsorsListing }
    def call
      update_sponsors_listing
    end

    private

    sig { returns SponsorsListing }
    attr_accessor :sponsors_listing

    sig { returns T.nilable(String) }
    attr_accessor :short_description

    sig { returns T.nilable(String) }
    attr_accessor :full_description

    sig { returns T.nilable(User) }
    attr_accessor :viewer

    sig { returns T.nilable(T.any(Symbol, String)) }
    attr_accessor :featured_state

    sig { returns T.nilable(T::Boolean) }
    attr_accessor :hide_past_sponsorships

    sig { returns T::Boolean }
    attr_accessor :enable_featured_sponsorships

    sig { returns T::Boolean }
    attr_accessor :automate_featured_sponsorships

    def update_sponsors_listing
      unless sponsors_listing.editable_by?(viewer)
        raise ForbiddenError.new("#{viewer} does not have permission to update the sponsors listing.")
      end

      sponsors_listing.full_description = full_description if full_description
      sponsors_listing.featured_state = featured_state
      sponsors_listing.featured_description = short_description
      sponsors_listing.short_description = short_description

      if sponsors_listing.save
        sponsors_listing.update_past_sponsorships_visibility!(hidden: hide_past_sponsorships)
        sponsors_listing.update_featured_sponsorships_settings(enabled: enable_featured_sponsorships, automatic: automate_featured_sponsorships)
        sponsors_listing
      else
        errors = sponsors_listing.errors.full_messages
        raise UnprocessableError.new("Could not update the sponsors listing: " \
          "#{errors.to_sentence}")
      end
    end
  end
end
