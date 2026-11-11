# typed: true
# frozen_string_literal: true

class SyncSponsorsPatreonUser
  include GitHub::Memoizer

  DATADOG_PREFIX = "sponsors.patreon_sync"

  class UnprocessableError < StandardError; end

  # Public: Update the details we have about a sponsorable maintainer's Patreon account based on information from
  # the Patreon API.
  #
  # inputs - a Hash with the following keys:
  #   :sponsors_patreon_user - a SponsorsPatreonUser instance
  #
  # Returns nothing. Raises a SyncSponsorsPatreonUser::UnprocessableError if something goes wrong.
  def self.call(inputs)
    new(**inputs).call
  end

  sig { params(sponsors_patreon_user: SponsorsPatreonUser).void }
  def initialize(sponsors_patreon_user:)
    @sponsors_patreon_user = sponsors_patreon_user
    @client = sponsors_patreon_user.patreon_client
  end

  sig { void }
  def call
    validate
    update_sponsors_patreon_campaign_details
  end

  private

  attr_reader :sponsors_patreon_user

  sig { void }
  def validate
    raise UnprocessableError.new("GitHub Sponsors is not enabled") unless GitHub.sponsors_enabled?
    raise UnprocessableError.new("Can't authenticate with Patreon API for given account") unless @client
  end

  def update_sponsors_patreon_campaign_details
    if patreon_campaigns_by_published_and_price.present?
      published_patreon_campaigns_by_price = patreon_campaigns_by_published_and_price[true] || {}
      sync_sponsors_patreon_tiers(published_patreon_campaigns_by_price)
    else
      delete_sponsors_patreon_tiers
    end
  end

  sig { params(published_patreon_campaigns_by_price: T::Hash[Integer, T::Hash[String, T.untyped]]).void }
  def sync_sponsors_patreon_tiers(published_patreon_campaigns_by_price)
    delete_sponsors_patreon_tiers(ids: sponsors_patreon_tier_ids_to_delete(published_patreon_campaigns_by_price))
    create_sponsors_patreon_tiers(published_patreon_campaigns_by_price)
  end

  sig do
    params(
      published_patreon_campaigns_by_price: T::Hash[Integer, T::Hash[String, T.untyped]],
    ).returns(T::Array[Integer])
  end
  def sponsors_patreon_tier_ids_to_delete(published_patreon_campaigns_by_price)
    valid_pairs = if sponsors_patreon_tiers_allowed?
      published_patreon_campaigns_by_price # tiers on Patreon
        .map { |price_in_cents, patreon_campaign| [price_in_cents, patreon_campaign["id"]] }
    else
      []
    end
    existing_pairs = existing_patreon_tiers # tiers in our database
      .map { |patreon_tier| [patreon_tier.amount_in_cents, patreon_tier.campaign_id] }
    invalid_existing_pairs = (existing_pairs - valid_pairs).to_h # tiers only in our database, not on Patreon
    return [] if invalid_existing_pairs.empty?

    invalid_existing_pairs.map do |price_in_cents, campaign_id|
      existing_patreon_tiers_for_price = T.must(existing_patreon_tiers_by_amount_and_campaign[price_in_cents])
      patreon_tier = T.must(existing_patreon_tiers_for_price[campaign_id])
      T.must(patreon_tier.id)
    end
  end

  sig { returns T::Array[SponsorsPatreonTier] }
  memoize def existing_patreon_tiers
    sponsors_patreon_user.sponsors_patreon_tiers.to_a
  end

  sig { returns T::Boolean }
  memoize def sponsors_patreon_tiers_allowed?
    # Only care about mirroring their Patreon tiers in our database if they have a Sponsors profile. If there's not
    # a Sponsors profile page to show them on, there's no point in having SponsorsPatreonTier records.
    listing = sponsors_patreon_user.sponsors_listing
    listing.present? &&
      listing.accepted_into_sponsors? # exclude those we've banned and those still on the waitlist
  end

  sig { returns T::Hash[Integer, T::Hash[String, SponsorsPatreonTier]] }
  memoize def existing_patreon_tiers_by_amount_and_campaign
    existing_patreon_tiers.each_with_object({}) do |patreon_tier, hash|
      hash[patreon_tier.amount_in_cents] ||= {}
      hash[patreon_tier.amount_in_cents][patreon_tier.campaign_id] = patreon_tier
    end
  end

  sig { params(published_patreon_campaigns_by_price: T::Hash[Integer, T::Hash[String, T.untyped]]).void }
  def create_sponsors_patreon_tiers(published_patreon_campaigns_by_price)
    return unless sponsors_patreon_tiers_allowed?

    published_patreon_campaigns_by_price.each do |price_in_cents, patreon_campaign|
      campaign_id = patreon_campaign["id"]
      if campaign_id.present? && SponsorsPatreonTier.valid_price?(cents: price_in_cents)
        ensure_sponsors_patreon_tier_exists(price_in_cents, campaign_id)
      end
    end
  end

  sig { params(price_in_cents: Integer, patreon_campaign_id: String).void }
  def ensure_sponsors_patreon_tier_exists(price_in_cents, patreon_campaign_id)
    existing_patreon_tier = existing_patreon_tiers_by_amount_and_campaign
      .dig(price_in_cents, patreon_campaign_id)
    return if existing_patreon_tier

    new_patreon_tier = sponsors_patreon_user.sponsors_patreon_tiers.new(
      amount_in_cents: price_in_cents,
      campaign_id: patreon_campaign_id,
    )

    success = ActiveRecord::Base.connected_to(role: :writing) { new_patreon_tier.save }
    unless success
      error = new_patreon_tier.errors.full_messages.to_sentence
      raise UnprocessableError.new("Could not save Patreon tier details: #{error}")
    end
  end

  # Private: Delete all or some of the maintainer's Patreon tiers from our database.
  #
  # ids - an optional list of IDs of particular tiers to delete. If nil, all tiers will be deleted.
  #       If an empty list, none of the tiers will be deleted.
  sig { params(ids: T.nilable(T::Array[Integer])).void }
  def delete_sponsors_patreon_tiers(ids: nil)
    return if ids&.empty? # gave a list of explicit IDs to delete, but there weren't any, so nothing to do

    ActiveRecord::Base.connected_to(role: :writing) do
      patreon_tiers_to_delete = sponsors_patreon_user.sponsors_patreon_tiers
      patreon_tiers_to_delete = patreon_tiers_to_delete.where(id: ids) if ids
      patreon_tiers_to_delete.destroy_all
    end
  end

  sig { returns T::Hash[T::Boolean, T::Hash[Integer, T::Hash[String, T.untyped]]] }
  memoize def patreon_campaigns_by_published_and_price
    result = {}

    monthly_patreon_campaigns.each do |campaign_data|
      campaign_published_at = campaign_data.dig("attributes", "published_at")
      patreon_tiers = campaign_data.dig("relationships", "tiers", "data") || []

      patreon_tiers.each do |tier_data|
        is_published = campaign_published_at.present? && tier_data.dig("attributes", "published") == true
        price = tier_data.dig("attributes", "amount_cents") || 0

        result[is_published] ||= {}
        result[is_published][price] ||= campaign_data
      end
    end

    result
  end

  sig { returns(T::Array[T::Hash[String, T.untyped]]) }
  memoize def monthly_patreon_campaigns
    client.get_monthly_campaigns
  rescue SponsorsPatreonClient::UnauthorizedError => err
    GitHub.dogstats.increment("#{DATADOG_PREFIX}.unauthorized")

    # Make one attempt to get a new access token, to see if that fixes the bad authorization:
    return [] unless refresh_patreon_tokens

    begin
      result = client.get_monthly_campaigns
      GitHub.dogstats.increment("#{DATADOG_PREFIX}.authorized_after_token_refresh")
      result
    rescue SponsorsPatreonClient::UnauthorizedError => err
      GitHub.dogstats.increment("#{DATADOG_PREFIX}.unauthorized_after_token_refresh")
      []
    end
  end

  sig { returns T::Boolean }
  def refresh_patreon_tokens
    success = ActiveRecord::Base.connected_to(role: :writing) { sponsors_patreon_user.refresh_tokens_or_destroy }

    if success
      @client = sponsors_patreon_user.patreon_client # make sure subsequent API calls use the new tokens
      true
    else
      false
    end
  end

  sig { returns SponsorsPatreonClient }
  def client
    T.must_because(@client) { "#validate runs before this method is called, ensuring non-nil @client" }
  end
end
