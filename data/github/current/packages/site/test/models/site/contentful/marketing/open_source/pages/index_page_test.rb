# typed: true
# frozen_string_literal: true

require "test_helper"

class Site::Contentful::Marketing::OpenSource::Pages::IndexPageTest < GitHub::TestCase
  require_cassettes_for_external_http_connections

  unless GitHub.enterprise?
    setup do
      @subject = Site::Contentful::Marketing::OpenSource::Pages::IndexPage.new
    end

    context "#fetch_data_from_contentful" do
      test "returns data from Contentful, but limits the number of articles to 4" do
        VCR.use_cassette("contentful/marketing-open-source-index-page") do
          Timecop.freeze(Time.utc(2024, 3, 14)) do
            result = @subject.view_data

            assert_equal 4, result[:stories].count

            assert_equal "Anton Mirhorodchenko", result[:stories].first[:name]
            assert_equal "Anton uses AI to write code and tackle more projects.", result[:stories].first[:subheading]
            assert_equal "/readme/stories/anton-mirhorodchenko", result[:stories].first[:url]

            assert_equal "Kyler Middleton", result[:stories][1][:name]
            assert_equal "Kyler discusses her path from rural tech repair jobs to revolutionizing tech education.", result[:stories][1][:subheading]
            assert_equal "/readme/stories/kyler-middleton", result[:stories][1][:url]

            assert_equal "Aaron Gustafson", result[:stories][2][:name]
            assert_equal "Aaron’s journey towards progressive enhancement and inclusive design.", result[:stories][2][:subheading]
            assert_equal "/readme/stories/aaron-gustafson", result[:stories][2][:url]

            assert_equal "Annalu  Waller", result[:stories].last[:name]
            assert_equal "Dr. Annalu Waller on the intricate, interdependent network of support that shapes our lives.", result[:stories].last[:subheading]
            assert_equal "/readme/stories/annalu-waller", result[:stories].last[:url]
          end
        end
      end
    end

    context "#cache_key" do
      test "builds the right key" do
        assert_equal "site.swp.open_source.index", @subject.cache_key
      end
    end
  end
end
