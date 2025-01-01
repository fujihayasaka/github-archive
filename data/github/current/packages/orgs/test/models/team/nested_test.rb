# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamNestedTest < GitHub::TestCase
  fixtures do
    @org = create :organization, plan: "bronze"

    @parent_team_1 = create :team, organization: @org, privacy: :closed
    @parent_team_member_1 = create(:user)
    @parent_team_1.add_member(@parent_team_member_1)
    @child_team_1 = create :team, organization: @org, privacy: :closed, parent_team_id: @parent_team_1.id
    @child_team_member_1 = create(:user)
    @child_team_1.add_member(@child_team_member_1)

    @parent_team_2 = create :team, organization: @org, privacy: :closed
    @parent_team_member_2 = create(:user)
    @parent_team_2.add_member(@parent_team_member_2)
    @child_team_2 = create :team, organization: @org, privacy: :closed, parent_team_id: @parent_team_2.id
    @child_team_member_2 = create(:user)
    @child_team_2.add_member(@child_team_member_2)

    @parent_team_3 = create :team, organization: @org, privacy: :closed
    @child_team_3 = create :team, organization: @org, privacy: :closed, parent_team_id: @parent_team_3.id
    @child_team_4 = create :team, organization: @org, privacy: :closed, parent_team_id: @child_team_3.id

    @parent_team_ids = [@parent_team_1.id, @parent_team_2.id]
  end

  context ".members_of" do
    context "with no argument" do
      test "should return only immediate children" do
        members = Team.members_of(@parent_team_ids)
        assert_same_elements [@parent_team_member_1, @parent_team_member_2], members
      end

      test "should be okay with teams passed as splat" do
        members = Team.members_of(*@parent_team_ids)
        assert_same_elements [@parent_team_member_1, @parent_team_member_2], members
      end
    end

    context "with immediate_only = true" do
      test "should return only immediate children" do
        members = Team.members_of(@parent_team_ids, immediate_only: true)
        assert_same_elements [@parent_team_member_1, @parent_team_member_2], members
      end
    end

    context "with immediate_only = false" do
      test "should return all descendant members" do
        members = Team.members_of(@parent_team_ids, immediate_only: false)
        assert_same_elements [@parent_team_member_1, @child_team_member_1, @parent_team_member_2, @child_team_member_2], members
      end
    end
  end

  context ".member_of?" do
    context "with no argument" do
      test "should return true for immediate members" do
        assert Team.member_of?(@parent_team_ids, @parent_team_member_1.id)
      end

      test "should be okay with teams passed as splat" do
        assert Team.member_of?(*@parent_team_ids, @parent_team_member_1.id)
      end

      test "should return false for descendant members" do
        refute Team.member_of?(@parent_team_ids, @child_team_member_1.id)
      end

      test "should return false for non-members" do
        refute Team.member_of?(@parent_team_ids, create(:user).id)
      end
    end

    context "with immediate_only = true" do
      test "should return true for immediate members" do
        assert Team.member_of?(@parent_team_ids, @parent_team_member_1.id, immediate_only: true)
      end

      test "should return false for descendant members" do
        refute Team.member_of?(@parent_team_ids, @child_team_member_1.id, immediate_only: true)
      end

      test "should return false for non-members" do
        refute Team.member_of?(@parent_team_ids, create(:user).id, immediate_only: true)
      end
    end

    context "with immediate_only = false" do
      test "should return true for immediate members" do
        assert Team.member_of?(@parent_team_ids, @parent_team_member_1.id, immediate_only: false)
      end

      test "should return true for descendant members" do
        assert Team.member_of?(@parent_team_ids, @child_team_member_1.id, immediate_only: false)
      end

      test "should return false for non-members" do
        refute Team.member_of?(@parent_team_ids, create(:user).id, immediate_only: false)
      end
    end
  end

  context ".descendant_ids" do
    test "returns descendant team IDs" do
      ids = Team.descendant_ids([@parent_team_1, @parent_team_2, @parent_team_3])
      expected_ids = [@child_team_1, @child_team_2, @child_team_3, @child_team_4].map(&:id)

      assert_same_elements expected_ids, ids
    end

    test "only returns immediate descendant team IDs if specified" do
      ids = Team.descendant_ids \
        [@parent_team_1, @parent_team_2, @parent_team_3],
        immediate_only: true
      expected_ids = [@child_team_1, @child_team_2, @child_team_3].map(&:id)

      assert_same_elements expected_ids, ids
    end
  end

  context ".ancestor_and_descendant_ids" do
    test "returns all ancestor and descendant team IDs" do
      ids = @child_team_3.ancestor_and_descendant_ids
      expected_ids = [@parent_team_3, @child_team_4].map(&:id)

      assert_same_elements expected_ids, ids
    end
  end

  context "has_child_teams?" do
    test "returns true when there are child teams" do
      assert @parent_team_1.has_child_teams?
    end

    test "returns false when there are no child teams" do
      refute @child_team_1.has_child_teams?
    end
  end

  context "unnotifiable_member_ids" do
    test "return all team members ids if user is ignoring team and has the flag enabled" do
      GitHub.flipper[:ignorable_team_notifications].enable

      perform_enqueued_jobs(only: [Newsies::NotifyListSubscriptionStatusChangeJob]) do
        GitHub.newsies.ignore_list(@child_team_member_2, @child_team_2)
      end

      assert_predicate @child_team_2.subscription_status(@child_team_member_2).value!, :ignored?

      ids = @child_team_2.reload.unnotifiable_member_ids
      expected_ids = [@child_team_member_2].map(&:id)

      assert_same_elements expected_ids, ids
    end

    test "return empty if user is ignoring team but has the flag disabled" do
      GitHub.flipper[:ignorable_team_notifications].disable

      perform_enqueued_jobs(only: [Newsies::NotifyListSubscriptionStatusChangeJob]) do
        GitHub.newsies.ignore_list(@child_team_member_2, @child_team_2)
      end

      assert_predicate @child_team_2.subscription_status(@child_team_member_2).value!, :ignored?
      assert_empty @child_team_2.reload.unnotifiable_member_ids
    end
  end

  context "notifiable_member_ids" do
    test "return all notifiable members id excluding users ignoring team and org has the flag enabled" do
      GitHub.flipper[:ignorable_team_notifications].enable

      assert GitHub.flipper[:ignorable_team_notifications].enabled?(@child_team_member_2)
      assert GitHub.flipper[:ignorable_team_notifications].enabled?(@org)

      perform_enqueued_jobs(only: [Newsies::NotifyListSubscriptionStatusChangeJob]) do
        GitHub.newsies.ignore_list(@child_team_member_2, @parent_team_2)
      end

      assert_predicate @parent_team_2.subscription_status(@child_team_member_2).value!, :ignored?

      ids = @parent_team_2.notifiable_member_ids
      expected_ids = [@parent_team_member_2].map(&:id)

      assert_same_elements expected_ids, ids
    end

    test "return all descendant or self member ids when user has the feature flag enable and organization has not" do
      GitHub.flipper[:ignorable_team_notifications].enable(@child_team_member_2)
      GitHub.flipper[:ignorable_team_notifications].disable(@org)

      assert GitHub.flipper[:ignorable_team_notifications].enabled?(@child_team_member_2)
      refute GitHub.flipper[:ignorable_team_notifications].enabled?(@org)

      perform_enqueued_jobs(only: [Newsies::NotifyListSubscriptionStatusChangeJob]) do
        GitHub.newsies.ignore_list(@child_team_member_2, @parent_team_2)
      end

      assert_predicate @parent_team_2.subscription_status(@child_team_member_2).value!, :ignored?

      ids = @parent_team_2.notifiable_member_ids
      expected_ids = [@parent_team_member_2, @child_team_member_2].map(&:id)

      assert_same_elements expected_ids, ids
    end

    test "return all descendant or self member ids" do
      GitHub.flipper[:ignorable_team_notifications].disable

      perform_enqueued_jobs(only: [Newsies::NotifyListSubscriptionStatusChangeJob]) do
        GitHub.newsies.ignore_list(@child_team_member_2, @parent_team_2)
      end

      assert_predicate @parent_team_2.subscription_status(@child_team_member_2).value!, :ignored?

      ids = @parent_team_2.notifiable_member_ids
      expected_ids = [@parent_team_member_2, @child_team_member_2].map(&:id)

      assert_same_elements expected_ids, ids
    end
  end

  context "notifiable_members" do
    test "return all notifiable members id excluding users ignoring team and has the flag enabled" do
      GitHub.flipper[:ignorable_team_notifications].enable

      perform_enqueued_jobs(only: [Newsies::NotifyListSubscriptionStatusChangeJob]) do
        GitHub.newsies.ignore_list(@child_team_member_2, @parent_team_2)
      end

      assert_predicate @parent_team_2.subscription_status(@child_team_member_2).value!, :ignored?

      collection = @parent_team_2.notifiable_members
      expected_collection = [@parent_team_member_2]

      assert_same_elements expected_collection, collection
    end

    test "return all descendant or self member ids" do
      GitHub.flipper[:ignorable_team_notifications].disable

      perform_enqueued_jobs(only: [Newsies::NotifyListSubscriptionStatusChangeJob]) do
        GitHub.newsies.ignore_list(@child_team_member_2, @parent_team_2)
      end

      assert_predicate @parent_team_2.subscription_status(@child_team_member_2).value!, :ignored?

      collection = @parent_team_2.notifiable_members
      expected_collection = [@parent_team_member_2, @child_team_member_2]

      assert_same_elements expected_collection, collection
    end
  end
end
