# typed: true
# frozen_string_literal: true

require "test_helper"

class SiteContentfulResourcePagesCategoryPageTest < GitHub::TestCase
  require_cassettes_for_external_http_connections

  setup do
    skip if GitHub.enterprise?
    @topic = "devops"
    @page = 1
    @features = "contentful_lp_seo_pages"
    @url = "/resources/articles/devops"

    @topic_alt = "innersource"
    @url_alt = "/resources/articles/innersource"
    @all_topics_url = "/resources/articles"

    @category_page = VCR.use_cassette("contentful/resources/pages/category-page/devops") do
      Site::Contentful::Marketing::Resources::Pages::Articles::CategoryPage.new(topic: @topic, page: @page, url: @url)
    end

    @category_page_alt = VCR.use_cassette("contentful/resources/pages/category-page/innersource") do
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
      assert_equal(@category_page.contentful_response["items"].size, 1)
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

        assert_equal(entry["fields"]["title"], "How to accelerate innovation with innersource")
        assert_equal(entry["fields"]["excerpt"], {
          "data" => {},
          "content" => [{
            "data" => {},
            "content" => [{
              "data" => {},
              "marks" => [],
              "value" => "Organizations around the world are accelerating their development cycles and tapping into new wells of innovation within their companies through \"innersource\" projects that share code and resources internally, enabling cross-team collaboration and contributions.",
              "nodeType" => "text"
            }],
            "nodeType" => "paragraph"
          }],
          "nodeType" => "document"
        })
        assert_equal(entry["fields"]["heroBackgroundImage"], { "sys" =>
          {
            "type" => "Link",
            "linkType" => "Entry",
            "id" => "4GJlMQxqAZlo5yT0OUGje5"
          }
        })
      end
    end

    test "returns empty contentful_response[\"items\"] if topic does not have any items" do
      VCR.use_cassette("contentful/resources/pages/category-page/test-internal-only") do
        page = Site::Contentful::Marketing::Resources::Pages::Articles::CategoryPage.new(topic: "test-internal-only", page: @page, url: "/resources/articles/test-internal-only")

        assert_nil(page.total_pages)
        assert_equal(page.contentful_response["items"], [])
      end
    end
  end

  context "filter_hidden_pages" do
    test "removes feature flagged items from the contentful_response" do
      VCR.use_cassette("contentful/resources/pages/category-page/ci-cd") do
        page = Site::Contentful::Marketing::Resources::Pages::Articles::CategoryPage.new(topic: "ci-cd", page: @page, url: "/resources/articles/ci-cd")

        # filter out pages that have a feature flag that wasn't passed in
        page.filter_hidden_pages { |flag| flag != @features }

        assert_equal(page.contentful_response["items"].size, 9)
      end
    end

    test "include feature flagged items to the contentful_response" do
      VCR.use_cassette("contentful/resources/pages/category-page/ci-cd") do
        page = Site::Contentful::Marketing::Resources::Pages::Articles::CategoryPage.new(topic: "ci-cd", page: @page, url: "/resources/articles/ci-cd")

        # include pages that have a feature flag that was passed in
        page.filter_hidden_pages { |flag| flag == "#{@features},contentful_lp_ci_cd" }

        assert_equal(page.contentful_response["items"].size, 15)
      end
    end
  end

  context "apply_pagination" do
    test "paginates the contentful_response for page 1" do
      VCR.use_cassette("contentful/resources/pages/category-page/ci-cd") do
        page = Site::Contentful::Marketing::Resources::Pages::Articles::CategoryPage.new(topic: "ci-cd", page: @page, url: "/resources/articles/ci-cd")

        page.filter_hidden_pages { |flag| flag == "#{@features},contentful_lp_ci_cd" }

        page.apply_pagination

        assert_equal(page.total_pages, 2)
        assert_equal(page.page_number, 1)
        assert_equal(page.contentful_response["items"].size, 12)
      end
    end

    test "paginates the contentful_response for page 2" do
      VCR.use_cassette("contentful/resources/pages/category-page/security") do
        page = Site::Contentful::Marketing::Resources::Pages::Articles::CategoryPage.new(topic: "security", page: 2, url: "/resources/articles/security")

        page.apply_pagination

        assert_equal(page.total_pages, 2)
        assert_equal(page.page_number, 2)
        assert_equal(page.contentful_response["items"].size, 3)
      end
    end
  end

  context "page_data" do
    test "returns correct data for first page" do
      assert_equal(@category_page.page_data[:title], "DevOps")
      assert_equal(@category_page.page_data[:description], "Gallery of articles for the topic DevOps")
      assert_equal(@category_page.page_data[:richweb], { title: "DevOps", url: "/resources/articles/devops", description: "Gallery of articles for the topic DevOps" })
    end

    test "returns correct data for second page" do
      VCR.use_cassette("contentful/resources/pages/category-page/security") do
        page = Site::Contentful::Marketing::Resources::Pages::Articles::CategoryPage.new(topic: "security", page: 2, url: "/resources/articles/security")

        assert_equal(page.page_data[:title], "Security - Page 2")
        assert_equal(page.page_data[:description], "Gallery of articles for the topic Security - Page 2")
        assert_equal(page.page_data[:richweb], { title: "Security - Page 2", url: "/resources/articles/security&page=2", description: "Gallery of articles for the topic Security - Page 2" })
      end
    end

    test "returns correct data for the topics index page 'All topics'" do
      assert_equal(@all_topics_index.page_data[:title], "All Topics")
      assert_equal(@all_topics_index.page_data[:description], "Gallery of articles for the topic All Topics")
      assert_equal(@all_topics_index.page_data[:richweb], { title: "All Topics", url: "/resources/articles", description: "Gallery of articles for the topic All Topics" })
    end
  end
end
