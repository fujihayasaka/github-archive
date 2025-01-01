# typed: true
# frozen_string_literal: true

# Public: Calculate how much sponsors have paid to maintainers total, across multiple sponsorships and one-time
# payments. Does not include sponsors who paid via Patreon.
class Sponsors::LifetimeSponsorshipValuesLoader
  extend T::Sig
  include GitHub::Memoizer

  # Public: Calculate lifetime sponsorship values the specified maintainers (sponsorables) have received. Only those
  # maintainers that are the viewer themselves or are an organization the viewer owns will be included.
  #
  # sponsorable_ids - IDs of the User and Organization maintainers to check
  # viewer - the currently authenticated user or integration, if any
  #
  # Returns a hash whose keys are the given sponsorable IDs and whose values are a hash of
  # [sponsoring user/org ID] => [total lifetime amount paid to the sponsorable by that sponsor].
  sig do
    params(
      sponsorable_ids: T::Array[Integer],
      viewer: T.nilable(T.any(User, Bot))
    ).returns(T::Hash[Integer, T::Hash[Integer, Billing::Money]])
  end
  def self.call(sponsorable_ids:, viewer:)
    new(sponsorable_ids: sponsorable_ids, viewer: viewer).call
  end

  sig { params(sponsorable_ids: T::Array[Integer], viewer: T.nilable(T.any(User, Bot))).void }
  def initialize(sponsorable_ids:, viewer:)
    @sponsorable_ids = sponsorable_ids
    @viewer = viewer
  end

  sig { returns T::Hash[Integer, T::Hash[Integer, Billing::Money]] }
  def call
    allowed_sponsorable_ids.each_with_object({}) do |sponsorable_id, hash|
      hash[sponsorable_id] = amounts_by_sponsor_id_for_sponsorable(sponsorable_id)
    end
  end

  private

  sig { returns T::Array[Integer] }
  attr_reader :sponsorable_ids

  sig { returns T.nilable(T.any(User, Bot)) }
  attr_reader :viewer

  sig { returns T::Set[Integer] }
  memoize def allowed_sponsorable_ids
    return Set.new unless viewer
    return Set.new unless GitHub.sponsors_enabled?

    # Easiest to just limit based on the sponsorable, rather than filtering line items, sponsorships, etc based on who
    # the sponsor is. Use User#async_total_funded_via_github_sponsors to load the total amount for a particular
    # sponsor.
    allowed_ids = T.must(viewer).owned_organization_ids + [T.must(viewer).id]
    sponsorable_ids.to_set & allowed_ids.to_set
  end

  sig { params(sponsorable_id: Integer).returns(T::Hash[Integer, Billing::Money]) }
  def amounts_by_sponsor_id_for_sponsorable(sponsorable_id)
    sponsor_ids_for_sponsorable(sponsorable_id).each_with_object(Hash.new(Billing::Money.zero)) do |sponsor_id, hash|
      alternate_sponsor_id = linked_org_ids_by_sponsor_id[sponsor_id]
      key = alternate_sponsor_id || sponsor_id
      amount = amount_for_sponsorable_from_sponsor(sponsor_id, sponsorable_id: sponsorable_id)
      if amount > 0
        hash[key] = amount
      end
    end
  end

  sig { params(paying_sponsor_id: Integer, sponsorable_id: Integer).returns(Billing::Money) }
  def amount_for_sponsorable_from_sponsor(paying_sponsor_id, sponsorable_id:)
    sponsorable_ledger_entries = ledger_entries_for_sponsorable(sponsorable_id)
    alternate_sponsor_id = linked_org_ids_by_sponsor_id[paying_sponsor_id]
    sponsor_ids = [paying_sponsor_id, alternate_sponsor_id].compact

    sponsor_ids.inject(Billing::Money.zero) do |sum, sponsor_id|
      sponsor_ledger_entries = ledger_entries_from_sponsor(sponsorable_ledger_entries, sponsor_id)
      sum + ledger_entry_total(sponsor_ledger_entries)
    end
  end

  sig { returns T::Hash[Integer, T::Set[Integer]] }
  memoize def sponsor_ids_by_sponsorable_id
    result = T.let({}, T::Hash[Integer, T::Set[Integer]])

    ledger_entries_by_sponsorable_id.each do |sponsorable_id, ledger_entries|
      sponsor_ids = ledger_entries.map(&:billing_transaction_user_id).uniq.compact
      result[sponsorable_id] = sponsor_ids.to_set
    end

    # Find spammy sponsors that the viewer shouldn't see:
    all_sponsor_ids = result.values.inject(Set.new, :|)
    visible_sponsor_ids = T.let(
      User.where(id: all_sponsor_ids).filter_spam_for(viewer).pluck(:id).to_set,
      T::Set[Integer],
    )

    # Filter out spammy sponsors for each sponsorable:
    result.each do |sponsorable_id, sponsor_ids|
      result[sponsorable_id] = sponsor_ids & visible_sponsor_ids
    end

    result
  end

  sig { params(sponsorable_id: Integer).returns(T::Set[Integer]) }
  def sponsor_ids_for_sponsorable(sponsorable_id)
    sponsor_ids_by_sponsorable_id[sponsorable_id] || Set.new
  end

  sig do
    params(
      ledger_entries: T::Array[Billing::PayoutsLedgerEntry],
      sponsor_id: Integer
    ).returns(T::Array[Billing::PayoutsLedgerEntry])
  end
  def ledger_entries_from_sponsor(ledger_entries, sponsor_id)
    ledger_entries.select { |ledger_entry| ledger_entry.billing_transaction_user_id == sponsor_id }
  end

  sig { returns T::Array[SponsorsListing] }
  memoize def sponsors_listings
    SponsorsListing.for_sponsorable_user_or_org(allowed_sponsorable_ids).to_a
  end

  sig { returns T::Array[Integer] }
  def sponsors_listing_ids
    sponsors_listings.map { |listing| T.must(listing.id) }
  end

  sig { params(ledger_entries: T::Array[Billing::PayoutsLedgerEntry]).returns(Billing::Money) }
  def ledger_entry_total(ledger_entries)
    ledger_entries.inject(Billing::Money.zero) do |total, ledger_entry|
      total + ledger_entry.to_money.exchange_to(Billing::Money.default_currency)
    end
  end

  sig { returns(T::Hash[Integer, Integer]) }
  memoize def linked_org_ids_by_sponsor_id
    OrganizationProfile.for_sponsoring_linked_org(sponsor_ids_for_all_sponsorables)
      .pluck(:sponsoring_linked_organization_id, :organization_id).to_h
  end

  sig { returns T::Array[Integer] }
  def sponsor_ids_for_all_sponsorables
    sponsor_ids_by_sponsorable_id.values.flat_map(&:to_a).uniq
  end

  sig { returns T::Array[Billing::PayoutsLedgerEntry] }
  memoize def ledger_entries
    result = Billing::PayoutsLedgerEntry.net_transfers_with_matches.for_sponsors_listing(sponsors_listing_ids)
      .includes(:billing_transaction).to_a
    GitHub::PrefillAssociations.prefill_associations(result, :sponsors_listing, available_records: sponsors_listings)
    result
  end

  sig { returns T::Hash[Integer, T::Array[Billing::PayoutsLedgerEntry]] }
  memoize def ledger_entries_by_sponsorable_id
    ledger_entries.each_with_object({}) do |ledger_entry, hash|
      sponsorable_id = ledger_entry.sponsorable_id
      hash[sponsorable_id] ||= []
      hash[sponsorable_id] << ledger_entry
    end
  end

  sig { params(sponsorable_id: Integer).returns(T::Array[Billing::PayoutsLedgerEntry]) }
  def ledger_entries_for_sponsorable(sponsorable_id)
    ledger_entries_by_sponsorable_id[sponsorable_id] || []
  end
end
