# typed: true
# frozen_string_literal: true

require "test_helper"

class Marketplace::Payloads::SearchTest < GitHub::TestCase
  fixtures do
    setup_search
    @user = create(:user)
    @newest_listing = create(:marketplace_listing, :verified)
    @older_listing = create(:marketplace_listing, :verified, created_at: 1.year.ago)
    @copilot_listing = create(:marketplace_listing, :verified, copilot_app: true, listable: create(:integration, owner: @user), created_at: 1.month.ago)
    @action = create(:repository_action, :verified, :listed, created_at: 1.month.ago)
    @category = create(:marketplace_category, navigation_visible: true, listings: [@newest_listing])
  end

  setup do
    make_searchable(@newest_listing, type: "marketplace_listing")
    make_searchable(@older_listing, type: "marketplace_listing")
    make_searchable(@copilot_listing, type: "marketplace_listing")
    make_searchable(@action, type: "repository_action")
    Marketplace::Payloads::Categories.any_instance.stubs(:call).returns({
      apps: [{ name: "Mock Category", slug: "mock-category", description_html: "<p>Mock Description</p>" }],
      actions: [],
    })
  end

  def payload(params: {}, page_size: 1)
    Marketplace::Payloads::IndexHelper.stub_const(:PER_PAGE, page_size) do
      Marketplace::Payloads::Search.new(current_user: @user, params: ActionController::Parameters.new(params)).call
    end
  end

  context "#call" do
    test "queries apps by name" do
      data = payload(params: { query: @older_listing.name })

      assert_equal @older_listing.id, data[:results].first[:id]
      assert_equal @older_listing.name, data[:results].first[:name]
      assert_equal 1, data[:total]
      assert_equal 1, data[:totalPages]
    end

    test "queries actions by name" do
      data = payload(params: { query: @action.name })

      assert_equal @action.id, data[:results].first[:id].to_i
      assert_equal @action.name, data[:results].first[:name]
      assert_equal 1, data[:total]
      assert_equal 1, data[:totalPages]
    end

    test "returns sorted results" do
      data = payload(params: { query: "sort:created-desc" })

      assert_equal @newest_listing.id, data[:results].first[:id].to_i
      assert_equal @newest_listing.name, data[:results].first[:name]
      assert_equal 4, data[:total]
    end

    test "filters by category" do
      data = payload(params: { category: @category.slug, type: "apps" })

      # @newest_listing is the only listing created with the category
      assert_equal @newest_listing.id, data[:results].first[:id].to_i
      assert_equal @newest_listing.name, data[:results].first[:name]
      assert_equal 1, data[:total]
    end

    test "filters by apps" do
      data = payload(params: { type: "apps" }, page_size: 10)

      app_ids = data[:results].map { |result| result[:id].to_i }
      assert_includes app_ids, @newest_listing.id
      assert_includes app_ids, @older_listing.id
      assert_includes app_ids, @copilot_listing.id
      assert_equal 3, data[:total]
    end

    test "filters by actions" do
      data = payload(params: { type: "actions" })

      assert_equal @action.id, data[:results].first[:id].to_i
      assert_equal @action.name, data[:results].first[:name]
      assert_equal 1, data[:total]
    end

    test "filters by copilot apps" do
      data = payload(params: { type: "apps", copilot_app: "true" })

      assert_equal @copilot_listing.id, data[:results].first[:id].to_i
      assert_equal @copilot_listing.name, data[:results].first[:name]
      assert_equal 1, data[:total]
    end

    context "when search params are not present" do
      test "returns null results" do
        Search::Queries::MarketplaceQuery.expects(:new).never
        data = payload

        assert_equal [], data[:results]
        assert_equal 0, data[:total]
        assert_equal 0, data[:totalPages]
      end
    end
  end
end unless GitHub.enterprise?
