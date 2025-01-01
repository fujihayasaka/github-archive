# typed: true
# frozen_string_literal: true

require "test_helper"

class UserFollowDependencyTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @spammy_user = create(:user)
    @staff = create(:staff_admin_user)
    @user_1 = create(:user)
    @user_2 = create(:user)
    @user_3 = create(:user)
  end

  def calculate_followerings_immediately(&block)
    User::FollowDependency.stub_const(:FOLLOW_CALCULATION_INTERVAL_IN_SECONDS, 0) do
      only = [AddToSearchIndexJob, CalculateFolloweringsCountJob, ProcessEventJob, UpdateEventFeedsJob]
      perform_enqueued_jobs(only: only, &block)
    end
  end

  def reset_stratocaster
    T.let(GitHub, T.untyped).reset_stratocaster
  end

  # We need to find and re-instantiate the User object in order to reset cached counts.
  # User#reload re-fetches object attributes from the database but does not re-instantiate the
  # object.
  def reload_user(user)
    User.find(user.id)
  end

  context ".bulk_can_follow_check" do
    test "returns a hash indicating whether users can be followed or not" do
      blocked_user = create(:user)
      @user_1.block(blocked_user)
      blocking_user = create(:user)
      blocking_user.block(@user_1)
      org = create(:organization)
      bot = create(:integration).bot

      expected = { @user_1.id => false,
        @user_2.id => true,
        blocked_user.id => false,
        blocking_user.id => false,
        org.id => true,
        bot.id => false,
      }
      user_ids = [@user_1.id, @user_2.id, blocked_user.id, blocking_user.id, org.id, bot.id]
      assert_equal expected, User.bulk_can_follow_check(@user_1.id, user_ids)
    end

    test "handles invalid user ids" do
      invalid_id = User.all.maximum(:id) + 1
      expected = { "ABC" => false,
        invalid_id => false,
        @user_1.id => false,
        @user_2.id => true,
      }

      user_ids = ["ABC", invalid_id, @user_1.id, @user_2.id]
      assert_equal expected, User.bulk_can_follow_check(@user_1.id, user_ids)
    end

    test "returns an empty hash when providing an empty array" do
      assert_equal Hash.new, User.bulk_can_follow_check(@user_1.id, [])
    end

    test "returns an empty hash when not providing any user ids" do
      assert_equal Hash.new, User.bulk_can_follow_check(@user_1.id, nil)
    end

    test "returns false for private users" do
      @private_user = create(:user, private_profile: true)
      expected = { @private_user.id => false,
        @user_2.id => true,
      }

      user_ids = [@private_user.id, @user_2.id]
      assert_equal expected, User.bulk_can_follow_check(@user_1.id, user_ids)
    end
  end

  context ".bulk_following_check" do
    test "returns a hash indicating whether users are followed or not" do
      followed_user = create(:user)
      @user_1.follow(followed_user)
      following_user = create(:user)
      following_user.follow(@user_1)

      expected = { @user_1.id => false,
        @user_2.id => false,
        followed_user.id => true,
        following_user.id => false,
      }
      user_ids = [@user_1.id, @user_2.id, followed_user.id, following_user.id]
      assert_equal expected, User.bulk_following_check(@user_1.id, user_ids)
    end

    test "handles invalid user ids" do
      followed_user = create(:user)
      @user_1.follow(followed_user)

      expected = { "ABC" => false,
        @user_1.id + followed_user.id => false,
        @user_1.id => false,
        followed_user.id => true,
      }

      user_ids = ["ABC", @user_1.id + followed_user.id, @user_1.id, followed_user.id]
      assert_equal expected, User.bulk_following_check(@user_1.id, user_ids)
    end

    test "returns an empty hash when providing an empty array" do
      assert_equal Hash.new, User.bulk_following_check(@user_1.id, [])
    end

    test "returns an empty hash when not providing any user ids" do
      assert_equal Hash.new, User.bulk_following_check(@user_1.id, nil)
    end

    test "returns private users that were previously followed when feature flag is enabled" do
      private_user = create(:user)
      @user_1.follow(private_user)
      private_user.update!(private_profile: true)

      expected = {
        private_user.id => true,
      }
      user_ids = [private_user.id]
      assert_equal expected, User.bulk_following_check(@user_1.id, user_ids)
    end
  end

  context "#can_follow?" do
    test "users cannot follow themselves" do
      refute @user_1.can_follow?(@user_1)
    end

    test "user can follow an organization" do
      assert @user_1.can_follow?(@org)
    end

    test "user cannot follow a bot" do
      bot = create(:integration).bot

      refute @user_1.can_follow?(bot)
    end

    test "user cannot follow a blocked user" do
      @user_1.block(@user_2)

      refute @user_1.can_follow?(@user_2)
    end

    test "user cannot follow a blocking user" do
      @user_2.block(@user_1)

      refute @user_1.can_follow?(@user_2)
    end

    test "user can follow another user" do
      assert @user_1.can_follow?(@user_2)
    end

    test "user cannot follow another user if they have hit the rate limit" do
      enable_content_creation_rate_limiting
      with_cache_enabled do
        Timecop.freeze do
          GitHub::RateLimitedCreation.use_custom_limits(user_minute: 1) do
            Following.create(user: @user_1, following: create(:user))
            Following.create(user: @user_1, following: create(:user))

            refute @user_1.can_follow?(create(:user)), "should be at the following rate limit"
          end
        end
      end
    end

    test "does not cause user to hit rate limit just by checking follow status" do
      enable_content_creation_rate_limiting
      with_cache_enabled do
        Timecop.freeze do
          GitHub::RateLimitedCreation.use_custom_limits(user_minute: 1) do
            assert @user_1.can_follow?(@user_2)
            assert @user_1.can_follow?(@user_2),
              "should not be rate limited just from checking ability to follow"
          end
        end
      end
    end
  end

  context "#follow" do
    test "returns false when that user cannot follow given user" do
      @user_2.block(@user_1)
      refute @user_1.follow(@user_2)
    end

    test "unblocks given user for that user" do
      @user_1.block(@user_2)
      assert_difference("@user_1.ignored_users.count", -1) do
        assert @user_1.follow(@user_2)
      end
    end

    test "can follow another user" do
      assert @user_1.follow(@user_2)

      assert_includes @user_1.reload.following, @user_2
      assert_includes @user_2.reload.followers, @user_1
    end

    test "creates an activity event" do
      reset_stratocaster

      perform_enqueued_jobs(only: ProcessEventJob) do
        assert @user_1.follow(@user_2)
      end

      assert event = GitHub.stratocaster_store.last, "expected a stratocaster event to be triggered"
      assert_equal "FollowEvent", event.event_type
      assert_equal @user_1, event.sender_record
      assert_equal @user_2.login, event.payload["target"]["login"]
    end

    test "does not create an activity event for org follows" do
      reset_stratocaster

      perform_enqueued_jobs(only: ProcessEventJob) do
        assert @user_1.follow(@org)
      end

      refute GitHub.stratocaster_store.last, "expected no stratocaster event to be triggered"
    end

    test "creates an instrumentation event" do
      events = subscribe("following.create")

      assert @user_1.follow(@user_2)

      assert event = events.pop, "an event was expected"

      assert_equal @user_1.login, event.payload[:follower]
      assert_equal @user_1.id,    event.payload[:follower_id]

      assert_equal @user_2.login, event.payload[:followee]
      assert_equal @user_2.id,    event.payload[:followee_id]
    end

    test "users can't follow themselves" do
      refute @user_1.follow @user_1
      refute_includes @user_1.reload.following, @user_1
    end

    test "can't follow someone twice" do
      calculate_followerings_immediately do
        assert_difference("@user_1.following_count(viewer: nil)", 1) do
          assert @user_1.follow(@user_2)
        end

        assert_no_difference "@user_1.following_count(viewer: nil)" do
          refute @user_1.follow(@user_2)
        end
      end
    end

    test "sets user_hidden if the following is spammy", spammy_only: true do
      @spammy_user.mark_as_spammy(actor: @staff, reason: "merit")
      @user_1.follow(@spammy_user)

      assert follow = Following.find_by(user: @user_1, following: @spammy_user)
      assert_predicate follow, :user_hidden?
    end

    test "sets user_hidden if the follower is spammy", spammy_only: true do
      @spammy_user.mark_as_spammy(actor: @staff, reason: "merit")
      @spammy_user.follow(@user_1)

      assert follow = Following.find_by(user: @spammy_user, following: @user_1)
      assert_predicate follow, :user_hidden?
    end
  end

  context "#unfollow" do
    test "updates that user's following count" do
      @user_1.follow(@user_2)

      assert_difference("@user_1.following_count(viewer: nil)", -1) do
        calculate_followerings_immediately { @user_1.unfollow(@user_2) }
      end
    end

    test "updates the given user's follower count" do
      @user_1.follow(@user_2)

      assert_difference("@user_2.followers_count(viewer: nil)", -1) do
        calculate_followerings_immediately { @user_1.unfollow(@user_2) }
      end
    end

    test "returns false when given self" do
      refute @user_1.unfollow(@user_1)
    end

    test "can unfollow another user" do
      assert @user_1.follow(@user_2)
      assert_includes @user_1.reload.following, @user_2

      assert @user_1.unfollow(@user_2)
      refute_includes @user_1.reload.following, @user_2
    end

    test "does not create an activity event" do
      assert @user_1.follow(@user_2)

      reset_stratocaster

      assert @user_1.unfollow(@user_2)

      assert_nil GitHub.stratocaster_store.last
    end

    test "users can't unfollow someone they're not already following" do
      assert_no_difference "@user_1.followers_count(viewer: nil)" do
        calculate_followerings_immediately { refute @user_1.unfollow(@user_2) }
      end
    end

    test "unfollowing a user invalidates the viewer's feed cache" do
      @user_1.follow(@user_2)
      Conduit::KVBackedCache.get_or_set_for(@user_1) { "cached-value" }

      @user_1.unfollow(@user_2)

      assert_equal Conduit::KVBackedCache.get_or_set_for(@user_1) { "expected-value" }, "expected-value"
    end
  end

  context "#following_count" do
    test "returns 0 if the user isn't following anyone" do
      assert_equal 0, @user_1.following_count(viewer: nil)
    end

    test "persists the count if it hasn't been set" do
      assert_nil Profiles::Kv.store.get("user.following_count.#{@user_1.id}").value!
      @user_1.following_count(viewer: nil)
      refute_nil Profiles::Kv.store.get("user.following_count.#{@user_1.id}").value!
    end

    test "returns the total count of users the user is following" do
      calculate_followerings_immediately { assert @user_1.follow(@user_2) }
      assert_equal 1, @user_1.following_count(viewer: nil)

      calculate_followerings_immediately { assert @user_1.follow(@user_3) }
      assert_equal 2, @user_1.following_count(viewer: nil)

      calculate_followerings_immediately { assert @user_1.unfollow(@user_2) }
      assert_equal 1, @user_1.following_count(viewer: nil)
    end
  end

  context "#followers_count" do
    test "returns 0 if the user doesn't have any followers" do
      assert_equal 0, @user_1.followers_count(viewer: nil)
    end

    test "persists the count if it hasn't been set" do
      assert_nil Profiles::Kv.store.get("user.followers_count.#{@user_1.id}").value!
      @user_1.followers_count(viewer: nil)
      refute_nil Profiles::Kv.store.get("user.followers_count.#{@user_1.id}").value!
    end

    test "returns the total count of followers" do
      assert_difference("@user_1.followers_count(viewer: nil)") do
        calculate_followerings_immediately { assert @user_2.follow(@user_1) }
      end

      assert_difference("@user_1.followers_count(viewer: nil)") do
        calculate_followerings_immediately { assert @user_3.follow(@user_1) }
      end

      assert_difference("@user_1.followers_count(viewer: nil)", -1) do
        calculate_followerings_immediately { assert @user_2.unfollow(@user_1) }
      end
    end
  end

  context "#followed_by?" do
    test "indicates whether the user is followed by another user" do
      refute @user_2.followed_by?(@user_1)

      assert @user_1.follow(@user_2), "should return true on follow success"
      assert @user_2.reload.followed_by?(@user_1)

      assert @user_1.unfollow(@user_2), "should return true on unfollow success"
      refute @user_2.reload.followed_by?(@user_1)

      assert @user_2.follow(@user_1), "should return true on follow success"
      refute @user_2.reload.followed_by?(@user_1)

      assert @user_1.follow(@user_2), "should return true on follow success"
      assert @user_2.reload.followed_by?(@user_1)
    end

    test "returns false if nil is passed" do
      refute @user_1.followed_by?(nil)
    end

    test "batches into a single followings query when using prelude" do
      assert_max_query_count_per_table({ followings: 1 }) do
        users = [@user_2, @user_3]
        GitHub::PrefillAssociations.prefill_batch_method(users, :followed_by?, @user_1)

        users.each do |user|
          user.followed_by?(@user_1)
        end
      end
    end
  end

  context "#following_users_count" do
    test "returns the number of users that follow the user" do
      @user_1.follow(@user_2)

      assert_equal 1, @user_1.following_users_count
    end
  end

  context "when user is deleted" do
    test "deletes the cached following count key" do
      @user_1.following_count(viewer: nil)
      refute_nil Profiles::Kv.store.get("user.following_count.#{@user_1.id}").value!

      @user_1.destroy
      assert_nil Profiles::Kv.store.get("user.following_count.#{@user_1.id}").value!
    end

    test "deletes the cached followers count key" do
      @user_1.followers_count(viewer: nil)
      refute_nil Profiles::Kv.store.get("user.followers_count.#{@user_1.id}").value!

      @user_1.destroy
      assert_nil Profiles::Kv.store.get("user.followers_count.#{@user_1.id}").value!
    end
  end

  unless GitHub.enterprise?
    test "doesn't count spammy user in regular user followers count" do
      @spammy_user.follow(@user_1)
      assert_equal 1, reload_user(@user_1).followers_count(viewer: nil)
      perform_enqueued_jobs(only: UpdateTableUserHiddenJob) do
        @spammy_user.mark_as_spammy(actor: @staff, reason: "merit")
      end
      @user_1.followers_count!
      assert_equal 0, reload_user(@user_1).followers_count(viewer: nil)
    end

    test "doesn't count spammy user in regular user following count" do
      @user_1.follow(@spammy_user)
      assert_equal 1, reload_user(@user_1).following_count(viewer: nil)
      perform_enqueued_jobs(only: UpdateTableUserHiddenJob) do
        @spammy_user.mark_as_spammy(actor: @staff, reason: "merit")
      end
      @user_1.following_count!
      assert_equal 0, reload_user(@user_1).following_count(viewer: nil)
    end

    test "hides spammy user followers count" do
      @user_1.follow(@spammy_user)
      assert_equal 1, reload_user(@spammy_user).followers_count(viewer: nil)
      perform_enqueued_jobs(only: UpdateTableUserHiddenJob) do
        @spammy_user.mark_as_spammy(actor: @staff, reason: "merit")
      end
      @spammy_user.followers_count!
      assert_equal 0, reload_user(@spammy_user).followers_count(viewer: nil)
    end

    test "hides spammy user followings count" do
      @spammy_user.follow(@user_1)
      assert_equal 1, reload_user(@spammy_user).following_count(viewer: nil)
      perform_enqueued_jobs(only: UpdateTableUserHiddenJob) do
        @spammy_user.mark_as_spammy(actor: @staff, reason: "merit")
      end
      @spammy_user.following_count!
      assert_equal 0, reload_user(@spammy_user).following_count(viewer: nil)
    end

    test "returns 0 followers for private users" do
      @private_user = create(:user)
      @user_1.follow(@private_user)
      assert_equal 1, reload_user(@private_user).followers_count(viewer: nil)
      @private_user.update!(private_profile: true)
      assert_equal 0, reload_user(@user_1).followers_count(viewer: nil)
    end

    test "returns 0 followings for private users" do
      @private_user = create(:user)
      @private_user.follow(@user_1)
      assert_equal 1, reload_user(@private_user).following_count(viewer: nil)
      @private_user.update!(private_profile: true)
      assert_equal 0, reload_user(@private_user).following_count(viewer: nil)
    end
  end

  context "#followers_for_viewer" do
    test "returns 0 followers for private users" do
      @user_2.follow(@user_1)
      @user_1.update!(private_profile: true)

      assert_empty @user_1.followers_for_viewer(@user_2)
    end

    test "returns followers for private users if they are the viewer" do
      @user_2.follow(@user_1)
      @user_1.update!(private_profile: true)

      assert_equal [@user_2], @user_1.followers_for_viewer(@user_1)
    end

    test "returns followers for non-private users even if viewer is nil" do
      @user_2.follow(@user_1)

      assert_equal [@user_2], @user_1.followers_for_viewer(nil)
    end

    test "returns followers sorted by user id" do
      @user_3.follow(@user_1)  # Create Followings in reverse order
      @user_2.follow(@user_1)

      expected_id_order = [@user_2, @user_3].map(&:id)
      assert_equal expected_id_order, @user_1.followers_for_viewer(nil).pluck(:id)
    end

    test "excludes spammy followers when a spammy user is viewing their own followers", spammy_only: true do
      @user_2.follow(@user_1)
      @user_3.follow(@user_1)

      perform_enqueued_jobs(only: UpdateTableUserHiddenJob) do
        @user_1.mark_as_spammy(actor: @staff, reason: "merit")
        @user_2.mark_as_spammy(actor: @staff, reason: "merit")
      end

      assert_equal [@user_3], @user_1.followers_for_viewer(@user_1)
    end

    test "includes spammy followers when the viewer is a staff member", spammy_only: true do
      @user_2.follow(@user_1)
      @user_3.follow(@user_1)

      perform_enqueued_jobs(only: UpdateTableUserHiddenJob) do
        @user_1.mark_as_spammy(actor: @staff, reason: "merit")
        @user_2.mark_as_spammy(actor: @staff, reason: "merit")
      end

      assert_same_elements [@user_2, @user_3], @user_1.followers_for_viewer(@staff)
    end
  end

  context "#following_for_viewer" do
    test "returns 0 followings for private users" do
      @user_1.follow(@user_2)
      @user_1.update!(private_profile: true)

      assert_empty @user_1.following_for_viewer(@user_2)
    end

    test "returns followings for private users if they are the viewer" do
      @user_1.follow(@user_2)
      @user_1.update!(private_profile: true)

      assert_equal [@user_2], @user_1.following_for_viewer(@user_1)
    end

    test "returns followings for non-private users even if viewer is nil" do
      @user_1.follow(@user_2)

      assert_equal [@user_2], @user_1.following_for_viewer(nil)
    end

    test "returns followings sorted by user id" do
      @user_2.follow(@user_3) # Create Followings in reverse order
      @user_2.follow(@user_1)

      expected_id_order = [@user_1, @user_3].map(&:id)
      assert_equal expected_id_order, @user_2.following_for_viewer(nil).pluck(:id)
    end

    test "excludes spammy following when a spammy user is viewing their own following", spammy_only: true do
      @user_1.follow(@user_2)
      @user_1.follow(@user_3)

      perform_enqueued_jobs(only: UpdateTableUserHiddenJob) do
        @user_1.mark_as_spammy(actor: @staff, reason: "merit")
        @user_2.mark_as_spammy(actor: @staff, reason: "merit")
      end

      assert_equal [@user_3], @user_1.following_for_viewer(@user_1)
    end

    test "includes spammy following when the viewer is a staff member", spammy_only: true do
      @user_1.follow(@user_2)
      @user_1.follow(@user_3)

      perform_enqueued_jobs(only: UpdateTableUserHiddenJob) do
        @user_1.mark_as_spammy(actor: @staff, reason: "merit")
        @user_2.mark_as_spammy(actor: @staff, reason: "merit")
      end

      assert_same_elements [@user_2, @user_3], @user_1.following_for_viewer(@staff)
    end
  end
end
