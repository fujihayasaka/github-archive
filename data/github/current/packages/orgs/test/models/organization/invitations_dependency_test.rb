# typed: true
# frozen_string_literal: true

require "test_helper"

# Tests related to inviting users to organizations.
#
# Not to be confused with the OrganizationInvitation model, which has its own
# tests.
class OrganizationInvitationsDependencyTest < GitHub::TestCase
  fixtures do
    @org_admin      = create(:user, login: "org-admin")
    @org_member     = create(:user)
    @non_org_member = create(:user)
    @org            = create(:organization, admin: @org_admin, plan: "bronze")
    @team           = create(:team, organization: @org, permission: "pull")

    @team.add_member(@org_admin)
    @team.add_member(@org_member)
  end

  test "adds a new invitation with a single team" do
    assert @org.pending_invitations.empty?

    invitation = @org.invite(create(:user), inviter: @org_admin, teams: [@team])

    assert_equal [invitation], @org.pending_invitations.to_a
    assert_equal [@team], invitation.teams.to_a
    assert_predicate invitation, :direct_member?
    assert invitation.valid?
  end

  test "adds a new invitation with multiple teams" do
    assert @org.pending_invitations.empty?

    other_team = create(:team, organization: @org)
    invitation = @org.invite(create(:user), inviter: @org_admin, teams: [@team, other_team])

    assert_equal [invitation], @org.pending_invitations.to_a
    assert_same_elements [@team, other_team], invitation.teams.to_a
    assert invitation.valid?
  end

  test "adds a new invitation with duplicate teams filtered" do
    assert @org.pending_invitations.empty?

    invitation = @org.invite(create(:user), inviter: @org_admin, teams: [@team, @team, @team])

    assert_equal [invitation], @org.pending_invitations.to_a
    assert_same_elements [@team], invitation.teams.to_a
    assert invitation.valid?
  end

  test "uses default role value of :direct_member if invalid role provided" do
    invitation = @org.invite(create(:user), inviter: @org_admin, role: :not_a_valid_role)

    assert_equal [invitation], @org.pending_invitations.to_a
    assert_predicate invitation, :direct_member?
    assert invitation.valid?
  end

  test "adds a new org member invitation" do
    invitation = @org.invite(create(:user), inviter: @org_admin, role: :direct_member)

    assert_equal [invitation], @org.pending_invitations.to_a
    assert_predicate invitation, :direct_member?
    assert invitation.valid?
  end

  test "adds a new org owner invitation" do
    invitation = @org.invite(create(:user), inviter: @org_admin, role: :admin)

    assert_equal [invitation], @org.pending_invitations.to_a
    assert_predicate invitation, :admin?
    assert invitation.valid?
  end

  test "adds extra teams to existing invitation" do
    invitee    = create(:user)
    invitation = @org.invite(invitee, inviter: @org_admin, teams: [@team])

    assert_equal [invitation], @org.pending_invitations.to_a
    assert_equal [@team], invitation.teams.to_a

    other_team = create(:team, organization: @org)
    invitation = @org.invite(invitee, inviter: @org_admin, teams: [other_team])

    assert_equal [invitation], @org.pending_invitations.reload.to_a
    assert_same_elements [@team, other_team], invitation.teams.to_a
  end

  test "filter duplicates when adding extra teams to existing invitation" do
    invitee    = create(:user)
    invitation = @org.invite(invitee, inviter: @org_admin, teams: [@team])

    assert_equal [invitation], @org.pending_invitations.to_a
    assert_equal [@team], invitation.teams.to_a

    other_team = create(:team, organization: @org)
    invitation = @org.invite(invitee, inviter: @org_admin, teams: [@team, other_team])

    assert_equal [invitation], @org.pending_invitations.reload.to_a
    assert_same_elements [@team, other_team], invitation.teams.to_a
    assert invitation.valid?
  end

  test "creates a new invitation if there's an existing accepted invitation for the same non-member user" do
    invitee        = create(:user)
    old_invitation = @org.invite(invitee, inviter: @org_admin, teams: [@team])

    # Accept the invitation, then remove the user from the org
    old_invitation.accept
    perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
      @org.remove_member(invitee)
    end

    new_invitation = @org.invite(invitee, inviter: @org_admin, teams: [@team])

    assert old_invitation.accepted?
    refute new_invitation.accepted?
    refute_equal old_invitation, new_invitation
  end

  test "allows a user to be re-invited to the same team after accepting an invitation and then leaving" do
    # The user is invited and accepts the invitation.
    invitee        = create(:user, login: "invitee")
    old_invitation = @org.invite(invitee, inviter: @org_admin, teams: [@team])
    old_invitation.accept

    perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
      # The user leaves the organization.
      @org.remove_member(invitee)
    end

    # The user is re-invited to the organization
    new_invitation = @org.invite(invitee, inviter: @org_admin, teams: [@team])

    assert_equal [new_invitation], @org.pending_invitations.to_a
    assert_equal [@team], new_invitation.teams.to_a
    assert new_invitation.valid?
  end

  test "creates a new invitation for user by email" do
    new_invitation = @org.invite(email: "garrett@github.com", inviter: @org_admin, teams: [@team])

    assert_equal [new_invitation], @org.pending_invitations.to_a
    assert_equal "garrett@github.com", new_invitation.email
    assert_nil new_invitation.invitee
    assert new_invitation.valid?
  end

  test "modifies existing invitation if sent to an equivalently normalized email address" do
    other_team = create(:team, organization: @org)

    existing_invitation = @org.invite(email: "john.smith@gmail.com", inviter: @org_admin, teams: [@team])
    new_invitation = @org.invite(email: "JohnSmith@gmail.com", inviter: @org_admin, teams: [other_team])

    assert_equal existing_invitation, new_invitation
    assert_same_elements [@team, other_team], new_invitation.teams
  end

  test "creates new invitation if existing private email invite exists" do
    user = create(:user)
    user.emails.delete_all

    user.add_email("verified-private@example.com", is_primary: true)
    user.primary_user_email.verify!
    user.primary_user_email.toggle_visibility
    refute user.primary_user_email.public?

    @org.invite(email: "verified-private@example.com", inviter: @org_admin)

    assert_equal 1, @org.pending_invitations.count

    @org.invite(user, inviter: @org_admin)

    assert_equal 2, @org.reload.pending_invitations.count
  end

  test "does not create new invitation if existing public email invite exists" do
    user = create(:user)
    user.emails.delete_all

    user.add_email("verified-public@example.com", is_primary: true)
    user.primary_user_email.verify!
    assert user.primary_user_email.public?

    @org.invite(email: "verified-public@example.com", inviter: @org_admin)

    assert_equal 1, @org.pending_invitations.count

    @org.invite(user, inviter: @org_admin)

    assert_equal 1, @org.reload.pending_invitations.count
  end

  context "with org_invite_revamp flag enabled" do
    test "creates new invitation if you try to invite an existing org member by unverified email" do
      user = create(:user)
      user.add_email("User@example.com", is_primary: true)
      @org.add_member(user)

      assert_nothing_raised do
        @org.invite(email: "user@example.com", inviter: @org_admin, teams: [@team])
      end
      assert_equal 1, @org.pending_invitations.count
    end

    test "errors if you try to invite an existing org member by verified email" do
      user = create(:user)
      user.add_email("User@example.com", is_primary: true)
      user.primary_user_email.verify!
      @org.add_member(user)

      assert_raises(OrganizationInvitation::InvalidError) do
        @org.invite(email: "user@example.com", inviter: @org_admin, teams: [@team])
      end
    end
  end

  test "errors if you try to invite someone by both a user and email" do
    assert_raises(OrganizationInvitation::InvalidError) do
      @org.invite(@org_member, email: "garrett@github.com", inviter: @org_admin, teams: [@team])
    end
  end

  test "errors if you try to invite someone without a user or email" do
    assert_raises(OrganizationInvitation::InvalidError) do
      @org.invite(nil, email: nil, inviter: @org_admin, teams: [@team])
    end

    assert_raises(OrganizationInvitation::InvalidError) do
      @org.invite(nil, email: "", inviter: @org_admin, teams: [@team])
    end
  end

  test "errors if you try to invite an existing org member" do
    user = create(:user)
    @org.add_member(user)

    assert_raises(OrganizationInvitation::InvalidError) do
      @org.invite(user, inviter: @org_admin, teams: [@team])
    end
  end

  test "errors if you try to invite a member to a team on a different org" do
    invitee            = create(:user, login: "invitee")
    different_org_team = create(:team, organization: create(:organization, login: "other-team"), name: "other-team")

    assert_raises(OrganizationInvitation::InvalidError) do
      @org.invite(invitee, inviter: @org_admin, teams: [@team, different_org_team])
    end
  end

  test "errors if you try to invite an organization to an organization" do
    bad_invitee = create(:organization, login: "bad-invitee")

    assert_raises(OrganizationInvitation::InvalidError) do
      @org.invite(bad_invitee, inviter: @org_admin, teams: [@team])
    end
  end

  test "errors if there are no seats available on this organization" do
    org = create(:organization, plan: "business", seats: 5)
    4.times { org.add_member(create(:user)) }
    team = create(:team, organization: org, name: "other-team")

    assert_raises(OrganizationInvitation::NoAvailableSeatsError) do
      org.invite(create(:user), inviter: org.admin, teams: [team])
    end

    last_invite = OrganizationInvitation.last
    assert_equal last_invite.failed_reason, "no_more_seats"
    refute_nil last_invite.failed_at
  end

  test "instruments the expected payload" do
    invitee = create(:user, login: "invitee")
    events  = subscribe("org.invite_member")
    invitation = @org.invite(invitee, inviter: @org_admin, teams: [@team])

    event            = events.pop
    expected_payload = {
      actor:          @org_admin.login,
      actor_id:       @org_admin.id,
      user:           invitee.login,
      user_id:        invitee.id,
      org:            @org.login,
      org_id:         @org.id,
      spammy:         invitee.spammy,
      invitation_id:  invitation.id,
    }

    refute_nil event
    assert_equal "org.invite_member", event.name
    assert_equal expected_payload, event.payload
  end

  test "mails the invited user" do
    invitee = create(:user, login: "invitee")

    AccountMailer.expects(:invited_to_org).returns(stub(deliver_later: nil))
    @org.invite(invitee, inviter: @org_admin, teams: [@team])
  end

  test "mails a user invited as a billing manager" do
    invitee = create(:user, login: "invitee")

    OrganizationMailer.expects(:invited_to_billing_manager_role).returns(stub(deliver_later: nil))
    @org.invite(invitee, inviter: @org_admin, role: :billing_manager)
  end

  test "does not check seat for billing manager invite" do
    invitee = create(:user, login: "invitee")

    @org.expects(:has_seat_for?).never
    OrganizationMailer.expects(:invited_to_billing_manager_role).returns(stub(deliver_later: nil))
    @org.invite(invitee, inviter: @org_admin, role: :billing_manager)
  end

  test "mails user invited by email" do
    AccountMailer.expects(:invited_to_org_by_email).returns(stub(deliver_later: nil))
    @org.invite(email: "garrett@github.com", inviter: @org_admin, teams: [@team])
  end

  test "drops email when invitee has blocked the inviter" do
    AccountMailer.expects(:invited_to_org_by_email).never
    @non_org_member.block(@org_admin)
    @org.invite(email: @non_org_member.email, inviter: @org_admin, teams: [@team])
  end

  test "drops email when invitee has blocked the org owner, but not the inviter" do
    AccountMailer.expects(:invited_to_org_by_email).never
    @non_org_member.block(@org_admin)
    @non_blocked_admin = create(:user)
    @org.add_member(@non_blocked_admin, action: :admin)
    @org.invite(email: @non_org_member.email, inviter: @non_blocked_admin, teams: [@team])
  end

  test "drops email when invitee has blocked the inviter, and using alternate address" do
    AccountMailer.expects(:invited_to_org_by_email).never
    @non_org_member.block(@org_admin)
    @non_org_member.add_email("lapis@lazuli.com")
    @org.invite(email: "lapis@lazuli.com", inviter: @org_admin, teams: [@team])
  end

  test "does not leak the existance of an account with a given email address" do
    @non_org_member.block(@org_admin)
    @org.invite(email: @non_org_member.email, inviter: @org_admin, teams: [@team])
    @invitation = @org.pending_invitation_for(nil, email: @non_org_member.email)
    assert @invitation, "attacker can infer existance of account with given email address"
  end

  test "does not deliver duplicate email for user invited by email" do
    @org.invite(email: "garrett@github.com", inviter: @org_admin, teams: [@team])
    AccountMailer.expects(:invited_to_org_by_email).never
    @org.invite(email: "garrett@github.com", inviter: @org_admin, teams: [@team])
  end

  test "prevents non-email values in invitations" do
    # https://github.com/github/github/issues/57683
    invitee = create(:user, login: "invitee")

    @org.invite(invitee, email: false, inviter: @org_admin, teams: [@team])

    assert_nil @org.pending_invitations.last.email
  end

  test "rolls back organization invitations if team invitations raise an error" do
    TeamInvitation.any_instance.stubs(:save!).raises

    assert_difference -> { OrganizationInvitation.count } => 0 do
      assert_raises do
        @org.invite(create(:user), inviter: @org_admin, role: :direct_member, teams: [@team])
      end
    end
  end

  context "trade controls restrictions" do
    test "works by role  when user is blocked due to OFAC sanctions" do
      user = create(:user, :fully_trade_restricted)

      invitation = @org.invite(user, inviter: @org_admin, teams: [@team])

      assert invitation.valid?
    end

    test "works by team when invitee is trade restricted and org is paid" do
      invitee = create(:user, :fully_trade_restricted)

      invitation = @org.invite(invitee, inviter: @org_admin, role: :direct_member)

      assert invitation.valid?
    end

    test "does not work if inviter is trade restricted and org is paid" do
      @org_admin.trade_controls_restriction.full!

      invitation = @org.invite(create(:user), inviter: @org_admin, role: :direct_member)

      assert invitation.valid?
    end

    test "does work if invitee is trade restricted and org is free" do
      invitee = create(:user, :fully_trade_restricted)
      @org.update(plan: "free")

      invitation = @org.reload.invite(invitee, inviter: @org_admin)
      assert invitation.valid?
    end

    test "does work if inviter is trade restricted and org is free" do
      @org.update(plan: "free")
      @org_admin.trade_controls_restriction.full!

      invitation = @org.reload.invite(create(:user), inviter: @org_admin)
      assert invitation.valid?
    end

    test "does not work if org is full trade restricted" do
      @org.trade_controls_restriction.full!

      assert_raises ::OrganizationInvitation::TradeControlsError do
        @org.invite(create(:user), inviter: @org_admin, role: :direct_member)
      end
    end

    test "does work if org is partial trade restricted" do
      @org.trade_controls_restriction.partial!

      invitation = @org.invite(create(:user), inviter: @org_admin, role: :direct_member)
      assert invitation.valid?
    end
  end

  test "queues a job to send VSS a status message", skip_enterprise: true do
    @org.business = create(:business, :volume_licensed)
    user = create(:user)
    create(:licensing_bundled_license_assignment, business_id: @org.business.id, email: user.email)
    create(:licensing_bundled_license_assignment, business_id: @org.business.id, email: user.email)

    assert_enqueued_jobs 2, only: Licensing::SendVssStatusMessageJob do
      @org.invite(user, inviter: @org_admin)
    end
  end

  if GitHub.spamminess_check_enabled?
    test "does not deliver invitations if inviter is spammy" do
      invitee = create(:user, login: "invitee")
      @org_admin.update_attribute :spammy, true

      AccountMailer.expects(:invited_to_org).never
      @org.invite(invitee, inviter: @org_admin, teams: [@team])

      AccountMailer.expects(:invited_to_org_by_email).never
      @org.invite(email: "garrett@github.com", inviter: @org_admin, teams: [@team])

      OrganizationMailer.expects(:invited_to_billing_manager_role).never
      @org.invite(invitee, inviter: @org_admin, role: :billing_manager)
    end
  end

  context "#rety_failed_invitations" do
    test "does not enqueue jobs when actor is not an org or site admin" do
      invitation = @org.invite (create :user), inviter: @org_admin
      invitation.update! failed_reason: :no_more_seats

      refute @org_member.site_admin?
      refute @org.admins.include?(@org_member)
      assert_enqueued_jobs 0, only: RetryFailedOrganizationInvitationJob do
        @org.retry_failed_invitations(@org_member)
      end
    end

    test "enqueues repository job" do
      invitation = @org.invite (create :user), inviter: @org_admin
      invitation.update! failed_reason: :no_more_seats

      repo = create(:repository, owner: @org)
      Timecop.freeze(Time.zone.now - GitHub.invitation_expiry_period.days - 1.day) do
        repo_invitation = create(
          :repository_invitation,
          repository: repo,
          inviter: @org_admin,
          invitee: create(:user),
          permissions: :write
        )
      end

      assert_enqueued_jobs 2, only: [RetryFailedOrganizationInvitationJob, RepositoryBulkInviteJob] do
        @org.retry_failed_invitations(@org_admin)
      end
    end
  end

  context "#destroy_failed_invitations" do
    test "does not enqueue job to destroy failed invitations when actor not an org or site admin" do
      invitation = @org.invite (create :user), inviter: @org_admin
      invitation.update! failed_reason: :no_more_seats

      refute @org_member.site_admin?
      refute @org.admins.include?(@org_member)
      assert_enqueued_jobs 0, only: DestroyFailedInvitationsToOrgJob do
        @org.destroy_failed_invitations(@org_member)
      end
    end

    test "enqueues job to destroy failed repository invitations" do
      site_admin = create :staff_admin_user
      invitation = @org.invite (create :user), inviter: @org_admin
      invitation.update! failed_reason: :no_more_seats

      assert site_admin.site_admin?
      refute @org.admins.include?(site_admin)
      assert_enqueued_jobs 2, only: [DestroyFailedInvitationsToOrgJob, DestroyFailedRepositoryInvitationsToOrgJob] do
        @org.destroy_failed_invitations(site_admin)
      end
    end
  end
end
