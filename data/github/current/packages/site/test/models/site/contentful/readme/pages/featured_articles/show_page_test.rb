# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/site/readme/cassette_helpers"

class Site::Contentful::Readme::Pages::FeaturedArticles::ShowPageTest < GitHub::TestCase
  include Site::Readme::CassetteHelpers
  require_cassettes_for_external_http_connections

  unless GitHub.enterprise?
    setup do
      @featured_article = VCR.use_cassette("contentful/readme-featured-article-react") do
        Site::Contentful::Readme::FeaturedArticle.find("react", include_unpublished: true)
      end

      @show_page_for_non_staff = Site::Contentful::Readme::Pages::FeaturedArticles::ShowPage.new(story_slug: @featured_article.slug)

      @show_page_for_non_staff_with_fake_story = Site::Contentful::Readme::Pages::FeaturedArticles::ShowPage.new(story_slug: "not-a-real-story")

      @show_page_for_staff = Site::Contentful::Readme::Pages::FeaturedArticles::ShowPage.new(story_slug: @featured_article.slug, for_readme_staff: true)
    end

    context "#fetch_data_from_contentful" do
      test "returns a blank result if the story is not found" do
        Timecop.freeze(Time.utc(2022, 7, 18)) do
          VCR.use_cassette("contentful/readme-featured-articles-show-page-not-found") do
            result = @show_page_for_non_staff_with_fake_story.fetch_data_from_contentful

            assert_nil result[:story]
            assert_nil result[:contributing]
            assert_nil result[:has_approved_sponsors_account]
            assert_nil result[:more_stories]
            assert_empty result[:navigation_topics]
          end
        end
      end

      test "returns data from Contentful if the story is found" do
        Timecop.freeze(Time.utc(2022, 9, 16)) do
          VCR.use_cassette("contentful/readme-featured-articles-show-page") do
            stub_more_stories_index_randomness

            result = @show_page_for_non_staff.fetch_data_from_contentful

            assert_equal @featured_article.to_json, result[:story]
            assert_equal @featured_article.has_approved_sponsors_account?, result[:has_approved_sponsors_account]
            assert_equal 4, result[:navigation_topics].count
            assert_equal 3, result[:more_stories].count

            # contributing is nil because Contentful information does not match
            # the information in our testing environment
            assert_nil result[:contributing]
          end
        end
      end
    end

    context "#cache_key" do
      test "builds the right cache key" do
        assert_equal "site.contentful.readme.pages.featured_articles.show.react.for_readme_staff:false/v1", @show_page_for_non_staff.cache_key
        assert_equal "site.contentful.readme.pages.featured_articles.show.react.for_readme_staff:true/v1", @show_page_for_staff.cache_key
      end
    end
  end
end
