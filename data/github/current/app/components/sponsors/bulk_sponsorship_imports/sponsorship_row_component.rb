# typed: true
# frozen_string_literal: true

# A row representing a valid sponsorship from a Bulk Sponsorship CSV
class Sponsors::BulkSponsorshipImports::SponsorshipRowComponent < ApplicationComponent
  # amount - a Billing::Money
  # index - an Integer representing the index of the row in the
  #         BulkSponsorshipImports table
  # sponsors_listing - a SponsorsListing or nil
  # error - a String error message about this row from the bulk sponsorship import, or nil
  # sponsor - the User or Organization who is sponsoring
  # sponsorable - the User or Organization, or nil if none exists; must be associated with the given SponsorsListing
  #               both are non-nil
  # sponsorable_login - the String username of the maintainer to be sponsored; must match the given sponsorable
  #                     if the sponsorable is not nil
  # is_correctable_error - optional Boolean indicating whether the error is something the sponsor can fix;
  #                        necessary if a non-nil error is given
  # valid_lower_amounts - Array of Integer dollar amounts that are less than the given amount but would still be
  #                       valid for a sponsorship of the given maintainer
  # frequency - Symbol, either :one_time or :recurring
  def initialize(
    amount:,
    index:,
    sponsors_listing: nil,
    error: nil,
    sponsor:,
    sponsorable: nil,
    sponsorable_login: nil,
    is_correctable_error: nil,
    valid_lower_amounts: [],
    frequency: :one_time
  )
    @amount = amount
    @index = index
    @sponsors_listing = sponsors_listing
    @error = error
    @sponsor = sponsor
    @sponsorable = sponsorable
    @sponsorable_login = sponsorable_login
    @is_correctable_error = is_correctable_error
    @valid_lower_amounts = valid_lower_amounts
    @frequency = frequency
  end

  private

  attr_reader :sponsors_listing, :amount, :error, :valid_lower_amounts, :index

  def render?
    return false unless GitHub.sponsors_enabled? && logged_in?
    return false if !error? && sponsors_listing.nil?
    return false if @sponsorable && @sponsorable_login && @sponsorable_login.downcase != @sponsorable.login.downcase
    if sponsors_listing
      return false if @sponsorable && sponsors_listing.sponsorable_id != @sponsorable.id
      if @sponsorable_login
        return false if sponsors_listing.sponsorable_login.downcase != @sponsorable_login.downcase
      end
    end
    return false if @is_correctable_error.nil? && error?
    sponsorable_login.present?
  end

  memoize def error?
    error.present?
  end

  def correctable_error?
    @is_correctable_error
  end

  def non_correctable_error?
    error? && !correctable_error?
  end

  def checked?
    !error?
  end

  def disabled?
    error?
  end

  def data_valid_amounts_attribute
    valid_lower_amounts.join(",")
  end

  memoize def custom_min_dollars
    min_custom_dollars = sponsors_listing&.min_custom_tier_amount_in_dollars
    min_custom_dollars&.to_i
  end

  def custom_min_amount_warning
    Sponsors::BulkSponsorshipRow.min_custom_amount_error_for(custom_min_dollars)
  end

  memoize def min_dollars
    return 1 if custom_min_dollars.nil?
    possible_minimum_amounts = [custom_min_dollars, valid_lower_amounts.min].compact
    return 1 if possible_minimum_amounts.empty?
    possible_minimum_amounts.min
  end

  memoize def sponsorable
    @sponsorable || sponsors_listing&.sponsorable
  end

  memoize def sponsorable_login
    sponsorable&.login || @sponsorable_login
  end

  memoize def organization?
    sponsorable&.organization?
  end

  memoize def sponsorable_url
    return unless sponsorable
    if sponsors_listing
      sponsorable_path(sponsorable_login)
    else
      user_path(sponsorable_login)
    end
  end

  memoize def frequency_text
    if @frequency == :recurring
      "a month"
    else
      "one time"
    end
  end
end
