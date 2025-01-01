# typed: true
# frozen_string_literal: true

require "test_helper"

class UserAbuseDependencyTest < GitHub::TestCase
  include AuditLogHelpers
  include HydroTestHelpers

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:user, last_ip: "127.0.0.1")
    @cutoff = (CancelSponsorshipsFromAbusiveSponsorsJob::GRACE_PERIOD_IN_DAYS + 1).days.ago
  end

  def mark_suspended_at(user, time)
    travel_to(time) do
      with_es_refresh { user.suspend("bad actor") }
    end
  end

  context ".timestamps_for_abuse_type_by_user_id" do
    if GitHub.spamminess_check_enabled?
      test "returns a hash keyed by user ID for the requested users indicating when they were marked as spammy" do
        spammer1, spammer2 = create_list(:user, 2)
        spammer1_marked_spammy_at = 1.week.ago
        spammer2_marked_spammy_at = Time.now

        travel_to(spammer1_marked_spammy_at) do
          with_es_refresh { perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) { spammer1.mark_as_spammy } }
        end

        travel_to(spammer2_marked_spammy_at) do
          with_es_refresh { perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) { spammer2.mark_as_spammy } }
        end

        result = User.timestamps_for_abuse_type_by_user_id(:spam, [@user.id, spammer1.id, spammer2.id])

        assert_nil result[@user.id], "should not include timestamp for user that has never been marked spammy"
        refute_nil result[spammer1.id]
        assert_equal spammer1_marked_spammy_at.to_i, result[spammer1.id].to_i
        refute_nil result[spammer2.id]
        assert_equal spammer2_marked_spammy_at.to_i, result[spammer2.id].to_i
      end

      test "returns a hash keyed by user ID for the requested users indicating when they were suspended" do
        suspended1, suspended2 = create_list(:user, 2)
        suspended1_timestamp = @cutoff
        suspended2_timestamp = @cutoff + 1.day

        mark_suspended_at(suspended1, suspended1_timestamp)
        mark_suspended_at(suspended2, suspended2_timestamp)

        result = User.timestamps_for_abuse_type_by_user_id(:suspension, [@user.id, suspended1.id, suspended2.id])

        assert_nil result[@user.id], "should not include timestamp for user that has never been suspended"
        refute_nil result[suspended1.id]
        assert_equal suspended1_timestamp.to_i, result[suspended1.id].to_i
        refute_nil result[suspended2.id]
        assert_equal suspended2_timestamp.to_i, result[suspended2.id].to_i
      end

      test "includes the most recent timestamp for a user that has been marked spammy multiple times" do
        timestamp = Time.now
        Timecop.freeze(timestamp) do
          spammer = create(:user)
          most_recently_marked_spammy_at = timestamp - 1.day

          with_es_refresh do
            log(action: "staff.mark_as_spammy", user_id: spammer.id, created_at: most_recently_marked_spammy_at - 1.day)
            log(action: "staff.mark_as_spammy", user_id: spammer.id, created_at: most_recently_marked_spammy_at)
          end

          result = User.timestamps_for_abuse_type_by_user_id(:spam, [spammer.id])

          refute_nil result[spammer.id]
          assert_in_delta most_recently_marked_spammy_at.to_i, result[spammer.id].to_i, 10.seconds # Allow for a 10 sec delay in updating ES
        end
      end

      test "includes the most recent timestamp for a user that has suspended multiple times" do
        timestamp = Time.now
        Timecop.freeze(timestamp) do
          suspended_user = create(:user)
          most_recently_suspended_at = timestamp - 1.day

          with_es_refresh do
            log(action: "user.suspend", user_id: suspended_user.id, created_at: most_recently_suspended_at - 1.day)
            log(action: "user.suspend", user_id: suspended_user.id, created_at: most_recently_suspended_at)
          end

          result = User.timestamps_for_abuse_type_by_user_id(:suspension, [suspended_user.id])

          refute_nil result[suspended_user.id]
          assert_in_delta most_recently_suspended_at.to_i, result[suspended_user.id].to_i, 10.seconds # Allow for a 10 sec delay in updating ES
        end
      end

      test "includes timestamp for spammy org" do
        timestamp = Time.now
        Timecop.freeze(timestamp) do
          org = create(:organization)
          with_es_refresh { log(action: "staff.mark_as_spammy", org_id: org.id, created_at: timestamp) }

          result = User.timestamps_for_abuse_type_by_user_id(:spam, [org.id])

          refute_nil result[org.id]
          assert_in_delta timestamp.to_i, result[org.id].to_i, 10.seconds # Allow for a 10 sec delay in updating ES
        end
      end

      test "includes timestamp for suspended org" do
        timestamp = Time.now
        Timecop.freeze(timestamp) do
          org = create(:organization)
          with_es_refresh { log(action: "user.suspend", org_id: org.id, created_at: timestamp) }

          result = User.timestamps_for_abuse_type_by_user_id(:suspension, [org.id])

          refute_nil result[org.id]
          assert_in_delta timestamp.to_i, result[org.id].to_i, 10.seconds # Allow for a 10 sec delay in updating ES
        end
      end

      test "returns an empty hash when no user IDs are given" do
        result = User.timestamps_for_abuse_type_by_user_id(:spam, [])
        assert_equal({}, result)
      end

      test "returns an empty hash when abuse type is invalid" do
        result = User.timestamps_for_abuse_type_by_user_id(:hammy, [])
        assert_equal({}, result)
      end
    else
      test "returns an empty hash when spamminess check is disabled" do
        result = User.timestamps_for_abuse_type_by_user_id(:spam, [@user.id])
        assert_equal({}, result)
      end
    end
  end

  context ".user_ids_marked_before" do
    if GitHub.spamminess_check_enabled?
      test "filters list to just those marked spammy before the given time" do
        spammer1, spammer2, spammer3 = create_list(:user, 3)
        with_es_refresh do
          log(action: "staff.mark_as_spammy", user_id: spammer3.id, created_at: 8.days.ago)
          log(action: "staff.mark_as_spammy", user_id: spammer1.id, created_at: 7.days.ago)
          log(action: "staff.mark_as_spammy", user_id: spammer2.id, created_at: 1.day.ago)
        end

        result = User.user_ids_marked_before(:spam, [spammer1.id, spammer2.id], cutoff_time: 3.days.ago)

        assert_includes result, spammer1.id, "should include requested user who was marked spammy before given time"
        refute_includes result, spammer2.id,
          "should not include requested user who was marked spammy after given time"
        refute_includes result, spammer3.id, "should not include user who was not requested"
      end

      test "filters list to just those suspended before the given time" do
        suspended1, suspended2, suspended3 = create_list(:user, 3)
        with_es_refresh do
          log(action: "user.suspend", user_id: suspended3.id, created_at: @cutoff)
          log(action: "user.suspend", user_id: suspended1.id, created_at: 3.days.ago)
          log(action: "user.suspend", user_id: suspended2.id, created_at: 2.days.ago)
        end

        result = User.user_ids_marked_before(:suspension, [suspended1.id, suspended2.id], cutoff_time: 3.days.ago)

        assert_includes result, suspended1.id, "should include requested user who was suspended before given time"
        refute_includes result, suspended2.id,
          "should not include requested user who was suspended after given time"
        refute_includes result, suspended3.id, "should not include user who was not requested"
      end

      test "returns an empty array when abuse type is invalid" do
        spammer1 = create(:user)
        with_es_refresh { log(action: "staff.mark_as_spammy", user_id: spammer1.id, created_at: 7.days.ago) }

        result = User.user_ids_marked_before(:hammy, [spammer1.id], cutoff_time: 3.days.ago)

        assert_equal([], result)
      end
    else
      test "returns an empty array when spamminess check is disabled" do
        spammer1 = create(:user)
        with_es_refresh { log(action: "staff.mark_as_spammy", user_id: spammer1.id, created_at: 7.days.ago) }

        result = User.user_ids_marked_before(:hammy, [spammer1.id], cutoff_time: 3.days.ago)

        assert_equal([], result)
      end
    end
  end

  context "#anonymizing_proxy_user?" do
    test "false if has_used_anonymizing_proxy attribute is nil" do
      assert_nil @user.has_used_anonymizing_proxy
      refute @user.anonymizing_proxy_user?
    end

    test "false if has_used_anonymizing_proxy attribute is false" do
      @user.has_used_anonymizing_proxy = false
      refute @user.anonymizing_proxy_user?
    end

    test "true if has_used_anonymizing_proxy attribute is true" do
      @user.has_used_anonymizing_proxy = true
      assert @user.anonymizing_proxy_user?
    end
  end
end
