# typed: true
# frozen_string_literal: true

require "test_helper"

class SiteContentfulNewsroomPagesCategoryPageTest < GitHub::TestCase
  require_cassettes_for_external_http_connections

  setup do
    skip if GitHub.enterprise?
    @url = "/newsroom/press-releases"
    @features = "contentful_lp_should_not_render"

    @category_page = Site::Contentful::Marketing::Newsroom::Pages::CategoryPage.new
    @category_page_2 = Site::Contentful::Marketing::Newsroom::Pages::CategoryPage.new(page: 2)
  end

  context "#fetch_data_from_contentful" do
    test "returns the right number of results from Contentful" do
      VCR.use_cassette("contentful/newsroom/pages/category-page") do
        assert_instance_of(Hash, @category_page.view_data)
        assert_equal(@category_page.view_data[:contentful_raw_json_response]["items"].size, 21)
      end
    end

    test "returns something that can be converted into JSON inside the contentful_raw_json_response" do
      VCR.use_cassette("contentful/newsroom/pages/category-page") do
        assert_nothing_raised do
          JSON.parse(@category_page.view_data[:contentful_raw_json_response].to_json)
        end
      end
    end

    test "confirm that only expected entries appear in contentful_response" do
      VCR.use_cassette("contentful/newsroom/pages/category-page") do
        entry_ids = []

        entries = @category_page.view_data[:contentful_raw_json_response]["includes"]["Entry"]
        entries.each do |entry|
          entry_ids.push(entry["sys"]["contentType"]["sys"]["id"]) if !entry_ids.include?(entry["sys"]["contentType"]["sys"]["id"])
        end

        %w[newsroomTemplateCategory pageSeo pageSettings templateResourcesArticle].each do |expected_id|
          assert_includes(entry_ids, expected_id)
        end
      end
    end
  end

  context "filter_hidden_pages" do
    test "removes feature flagged items from the contentful_response" do
      VCR.use_cassette("contentful/newsroom/pages/category-page") do
        @category_page.filter_hidden_pages { |flag| flag == @features }

        assert_equal(@category_page.view_data[:contentful_raw_json_response]["items"].size, 3)
      end
    end

    test "include feature flagged items to the contentful_response" do
      VCR.use_cassette("contentful/newsroom/pages/category-page") do
        @category_page.filter_hidden_pages { |flag| flag != @features }

        assert_equal(@category_page.view_data[:contentful_raw_json_response]["items"].size, 21)
      end
    end
  end

  context "apply_pagination" do
    test "truncates results to 15 plus container" do
      VCR.use_cassette("contentful/newsroom/pages/category-page") do

        @category_page.apply_pagination

        assert_equal(@category_page.view_data[:contentful_raw_json_response]["items"].size, 16)
      end
    end

    test "truncates to 5 results plus container for the second page" do
      VCR.use_cassette("contentful/newsroom/pages/category-page") do
        @category_page_2.apply_pagination

        assert_equal(@category_page_2.view_data[:contentful_raw_json_response]["items"].size, 6)
      end

    end
  end
end
