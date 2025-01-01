# typed: false
# frozen_string_literal: true

require "test_helper"

class UseruserRankingDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:credit_card_user, plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons)

    @followed_user1 = create(:user, login: "followed-user1")
    @user.follow(@followed_user1)

    @unfollowed_user1 = create(:user, login: "unfollowed-user1")
    @unfollowed_user2 = create(:user, login: "unfollowed-user2")

    @followed_user2 = create(:user, login: "followed-user2")
    @user.follow(@followed_user2)
  end

  context "#ranked_for_ids" do
    test "limits queries per table" do
      scoped_ids = [@user, @followed_user1, @followed_user2, @unfollowed_user1, @unfollowed_user2].map(&:id)
      assert_query_count_per_table({ followers: 1, users: 1, sponsorships: 1 }) do
        User.ranked_for_ids(@user, scoped_ids: scoped_ids)
      end
    end
  end

  context "#ranked_for" do
    test "sorts followed users higher than unfollowed users" do
      relevant_users = User.where(id: [@followed_user1, @unfollowed_user1, @unfollowed_user2,
                                       @followed_user2])
      expected = [@followed_user2, @followed_user1, @unfollowed_user1, @unfollowed_user2]

      actual = User.ranked_for(@user, scope: relevant_users)

      assert_equal expected, actual
    end

    test "sorts mutually followed users higher than followed users" do
      @followed_user2.follow(@user)
      followed_user3 = create(:user, login: "followed-user3")
      @user.follow(followed_user3)
      relevant_users = User.where(id: [@followed_user1, @followed_user2, followed_user3])
      expected = [@followed_user2, followed_user3, @followed_user1]

      actual = User.ranked_for(@user, scope: relevant_users)

      assert_equal expected, actual
    end

    test "sorts sponsored users higher than followed users and unfollowed users" do
      sponsored_user1 = create(:user, :sponsorable, login: "sponsored-user1")
      create(:sponsorship, sponsor: @user, sponsorable: sponsored_user1)
      sponsored_user2 = create(:user, :sponsorable, login: "sponsored-user2")
      create(:sponsorship, sponsor: @user, sponsorable: sponsored_user2)
      relevant_users = User.where(id: [@followed_user1, @unfollowed_user1, @unfollowed_user2,
                                       @followed_user2, sponsored_user1, sponsored_user2])
      expected = [sponsored_user2, sponsored_user1, @followed_user2, @followed_user1, @unfollowed_user1,
        @unfollowed_user2]

      actual = User.ranked_for(@user, scope: relevant_users)

      assert_equal expected, actual
    end

    test "sorts sponsored users higher than mutual followers" do
      @followed_user2.follow(@user) # user is following and being followed by followed_user2
      sponsored_user = create(:user, :sponsorable, login: "sponsored-user")
      create(:sponsorship, sponsor: @user, sponsorable: sponsored_user)
      relevant_users = User.where(id: [@followed_user2, sponsored_user])

      actual = User.ranked_for(@user, scope: relevant_users)

      assert_equal [sponsored_user, @followed_user2], actual
    end

    test "limits queries per table" do
      assert_query_count_per_table({ followers: 1, users: 1, sponsorships: 1 }) do
        User.ranked_for(@user, scope: User.all)
      end
    end
  end
end
