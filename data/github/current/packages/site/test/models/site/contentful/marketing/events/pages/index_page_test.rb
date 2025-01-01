# typed: true
# frozen_string_literal: true

require "test_helper"

class Site::Contentful::Marketing::Events::Pages::IndexPageTest < GitHub::TestCase
  require_cassettes_for_external_http_connections

  setup do
    skip if GitHub.enterprise?

    @events_index_page = Site::Contentful::Marketing::Events::Pages::IndexPage.new
  end

  context "#fetch_data_from_contentful" do
    test "returns page data" do
      Timecop.freeze(Time.utc(2023, 1, 10)) do
        VCR.use_cassette("contentful/events/index-page-data") do
          page_data = @events_index_page.fetch_data_from_contentful[:page_data]

          assert_equal page_data[:title], "GitHub Events"
          assert_equal page_data[:seo_description], "GitHub is where people build software. More than 94 million people use GitHub to discover, fork, and contribute to over 330 million projects."
          assert_equal page_data[:heading], "Events"
          assert_equal page_data[:subheading], "Connect with the GitHub community at conferences, meetups, and hackathons around the world."
        end
      end
    end

    test "returns events of type active or persistent" do
      Timecop.freeze(Time.utc(2023, 1, 10)) do
        VCR.use_cassette("contentful/events/index-page-data") do

          events = @events_index_page.fetch_data_from_contentful[:events]

          is_active = -> (event) { Date.parse(event[:end_date]) >= Date.today && event[:sponsored] == false }
          is_persistent = -> (event) { event[:always_show] == true && event[:sponsored] == false }

          assert events.all? { |event| is_active.call(event) || is_persistent.call(event) }
        end
      end
    end

    test "returns active and persistent events in reverse chronological start_date order" do
      Timecop.freeze(Time.utc(2023, 1, 10)) do
        VCR.use_cassette("contentful/events/index-page-data") do
          active_persistent_events = @events_index_page.fetch_data_from_contentful[:events]

          assert_equal 5, active_persistent_events.count

          assert_operator active_persistent_events[0][:start_date], :>=, active_persistent_events[1][:start_date]
          assert_operator active_persistent_events[1][:start_date], :>=, active_persistent_events[2][:start_date]
          assert_operator active_persistent_events[2][:start_date], :>=, active_persistent_events[3][:start_date]
          assert_operator active_persistent_events[3][:start_date], :>=, active_persistent_events[4][:start_date]
        end
      end
    end

    test "returns sponsored events" do
      Timecop.freeze(Time.utc(2023, 1, 10)) do
        VCR.use_cassette("contentful/events/index-page-data") do
          sponsored_events = @events_index_page.fetch_data_from_contentful[:sponsored_events]

          sponsored_events.each do |event|
            assert_equal event[:sponsored], true
          end
        end
      end
    end
  end

  context "#cache_key" do
    test "builds the right key" do
      assert_equal "site.contentful.marketing.events.pages.index/v1", @events_index_page.cache_key
    end
  end
end
