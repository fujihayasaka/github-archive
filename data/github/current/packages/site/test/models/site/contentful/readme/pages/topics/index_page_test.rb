# typed: true
# frozen_string_literal: true

require "test_helper"

class Site::Contentful::Readme::Pages::Topics::IndexPageTest < GitHub::TestCase
  require_cassettes_for_external_http_connections

  unless GitHub.enterprise?
    setup do
      @index_page_for_non_staff = Site::Contentful::Readme::Pages::Topics::IndexPage.new

      @index_page_for_staff = Site::Contentful::Readme::Pages::Topics::IndexPage.new(for_readme_staff: true)
    end

    context "#fetch_data_from_contentful" do
      test "returns the right data from Contentful" do
        VCR.use_cassette("contentful/readme-topics-index-page") do
          Timecop.freeze(Time.utc(2022, 6, 13)) do
            data = @index_page_for_non_staff.fetch_data_from_contentful

            assert_equal(4, data[:topics_with_stories].count)

            assert_equal("Culture", data[:topics_with_stories][0][0][:name])
            assert_equal("Hiring technical talent: An exercise in clarity, patience, and preparation", data[:topics_with_stories][0][1][0][:heading])
            assert_equal("Chaos engineering helps DevOps cope with complexity", data[:topics_with_stories][0][1][1][:heading])

            assert_equal("DevOps", data[:topics_with_stories][1][0][:name])
            assert_equal("Chaos engineering helps DevOps cope with complexity", data[:topics_with_stories][1][1][0][:heading])
            assert_equal("Using ‘Roofshots’ to make impossible decisions", data[:topics_with_stories][1][1][1][:heading])

            assert_equal("Open Source", data[:topics_with_stories][2][0][:name])
            assert_equal("There are no warranties on open source", data[:topics_with_stories][2][1][0][:heading])
            assert_equal("Move over JavaScript: Back-end languages are coming to the front-end", data[:topics_with_stories][2][1][1][:heading])

            assert_equal("Security", data[:topics_with_stories][3][0][:name])
            assert_equal("There are no warranties on open source", data[:topics_with_stories][3][1][0][:heading])
            assert_equal("What we talk about when we talk about ‘root cause’", data[:topics_with_stories][3][1][1][:heading])

            assert_equal(4, data[:navigation_topics].count)

            assert_equal("Open Source", data[:navigation_topics][0][:name])
            assert_equal("Culture", data[:navigation_topics][1][:name])
            assert_equal("Security", data[:navigation_topics][2][:name])
            assert_equal("DevOps", data[:navigation_topics][3][:name])
          end
        end
      end
    end

    context "#cache_key" do
      test "builds the right key" do
        assert_equal "site.swp.readme.topics.index.staff:true", @index_page_for_staff.cache_key
        assert_equal "site.swp.readme.topics.index.staff:false", @index_page_for_non_staff.cache_key
      end
    end
  end
end
