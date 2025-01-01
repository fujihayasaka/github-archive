# typed: true
# frozen_string_literal: true

require "test_helper"

class SiteContentfulResourcesWhitepaperPagesIndexPageTest < GitHub::TestCase
  require_cassettes_for_external_http_connections

  setup do
    skip if GitHub.enterprise?
    @url = "/resources/whitepapers"
    @features = "contentful_lp_whitepapers"

    @index_page = Site::Contentful::Marketing::Resources::Pages::Whitepapers::IndexPage.new
    @index_page_4 = Site::Contentful::Marketing::Resources::Pages::Whitepapers::IndexPage.new(page: "4")
  end

  context "#fetch_data_from_contentful" do
    test "returns the right number of results from Contentful" do
      VCR.use_cassette("contentful/resources/pages/whitepaper/index-page") do
        assert_instance_of(Hash, @index_page.view_data)
        assert_equal(@index_page.view_data[:contentful_raw_json_response]["items"].size, 40)
      end
    end

    test "returns something that can be converted into JSON inside the contentful_raw_json_response" do
      VCR.use_cassette("contentful/resources/pages/whitepaper/index-page") do
        assert_nothing_raised do
          JSON.parse(@index_page.view_data[:contentful_raw_json_response].to_json)
        end
      end
    end

    test "confirm that only expected entries appear in contentful_response" do
      VCR.use_cassette("contentful/resources/pages/whitepaper/index-page") do
        expected_content_types = %w[templateWhitepaperIndex pageSeo pageSettings templateWhitepaper]
        included_entries = @index_page.view_data[:contentful_raw_json_response]["includes"]["Entry"]
        included_entry_ids = included_entries.map { |entry| entry["sys"]["contentType"]["sys"]["id"] }.uniq
        assert_equal expected_content_types.sort, included_entry_ids.sort
      end
    end

    test "returns template data in correct format with unneeded data removed" do
      VCR.use_cassette("contentful/resources/pages/whitepaper/index-page") do
        @index_page.view_data[:contentful_raw_json_response]["includes"]["Entry"].each do |entry|
          next unless entry["sys"]["contentType"]["sys"]["id"] == "templateWhitepaper"
          assert_includes entry["fields"], "heading"
          assert_includes entry["fields"], "contentType"
          assert_includes entry["fields"], "topics"
          assert_includes entry["fields"], "excerpt"
          assert_includes entry["fields"], "publishedDate"
          refute_includes entry["fields"], "title"
          refute_includes entry["fields"], "lede"
          refute_includes entry["fields"], "body"
          refute_includes entry["fields"], "form"
          refute_includes entry["fields"], "downloadableAsset"
          refute_includes entry["fields"], "downloadableAssetUrl"
          refute_includes entry["fields"], "downloadableAssetCta"
          refute_includes entry["fields"], "confirmationCtaDescription"
          refute_includes entry["fields"], "relatedResources"
        end
      end
    end
  end

  context "filter_hidden_pages" do
    test "removes feature flagged items from the contentful_response" do
      VCR.use_cassette("contentful/resources/pages/whitepaper/index-page") do
        @index_page.filter_hidden_pages { |flag| flag == @features }

        assert_equal(@index_page.view_data[:contentful_raw_json_response]["items"].size, 0)
      end
    end

    test "include feature flagged items to the contentful_response" do
      VCR.use_cassette("contentful/resources/pages/whitepaper/index-page") do
        @index_page.filter_hidden_pages { |flag| flag != @features }

        assert_equal(@index_page.view_data[:contentful_raw_json_response]["items"].size, 40)
      end
    end
  end

  context "apply_pagination" do
    test "truncates results to 12 plus container" do
      VCR.use_cassette("contentful/resources/pages/whitepaper/index-page") do
        @index_page.apply_pagination

        assert_equal(@index_page.view_data[:contentful_raw_json_response]["items"].size, 13)
      end
    end

    test "truncates to 3 results plus container for the second page" do
      VCR.use_cassette("contentful/resources/pages/whitepaper/index-page") do
        @index_page_4.apply_pagination

        assert_equal(@index_page_4.view_data[:contentful_raw_json_response]["items"].size, 4)
      end
    end
  end
end
