# typed: true
# frozen_string_literal: true

require "test_helper"

class Sponsors::TierSuggestionTest < GitHub::TestCase
  fixtures do
    @draft_listing = create(:sponsors_listing, :draft, tier_count: 0)
    @inspiring_user = create(:user)
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
            monthly_price_in_cents: 3_00,
            description: "3 a month"
          },
          {
            frequency: :one_time,
            monthly_price_in_cents: 4_00,
            description: "4 one time"
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
            monthly_price_in_cents: 1_00,
            description: "1 one time"
          },
          {
            frequency: :recurring,
            monthly_price_in_cents: 2_00,
            description: "2 a month"
          },
          {
            frequency: :recurring,
            monthly_price_in_cents: 5_00,
            description: "5 a month"
          },
        ]
      },
    ])
  end

  context "#amount" do
    test "returns a whole dollar amount for the tier" do
      tier_suggestions = Sponsors::TierSuggestion.for_frequency(:recurring)
      refute_empty tier_suggestions
      tier_suggestions.each do |tier_suggestion|
        expected_amount = tier_suggestion.monthly_price_in_cents / 100
        assert_equal expected_amount, tier_suggestion.amount
      end
    end
  end

  context "#recurring?" do
    test "returns whether the tier recurs every month or not" do
      tier_suggestions = Sponsors::TierSuggestion.for_frequency(:recurring)
      refute_empty tier_suggestions
      tier_suggestions.each do |tier_suggestion|
        assert_predicate tier_suggestion, :recurring?
      end

      tier_suggestions = Sponsors::TierSuggestion.for_frequency(:one_time)
      refute_empty tier_suggestions
      tier_suggestions.each do |tier_suggestion|
        refute_predicate tier_suggestion, :recurring?
      end
    end
  end

  context ".inspiring_users" do
    test "returns inspiring users" do
      Sponsors::TierSuggestion::Data.stubs(:inspiring_users).returns(
        [@inspiring_user.login]
      )
      inspiring_users = Sponsors::TierSuggestion.inspiring_users
      assert_equal 1, inspiring_users.count
      assert_equal @inspiring_user.login, inspiring_users.first.login
    end

    test "omits nonexistent inspiring users" do
      Sponsors::TierSuggestion::Data.stubs(:inspiring_users).returns(
        [@inspiring_user.login, "missingno"]
      )
      inspiring_users = Sponsors::TierSuggestion.inspiring_users
      assert_equal 1, inspiring_users.count
      assert_equal @inspiring_user.login, inspiring_users.first.login
    end

    test "returns correct number of inspiring users" do
      limit = 1
      users = create_list(:user, limit + 1)
      Sponsors::TierSuggestion::Data.stubs(:inspiring_users).returns(users.map(&:login))
      Sponsors::TierSuggestion.stub_const(:INSPIRING_USER_DISPLAY_COUNT, limit) do
        inspiring_users = Sponsors::TierSuggestion.inspiring_users
        assert_equal limit, inspiring_users.count
      end
    end
  end

  test "returns all tiers" do
    stub_data
    tiers = Sponsors::TierSuggestion.all
    assert_equal 5, tiers.count
  end

  test "#for_frequency returns recurring tiers" do
    stub_data
    tiers = Sponsors::TierSuggestion.for_frequency(:recurring)
    assert_equal 3, tiers.count
    assert tiers.all? { |tier| tier.frequency == :recurring }
  end

  test "#for_category returns test1 category tiers" do
    stub_data
    tiers = Sponsors::TierSuggestion.for_category(:test1)
    assert_equal 2, tiers.count
    assert tiers.all? { |tier| tier.category == :test1 }
  end

  test "returns emoji alias" do
    stub_data
    assert_equal :smile, Sponsors::TierSuggestion.emoji_alias(category: :test2)
  end
end unless GitHub.enterprise?
