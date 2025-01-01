# typed: true
# frozen_string_literal: true

require "test_helper"

class Site::Contentful::Marketing::Events::Pages::ShowPageTest < GitHub::TestCase
  require_cassettes_for_external_http_connections

  setup do
    skip if GitHub.enterprise?

    @event = VCR.use_cassette("contentful/events/demodays") do
      Site::Contentful::Marketing::Events::Event.find("demodays").to_json
    end

    @demo_days_show_event_page = Site::Contentful::Marketing::Events::Pages::ShowPage.new(slug: "demodays")

    @fake_non_existent_event = Site::Contentful::Marketing::Events::Pages::ShowPage.new(slug: "non-existent-fake-event")
  end

  context "#fetch_data_from_contentful" do
    test "returns a blank result if the event is not found" do
      VCR.use_cassette("contentful/events/show-page-non-existent-story") do
        result = @fake_non_existent_event.fetch_data_from_contentful

        assert_nil result[:event]
      end
    end

    test "returns the right data from Contentful if the event is found" do
      VCR.use_cassette("contentful/events/show-page") do
        result = @demo_days_show_event_page.fetch_data_from_contentful[:event]

        assert_equal @event, result
      end
    end
  end

  context "#cache_key" do
    test "builds the right cache key" do
      assert_equal "site.contentful.marketing.events.pages.show.demodays/v1", @demo_days_show_event_page.cache_key
    end
  end
end
