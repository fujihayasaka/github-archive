# typed: true
# frozen_string_literal: true

require "test_helper"

class SiteContentfulResourcePagesCategoryPageTest < GitHub::TestCase
  require_cassettes_for_external_http_connections

  setup do
    skip if GitHub.enterprise?
    @topic = "devops"
    @page = "1"
    @url = "/resources/articles/devops"

    @topic_alt = "software-development"
    @url_alt = "/resources/articles/software-development"
    @all_topics_url = "/resources/articles"

    @category_page = VCR.use_cassette("contentful/resources/pages/category-page/devops") do
      Site::Contentful::Marketing::Resources::Pages::Articles::CategoryPage.new(topic: @topic, page: @page, url: @url)
    end

    @category_page_alt = VCR.use_cassette("contentful/resources/pages/category-page/software-development") do
      Site::Contentful::Marketing::Resources::Pages::Articles::CategoryPage.new(topic: @topic_alt, page: @page, url: @url_alt)
    end

    @all_topics_index = VCR.use_cassette("contentful/resources/pages/category-page/all-topics") do
      Site::Contentful::Marketing::Resources::Pages::Articles::CategoryPage.new(topic: "", page: @page, url: @all_topics_url)
    end
  end

  context "#fetch_data_from_contentful" do
    test "returns the right number of results from Contentful" do
      assert_equal("DevOps", @category_page.topic_name)
      assert_instance_of(Hash, @category_page.contentful_response)
      assert_equal(1, @category_page.contentful_response["items"].size)
    end

    test "returns something that can be converted into JSON inside the contentful_raw_json_response" do
      assert_nothing_raised do
        JSON.parse(@category_page.contentful_response.to_json)
      end
    end

    test "confirm that only expected entries appear in contentful_response" do
      entry_ids = []

      entries = @category_page_alt.contentful_response["includes"]["Entry"]
      entries.each do |entry|
        entry_ids.push(entry["sys"]["contentType"]["sys"]["id"])
      end

      assert_equal(%w[backgroundImage pageSeo pageSettings templateResourcesArticle], entry_ids.sort)
    end

    # These assertions only run if the previous test was successful
    test "returns template data in correct format with unneeded data removed" do
      (@category_page_alt.contentful_response.dig("includes", "Entry")).each do |entry|
        next unless entry["sys"]["contentType"]["sys"]["id"] == "templateResourcesArticle"

        assert_equal("What is a programming language?", entry["fields"]["title"])
        assert_equal({
          "data" => {},
          "content" => [{
            "data" => {},
            "content" => [{
              "data" => {},
              "marks" => [],
              "value" => "A programming language is a set of instructions that enables humans to communicate commands to a computer in software development.",
              "nodeType" => "text"
            }],
            "nodeType" => "paragraph"
          }],
          "nodeType" => "document"
        }, entry["fields"]["excerpt"])
        assert_equal({
          "sys" => {
            "type" => "Link",
            "linkType" => "Entry",
            "id" => "4K9ztlAw2RtEvU5E6dcUYi"
          }
        }, entry["fields"]["heroBackgroundImage"])
      end
    end

    test "returns empty contentful_response[\"items\"] if topic does not have any items" do
      VCR.use_cassette("contentful/resources/pages/category-page/test-internal-only") do
        page = Site::Contentful::Marketing::Resources::Pages::Articles::CategoryPage.new(topic: "test-internal-only", page: @page, url: "/resources/articles/test-internal-only")

        assert_nil(page.total_pages)
        assert_equal([], page.contentful_response["items"])
      end
    end
  end

  context "filter_hidden_pages" do
    test "include feature flagged items to the contentful_response" do
      VCR.use_cassette("contentful/resources/pages/category-page/ai") do
        page = Site::Contentful::Marketing::Resources::Pages::Articles::CategoryPage.new(topic: "ai", page: @page, url: "/resources/articles/ai")

        # include pages that have a feature flag that was passed in
        page.filter_hidden_pages! { |flag| flag == "contentful_lp_ai" }
        assert_equal(16, page.contentful_response["items"].size)
      end
    end
  end

  context "apply_pagination" do
    test "paginates the contentful_response for page 1" do
      VCR.use_cassette("contentful/resources/pages/category-page/ai") do
        page = Site::Contentful::Marketing::Resources::Pages::Articles::CategoryPage.new(topic: "ai", page: @page, url: "/resources/articles/ai")

        page.filter_hidden_pages! { |flag| flag == "contentful_lp_ai" }

        page.apply_pagination!

        assert_equal(2, page.total_pages)
        assert_equal(1, page.page_number)
        assert_equal(12, page.contentful_response["items"].size)
      end
    end

    test "paginates the contentful_response for page 2" do
      VCR.use_cassette("contentful/resources/pages/category-page/ai") do
        page = Site::Contentful::Marketing::Resources::Pages::Articles::CategoryPage.new(topic: "ai", page: "2", url: "/resources/articles/ai")

        page.apply_pagination!

        assert_equal(2, page.total_pages)
        assert_equal(2, page.page_number)
        assert_equal(5, page.contentful_response["items"].size)
      end
    end
  end

  context "page_data" do
    test "returns correct data for first page" do
      assert_equal("DevOps", @category_page.page_data[:title])
      assert_equal("Gallery of articles for the topic DevOps", @category_page.page_data[:description])
      assert_equal({ title: "DevOps", url: "/resources/articles/devops", description: "Gallery of articles for the topic DevOps" }, @category_page.page_data[:richweb])
    end

    test "returns correct data for second page" do
      VCR.use_cassette("contentful/resources/pages/category-page/security") do
        page = Site::Contentful::Marketing::Resources::Pages::Articles::CategoryPage.new(topic: "security", page: "2", url: "/resources/articles/security")

        assert_equal("Security - Page 2", page.page_data[:title])
        assert_equal("Gallery of articles for the topic Security - Page 2", page.page_data[:description])
        assert_equal({ title: "Security - Page 2", url: "/resources/articles/security&page=2", description: "Gallery of articles for the topic Security - Page 2" }, page.page_data[:richweb])
      end
    end

    test "returns correct data for the topics index page 'All topics'" do
      assert_equal("All Topics", @all_topics_index.page_data[:title])
      assert_equal("Gallery of articles for the topic All Topics", @all_topics_index.page_data[:description])
      assert_equal({ title: "All Topics", url: "/resources/articles", description: "Gallery of articles for the topic All Topics" }, @all_topics_index.page_data[:richweb])
    end
  end
end
