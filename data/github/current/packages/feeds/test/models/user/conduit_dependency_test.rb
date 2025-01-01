# typed: true
# frozen_string_literal: true

require "test_helper"

class ConduitDependencyTest < GitHub::TestCase
  context "last_conduit_event_at" do
    test "returns nil if there are no events" do
      user = create(:user)
      GitHub.conduit_client.class.any_instance.expects(:get_user_events)
        .returns({ items: Conduit::FeedItemCollection.new([]) })
        .at_least_once

      refute_predicate user.events, :any?
      assert_nil user.last_conduit_event_at, "should not have event timestamp"
    end

    test "fails gracefully if conduit is unavailable" do
      user = create(:user)
      GitHub.conduit_client.stubs(:get_user_events).raises(Conduit::Client::Unavailable)

      assert_nil user.last_conduit_event_at
    end

    test "returns date of the most recent conduit event" do
      user = create(:user)
      first_active_date = Time.rfc2822("Tue, 8 Jul 2008 17:40:30 -0700").utc
      last_active_date = Time.rfc2822("Tue, 15 Jul 2008 17:40:30 -0700").utc

      old_item = build(:twirp_conduit_starred_repository_feed_item, :with_created_at)
      time = Google::Protobuf::Timestamp.new(seconds: first_active_date.to_i, nanos: first_active_date.nsec)
      old_item["time"] = time

      new_item = build(:twirp_conduit_starred_repository_feed_item, :with_created_at)
      time = Google::Protobuf::Timestamp.new(seconds: last_active_date.to_i, nanos: last_active_date.nsec)
      new_item["time"] = time

      GitHub.conduit_client.class.any_instance.expects(:get_user_events)
        .returns({ items: Conduit::FeedItemCollection.new([new_item, old_item]) })

      assert_equal last_active_date.in_time_zone, user.last_conduit_event_at
    end
  end
end
