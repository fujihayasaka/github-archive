# typed: true
# frozen_string_literal: true

require "test_helper"

class Sponsors::CreateTiersFromSuggestionsTest < GitHub::TestCase
  fixtures do
    @draft_listing = create(:sponsors_listing, :draft, tier_count: 0)
  end

  def stub_data
    Sponsors::TierSuggestion::Data.stubs(:categorized).returns([
      {
        category: :test1,
        emoji_alias: :tada,
        tiers: [
          {
            preselect: true,
            frequency: :recurring,
            monthly_price_in_cents: 5_00,
            description: "test1 5 a month"
          },
          {
            frequency: :one_time,
            monthly_price_in_cents: 5_00,
            description: "test1 5 one time"
          }
        ]
      },
      {
        category: :test2,
        emoji_alias: :smile,
        tiers: [
          {
            preselect: true,
            frequency: :one_time,
            monthly_price_in_cents: 5_00,
            description: "test2 5 one time"
          },
          {
            frequency: :recurring,
            monthly_price_in_cents: 10_00,
            description: "test2 10 a month"
          }
        ]
      },
    ])
  end

  test "all data is valid" do
    tier_suggestions = Sponsors::TierSuggestion.all

    refute_empty tier_suggestions

    tier_suggestions.each do |tier_suggestion|
      assert_difference -> { @draft_listing.sponsors_tiers.count } do
        Sponsors::CreateTiersFromSuggestions.call(input_ids: [tier_suggestion.input_id],
          creator: @draft_listing.sponsorable,
          listing: @draft_listing
        )
      end
    end
  end

  context "tier coalescing" do
    test "two suggestions with same amount/frequency create single tier" do
      stub_data
      tier_suggestions = Sponsors::TierSuggestion.all.select do |tier_suggestion|
        tier_suggestion.frequency == :one_time && tier_suggestion.monthly_price_in_cents == 5_00
      end

      assert_equal 2, tier_suggestions.count

      assert_difference -> { @draft_listing.sponsors_tiers.count } do
        Sponsors::CreateTiersFromSuggestions.call(input_ids: tier_suggestions.map(&:input_id),
          creator: @draft_listing.sponsorable,
          listing: @draft_listing
        )
      end

      expected_description = "<p>test1 5 one time<br>\ntest2 5 one time</p>"
      assert_equal expected_description, @draft_listing.sponsors_tiers.first.description_html
    end

    test "two suggestions with different frequencies create two tiers" do
      stub_data
      tier_suggestion1 = Sponsors::TierSuggestion.all.find do |tier_suggestion|
        tier_suggestion.description == "test1 5 one time"
      end

      tier_suggestion2 = Sponsors::TierSuggestion.all.find do |tier_suggestion|
        tier_suggestion.description == "test1 5 a month"
      end

      assert tier_suggestion1
      assert tier_suggestion2

      tier_suggestions = [tier_suggestion1, tier_suggestion2]

      assert_difference -> { @draft_listing.sponsors_tiers.count } => 2 do
        Sponsors::CreateTiersFromSuggestions.call(input_ids: tier_suggestions.map(&:input_id),
          creator: @draft_listing.sponsorable,
          listing: @draft_listing
        )
      end
    end

    test "two suggestions with different amounts create two tiers" do
      stub_data
      tier_suggestion1 = Sponsors::TierSuggestion.all.find do |tier_suggestion|
        tier_suggestion.description == "test1 5 a month"
      end

      tier_suggestion2 = Sponsors::TierSuggestion.all.find do |tier_suggestion|
        tier_suggestion.description == "test2 10 a month"
      end

      assert tier_suggestion1
      assert tier_suggestion2

      tier_suggestions = [tier_suggestion1, tier_suggestion2]

      assert_difference -> { @draft_listing.sponsors_tiers.count } => 2 do
        Sponsors::CreateTiersFromSuggestions.call(input_ids: tier_suggestions.map(&:input_id),
          creator: @draft_listing.sponsorable,
          listing: @draft_listing
        )
      end
    end
  end
end unless GitHub.enterprise?
