# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamInvitationAssociationsTest < GitHub::TestCase
  fixtures do
    @invitation = create :team_invitation
  end

  test "belongs_to save to the database" do
    assert @invitation.valid?
    refute @invitation.new_record?

    assert @invitation.organization_invitation.present?
    assert @invitation.inviter.present?
    assert @invitation.team.present?
  end

  context "organization_invitation" do
    test "destroys the invitation when destroyed" do
      id = @invitation.id
      refute_nil TeamInvitation.find_by(id: id)

      @invitation.organization_invitation.destroy

      assert_nil TeamInvitation.find_by(id: id)
    end
  end

  context "team" do
    test "destroys the invitation when destroyed" do
      self.perform_enqueued_jobs = true # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
      id = @invitation.id
      refute_nil TeamInvitation.find_by(id: id)

      @invitation.team.destroy

      assert_nil TeamInvitation.find_by(id: id)
    end
  end
end

class TeamInvitationValidationsTest < GitHub::TestCase
  fixtures do
    @org_invitation = create :organization_invitation
    @team           = create :team, organization: @org_invitation.organization
    @inviter        = @org_invitation.organization.admins.last
  end

  test "can be valid" do
    invitation = TeamInvitation.new(
      organization_invitation: @org_invitation,
      inviter: @inviter,
      team: @team,
      role: :member,
    )
    assert invitation.valid?, "should be valid"
  end

  test "requires an org invitation" do
    invitation = TeamInvitation.new(
      inviter: @inviter,
      team: @team,
      role: :member,
    )

    refute invitation.valid?, "should require an org invitation"
  end

  test "requires an inviter" do
    invitation = TeamInvitation.new(
      organization_invitation: @org_invitation,
      team: @team,
      role: :member,
    )

    refute invitation.valid?, "should require an inviter"
  end

  test "requires a team" do
    invitation = TeamInvitation.new(
      organization_invitation: @org_invitation,
      inviter: @inviter,
      role: :member,
    )

    refute invitation.valid?, "should require a team"
  end

  context "requires role" do
    test "to be one of the valid symbols" do
      invitation = TeamInvitation.new(
        organization_invitation: @org_invitation,
        inviter: @inviter,
        team: @team,
      )

      T.unsafe(invitation).role = nil
      refute invitation.valid?, "should require a role"

      invitation.role = :member
      assert invitation.valid?, "should work for the :member role"

      invitation.role = :maintainer
      assert invitation.valid?, "should work for the :maintainer role"

      assert_raises(ArgumentError) do
        invitation.role = :invalid_role
      end
    end
  end

  test "can invite to two different teams on the same org invitation" do
    first_invitation  = create :team_invitation
    second_invitation = TeamInvitation.new(
      organization_invitation: first_invitation.organization_invitation,
      inviter: first_invitation.inviter,
      team: (create :team, organization: first_invitation.organization_invitation.organization),
      role: :member,
    )

    assert second_invitation.valid?, "should be able to invite to two different teams"
  end

  test "can only invite to a given team once per org invitation" do
    original_invitation = create :team_invitation

    other_owner = create(:user)
    original_invitation.organization_invitation.organization.add_admin(other_owner)

    dupe_invitation = TeamInvitation.new(
      organization_invitation: original_invitation.organization_invitation,
      inviter: other_owner,
      team: original_invitation.team,
      role: :member,
    )

    refute dupe_invitation.valid?, "can't invite to the same team twice on one org invitation"
  end
end
