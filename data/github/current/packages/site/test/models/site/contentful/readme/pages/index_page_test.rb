# typed: true
# frozen_string_literal: true

require "test_helper"

STORIES_CACHE_KEY_REGEX = /\A([a-f0-9]{64}\/?){5}\z/

class Site::Contentful::Readme::Pages::IndexPageTest < GitHub::TestCase
  require_cassettes_for_external_http_connections

  unless GitHub.enterprise?
    setup do
      @subject_for_non_staff = Site::Contentful::Readme::Pages::IndexPage.new(for_readme_staff: false)
      @subject_for_staff = Site::Contentful::Readme::Pages::IndexPage.new(for_readme_staff: true)
    end

    context "#fetch_data_from_contentful" do
      test "returns data from Contentful" do
        VCR.use_cassette("contentful/readme-index-page") do
          result = @subject_for_staff.view_data

          assert_match /[a-f0-9]{64}.for_readme_staff:true\/v1/, result[:cache_key]

          assert_instance_of String, result[:homepage_id]

          assert_equal 4, result[:navigation_topics].size

          assert_match STORIES_CACHE_KEY_REGEX, result[:developer_stories_cache_key]
          assert_match STORIES_CACHE_KEY_REGEX, result[:guides_cache_key]
          assert_match STORIES_CACHE_KEY_REGEX, result[:featured_articles_cache_key]
          assert_match STORIES_CACHE_KEY_REGEX, result[:podcasts_cache_key]

          assert_equal 5, result[:developer_stories_slugs].size
          assert_equal 5, result[:guides_slugs].size
          assert_equal 5, result[:featured_articles_slugs].size
          assert_equal 5, result[:podcasts_slugs].size
        end
      end
    end

    context "#cache_key" do
      test "builds the right key" do
        assert_equal "site.contentful.readme.pages.index.for_readme_staff:true/v1", @subject_for_staff.cache_key
        assert_equal "site.contentful.readme.pages.index.for_readme_staff:false/v1", @subject_for_non_staff.cache_key
      end
    end
  end
end
