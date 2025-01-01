# typed: true
# frozen_string_literal: true

require "test_helper"

class Site::Contentful::CustomerStories::CategoryPageTest < GitHub::TestCase
  context ".content" do
    test "returns page data and stories from Contentful for category" do
      VCR.use_cassette("contentful/customer-stories-category-page-enterprise") do
        page_data = Site::Contentful::CustomerStories::CategoryPage.content("enterprise")
        featured_stories = page_data.featured_stories

        assert_equal "GitHub for Enterprises", page_data.heading
        assert_equal "A smarter way to work together.", page_data.tagline
        assert_equal 3, featured_stories.count
      end
    end
  end
end
