# typed: true
# frozen_string_literal: true

require "test_helper"

class FollowingTest < GitHub::TestCase
  setup do
    @user     = create(:user)
    @follower = create(:user)
    @spammer  = create(:user)
    @organization = create(:organization)

    @spammer.mark_as_spammy

    @follower.follow(@user)
    @follower.follow(@spammer)
    @spammer.follow(@user)
  end

  setup do
    reset_cache
  end

  setup_once do
    enable_cache_storage
  end

  teardown_once do
    disable_cache_storage
  end

  context "#mutual_followers" do
    test "returns mutual followers" do
      viewer = create(:user)
      mutual_follower = create(:user)
      user = create(:user)
      user1 = create(:user)
      viewer.follow(mutual_follower)
      mutual_follower.follow(user)
      user1.follow(user)

      mutual_followers = Following.mutual_followers(user: user, viewer: viewer)

      assert_equal [mutual_follower], mutual_followers
    end

    if GitHub.spamminess_check_enabled?
      test "excludes spammy followers for non-site admin viewer" do
        viewer = create(:user)
        spammer = create(:user, spammy: true)
        user = create(:user)
        viewer.follow(spammer)
        spammer.follow(user)

        mutual_followers = Following.mutual_followers(user: user, viewer: viewer)

        assert_empty mutual_followers
      end

      test "includes spammy follower for site admin viewer" do
        site_admin = create(:staff_admin_user)
        spammer = create(:user)
        user = create(:user)
        site_admin.follow(spammer)
        spammer.follow(user)
        spammer.mark_as_spammy

        mutual_followers = Following.mutual_followers(user: user, viewer: site_admin)

        assert_equal [spammer], mutual_followers
      end
    end

    test "includes organizations" do
      viewer = create(:user)
      user = create(:user)
      viewer.follow(@organization)
      @organization.follow(user)

      mutual_followers = Following.mutual_followers(user: user, viewer: viewer)

      assert_equal [@organization], mutual_followers
    end

    test "for a private profile does not return followings" do
      viewer = create(:user)
      user = create(:user)
      private_profile = create(:user)
      viewer.follow(private_profile)
      private_profile.follow(user)
      private_profile.update!(private_profile: true)

      mutual_followers = Following.mutual_followers(user: user, viewer: viewer)

      assert_equal [private_profile], mutual_followers
    end
  end

  context "filter_spammy_followers_and_followed_users scope" do
    if GitHub.spamminess_check_enabled?
      test "excludes spammy follower for non-site admin viewer" do
        followings = Following.filter_spammy_followers_and_followed_users(@user, type: :follower)

        refute_empty followings, "should include other followings from fixtures block"
        refute_includes followings.map(&:user), @spammer, "should not include spammy follower"
      end

      test "excludes spammy followed user for non-site admin viewer" do
        followings = Following.filter_spammy_followers_and_followed_users(@user,
                                                                          type: :followed_user)

        refute_empty followings, "should include other followings from fixtures block"
        refute_includes followings.map(&:following), @spammer,
          "should not include spammy followed user"
      end

      test "includes spammy follower for site admin viewer" do
        site_admin = create(:staff_admin_user)

        followings = Following.filter_spammy_followers_and_followed_users(site_admin,
                                                                          type: :follower)

        assert_includes followings.map(&:user), @spammer, "should include spammy follower"
      end

      test "includes spammy followed user for site admin viewer" do
        site_admin = create(:staff_admin_user)

        followings = Following.filter_spammy_followers_and_followed_users(site_admin,
                                                                          type: :followed_user)

        assert_includes followings.map(&:following), @spammer, "should include spammy followed user"
      end
    end
  end

  context "not_suspended scope" do
    test "excludes followings where the follower is suspended" do
      suspended_user = create(:suspended_user)
      user = create(:user)
      suspended_user.follow(user)

      followings = Following.not_suspended(type: :follower)

      refute_empty followings, "should include other followings from fixtures block"
      refute_includes followings.map(&:user), suspended_user,
        "followings should not include one where the user doing the following is suspended"
    end

    test "excludes followings where the followed user is suspended" do
      suspended_user = create(:suspended_user)
      user = create(:user)
      user.follow(suspended_user)

      followings = Following.not_suspended(type: :followed_user)

      refute_empty followings, "should include other followings from fixtures block"
      refute_includes followings.map(&:following), suspended_user,
        "followings should not include one where the followed user is suspended"
    end
  end

  context "followed_by scope" do
    test "includes followings where the given user is the one doing following" do
      followings = Following.followed_by(@follower)

      assert_equal 2, followings.size
      assert_same_elements [@user, @spammer], followings.map(&:following)
    end
  end

  context "follower_of scope" do
    test "includes followings where the given user is being followed" do
      followings = Following.follower_of(@user)

      assert_equal 2, followings.size
      assert_same_elements [@follower, @spammer], followings.map(&:user)
    end
  end

  context "following users" do
    if GitHub.spamminess_check_enabled?
      test "spammers are not followers" do
        all_followers = Following.where(following_id: @user)
        assert_equal 2, all_followers.size

        followers_without_spammers = Following.not_spammy.where(following_id: @user)
        assert_equal 1, followers_without_spammers.size
        assert_equal @follower.id, T.must(T.must(followers_without_spammers.first).user).id
      end
    end
  end

  context "#valid?" do
    test "returns false when rate limit is exceeded" do
      enable_content_creation_rate_limiting

      user = create(:user)
      expected_errors = [GitHub::RateLimitedCreation::ERROR_MESSAGE]
      limit = 2

      Timecop.freeze do
        GitHub::RateLimitedCreation.use_custom_limits(user_minute: limit) do
          limit.times { Following.create(user: user, following: create(:user)) }

          following = Following.new(user: user, following: create(:user))

          refute_predicate following, :valid?
          assert_equal expected_errors, following.errors.full_messages
        end
      end
    end

    test "returns true when rate limit is not exceeded" do
      enable_content_creation_rate_limiting

      user = create(:user)
      limit = 2

      Timecop.freeze do
        GitHub::RateLimitedCreation.use_custom_limits(user_minute: limit) do
          (limit - 1).times { Following.create(user: user, following: create(:user)) }

          following = Following.new(user: user, following: create(:user))

          assert_predicate following, :valid?
        end
      end
    end
  end

  test "can't follow the same user twice" do
    assert @user.followed_by?(@follower)

    following = Following.new(user: @follower, following: @user)
    refute following.valid?
    refute following.errors[:user_id].blank?
  end

  test "followee_id is present event when following user has been deleted" do
    following_id = @user.id

    subscriber = GlobalInstrumenter.subscribe("user.unfollow") do |_event, _, _, _, payload|
      assert_nil payload[:followee]
      assert_equal following_id, payload[:followee_id]
    end

    @user.destroy
    GlobalInstrumenter.notifier.unsubscribe(subscriber)
  end

  test "followee_id is present when following org has been deleted" do
    org = create(:organization)
    following_id = org.id

    user = create(:user)
    user.follow(org)

    subscriber = GlobalInstrumenter.subscribe("user.unfollow") do |_event, _, _, _, payload|
      assert_nil payload[:followee]
      assert_equal following_id, payload[:followee_id]
    end

    org.destroy
    GlobalInstrumenter.notifier.unsubscribe(subscriber)
  end
end
