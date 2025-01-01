# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationModerationTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @owner              = create(:user)
    @org                = create(:organization, admin: @owner)
    @member             = create(:user)
    @moderator_via_team = create(:user)
    @rando              = create(:user)
    @team               = create(:team, organization: @org)

    @org.add_member(@member)
    @org.add_member(@moderator_via_team)
    @team.add_member(@moderator_via_team)
  end

  setup do
    skip unless GitHub.organization_moderators_enabled?
    @moderation = Organization::Moderation.new(@org)
  end

  context "#moderator?" do
    test "true if member is a moderator" do
      @moderation.add_moderator(@member, actor: @owner)
      assert @moderation.moderator?(@member)
    end

    test "true if team is a moderator" do
      @moderation.add_moderator(@team, actor: @owner)
      assert @moderation.moderator?(@team)
    end

    test "true if member is a moderator via team" do
      @moderation.add_moderator(@moderator_via_team, actor: @owner)
      assert @moderation.moderator?(@moderator_via_team)
    end

    test "false if member is not a moderator" do
      refute @moderation.moderator?(@member)
      refute @moderation.moderator?(@moderator_via_team)
    end

    test "false for random user" do
      refute @moderation.moderator?(@rando)
    end
  end

  context "#add_moderator" do
    test "adds a user as a moderator" do
      refute @moderation.moderator?(@member)
      result = @moderation.add_moderator(@member, actor: @owner)
      assert_predicate result, :success?
      assert_equal @member, result.moderator
      assert_empty result.errors
      assert @moderation.moderator?(@member)
    end

    test "adds a team as a moderator" do
      refute @moderation.moderator?(@team)
      result = @moderation.add_moderator(@team, actor: @owner)
      assert_predicate result, :success?
      assert_equal @team, result.moderator
      assert_empty result.errors
      assert @moderation.moderator?(@team)
    end

    test "succeeds if user is already a moderator" do
      @moderation.add_moderator(@member, actor: @owner)
      assert @moderation.moderator?(@member)

      result = @moderation.add_moderator(@member, actor: @owner)
      assert_predicate result, :success?
      assert_equal @member, result.moderator
      assert_empty result.errors
      assert @moderation.moderator?(@member)
    end

    test "errors if actor is not authorized" do
      refute @moderation.moderator?(@member)
      result = @moderation.add_moderator(@member, actor: @rando)
      refute_predicate result, :success?
      assert_equal @member, result.moderator
      assert_equal ["Actor is not authorized to manage moderators"], result.errors
      refute @moderation.moderator?(@member)
    end

    test "errors if user is not an org member" do
      refute @moderation.moderator?(@rando)
      result = @moderation.add_moderator(@rando, actor: @owner)
      refute_predicate result, :success?
      assert_equal @rando, result.moderator
      assert_equal ["User must be a member of the organization"], result.errors
      refute @moderation.moderator?(@rando)
    end

    test "errors if team is not part of the org" do
      random_team = create(:team)
      refute @moderation.moderator?(random_team)

      result = @moderation.add_moderator(random_team, actor: @owner)
      refute_predicate result, :success?
      assert_equal random_team, result.moderator
      assert_equal ["Team must be a member of the organization"], result.errors
      refute @moderation.moderator?(random_team)
    end

    test "errors if at moderator limit" do
      Organization::Moderation.stub_const(:MODERATOR_LIMIT, 1) do
        @moderation.add_moderator(@member, actor: @owner)
        assert @moderation.moderator?(@member)
        assert_equal 1, @moderation.moderators.count

        result = @moderation.add_moderator(@team, actor: @owner)
        refute_predicate result, :success?
        assert_equal @team, result.moderator
        expected = ["You can only have a maximum of 1 users or teams as moderators"]
        assert_equal expected, result.errors
        refute @moderation.moderator?(@team)
      end
    end

    test "creates audit log event when adding a user" do
      events = subscribe "organization_moderators.add_user"
      expected_payload = {
        org: @org.login,
        org_id: @org.id,
        user: @member.login,
        user_id: @member.id,
        actor: @owner.login,
        actor_id: @owner.id,
      }

      result = @moderation.add_moderator(@member, actor: @owner)
      assert_predicate result, :success?
      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "creates audit log event when adding a team" do
      events = subscribe "organization_moderators.add_team"
      expected_payload = {
        org: @org.login,
        org_id: @org.id,
        team: @team.combined_slug,
        team_id: @team.id,
        actor: @owner.login,
        actor_id: @owner.id,
      }

      result = @moderation.add_moderator(@team, actor: @owner)
      assert_predicate result, :success?
      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments hydro event when adding a user" do
      result = @moderation.add_moderator(@member, actor: @owner)
      assert_predicate result, :success?

      message = {
        organization: Hydro::EntitySerializer.organization(@org),
        action: "ADDED",
        moderator_type: "USER",
        moderator_id: @member.id,
        actor: Hydro::EntitySerializer.user(@owner),
      }
      assert_hydro_published(message, schema: "github.organization_moderators.v0.ModeratorUpdate")
    end

    test "instruments hydro event when adding a team" do
      result = @moderation.add_moderator(@team, actor: @owner)
      assert_predicate result, :success?

      message = {
        organization: Hydro::EntitySerializer.organization(@org),
        action: "ADDED",
        moderator_type: "TEAM",
        moderator_id: @team.id,
        actor: Hydro::EntitySerializer.user(@owner),
      }
      assert_hydro_published(message, schema: "github.organization_moderators.v0.ModeratorUpdate")
    end
  end

  context "#remove_moderator" do
    test "removes a user from being a moderator" do
      @moderation.add_moderator(@member, actor: @owner)
      assert @moderation.moderator?(@member)

      result = @moderation.remove_moderator(@member, actor: @owner)
      assert_predicate result, :success?
      assert_equal @member, result.moderator
      assert_empty result.errors
      refute @moderation.moderator?(@member)
    end

    test "removes a team from being a moderator" do
      @moderation.add_moderator(@team, actor: @owner)
      assert @moderation.moderator?(@team)
      assert @moderation.moderator?(@moderator_via_team)

      result = @moderation.remove_moderator(@team, actor: @owner)
      assert_predicate result, :success?
      assert_equal @team, result.moderator
      assert_empty result.errors
      refute @moderation.moderator?(@team)
      refute @moderation.moderator?(@moderator_via_team)
    end

    test "errors if actor is not an org owner" do
      @moderation.add_moderator(@member, actor: @owner)
      assert @moderation.moderator?(@member)

      result = @moderation.remove_moderator(@member, actor: @moderator_via_team)
      refute_predicate result, :success?
      assert_equal @member, result.moderator
      assert_equal ["Actor is not authorized to manage moderators"], result.errors
      assert @moderation.moderator?(@member)
    end

    test "does not error if actor is not an org owner if force kwarg is true" do
      @moderation.add_moderator(@member, actor: @owner)
      assert @moderation.moderator?(@member)

      result = @moderation.remove_moderator(
        @member,
        actor: @moderator_via_team,
        force: true,
      )
      assert_predicate result, :success?
      assert_equal @member, result.moderator
      assert_empty result.errors
      refute @moderation.moderator?(@member)
    end

    test "creates audit log event when removing a user" do
      events = subscribe "organization_moderators.remove_user"
      expected_payload = {
        org: @org.login,
        org_id: @org.id,
        user: @member.login,
        user_id: @member.id,
        actor: @owner.login,
        actor_id: @owner.id,
      }

      @moderation.add_moderator(@member, actor: @owner)
      assert @moderation.moderator?(@member)

      result = @moderation.remove_moderator(@member, actor: @owner)
      assert_predicate result, :success?
      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "creates audit log event when removing a team" do
      events = subscribe "organization_moderators.remove_team"
      expected_payload = {
        org: @org.login,
        org_id: @org.id,
        team: @team.combined_slug,
        team_id: @team.id,
        actor: @owner.login,
        actor_id: @owner.id,
      }

      @moderation.add_moderator(@team, actor: @owner)
      assert @moderation.moderator?(@team)

      result = @moderation.remove_moderator(@team, actor: @owner)
      assert_predicate result, :success?
      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments hydro event when removing a user" do
      result = @moderation.add_moderator(@member, actor: @owner)
      assert_predicate result, :success?
      reset_hydro

      result = @moderation.remove_moderator(@member, actor: @owner)
      assert_predicate result, :success?

      message = {
        organization: Hydro::EntitySerializer.organization(@org),
        action: "REMOVED",
        moderator_type: "USER",
        moderator_id: @member.id,
        actor: Hydro::EntitySerializer.user(@owner),
      }
      assert_hydro_published(message, schema: "github.organization_moderators.v0.ModeratorUpdate")
    end

    test "instruments hydro event when removing a team" do
      result = @moderation.add_moderator(@team, actor: @owner)
      assert_predicate result, :success?
      reset_hydro

      result = @moderation.remove_moderator(@team, actor: @owner)
      assert_predicate result, :success?

      message = {
        organization: Hydro::EntitySerializer.organization(@org),
        action: "REMOVED",
        moderator_type: "TEAM",
        moderator_id: @team.id,
        actor: Hydro::EntitySerializer.user(@owner),
      }
      assert_hydro_published(message, schema: "github.organization_moderators.v0.ModeratorUpdate")
    end
  end

  context "#remove_all_user_moderators" do
    test "removes all direct user moderators from an organization" do
      @moderation.add_moderator(@member, actor: @owner)
      @moderation.add_moderator(@team, actor: @owner)
      assert @moderation.moderator?(@member)
      assert @moderation.moderator?(@team)
      assert @moderation.moderator?(@moderator_via_team)

      @moderation.remove_all_user_moderators

      refute @moderation.moderator?(@member)
      assert @moderation.moderator?(@team)
      assert @moderation.moderator?(@moderator_via_team)
    end
  end
end
