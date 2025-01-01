# typed: true
# frozen_string_literal: true

require "test_helper"

class Site::Contentful::CustomerStories::Pages::CustomerStoryShowPageTest < GitHub::TestCase
  require_cassettes_for_external_http_connections

  setup do
    skip if GitHub.enterprise?

    @customer_story = VCR.use_cassette("contentful/customer-stories-3m") do
      Site::Contentful::CustomerStories::CustomerStory.find("3m")
    end

    @customer_stories_show_page_for_non_staff = Site::Contentful::CustomerStories::Pages::CustomerStoryShowPage.new(story_slug: "3m")

    @customer_stories_show_page_for_fake_story = Site::Contentful::CustomerStories::Pages::CustomerStoryShowPage.new(story_slug: "not-a-real-story")
  end

  context "#fetch_data_from_contentful" do
    test "returns a blank result if the customer story is not found" do
      VCR.use_cassette("contentful/customer-stories-show-page-non-existant-story") do
        result = @customer_stories_show_page_for_fake_story.fetch_data_from_contentful

        assert_nil result[:customer_story]
      end
    end

    test "returns the right data from Contentful if the customer story is found" do
      VCR.use_cassette("contentful/customer-stories-show-page") do
        result = @customer_stories_show_page_for_non_staff.fetch_data_from_contentful

        assert_equal @customer_story.to_json, result[:customer_story]
      end
    end
  end

  context "#cache_key" do
    test "builds the right cache key" do
      assert_equal "site.contentful.customer_stories.pages.story.3m.for_staff:false", @customer_stories_show_page_for_non_staff.cache_key

      customer_stories_show_page_for_staff = Site::Contentful::CustomerStories::Pages::CustomerStoryShowPage.new(story_slug: "3m", for_staff: true)

      assert_equal "site.contentful.customer_stories.pages.story.3m.for_staff:true", customer_stories_show_page_for_staff.cache_key
    end
  end
end
