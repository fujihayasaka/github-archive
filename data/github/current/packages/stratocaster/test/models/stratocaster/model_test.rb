# typed: true
# frozen_string_literal: true

require "test_helper"

class StratocasterModelTest < GitHub::TestCase
  include DogstatsTestHelpers
  include GitHub::LoggerHelper

  fixtures do
    @user = create :user
    @bad_gzip = Stratocaster::Model.connection.insert <<-SQL
      INSERT INTO `stratocaster_events` (`raw_data`, `updated_at`) VALUES ("this will fail unzip", NOW())
    SQL
  end

  test "sets created_at time in raw_data during creation" do
    freeze_time do
      model = Stratocaster::Model.create
      assert_equal Time.current.round, model.created_at # cast as Time when read
      assert_equal Time.current.round.to_i, model.raw_data[:created_at] # integer in datastore
      assert_equal model.updated_at.to_i, model.raw_data[:created_at]
    end
  end

  test "sets created_at time in raw_data with correct timezone" do
    freeze_time do
      Time.use_zone("Hawaii") do
        model = Stratocaster::Model.create
        assert_equal Time.current.round, model.created_at # cast as Time when read
        assert_equal Time.current.round.to_i, model.raw_data[:created_at] # integer in datastore
        assert_equal model.updated_at.to_i, model.raw_data[:created_at]
      end
    end
  end

  test "can be created from an event" do
    event = Stratocaster::Event.new(updated_at: Time.now)
    model = Stratocaster::Model.create_from_event!(event)

    assert_equal ({
      "sender" => {}, "user" => {}, "org" => {}, "repo" => {}, "payload" => {}, "team_members" => [], "states" => []
    }), model.raw_data.except(:created_at)
    refute_nil model.id
    assert_equal ActiveSupport::TimeWithZone, model.updated_at.class
  end

  test "respects updated_at/created_at if already set on event" do
    updated_at = Time.current.round # sub-seconds are truncated way when round-tripped thru db
    created_at = Time.current.yesterday.round # created_at goes to Integer when in json

    event = Stratocaster::Event.new updated_at: updated_at, created_at: created_at
    model = Stratocaster::Model.create_from_event!(event)

    assert_equal event.updated_at, model.updated_at
    assert_equal event.created_at.to_i, model.raw_data[:created_at]
  end

  test "can be updated from an event" do
    event = Stratocaster::Event.new(updated_at: Time.now)
    model = Stratocaster::Model.create_from_event!(event)

    event.user = @user
    model.update_from_event!(event)

    assert_equal ({
      "sender" => {},
      "user" => { "id" => @user.id, "login" => @user.login, "display_login" => @user.display_login, "gravatar_id" => "" },
      "org" => {}, "repo" => {}, "payload" => {}, "team_members" => [], "states" => []
    }), model.raw_data
  end

  test "records deserialization errors" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    # see test/lib/github/failbot_redacting_test.rb
    # for test ensuring exception is redacted at the failbot level
    Failbot.expects(:report).with(instance_of(Zlib::GzipFile::Error), type: "Error deserializing stratocaster event")

    expected_logs = {
      "Body": "Error deserializing stratocaster event",
      "exception.type": "Zlib::GzipFile::Error",
      "exception.message": "not in gzip format",
      "gh.stratocaster.adapter_name": "Stratocaster::Model"
    }
    assert_logged **expected_logs do
      model = Stratocaster::Model.find(@bad_gzip)

      assert_empty model.raw_data
      refute_empty GitHub.dogstats.increments "stratocaster.bad_gzip"
    end
  end

  context ".from_event" do
    test "builds a Model from an Event" do
      event = Stratocaster::Event.new updated_at: Time.current
      model = Stratocaster::Model.from_event(event)

      assert_equal ({
        "sender" => {}, "user" => {}, "org" => {}, "repo" => {}, "payload" => {}, "team_members" => [], "states" => []
      }), model.raw_data
      assert_in_delta event.updated_at, model.updated_at, 1
    end

    test "ignores the ID" do
      event = Stratocaster::Event.new(id: 7)

      model = Stratocaster::Model.from_event(event)

      assert_nil model.to_event.id
    end
  end

  context ".get_all" do
    test "orders by keys given" do
      event1 = Stratocaster::Model.create_from_event!(Stratocaster::Event.new).to_event
      event2 = Stratocaster::Model.create_from_event!(Stratocaster::Event.new).to_event
      event3 = Stratocaster::Model.create_from_event!(Stratocaster::Event.new).to_event

      assert_equal [event2, event3, event1],
        Stratocaster::Model.get_all(event2.id, event3.id, event1.id)

      model1 = Stratocaster::Model.create
      model2 = Stratocaster::Model.create
      model3 = Stratocaster::Model.create

      assert_equal [model2, model3, model1].map(&:id),
        Stratocaster::Model.get_all(model2.id, model3.id, model1.id).map(&:id)
    end

    test "omits unsuccessfully deserialized events" do
      model = Stratocaster::Model.create! created_at: Time.current

      assert_equal [model.to_event, nil], Stratocaster::Model.get_all(model.id, @bad_gzip)

      assert_equal [nil], Stratocaster::Model.get_all(@bad_gzip)
    end
  end

  context ".get" do
    test "returns Event for given id" do
      event = Stratocaster::Model.create_from_event!(Stratocaster::Event.new).to_event
      assert_equal event, Stratocaster::Model.get(event.id)
    end

    test "returns nil if not found" do
      assert_nil Stratocaster::Model.get(9000)
    end
  end

  context "#to_event" do
    test "converts a Model to an Event" do
      timestamp = Time.current
      event = Stratocaster::Event.new id: 7, updated_at: timestamp, event_type: "PublicEvent"
      model = Stratocaster::Model.new id: 7, updated_at: timestamp, raw_data: { event_type: "PublicEvent" }

      assert_equal event, model.to_event
    end
  end
end
