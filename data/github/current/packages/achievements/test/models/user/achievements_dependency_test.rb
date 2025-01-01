# typed: true
# frozen_string_literal: true

require "test_helper"

class UserAchievementsDependencyTest < GitHub::TestCase
  fixtures do
    @user, @achieved_user = create_pair(:verified_user)

    @ach_dust_bunny = create(:achievement, :dust_bunny, user: @achieved_user)
    @ach_heart_on_your_sleeve = create(:achievement, :heart_on_your_sleeve, user: @achieved_user)
  end

  context "achievements relation" do
    test "links a user to their earned achievements" do
      assert_same_elements [@ach_dust_bunny, @ach_heart_on_your_sleeve], @achieved_user.reload.achievements
      @achieved_user.achievements.each do |ach|
        assert_same @achieved_user, ach.user
      end
    end

    test "should destroy achievements when user is destroyed" do
      assert_difference -> { Achievement.count }, -2 do
        @achieved_user.destroy
      end

      assert_empty Achievement.where(user: @achieved_user)
    end
  end

  context "visible_highest_tier_achievements" do
    test "returns highest-tier public achievements for users with private contributions disabled" do
      @user.profile_settings.show_private_contribution_count = false

      create(:achievement, :heart_on_your_sleeve, :public_scope, user: @user, tier: 0)
      create(:achievement, :heart_on_your_sleeve, :public_scope, user: @user, tier: 1)
      ach0 = create(:achievement, :heart_on_your_sleeve, :public_scope, user: @user, tier: 2, unlocked_at: 2.days.ago)

      ach1 = create(:achievement, :heartbreaker, :public_scope, user: @user, unlocked_at: 1.day.ago)

      create(:achievement, :heart_on_your_sleeve, :private_scope, user: @user, tier: 3, unlocked_at: Time.now)

      assert_equal [ach1, ach0], @user.visible_highest_tier_achievements
    end

    test "returns highest-tier private achievements for users with private contributions enabled" do
      @user.profile_settings.show_private_contribution_count = true

      create(:achievement, :pull_shark, :private_scope, user: @user, tier: 0)
      create(:achievement, :pull_shark, :private_scope, user: @user, tier: 1)
      create(:achievement, :pull_shark, :private_scope, user: @user, tier: 2)
      ach0 = create(:achievement, :pull_shark, :private_scope, user: @user, tier: 3, unlocked_at: 2.days.ago)

      ach1 = create(:achievement, :heart_on_your_sleeve, :private_scope, user: @user, tier: 0, unlocked_at: 1.day.ago)

      create(:achievement, :heart_on_your_sleeve, :public_scope, user: @user, tier: 1, unlocked_at: Time.now)

      assert_equal [ach1, ach0], @user.visible_highest_tier_achievements
    end

    test "returns achievements for multiple users at once, respecting visibility settings for each individually" do
      @user.profile_settings.show_private_contribution_count = false
      other = create(:user)
      other.profile_settings.show_private_contribution_count = true

      create(:achievement, :pull_shark, :public_scope, user: @user, tier: 0)
      ach0_0 = create(:achievement, :pull_shark, :public_scope, user: @user, tier: 1, unlocked_at: 1.day.ago)
      create(:achievement, :pull_shark, :private_scope, user: @user, tier: 2)
      ach0_1 = create(:achievement, :yolo, :public_scope, user: @user, unlocked_at: Time.now)

      ach1_0 = create(:achievement, :pull_shark, :private_scope, user: other, tier: 0, unlocked_at: 1.day.ago)
      create(:achievement, :pull_shark, :public_scope, user: other, tier: 1)
      ach1_1 = create(:achievement, :heart_on_your_sleeve, :private_scope, user: other, tier: 0, unlocked_at: Time.now)

      promises = [
        @user.async_batch_visible_highest_tier_achievements.then { |achs| [@user, achs] },
        other.async_batch_visible_highest_tier_achievements.then { |achs| [other, achs] },
      ]
      results = Promise.all(promises).sync
      assert_equal [
        [@user, [ach0_1, ach0_0]],
        [other, [ach1_1, ach1_0]],
      ], results
    end
  end

  context "highest_tier_achievements" do
    test "returns an empty array if no achievements are earned" do
      assert_empty @user.highest_tier_achievements
    end

    test "returns an array of the highest-tier achievements for each achievable, ordered by most recently earned" do
      ach3 = create(:achievement, :dust_bunny, user: @user, unlocked_at: 3.days.ago)

      create(:achievement, :pull_shark, user: @user, tier: 0, unlocked_at: 4.days.ago)
      ach2 = create(:achievement, :pull_shark, user: @user, tier: 1, unlocked_at: 2.days.ago)

      ach1 = create(:achievement, :yolo, user: @user, unlocked_at: 1.day.ago)

      assert_equal [ach1, ach2, ach3], @user.highest_tier_achievements
    end

    test "returns the highest tier of each achievable even if the unlocking timestamps are out of order" do
      ach0 = create(:achievement, :pull_shark, user: @user, tier: 0, unlocked_at: 5.days.ago)
      ach1 = create(:achievement, :pull_shark, user: @user, tier: 1, unlocked_at: 1.day.ago)
      ach2 = create(:achievement, :pull_shark, user: @user, tier: 2, unlocked_at: 3.days.ago)

      ach3 = create(:achievement, :galaxy_brain, user: @user, tier: 0, unlocked_at: 4.days.ago)
      ach4 = create(:achievement, :galaxy_brain, user: @user, tier: 1, unlocked_at: 2.days.ago)

      assert_equal [ach4, ach2], @user.highest_tier_achievements
    end
  end

  context "all_highest_tier_achievements" do
    test "returns a pair of arrays of the highest-tier achievements for each achievable" do
      pub_ach0 = create(:achievement, :pull_shark, :public_scope, user: @user, tier: 0, unlocked_at: 3.days.ago)
      create(:achievement, :open_sourcerer, :public_scope, user: @user, tier: 0, unlocked_at: 2.days.ago)
      pub_ach1 = create(:achievement, :open_sourcerer, :public_scope, user: @user, tier: 1, unlocked_at: 1.day.ago)

      create(:achievement, :pull_shark, :private_scope, user: @user, tier: 0, unlocked_at: 4.days.ago)
      priv_ach0 = create(:achievement, :pull_shark, :private_scope, user: @user, tier: 1, unlocked_at: 3.days.ago)
      priv_ach1 = create(:achievement, :open_sourcerer, :private_scope, user: @user, tier: 1, unlocked_at: 2.days.ago)
      priv_ach2 = create(:achievement, :dust_bunny, :private_scope, user: @user, unlocked_at: 1.day.ago)

      assert_query_count_per_table({ achievements: 1 }) do
        assert_equal [[pub_ach1, pub_ach0], [priv_ach2, priv_ach1, priv_ach0]], @user.all_highest_tier_achievements
      end
    end

    test "identifies the highest-tier achievement even when unlocking timestamps are out of order" do
      pub_ach0 = create(:achievement, :pull_shark, :public_scope, user: @user, tier: 0, unlocked_at: 3.days.ago)
      create(:achievement, :open_sourcerer, :public_scope, user: @user, tier: 0, unlocked_at: 1.day.ago)
      pub_ach1 = create(:achievement, :open_sourcerer, :public_scope, user: @user, tier: 1, unlocked_at: 2.days.ago)

      create(:achievement, :pull_shark, :private_scope, user: @user, tier: 0, unlocked_at: 3.days.ago)
      priv_ach0 = create(:achievement, :pull_shark, :private_scope, user: @user, tier: 1, unlocked_at: 4.days.ago)
      priv_ach1 = create(:achievement, :open_sourcerer, :private_scope, user: @user, tier: 1, unlocked_at: 2.days.ago)
      priv_ach2 = create(:achievement, :dust_bunny, :private_scope, user: @user, unlocked_at: 1.day.ago)

      assert_query_count_per_table({ achievements: 1 }) do
        assert_equal [[pub_ach1, pub_ach0], [priv_ach2, priv_ach1, priv_ach0]], @user.all_highest_tier_achievements
      end
    end
  end

  context "#has_achievement?" do
    test "it returns true when the user has the given achievement" do
      create(:achievement, :heartbreaker, user: @user)

      assert @user.has_achievement?(Achievable::Heartbreaker)
    end

    test "it returns false when the user does not have the given achievement" do
      refute @user.has_achievement?(Achievable::Heartbreaker)
    end
  end

  context "#has_achievement_with_tier?" do
    test "it returns true when the user has the given achievement with the given tier" do
      create(:achievement, :heartbreaker, user: @user, tier: 0)

      assert @user.has_achievement_with_tier?(Achievable::Heartbreaker, 0)
      refute @user.has_achievement_with_tier?(Achievable::Heartbreaker, 3)
    end

    test "it returns false when the user does not have the given achievement with the given tier" do
      refute @user.has_achievement_with_tier?(Achievable::Heartbreaker, 1)
    end
  end

  context "#achievement_tier_for" do
    test "it returns the tier of the given achievement" do
      create(:achievement, :heartbreaker, user: @user, tier: 0)

      assert_equal 0, @user.achievement_tier_for(Achievable::Heartbreaker)
    end

    test "it returns -1 when the user does not have the given achievement" do
      assert_equal -1, @user.achievement_tier_for(Achievable::Heartbreaker)
    end
  end

  context "#achievements_for" do
    test "it returns a collection of achievements for the given achievable" do
      heartbreaker_achievement = create(:achievement, :heartbreaker, user: @user)

      assert_same_elements [heartbreaker_achievement], @user.achievements_for(Achievable::Heartbreaker)
    end

    test "it returns an empty collection when the user does not have any of the given achievable" do
      assert_empty @user.achievements_for(Achievable::Heartbreaker)
    end

    test "it returns only visible achievements for anonymous and non-self users" do
      heartbreaker_ach = create(:achievement, :heartbreaker, user: @user, hidden: true)

      assert_empty @user.achievements_for(Achievable::Heartbreaker)
    end

    test "it returns all achievements for self users" do
      heartbreaker_ach = create(:achievement, :heartbreaker, user: @user, hidden: true)

      assert_equal(
        [heartbreaker_ach],
        @user.achievements_for(Achievable::Heartbreaker, viewer: @user),
      )
    end
  end

  context "#achievement_progress_for" do
    test "it returns the progress of the given achievement" do
      achievement_progression = create(
        :pair_extraordinaire_achievement_progression,
        user: @user,
        private_count: 5,
        public_count: 10,
      )

      assert_equal(
        achievement_progression,
        @user.achievement_progression_for(Achievable::PairExtraordinaire),
      )
    end

    test "it returns 0 when the user does not have progress for the given achievement" do
      assert_equal(
        { private_count: 0, public_count: 0 },
        @user.achievement_progression_for(Achievable::PairExtraordinaire).to_h,
      )
    end
  end
end
