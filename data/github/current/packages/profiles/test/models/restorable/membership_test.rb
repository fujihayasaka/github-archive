# typed: true
# frozen_string_literal: true

require "test_helper"

class RestorableMembershipTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @org = create(:organization)
    @team = create(:team, organization: @org)
    @repo = create(:repository, owner: @org)
    @restorable = Restorable.create
    @actor = @org.admins.last
  end

  test ".restore adds member to org" do
    @restorable.memberships.create({
      subject_type: "Organization",
      subject_id: @org.id,
      action: :read,
    })
    Restorable::Membership.restore(
      restorable: @restorable,
      user: @user,
      actor: @actor,
    )
    assert_includes @org.members, @user
    refute @org.adminable_by?(@user)
  end

  test ".restore adds owner to org" do
    @restorable.memberships.create({
      subject_type: "Organization",
      subject_id: @org.id,
      action: :admin,
    })
    Restorable::Membership.restore(
      restorable: @restorable,
      user: @user,
      actor: @actor,
    )

    assert_includes @org.members, @user
    assert @org.adminable_by?(@user)
  end

  test ".restore adds member to team" do
    @restorable.memberships.create({
      subject_type: "Team",
      subject_id: @team.id,
      action: :read,
    })
    Restorable::Membership.restore(
      restorable: @restorable,
      user: @user,
      actor: @actor,
    )

    assert_includes @team.members, @user
    refute_includes @team.maintainers, @user
  end

  test ".restore adds maintainer to team" do
    @restorable.memberships.create({
      subject_type: "Team",
      subject_id: @team.id,
      action: :admin,
    })
    Restorable::Membership.restore(
      restorable: @restorable,
      user: @user,
      actor: @actor,
    )

    assert_includes @team.maintainers, @user
  end

  test ".restore restores both team and organization memberships" do
    @restorable.memberships.create({
      subject_type: "Organization",
      subject_id: @org.id,
      action: :read,
    })
    @restorable.memberships.create({
      subject_type: "Team",
      subject_id: @team.id,
      action: :admin,
    })
    Restorable::Membership.restore(
      restorable: @restorable,
      user: @user,
      actor: @actor,
    )

    assert_includes @team.maintainers, @user
    assert_includes @org.members, @user
    refute @org.adminable_by?(@user)
  end

  test ".restore adds outside_collaborator to repository" do
    @restorable.memberships.create({
      subject_type: "Repository",
      subject_id: @repo.id,
      action: :read,
    })
    Restorable::Membership.restore(
      restorable: @restorable,
      user: @user,
      actor: @actor,
    )

    assert @org.user_is_outside_collaborator?(@user.id)
    refute @repo.adminable_by?(@user)
  end

  test ".restore adds outside_collaborator as admin to repository" do
    @restorable.memberships.create({
      subject_type: "Repository",
      subject_id: @repo.id,
      action: :admin,
    })
    Restorable::Membership.restore(
      restorable: @restorable,
      user: @user,
      actor: @actor,
    )

    assert_includes @org.outside_collaborators, @user
    assert @repo.adminable_by?(@user)
  end

  test ".restore does not attempt to restore if subject has been deleted" do
    @restorable.memberships.create({
      subject_type: "Team",
      subject_id: @team.id,
      action: :read,
    })
    @restorable.saved(:restorable_memberships)
    @team.delete

    assert_difference("@user.teams.count", 0) do
      Restorable::Membership.restore(
        restorable: @restorable,
        user: @user,
        actor: @actor,
      )
    end
  end

  test ".restore marks restorable_memberships as restored after restoring all records" do
    @restorable.memberships.create({
      subject_type: "Organization",
      subject_id: @org.id,
      action: :read,
    })
    @restorable.saved(:restorable_memberships)

    Restorable::Membership.restore(
      restorable: @restorable,
      user: @user,
      actor: @actor,
    )

    assert @restorable.restored?([:restorable_memberships])
  end

  test ".restore does not bomb if an org admin is added as a team maintainer" do
    @restorable.memberships.create({
      subject_type: "Organization",
      subject_id: @org.id,
      action: :admin,
    })
    @restorable.memberships.create({
      subject_type: "Team",
      subject_id: @team.id,
      action: :admin,
    })
    Restorable::Membership.restore(
      restorable: @restorable,
      user: @user,
      actor: @actor,
    )
  end

  test "sends the actor forward to be instrumented" do
    events = subscribe "org.add_member"
    actor = @org.admins.last

    @restorable.memberships.create(
      subject_type: "Organization",
      subject_id: @org.id,
      action: :admin,
    )

    Restorable::Membership.restore(
      restorable: @restorable,
      user: @user,
      actor: actor
    )

    assert event = events.pop, "expected an org.add_member event"
    assert_equal actor.id, event.payload.dig(:actor_id)
  end

  test "sends the actor forward to be instrumented for teams" do
    events = subscribe "team.add_member"

    @restorable.memberships.create(
      subject_type: "Organization",
      subject_id: @org.id,
      action: :admin,
    )

    @restorable.memberships.create(
      subject_type: "Team",
      subject_id: @team.id,
      action: :admin,
    )

    Restorable::Membership.restore(
      restorable: @restorable,
      user: @user,
      actor: @actor
    )

    assert event = events.pop, "expected an team.add_member event"
    assert_equal @actor.id, event.payload.dig(:actor_id)
  end
end
