# typed: true
# frozen_string_literal: true

class Billing::StripeConnect::LinkAccount
  class ValidationError < StandardError; end
  class StripeSyncError < StandardError; end

  # Public: Create a new Stripe account record to associate a known, existing account in Stripe with a record, such as
  # a Sponsors profile, in our system.
  #
  # inputs - a Hash of attributes with keys:
  #   :stripe_account_id - String Stripe account ID, e.g., "acct_1FTkPuHZwjRbhiNt"
  #   :sponsors_listing - a SponsorsListing to associate with the Stripe account
  #   :actor - the User who is linking the Stripe account
  #
  # Returns a Billing::StripeConnect::Account or raises an exception: either
  # Billing::StripeConnect::LinkAccount::ValidationError or Billing::StripeConnect::LinkAccount::StripeSyncError.
  def self.call(inputs)
    new(**inputs).call
  end

  # stripe_account_id - String Stripe account ID, e.g., "acct_1FTkPuHZwjRbhiNt"
  # sponsors_listing - a SponsorsListing to associate with the Stripe account
  # actor - the User who is linking the Stripe account
  def initialize(stripe_account_id:, sponsors_listing:, actor:)
    @stripe_account_id = stripe_account_id
    @sponsors_listing = sponsors_listing
    @actor = actor
  end

  def call
    validate

    return existing_stripe_account if existing_stripe_account && existing_stripe_account.sponsors_listing == sponsors_listing

    build_stripe_account

    stripe_account.sponsors_listing = sponsors_listing
    stripe_account.active = !sponsors_listing_has_active_stripe_account?

    sync_with_stripe_api
    instrument_link_account
    stripe_account
  end

  private

  attr_reader :stripe_account_id, :stripe_account, :sponsors_listing, :actor

  def validate
    raise ValidationError.new("Stripe account ID is required") if stripe_account_id.blank?
    unless sponsors_listing
      raise ValidationError.new("Sponsors listing to associate with the Stripe account is required")
    end
    raise ValidationError.new("Actor is required") unless actor

    if existing_stripe_account && existing_stripe_account.sponsors_listing != sponsors_listing
      other_sponsors_listing = existing_stripe_account.sponsors_listing
      if other_sponsors_listing && other_sponsors_listing != sponsors_listing
        raise ValidationError.new("Stripe account #{stripe_account_id} is already tied to #{other_sponsors_listing}")
      end
    end
  end

  def build_stripe_account
    @stripe_account = Billing::StripeConnect::Account.new(stripe_account_id: stripe_account_id)
  end

  def sponsors_listing_has_active_stripe_account?
    sponsors_listing.active_stripe_connect_account.present?
  end

  def existing_stripe_account
    return @existing_stripe_account if defined?(@existing_stripe_account)
    @existing_stripe_account = Billing::StripeConnect::Account.find_by(stripe_account_id: stripe_account_id)
  end

  def sync_with_stripe_api
    Sponsors::SyncStripeAccountDetails.call(stripe_account)
  rescue ActiveRecord::RecordInvalid,
         Billing::StripeConnect::Account::SyncError => err
    raise ValidationError.new("Could not save Stripe account: #{err.message}")
  rescue Stripe::PermissionError => err
    raise StripeSyncError.new("Could not sync account details with Stripe: #{err.message}")
  end

  def instrument_link_account
    stripe_account.instrument_link_account(actor)
  end
end
