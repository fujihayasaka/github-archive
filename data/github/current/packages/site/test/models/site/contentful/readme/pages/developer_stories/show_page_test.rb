# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/site/readme/cassette_helpers"

class Site::Contentful::Readme::Pages::DeveloperStories::ShowPageTest < GitHub::TestCase
  include Site::Readme::CassetteHelpers
  require_cassettes_for_external_http_connections

  unless GitHub.enterprise?
    setup do
      @developer_story = VCR.use_cassette("contentful/readme-developer-story-brian-douglas") do
        Site::Contentful::Readme::DeveloperStory.find("brian-douglas", include_unpublished: true)
      end

      @show_page_for_non_staff = Site::Contentful::Readme::Pages::DeveloperStories::ShowPage.new(story_slug: @developer_story.slug)

      @show_page_for_non_staff_with_fake_story = Site::Contentful::Readme::Pages::DeveloperStories::ShowPage.new(story_slug: "not-a-real-story")

      @show_page_for_staff = Site::Contentful::Readme::Pages::DeveloperStories::ShowPage.new(story_slug: @developer_story.slug, for_readme_staff: true)
    end

    context "#fetch_data_from_contentful" do
      test "returns a blank result if the story is not found" do
        Timecop.freeze(Time.utc(2022, 7, 18)) do
          VCR.use_cassette("contentful/readme-developer-stories-show-page-not-found") do
            result = @show_page_for_non_staff_with_fake_story.fetch_data_from_contentful

            assert_nil result[:story]
            assert_nil result[:contributing]
            assert_nil result[:more_stories]
            assert_empty result[:navigation_topics]
          end
        end
      end

      test "returns data from Contentful if the story is found" do
        stub_more_stories_index_randomness

        Timecop.freeze(Time.utc(2022, 9, 16)) do
          VCR.use_cassette("contentful/readme-developer-stories-show-page") do
            result = @show_page_for_non_staff.fetch_data_from_contentful

            assert_equal @developer_story.to_json, result[:story]
            assert_equal 3, result[:more_stories].count
            assert_equal 4, result[:navigation_topics].count

            # contributing is nil because Contentful information does not match
            # the information in our testing environment
            assert_nil result[:contributing]
          end
        end
      end
    end

    context "#cache_key" do
      test "builds the right cache key" do
        assert_equal "site.swp.readme.developer_stories.brian-douglas.staff:false", @show_page_for_non_staff.cache_key
        assert_equal "site.swp.readme.developer_stories.brian-douglas.staff:true", @show_page_for_staff.cache_key
      end
    end
  end
end
