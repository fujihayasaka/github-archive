# typed: true
# frozen_string_literal: true

require "test_helper"

class Marketplace::Payloads::IndexTest < GitHub::TestCase
  fixtures do
    setup_search
    @user = create(:user)
    @newest_listing = create(:marketplace_listing, :verified)
    @older_listing = create(:marketplace_listing, :verified, created_at: 1.year.ago)
    @copilot_listing = create(:marketplace_listing, :verified, copilot_app: true, listable: create(:integration, owner: @user), created_at: 1.month.ago)
    @marketplace_listing_recommendation = create(:marketplace_listing, :verified, :verified_publisher, created_at: 1.month.ago)
    @action = create(:repository_action, :verified, :listed, name: "Verified Acme Actions", created_at: 1.month.ago)
    @copilot_listing_two = create(:marketplace_listing, :verified, copilot_app: true, listable: create(:integration, owner: @user), created_at: 1.month.ago)
    @installation = create(:integration_installation, integration_id: @copilot_listing_two.listable_id, created_at: 20.days.ago)
  end

  setup do
    Marketplace::KV.store.set("marketplace/recommendations", [@marketplace_listing_recommendation.id].to_json)
    make_searchable(@newest_listing, type: "marketplace_listing")
    make_searchable(@older_listing, type: "marketplace_listing")
    make_searchable(@copilot_listing, type: "marketplace_listing")
    make_searchable(@copilot_listing_two, type: "marketplace_listing")
    make_searchable(@marketplace_listing_recommendation, type: "marketplace_listing")
    make_searchable(@action, type: "repository_action")
    Marketplace::Payloads::Categories.any_instance.stubs(:call).returns({
      apps: [{ name: "Mock Category", slug: "mock-category", description_html: "<p>Mock Description</p>" }],
      actions: [],
    })
  end

  def payload(params = {})
    Marketplace::Payloads::IndexHelper.stub_const(:PER_PAGE, 1) do
      Marketplace::Payloads::Index.new(current_user: @user,
                                       params: ActionController::Parameters.new(params),
                                       is_eu_request: false).call
    end
  end

  context "#call" do
    context "when not searching" do
      test "returns copilot listings for featured, sorted by last month popularity" do
        data = payload

        assert_equal 2, data[:featured].count
        assert_equal @copilot_listing_two.id, data[:featured].first[:id]
        assert_equal @copilot_listing_two.name, data[:featured].first[:name]
      end

      test "returns listings from marketplace/recommendations for recommended" do
        data = payload

        assert_equal @marketplace_listing_recommendation.id, data[:recommended].first[:id]
        assert_equal @marketplace_listing_recommendation.name, data[:recommended].first[:name]
      end

      test "returns the most recent listings for recentlyAdded" do
        data = payload

        assert_equal @newest_listing.id, data[:recentlyAdded].first[:id]
        assert_equal @newest_listing.name, data[:recentlyAdded].first[:name]
      end

      test "returns empty for searchResults" do
        data = payload

        assert_equal [], data[:searchResults][:results]
        assert_equal 0, data[:searchResults][:total]
        assert_equal 0, data[:searchResults][:totalPages]
      end

      test "returns categories" do
        assert_equal "Mock Category", payload.dig(:categories, :apps).first[:name]
      end
    end

    context "when searching" do
      test "returns empty for featured, recommended, and recentlyAdded" do
        data = payload({ query: @older_listing.name })

        assert_equal [], data[:featured]
        assert_equal [], data[:recommended]
        assert_equal [], data[:recentlyAdded]
      end

      test "returns apps in searchResults" do
        data = payload({ query: @older_listing.name })

        assert_equal @older_listing.id, data[:searchResults][:results].first[:id]
        assert_equal @older_listing.name, data[:searchResults][:results].first[:name]
        assert_equal 1, data[:searchResults][:total]
        assert_equal 1, data[:searchResults][:totalPages]
      end

      test "returns actions in searchResults" do
        data = payload({ query: @action.name })

        assert_equal @action.id, data[:searchResults][:results].first[:id].to_i
        assert_equal @action.name, data[:searchResults][:results].first[:name]
        assert_equal 1, data[:searchResults][:total]
        assert_equal 1, data[:searchResults][:totalPages]
      end

      test "returns categories" do
        assert_equal "Mock Category", payload({ query: @older_listing.name }).dig(:categories, :apps).first[:name]
      end
    end
  end
end unless GitHub.enterprise?
