# typed: strict
# frozen_string_literal: true

class SponsorsPatreonSponsorshipLoader
  extend T::Sig
  include GitHub::Memoizer

  class UnprocessableError < StandardError; end

  class Result < T::Struct
    extend T::Sig

    sig { returns Result }
    def self.empty
      new(
        membership_next_page_cursors_by_campaign_id: {},
        sponsorships_to_cancel: Set.new,
        sponsorships_to_update: Set.new,
        target_sponsorship_cents_by_sponsor_id: {},
      )
    end

    # Public: Pagination cursors for the Patreon API to get the next page of memberships, per Patreon campaign,
    # after the results that were just processed.
    const :membership_next_page_cursors_by_campaign_id, T::Hash[String, String]

    const :sponsorships_to_cancel, T::Set[Sponsorship]

    const :sponsorships_to_update, T::Set[Sponsorship]

    # Public: Keys are sponsor IDs, values are USD cents for how much their sponsorship should be worth. Includes
    # values for sponsorships that don't yet exist as well as existing sponsorships whose value needs to be updated.
    const :target_sponsorship_cents_by_sponsor_id, T::Hash[Integer, Integer]

    sig { returns T::Boolean }
    def has_another_page_of_memberships?
      membership_next_page_cursors_by_campaign_id.present?
    end
  end

  # sponsors_patreon_user - a SponsorsPatreonUser instance for the sponsorable
  # membership_page_cursors_by_campaign_id - a Hash where the keys are Patreon campaign IDs and the values are the
  #                                          pagination cursor for which page of Patreon memberships to start with
  #                                          for that campaign, if not the first page
  # max_membership_pages - optional Integer number of pages of Patreon memberships should be fetched
  # target_sponsorship_cents_by_sponsor_id - a Hash of known amounts that sponsors are paying on Patreon per month to
  #                                          the sponsorable, such as was calculated for a previous batch of Patreon
  #                                          membership API results; amounts should already be rounded down to the
  #                                          nearest whole-dollar amount, to be valid for use in a SponsorsTier
  sig do
    params(
      sponsors_patreon_user: SponsorsPatreonUser,
      membership_page_cursors_by_campaign_id: T::Hash[String, String],
      max_membership_pages: T.nilable(Integer),
      target_sponsorship_cents_by_sponsor_id: T::Hash[Integer, Integer]
    ).returns(Result)
  end
  def self.call(sponsors_patreon_user:, membership_page_cursors_by_campaign_id: {}, max_membership_pages: 5, target_sponsorship_cents_by_sponsor_id: {})
    new(
      sponsors_patreon_user: sponsors_patreon_user,
      membership_page_cursors_by_campaign_id: membership_page_cursors_by_campaign_id,
      max_membership_pages: max_membership_pages,
      target_sponsorship_cents_by_sponsor_id: target_sponsorship_cents_by_sponsor_id,
    ).call
  end

  sig do
    params(
      sponsors_patreon_user: SponsorsPatreonUser,
      membership_page_cursors_by_campaign_id: T::Hash[String, String],
      max_membership_pages: T.nilable(Integer),
      target_sponsorship_cents_by_sponsor_id: T::Hash[Integer, Integer]
    ).void
  end
  def initialize(sponsors_patreon_user:, membership_page_cursors_by_campaign_id: {}, max_membership_pages: 5, target_sponsorship_cents_by_sponsor_id: {})
    @sponsors_patreon_user = sponsors_patreon_user
    @membership_page_cursors_by_campaign_id = membership_page_cursors_by_campaign_id
    @membership_next_page_cursors_by_campaign_id = T.let({}, T::Hash[String, String])
    @max_membership_pages = max_membership_pages
    @target_sponsorship_cents_by_sponsor_id = target_sponsorship_cents_by_sponsor_id
  end

  sig { returns(Result) }
  def call
    validate
    Result.new(
      membership_next_page_cursors_by_campaign_id: membership_next_page_cursors_by_campaign_id,
      sponsorships_to_cancel: sponsorships_to_cancel,
      sponsorships_to_update: sponsorships_to_update,
      target_sponsorship_cents_by_sponsor_id: target_sponsorship_cents_by_sponsor_id,
    )
  end

  private

  sig { returns SponsorsPatreonUser }
  attr_reader :sponsors_patreon_user

  # Private: After loading this set of memberships, these are the cursors for loading the next batch from Patreon.
  sig { returns T::Hash[String, String] }
  attr_reader :membership_next_page_cursors_by_campaign_id

  # Private: Which page of memberships we should load from Patreon for each campaign.
  sig { returns T::Hash[String, String] }
  attr_reader :membership_page_cursors_by_campaign_id

  # Private: How many pages of Patreon memberships should we load in this batch.
  sig { returns T.nilable(Integer) }
  attr_reader :max_membership_pages

  delegate :sponsors_listing, :enabled_as_sponsorable?, to: :sponsors_patreon_user

  sig { void }
  def validate
    raise UnprocessableError.new("GitHub Sponsors is not enabled") unless GitHub.sponsors_enabled?
    unless sponsors_patreon_user.patreon_client
      raise UnprocessableError.new("Can't authenticate with Patreon API for given account")
    end
    raise UnprocessableError.new("Invalid Patreon account given for sponsorable") unless sponsors_patreon_user.user
  end

  sig { returns(T::Set[Sponsorship]) }
  memoize def sponsorships_to_keep
    return Set[] unless enabled_as_sponsorable?

    list = existing_patreon_sponsorships_for_sponsorable.select do |sponsorship|
      sponsor_patreon_user_id = patreon_user_ids_by_sponsor_id[sponsorship.sponsor_id]
      next false unless sponsor_patreon_user_id

      cents = active_membership_cents_by_sponsor_patreon_user_id[sponsor_patreon_user_id]

      # Should cancel this sponsorship, the sponsor has no active membership with the sponsorable's Patreon campaign
      # right now:
      next false unless cents

      # If sponsorship is worth the same amount as the Patreon membership, we can keep it without changes:
      round_down_to_whole_dollar_amount_in_cents(cents) == sponsorship.monthly_price_in_cents ||

        # Or if the maintainer has set a minimum on GitHub that's higher than what the sponsor is paying on Patreon,
        # we don't want to cancel the existing sponsorship since we wouldn't do that for a regular GitHub sponsorship,
        # but we don't want to try and update it either since we can't create a new tier for less than the
        # maintainer's minimum.
        cents < maintainer_min_amount_in_cents
    end

    list.to_set
  end

  sig { returns T::Hash[Integer, Integer] }
  memoize def target_sponsorship_cents_by_sponsor_id
    update_pairs = sponsorships_to_update.map do |sponsorship|
      sponsor_patreon_user_id = T.must(patreon_user_ids_by_sponsor_id[sponsorship.sponsor_id])
      raw_cents = T.must(active_membership_cents_by_sponsor_patreon_user_id[sponsor_patreon_user_id])
      target_cents = round_down_to_whole_dollar_amount_in_cents(raw_cents)
      sponsor_id = T.must(sponsor_ids_by_patreon_user_ids[sponsor_patreon_user_id])
      [sponsor_id, target_cents]
    end
    update_pairs.to_h.merge(sponsorships_to_create)
  end

  sig { returns(T::Set[Sponsorship]) }
  memoize def sponsorships_to_update
    return Set[] unless enabled_as_sponsorable?

    sponsorships = (existing_patreon_sponsorships_for_sponsorable - sponsorships_to_keep).to_a
    GitHub::PrefillAssociations.prefill_associations(sponsorships, :sponsors_listing,
      available_records: [sponsors_listing])

    list = sponsorships.select do |sponsorship|
      sponsor_patreon_user_id = patreon_user_ids_by_sponsor_id[sponsorship.sponsor_id]
      next false unless sponsor_patreon_user_id

      cents = active_membership_cents_by_sponsor_patreon_user_id[sponsor_patreon_user_id]
      next false unless cents

      next false if cents < maintainer_min_amount_in_cents

      next false if sponsorship.sponsor&.has_any_trade_restrictions?

      # The sponsor is paying a different amount on Patreon than they're being given credit for on GitHub, so we
      # should look for a better tier match:
      round_down_to_whole_dollar_amount_in_cents(cents) != sponsorship.monthly_price_in_cents
    end

    list.to_set
  end

  sig { returns(T::Set[Sponsorship]) }
  def sponsorships_to_cancel
    return Set.new unless can_determine_cancellations?
    existing_patreon_sponsorships_for_sponsorable - sponsorships_to_keep - sponsorships_to_update
  end

  sig { returns T::Boolean }
  memoize def can_determine_cancellations?
    # Populate #membership_next_page_cursors_by_campaign_id:
    active_membership_cents_for_campaigns_by_sponsor_patreon_user_id

    # No more pages means we've loaded the last page, so we have all the data and can make decisions based on it:
    membership_next_page_cursors_by_campaign_id.empty?
  end

  # Private: Returns a Hash of sponsor IDs and the amount in cents they should be credited for via new sponsorships.
  sig { returns T::Hash[Integer, Integer] }
  memoize def sponsorships_to_create
    return {} unless enabled_as_sponsorable?
    valid_pairs = active_patreon_membership_cents_by_sponsor_id.reject do |sponsor_id, active_cents|
      next true if existing_sponsorship_sponsor_ids.include?(sponsor_id)
      next true if active_cents < maintainer_min_amount_in_cents
      false
    end
    valid_pairs
      .map { |sponsor_id, raw_cents| [sponsor_id, round_down_to_whole_dollar_amount_in_cents(raw_cents)] }
      .to_h
  end

  sig { returns(T::Set[Integer]) }
  memoize def existing_sponsorship_sponsor_ids
    existing_patreon_sponsorship_sponsor_ids +
      existing_github_sponsorships_from_sponsorable.map(&:sponsor_id).to_set
  end

  sig { returns(T::Set[Sponsorship]) }
  memoize def existing_github_sponsorships_from_sponsorable
    sponsorable.active_sponsorships_as_sponsorable.github.to_set
  end

  sig { returns(T::Set[Sponsorship]) }
  memoize def existing_patreon_sponsorships_for_sponsorable
    sponsorable.active_sponsorships_as_sponsorable.patreon.includes(:tier, :sponsor).to_set
  end

  sig { returns(T::Hash[Integer, String]) }
  memoize def patreon_user_ids_by_sponsor_id
    known_sponsor_ids = @target_sponsorship_cents_by_sponsor_id.keys.to_set +
      existing_patreon_sponsorship_sponsor_ids
    sponsors_patreon_users = SponsorsPatreonUser.for_user(known_sponsor_ids).or(
      SponsorsPatreonUser.for_patreon_user(active_membership_cents_for_campaigns_by_sponsor_patreon_user_id.keys),
    )
    sponsors_patreon_users.map { |spu| [spu.user_id, spu.patreon_user_id] }.to_h
  end

  sig { returns(T::Set[Integer]) }
  memoize def existing_patreon_sponsorship_sponsor_ids
    existing_patreon_sponsorships_for_sponsorable.map(&:sponsor_id).to_set
  end

  sig { returns T::Hash[String, Integer] }
  memoize def active_membership_cents_for_campaigns_by_sponsor_patreon_user_id
    result = {}

    campaign_ids.each do |campaign_id|
      params = {}
      cursor = membership_page_cursors_by_campaign_id[campaign_id]
      if cursor.present?
        params[SponsorsPatreonClient::PAGE_CURSOR_PARAM] = cursor
      end

      campaign_result = client.get_active_membership_cents_by_patron_patreon_user_id(campaign_id, params: params,
        max_pages: max_membership_pages)

      campaign_result.amount_in_cents_by_patreon_user_id.each do |patreon_user_id, cents|
        # Sum all the Patreon tiers the user is paying for, to give them credit in a single sponsorship for the total:
        result[patreon_user_id] ||= 0
        result[patreon_user_id] += cents
      end

      next_page_cursor = campaign_result.next_cursor
      if next_page_cursor.present?
        membership_next_page_cursors_by_campaign_id[campaign_id] = next_page_cursor
      end
    end

    result
  end

  # Private: Returns a Hash of sponsor IDs and the amount in cents they should be credited for, based on this batch
  # of Patreon membership data and combined with any other known pairs that were provided.
  sig { returns T::Hash[Integer, Integer] }
  memoize def active_patreon_membership_cents_by_sponsor_id
    known_active_cents_by_sponsor_id = @target_sponsorship_cents_by_sponsor_id
    this_batch_active_cents_by_sponsor_id = active_membership_cents_by_sponsor_patreon_user_id
      .select { |patreon_user_id, _cents| sponsor_ids_by_patreon_user_ids[patreon_user_id.to_s].present? }
      .map { |patreon_user_id, cents| [T.must(sponsor_ids_by_patreon_user_ids[patreon_user_id.to_s]), cents] }
      .to_h
    known_active_cents_by_sponsor_id.merge(this_batch_active_cents_by_sponsor_id)
  end

  sig { returns T::Hash[String, Integer] }
  memoize def active_membership_cents_by_sponsor_patreon_user_id
    result = {}

    # Keep track of known Patreon memberships from previous batches we processed:
    @target_sponsorship_cents_by_sponsor_id.each do |sponsor_id, cents|
      patreon_user_id = patreon_user_ids_by_sponsor_id[sponsor_id]
      if patreon_user_id
        result[patreon_user_id] = cents
      end
    end

    # Look at this batch of Patreon membership data:
    result.merge!(active_membership_cents_for_campaigns_by_sponsor_patreon_user_id)

    result
  end

  sig { returns(T::Hash[String, Integer]) }
  memoize def sponsor_ids_by_patreon_user_ids
    patreon_user_ids_by_sponsor_id.invert
  end

  sig { returns T::Array[String] }
  memoize def campaign_ids
    if membership_page_cursors_by_campaign_id.present?
      # If pagination cursors were given for particular campaigns, assume we're fetching the next batch of results and
      # only want to load those campaigns, as opposed to also loading the first page of non-specified campaigns.
      membership_page_cursors_by_campaign_id.keys
    else
      client.get_monthly_campaigns.map { |campaign| campaign["id"] }
    end
  end

  sig { returns(SponsorsPatreonClient) }
  memoize def client
    T.must_because(sponsors_patreon_user.patreon_client) { "#validate ensures non-nil" }
  end

  sig { returns GitHubSponsors::Types::Sponsorable }
  memoize def sponsorable
    T.must_because(sponsors_patreon_user.user) { "#validate ensures non-nil" }
  end

  sig { params(amount_in_cents: Integer).returns(Integer) }
  def round_down_to_whole_dollar_amount_in_cents(amount_in_cents)
    # Patreon allows non-whole-dollar amounts whereas GitHub Sponsors requires whole-dollar amounts, so shave off
    # the extra cents:
    extra_cents = amount_in_cents % 100
    amount_in_cents - extra_cents # e.g., 225 => 200 for $2.00
  end

  sig { returns Integer }
  memoize def maintainer_min_amount_in_cents
    sponsors_listing&.min_custom_tier_amount_in_cents || SponsorsTier::MIN_PRICE_IN_CENTS
  end
end
