# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.interaction_limits_enabled?
  class UserInteractionBlockingTest < GitHub::TestCase
    fixtures do
      @user = create(:user, login: "johnnycash")
      @owner = create(:user, login: "junecartercash")
      @repo = create(:repository, owner: @owner)
    end

    context "user_can_push is already known and true" do
      test ".interaction_allowed? doesn't check pushable and returns true" do
        @repo.expects(:async_pushable_by?).never
        assert User::InteractionAbility.interaction_allowed?(user: @user, repository: @repo, user_can_push: true)
      end
    end

    context "user_can_push is already known and false" do
      test ".interaction_allowed? doesn't check pushable" do
        @repo.expects(:async_pushable_by?).never
        User::InteractionAbility.interaction_allowed?(user: @user, repository: @repo, user_can_push: false)
      end
    end

    context "user blocked from interaction" do
      test ".interaction_allowed?" do
        User::InteractionAbility.disallow_interactions(@user)
        refute User::InteractionAbility.interaction_allowed?(user: @user)
      end

      test "collaborators_only" do
        repo = create(:repository, owner: @owner)
        repo_interactions = RepositoryInteractionAbility.new(repo)
        user = create(:user)

        assert User::InteractionAbility.interaction_allowed?(user: user, repository: repo)
        repo_interactions.set_ability(:collaborators_only, @owner)
        refute User::InteractionAbility.interaction_allowed?(user: user, repository: repo)

        repo.add_member(user)
        assert User::InteractionAbility.interaction_allowed?(user: user, repository: repo)
      end

      test "returns false if user is not specified" do
        refute User::InteractionAbility::interaction_allowed?(user: nil, repository: @repo)
      end

      test ".ban_expiry" do
        User::InteractionAbility.disallow_interactions(@user)
        expiry = User::InteractionAbility.ban_expiry(@user)
        assert expiry > DateTime.now
      end

      test ".toggle_interaction_ban" do
        User::InteractionAbility.disallow_interactions(@user)
        User::InteractionAbility.toggle_interaction_ban(@user)
        assert User::InteractionAbility.interaction_allowed?(user: @user)
      end

      test "instruments interaction ban" do
        events = subscribe("stafftools_interaction_ability.disallow")
        User::InteractionAbility.disallow_interactions(@user)
        expected_payload = { user_id: @user.id }
        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end
    end

    context "user not blocked from interaction" do
      test ".interaction_allowed?" do
        User::InteractionAbility.allow_interactions(@user)
        assert User::InteractionAbility.interaction_allowed?(user: @user)
      end

      test ".toggle_interaction_ban" do
        User::InteractionAbility.allow_interactions(@user)
        User::InteractionAbility.toggle_interaction_ban(@user)
        refute User::InteractionAbility.interaction_allowed?(user: @user)
      end

      test "instruments interaction ban lifted" do
        events = subscribe("stafftools_interaction_ability.allow")
        User::InteractionAbility.allow_interactions(@user)
        expected_payload = { user_id: @user.id }
        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end
    end
  end
end
