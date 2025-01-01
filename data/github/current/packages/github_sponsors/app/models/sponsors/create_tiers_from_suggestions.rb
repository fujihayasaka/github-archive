# typed: true
# frozen_string_literal: true

class Sponsors::CreateTiersFromSuggestions
  # input_ids - Array of suggestion tier input_ids to create.
  # listing - The SponsorsListing for the tiers.
  # creator - The User creating the tiers.
  def self.call(input_ids:, listing:, creator:)
    new(input_ids: input_ids, listing: listing, creator: creator).call
  end

  def initialize(input_ids:, listing:, creator:)
    @input_ids = input_ids
    @listing = listing
    @creator = creator
  end

  def call
    tier_ids_set = Set[*@input_ids]
    to_create = Sponsors::TierSuggestion.all.select { |tier| tier_ids_set.include?(tier.input_id) }
    to_create.group_by(&:name).each do |_tier_name, tier_suggestions|
      tier_suggestion = tier_suggestions.first
      Sponsors::CreateSponsorsTier.call(
        custom: false,
        sponsors_listing: @listing,
        description: tier_suggestions.map(&:description).join("\n"),
        amount: tier_suggestion.amount,
        viewer: @creator,
        is_recurring: tier_suggestion.recurring?,
      )
    end
  end
end
