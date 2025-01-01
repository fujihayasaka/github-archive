# typed: true
# frozen_string_literal: true

require "test_helper"

module GitHub::StreamProcessors
  class UserContributionHistoryProcessorTest < GitHub::TestCase
    include HydroTestHelpers

    fixtures do
      @user1 = create(:user)
      @user2 = create(:user)
    end

    setup do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    end

    sig { params(user: User).returns(T::Hash[Symbol, T.untyped]) }
    def event_message(user)
      {
        user: Hydro::EntitySerializer.user(user)
      }
    end

    test "(re)sets the user namespace for all users in the batch" do
      key1 = "contribs-accessor-ns:#{@user1.id}"
      value = [@user1.id, 1.minute.ago.to_f.to_s].join(",")
      Profiles::Kv.store.set(key1, value)
      key2 = "contribs-accessor-ns:#{@user2.id}"

      assert_equal value, Profiles::Kv.store.get(key1).value!
      assert_nil Profiles::Kv.store.get(key2).value!

      now = Time.now
      Timecop.freeze(now) do
        hydro_publisher.publish(event_message(@user1), schema: "github.users.v1.ContributionHistoryModified")
        hydro_publisher.publish(event_message(@user2), schema: "github.users.v1.ContributionHistoryModified")
        run_processor(GitHub::StreamProcessors::UserContributionHistoryProcessor.new)
      end

      expected_value1 = [@user1.id, now.to_f.to_s].join(",")
      expected_value2 = [@user2.id, now.to_f.to_s].join(",")

      assert_equal expected_value1, Profiles::Kv.store.get(key1).value!
      assert_equal expected_value2, Profiles::Kv.store.get(key2).value!
    end

    test "processes multiple events in a single batch" do
      now = Time.now

      hydro_publisher.publish(event_message(@user1), schema: "github.users.v1.ContributionHistoryModified")
      hydro_publisher.publish(event_message(@user2), schema: "github.users.v1.ContributionHistoryModified")
      hydro_publisher.publish(event_message(@user1), schema: "github.users.v1.ContributionHistoryModified")
      Contribution::Accessor::Cache.expects(:bulk_reset_user_namespace).with([@user1.id], expires: now + 2.days).once
      Contribution::Accessor::Cache.expects(:bulk_reset_user_namespace).with([@user2.id], expires: now + 2.days).once

      Timecop.freeze(now) { run_processor(GitHub::StreamProcessors::UserContributionHistoryProcessor.new) }
    end

    test "instrumentation records message metrics" do
      hydro_publisher.publish(event_message(@user1), schema: "github.users.v1.ContributionHistoryModified")
      hydro_publisher.publish(event_message(@user2), schema: "github.users.v1.ContributionHistoryModified")
      hydro_publisher.publish(event_message(@user1), schema: "github.users.v1.ContributionHistoryModified")

      run_processor(GitHub::StreamProcessors::UserContributionHistoryProcessor.new)

      assert_equal 3, GitHub.dogstats.increments("github.stream_processor.message_received", tags: ["processor:github/stream_processors/user_contribution_history_processor"]).count
      assert_equal 3, GitHub.dogstats.timings("github.stream_processor.message_latency", tags: ["processor:github/stream_processors/user_contribution_history_processor"]).count
    end
  end
end
