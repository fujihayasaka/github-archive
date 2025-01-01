# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationModerationDependencyTest < GitHub::TestCase
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

  context "#moderator?" do
    if GitHub.user_abuse_mitigation_enabled?
      test "true if member is a moderator" do
        moderation = Organization::Moderation.new(@org)
        moderation.add_moderator(@member, actor: @owner)
        assert @org.moderator?(@member)
      end

      test "true if team is a moderator" do
        moderation = Organization::Moderation.new(@org)
        moderation.add_moderator(@team, actor: @owner)
        assert @org.moderator?(@team)
      end

      test "true if member is a moderator via team" do
        moderation = Organization::Moderation.new(@org)
        moderation.add_moderator(@team, actor: @owner)
        assert @org.moderator?(@moderator_via_team)
      end

      test "false if member is not a moderator" do
        refute @org.moderator?(@member)
        refute @org.moderator?(@moderator_via_team)
      end

      test "false for random user" do
        refute @org.moderator?(@rando)
      end
    else
      test "false if abuse mitigation is not enabled" do
        moderation = Organization::Moderation.new(@org)
        moderation.add_moderator(@team, actor: @owner)
        refute @org.moderator?(@team)
      end
    end
  end

  context "#moderators" do
    if GitHub.user_abuse_mitigation_enabled?
      test "returns moderators with direct access" do
        moderation = Organization::Moderation.new(@org)
        moderation.add_moderator(@member, actor: @owner)
        moderation.add_moderator(@team, actor: @owner)

        assert_equal [@team, @member], @org.moderators
      end

      test "returns moderators with direct access even if they are also a team member" do
        moderation = Organization::Moderation.new(@org)
        moderation.add_moderator(@member, actor: @owner)
        moderation.add_moderator(@team, actor: @owner)
        moderation.add_moderator(@moderator_via_team, actor: @owner)

        assert_same_elements [@team, @member, @moderator_via_team], @org.moderators
      end
    else
      test "returns empty array if abuse mitigation is not enabled" do
        moderation = Organization::Moderation.new(@org)
        moderation.add_moderator(@member, actor: @owner)
        moderation.add_moderator(@team, actor: @owner)
        moderation.add_moderator(@moderator_via_team, actor: @owner)

        assert_empty @org.moderators
      end
    end
  end

  if GitHub.user_abuse_mitigation_enabled?
    context "after_commit" do
      test "removes user moderators when org is deleted" do
        moderation = Organization::Moderation.new(@org)
        moderation.add_moderator(@member, actor: @owner)
        moderation.add_moderator(@team, actor: @owner)

        actor_ids = Ability.where(
          subject_type: "Organization::Moderation",
          subject_id: @org.id,
          actor_type: User,
        ).pluck(:actor_id)
        assert_equal [@member.id], actor_ids

        @org.destroy

        refute Ability.where(
          subject_type: "Organization::Moderation",
          subject_id: @org.id,
          actor_type: User,
        ).any?
      end
    end
  end
end
