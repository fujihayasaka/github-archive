# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/site/readme/cassette_helpers"

class Site::Contentful::Readme::Pages::Fetchers::MoreStoriesFetcherTest < GitHub::TestCase
  include Site::Readme::CassetteHelpers
  include Site::Contentful::Readme::Pages::Fetchers::MoreStoriesFetcher
  require_cassettes_for_external_http_connections

  unless GitHub.enterprise?
    setup do
      @developer_story = VCR.use_cassette("contentful/readme-developer-story-brian-douglas") do
        Site::Contentful::Readme::DeveloperStory.find("brian-douglas", include_unpublished: true)
      end
    end

    context "#fetch_more_stories_for" do
      test "returns the current limit of 3 recirculation stories per story" do
        stub_more_stories_index_randomness

        VCR.use_cassette("contentful/readme-helper-more-stories-fetcher") do
          Timecop.freeze(Time.utc(2022, 9, 16)) do
            stories = fetch_more_stories_for(@developer_story)

            assert_equal 3, stories.count
          end
        end
      end
    end
  end
end
