# typed: true
# frozen_string_literal: true
require "test_helper"
require "test_helpers/ability_models"

class GrantTestGrant < Permissions::Granter
  def grant!
  end

  def revoke!
  end
end

class Permissions::GranterTest < GitHub::TestCase
  fixtures do
    @actor = AnActor.create
    @subject = ASubject.create
  end

  context ".grant" do
    test "does not grant for actions that are not registered" do
      result = Permissions::Granter.grant(actor_id: @actor.id, action: :non_existent_action, subject_id: @subject.id)

      assert_predicate result, :failure?
      refute_predicate result, :success?
    end

    test "uses the registered grant for an action" do
      fake_grant = mock("GrantTestGrant")
      fake_action_grants = {
        some_action: GrantTestGrant,
      }

      Permissions::ActionGrants.stub_const(:GRANTS_BY_ACTION, fake_action_grants) do
        GrantTestGrant.expects(:new).returns(fake_grant)
        fake_grant.expects(:grant!).once.with(actor_id: @actor.id, subject_id: @subject.id, entry_point: :test_case)
        Permissions::Granter.grant(actor_id: @actor.id, action: :some_action, subject_id: @subject.id, entry_point: :test_case)
      end
    end

    test "does not grant when no actor_id or subject_id are supplied" do
      fake_grant = mock("GrantTestGrant")
      fake_action_grants = {
        some_action: GrantTestGrant,
      }

      Permissions::ActionGrants.stub_const(:GRANTS_BY_ACTION, fake_action_grants) do
        assert_raises ArgumentError do
          Permissions::Granter.grant(actor_id: nil, action: :some_action, subject_id: nil)
        end
      end
    end
  end

  context ".revoke" do
    test "does not revoke when no actor_id or subject_id are supplied" do
      fake_grant = mock("GrantTestGrant")
      fake_action_grants = {
        some_action: GrantTestGrant,
      }

      Permissions::ActionGrants.stub_const(:GRANTS_BY_ACTION, fake_action_grants) do
        assert_raises ArgumentError do
          Permissions::Granter.revoke(actor_id: nil, action: :some_action, subject_id: nil)
        end
      end
    end

    test "does not revoke for actions that are not registered" do
      result = Permissions::Granter.revoke(actor_id: @actor.id, action: :non_existent_action, subject_id: @subject.id)

      assert_predicate result, :failure?
      refute_predicate result, :success?
    end

    test "uses the registered grant for an action" do
      fake_grant = mock("GrantTestGrant")
      fake_action_grants = {
        some_action: GrantTestGrant,
      }

      Permissions::ActionGrants.stub_const(:GRANTS_BY_ACTION, fake_action_grants) do
        GrantTestGrant.expects(:new).returns(fake_grant)
        fake_grant.expects(:revoke!).once.with(actor_id: @actor.id, subject_id: @subject.id, entry_point: :test_case)
        Permissions::Granter.revoke(actor_id: @actor.id, action: :some_action, subject_id: @subject.id, entry_point: :test_case)
      end
    end
  end
end
