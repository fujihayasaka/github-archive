# typed: true
# frozen_string_literal: true

require "test_helper"

class Site::Contentful::Marketing::Events::EventTest < GitHub::TestCase
  setup do
    skip if GitHub.enterprise?
  end

  context ".find" do
    test "returns appropriate data from Contentful" do
      Timecop.freeze(Time.utc(2022, 12, 13)) do
        VCR.use_cassette("contentful/events/24-pull-requests-2018") do
          event = Site::Contentful::Marketing::Events::Event.find("24-pull-requests-2018")

          assert_equal "24 Pull Requests", event.name
        end
      end
    end

    test "returns nil if event does not exist" do
      VCR.use_cassette("contentful/events/non-existent-event") do
        Timecop.freeze(Time.utc(2022, 12, 13)) do
          event = Site::Contentful::Marketing::Events::Event.find("non-existent-event")

          assert_nil event
        end
      end
    end
  end

  context ".active" do
    test "returns all active" do
      Timecop.freeze(Time.utc(2022, 12, 13)) do
        VCR.use_cassette("contentful/events/active-events") do
          active_events = Site::Contentful::Marketing::Events::Event.active

          assert_equal 2, active_events.count

          assert_operator active_events[0].end_date, :>=, Date.today
          assert_operator active_events[1].end_date, :>=, Date.today
        end
      end
    end
  end

  context ".persistent" do
    test "returns all persistent events" do
      Timecop.freeze(Time.utc(2022, 12, 13)) do
        VCR.use_cassette("contentful/events/persistent-events") do
          persistent_events = Site::Contentful::Marketing::Events::Event.persistent

          assert_equal 3, persistent_events.count

          assert_equal persistent_events[0].always_show, true
          assert_equal persistent_events[0].sponsored, false

          assert_equal persistent_events[1].always_show, true
          assert_equal persistent_events[1].sponsored, false

          assert_equal persistent_events[2].always_show, true
          assert_equal persistent_events[2].sponsored, false
        end
      end
    end

    context ".sponsored" do
      test "returns all sponsored events" do
        Timecop.freeze(Time.utc(2022, 12, 13)) do
          VCR.use_cassette("contentful/events/sponsored-events") do
            sponsored_events = Site::Contentful::Marketing::Events::Event.sponsored

            assert_equal 1, sponsored_events.count

            assert_operator sponsored_events[0].end_date, :>=, Date.today
            assert_equal sponsored_events[0].sponsored, true
          end
        end
      end
    end
  end
end
