# typed: true
# frozen_string_literal: true

module Sponsors
  # Public: A Plain Old Ruby Object (PORO) used for updating a waitlisted Sponsors listing.
  class UpdateWaitlistedListing
    extend T::Sig

    class AutoAcceptError < StandardError; end

    # listing - [SponsorsListing] The listing to be updated.
    # inputs - [Hash] The parameters for the update.
    # @option inputs [String] :country_of_residence The country of residence.
    # @option inputs [String || Integer] :contact_email_id The ID of the contact email.
    # @option inputs [String] :billing_country The billing country.
    #
    # returns [Boolean]
    sig { params(listing: SponsorsListing, inputs: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
    def self.call(listing, inputs)
      new(
        listing,
        country_of_residence: inputs[:country_of_residence],
        contact_email_id: inputs[:contact_email_id],
        billing_country: inputs[:billing_country]
      ).call
    end

    sig do
      params(
        listing: SponsorsListing,
        country_of_residence: T.nilable(String),
        contact_email_id: T.nilable(T.any(String, Integer)),
        billing_country: T.nilable(String)
      ).void
    end
    def initialize(listing, country_of_residence: nil, contact_email_id: nil, billing_country: nil)
      @listing = listing
      @country_of_residence = country_of_residence
      @contact_email_id = contact_email_id
      @billing_country = billing_country
    end

    sig { returns(T::Boolean) }
    def call
      return false unless update_waitlisted_listing

      process_auto_accept if listing.billing_country_previously_changed?

      true
    end

    private

    sig { returns(SponsorsListing) }
    attr_reader :listing

    sig { returns(T.nilable(String)) }
    attr_reader :country_of_residence

    sig { returns(T.nilable(T.any(String, Integer))) }
    attr_reader :contact_email_id

    sig { returns(T.nilable(String)) }
    attr_reader :billing_country

    sig { returns(T::Boolean) }
    def update_waitlisted_listing
      listing.update(
        country_of_residence: country_of_residence,
        contact_email_id: contact_email_id,
        billing_country: billing_country
      )
    end

    sig { void }
    def process_auto_accept
      return unless listing.auto_acceptable?

      result = Sponsors::AcceptSponsorsMembership.call(
        sponsorable: listing.sponsorable,
        actor: nil,
        automated: true,
      )

      unless result.success?
        Failbot.report(
          AutoAcceptError.new("Failed to auto accept listing (#{listing.id})"),
          sponsors_listing_id: listing.id,
          errors: result.errors,
        )
      end
    end
  end
end
