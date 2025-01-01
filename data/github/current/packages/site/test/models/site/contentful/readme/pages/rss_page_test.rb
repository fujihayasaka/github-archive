# typed: true
# frozen_string_literal: true

require "test_helper"

class Site::Contentful::Readme::Pages::RssPageTest < GitHub::TestCase
  require_cassettes_for_external_http_connections

  unless GitHub.enterprise?
    setup do
      @subject = Site::Contentful::Readme::Pages::RssPage.new
    end

    context "#fetch_data_from_contentful" do
      test "returns data from Contentful, but limits the number of articles to 30" do
        VCR.use_cassette("contentful/readme-rss-page") do
          Timecop.freeze(Time.utc(2023, 3, 23)) do
            result = @subject.view_data

            assert_equal 30, result[:stories].count

            assert_equal "Help your team sustain a healthy work-life balance", result[:stories].first[:heading]
            assert_equal "Tue, 14 Mar 2023 02:00:00 +0000", result[:stories].first[:publication_date_rfc2822]

            assert_equal "The modern web’s underrated powerhouse", result[:stories][9][:heading]
            assert_equal "Tue, 14 Feb 2023 02:00:00 +0000", result[:stories][9][:publication_date_rfc2822]

            assert_equal "Driven by conversation and connection", result[:stories].last[:heading]
            assert_equal "Tue, 14 Jun 2022 02:00:00 +0000", result[:stories].last[:publication_date_rfc2822]
          end
        end
      end
    end

    context "#cache_key" do
      test "builds the right key" do
        assert_equal "site.contentful.readme.pages.rss/v1", @subject.cache_key
      end
    end
  end
end
