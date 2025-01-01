# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectWorkflowActionTest < GitHub::TestCase
  fixtures do
  end

  context "validations" do
    test "requires a workflow" do
      action = build(:memex_project_workflow_action, workflow: nil)

      refute action.save
      assert_includes action.errors.full_messages, "Workflow can't be blank"
    end

    test "requires a creator on create" do
      action = build(:memex_project_workflow_action, creator: nil)

      refute action.save
      assert_includes action.errors.full_messages, "Creator can't be blank"
    end

    test "does not require a creator on update" do
      user = create(:verified_user)
      action = create(:memex_project_workflow_action, creator: user)

      assert user.destroy!
      assert action.reload
      assert_nil action.creator, "should not locate a user for the creator association"
      assert_equal user.id, action.creator_id, "creator_id should still be set to the user's id"
      assert action.save, "action should still be valid"
    end

    test "requires a last updater on create" do
      action = build(:memex_project_workflow_action)
      action.stubs(:set_last_updater) # Make the default setter a no-op.

      refute action.save
      assert_includes action.errors.full_messages, "Last updater can't be blank"
    end

    test "updates last updater to provided user on update instead of using context" do
      user = create(:verified_user)
      actor = create(:verified_user)

      action = create(:memex_project_workflow_action, last_updater: user)
      assert action.save
      assert action.reload
      assert_equal user.id, action.last_updater_id, "last_updater_id should still be set to the user's id"
      action.update(last_updater: actor)
      assert action.save
      assert_equal actor, action.reload.last_updater, "last_updater should be set to the provided actor"
    end

    test "sets last updater to ghost user on update if original last updater is gone" do
      user = create(:verified_user)
      action = create(:memex_project_workflow_action, last_updater: user)

      assert user.destroy!
      assert action.reload
      assert_nil action.last_updater, "should not locate a user for the last_updater association"
      assert_equal user.id, action.last_updater_id, "last_updater_id should still be set to the user's id"
      assert action.save
      assert_equal User.ghost, action.reload.last_updater, "last_updater should be set to the ghost user"
    end

    test "sets last updater to actor from context on update if original last updater is gone" do
      user = create(:verified_user)
      actor = create(:verified_user)
      action = create(:memex_project_workflow_action, last_updater: user)

      assert user.destroy!
      assert action.reload
      assert_nil action.last_updater, "should not locate a user for the last_updater association"
      assert_equal user.id, action.last_updater_id, "last_updater_id should still be set to the user's id"
      GitHub.context.push(actor: actor) do
        assert action.save
      end
      assert_equal actor, action.reload.last_updater, "last_updater should be set to the actor user from context"
    end

    test "sets a last updater by default" do
      action = build(:memex_project_workflow_action, last_updater: nil)
      action.save!

      refute_nil action.reload.last_updater_id
    end

    test "requires an action type" do
      action = build(:memex_project_workflow_action, action_type: nil)

      refute action.save
      assert_includes action.errors.full_messages, "Action type can't be blank"
    end

    test "requires arguments" do
      action = build(:memex_project_workflow_action, arguments: nil, skip_argument_build: true)

      refute action.save
      assert_includes action.errors.full_messages, "Arguments must be a Hash"

      action.arguments = []
      refute action.save
      assert_includes action.errors.full_messages, "Arguments must be a Hash"
    end

    test "casts certain argument values to integer" do
      action = build(:memex_project_workflow_action)
      field_id = action.arguments["fieldId"]
      assert field_id.is_a?(Integer)
      action.arguments["fieldId"] = field_id.to_s

      assert action.save
      assert_equal field_id, action.reload.arguments["fieldId"]
    end

    test "validates arguments" do
      action = build(
        :memex_project_workflow_action,
        action_type: :set_field,
        arguments: {},
        skip_argument_build: true
      )

      refute action.save
      assert_includes action.errors.full_messages, "Arguments must include a 'fieldId' value"
    end
  end

  context "equal?" do

    context "get_items" do
      test "equal actions" do
        action_a = build(
          :memex_project_workflow_action,
          action_type: :get_items,
          arguments: { repositoryId: 1 , query: "is:open is:issue,pr label:bug" },
          skip_argument_build: true
        )

        action_b = build(
          :memex_project_workflow_action,
          action_type: :get_items,
          arguments: { repositoryId: 1 , query: "is:issue is:pr label:bug is:open" },
          skip_argument_build: true
        )

        assert action_a.equal?(action_b)
      end

      test "not equal actions - different queries" do
        action_a = build(
          :memex_project_workflow_action,
          action_type: :get_items,
          arguments: { repositoryId: 1 , query: "is:open is:issue,pr label:not-a-bug" },
          skip_argument_build: true
        )

        action_b = build(
          :memex_project_workflow_action,
          action_type: :get_items,
          arguments: { repositoryId: 1 , query: "is:issue is:pr label:bug is:open" },
          skip_argument_build: true
        )

        refute action_a.equal?(action_b)
      end

      test "not equal actions - different repository ids" do
        action_a = build(
          :memex_project_workflow_action,
          action_type: :get_items,
          arguments: { repositoryId: 1 , query: "is:open is:issue,pr label:bug" },
          skip_argument_build: true
        )

        action_b = build(
          :memex_project_workflow_action,
          action_type: :get_items,
          arguments: { repositoryId: 2 , query: "is:issue is:pr label:bug is:open" },
          skip_argument_build: true
        )

        refute action_a.equal?(action_b)
      end
    end

    context "default" do
      test "equal actions" do
        action_a = build(
          :memex_project_workflow_action,
          action_type: :set_field,
          arguments: { fieldId: 1, fieldOptionId: 2 },
          skip_argument_build: true
        )
        action_b = build(
          :memex_project_workflow_action,
          action_type: :set_field,
          arguments: { fieldId: 1, fieldOptionId: 2 },
          skip_argument_build: true
        )

        assert action_a.equal?(action_b)
      end

      test "not-equal actions" do
        action_a = build(
          :memex_project_workflow_action,
          action_type: :set_field,
          arguments: { fieldId: 2, fieldOptionId: 2 },
          skip_argument_build: true
        )
        action_b = build(
          :memex_project_workflow_action,
          action_type: :set_field,
          arguments: { fieldId: 1, fieldOptionId: 2 },
          skip_argument_build: true
        )

        refute action_a.equal?(action_b)
      end
    end
  end
end
