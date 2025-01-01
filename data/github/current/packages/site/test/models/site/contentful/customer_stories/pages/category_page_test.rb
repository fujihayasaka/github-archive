# typed: true
# frozen_string_literal: true

require "test_helper"

class Site::Contentful::CustomerStories::Pages::CategoryPageTest < GitHub::TestCase
  require_cassettes_for_external_http_connections

  setup do
    skip if GitHub.enterprise?

    @category_page_content = VCR.use_cassette("contentful/customer-stories-enterprise-content") do
      Site::Contentful::CustomerStories::CategoryPage.content("enterprise")
    end

    @category_page_stories = VCR.use_cassette("contentful/customer-stories-enterprise-stories") do
      Site::Contentful::CustomerStories::CustomerStory.find_stories_by_category(Site::Contentful::CustomerStories::Categories::ENTERPRISE)
    end

    @category_page = Site::Contentful::CustomerStories::Pages::CategoryPage.new(category_id: "enterprise")

    @category_page_for_non_existant_category = Site::Contentful::CustomerStories::Pages::CategoryPage.new(category_id: "non-existant-category")
  end

  context "#fetch_data_from_contentful" do
    test "returns a blank result if the category is not found" do
      VCR.use_cassette("contentful/customer-stories-show-page-non-existant-category") do
        result = @category_page_for_non_existant_category.fetch_data_from_contentful

        assert_nil result[:page_data]
        assert_empty result[:stories]
        assert_equal 0, result[:total_stories]
      end
    end

    test "returns page data and stories" do
      VCR.use_cassette("contentful/customer-stories-show-page-for-category") do
        expected_stories = @category_page_stories.map(&:preview_json)

        result = @category_page.fetch_data_from_contentful

        assert_equal @category_page_content.to_json, result[:page_data]
        assert_equal 106, result[:total_stories]

        # todo: add this assertion back once we figure out best way to consistently test Contentful data
        # assert_equal expected_stories, result[:stories]
      end
    end

    test "limits number of stories to 12" do
      VCR.use_cassette("contentful/customer-stories-show-page-for-category") do
        assert_equal 12, @category_page.fetch_data_from_contentful[:stories].count
      end
    end

    test "applies filters to the fetched stories" do
      VCR.use_cassette("contentful/customer-stories-category-page-with-filters") do
        page = Site::Contentful::CustomerStories::Pages::CategoryPage.new(category_id: "enterprise", industry_filters: "Government", regions: "Americas")

        assert_equal 3, page.fetch_data_from_contentful[:stories].count
      end
    end
  end

  context "#cache_key" do
    test "builds the right cache key" do
      assert_equal "site.swp.customer_stories.category.enterprise.staff:false", @category_page.cache_key

      category_page_for_staff = Site::Contentful::CustomerStories::Pages::CategoryPage.new(category_id: "enterprise", for_staff: true)

      assert_equal "site.swp.customer_stories.category.enterprise.staff:true", category_page_for_staff.cache_key
    end
  end

  context "#skip_cache?" do
    test "returns true if there are filter options" do
      page = Site::Contentful::CustomerStories::Pages::CategoryPage.new(category_id: "enterprise", industry_filters: "Finance")

      assert page.skip_cache?
    end
  end
end
