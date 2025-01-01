# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryInvitationValidationsTest < GitHub::TestCase
  include BackgroundDeletesTestHelpers

  fixtures do
    @inviter = create(:user)
    @invitee = create(:user)
    @repo = create(:repository)
  end

  test "can be valid" do
    invitation = RepositoryInvitation.new(
      repository: @repo,
      inviter: @inviter,
      invitee: @invitee,
      permissions: 1,
    )
    assert invitation.valid?, "should be valid"
  end

  test "requires a repository" do
    invitation = RepositoryInvitation.new(
      inviter: @inviter,
      invitee: @invitee,
      permissions: 1,
    )

    refute invitation.valid?, "should require a repository"
  end

  test "get's destroyed in background with repository" do
    repo = create(:public_repository)
    invitation = create(:repository_invitation, repository: repo)
    other_repo_invitation = create(:repository_invitation)

    assert_destroyed_in_background_with_parent do |config|
      config.parent_record = repo
      config.expect_destroyed = [invitation]
      config.expect_not_destroyed = [other_repo_invitation]
    end
  end

  test "requires an inviter" do
    invitation = RepositoryInvitation.new(
      repository: @repo,
      invitee: @invitee,
      permissions: 1,
    )

    refute invitation.valid?, "should require an inviter"
  end

  test "email can't be more than 100 characters" do
    invitation = RepositoryInvitation.new(
      repository: @repo,
      inviter: @inviter,
      email: "fawazfarid@#{"a" * 100}.com",
      permissions: 1,
    )

    refute invitation.valid?, "email not valid"
    assert invitation.errors[:email].any?, "should have email error"
  end

  test "email can't be more less than 3 characters" do
    invitation = RepositoryInvitation.new(
      repository: @repo,
      inviter: @inviter,
      email: "ff",
      permissions: 1,
    )

    refute invitation.valid?, "email not valid"
    assert invitation.errors[:email].any?, "should have email error"
  end

  test "email can't include a mailto: prefix" do
    invitation = RepositoryInvitation.new(
      repository: @repo,
      inviter: @inviter,
      email: "mailto:fawazfarid@github.com",
      permissions: 1,
    )

    refute invitation.valid?, "email should not be valid"
    assert invitation.errors[:email].any?, "should have email error"
  end

  test "requires either an invitee or email" do
    invitation = RepositoryInvitation.new(
      repository: @repo,
      inviter: @inviter,
      permissions: 1,
    )

    refute invitation.valid?, "should require an invitee or email"
  end

  test "requires no invitee if email present" do
    invitation = RepositoryInvitation.new(
      repository: @repo,
      inviter: @inviter,
      email: "fawazfarid@github.com",
      permissions: 1,
    )

    assert invitation.valid?, "should not require an invitee"
  end

  test "requires no email if invitee present" do
    invitation = RepositoryInvitation.new(
      repository: @repo,
      inviter: @inviter,
      invitee: @invitee,
      permissions: 1,
    )

    assert invitation.valid?, "should not require an email"
  end

  test "can't have both email and invitee" do
    invitation = RepositoryInvitation.new(
      repository: @repo,
      inviter: @inviter,
      invitee: @invitee,
      email: "fawazfarid@github.com",
      permissions: 1,
    )

    refute invitation.valid?, "should not have email and invitee"
  end

  test "invalid if not unique by repository and invitee" do
    old_invitation = RepositoryInvitation.create(
      repository: @repo,
      inviter: @inviter,
      invitee: @invitee,
      permissions: 1,
    )

    new_invitation = RepositoryInvitation.new(
      repository: @repo,
      inviter: @inviter,
      invitee: @invitee,
      permissions: 1,
    )

    refute new_invitation.valid?
    assert_includes new_invitation.errors[:invitee_id], "has already been invited"
  end

  test "invalid if not unique by repository and email" do
    old_invitation = RepositoryInvitation.create(
      repository: @repo,
      inviter: @inviter,
      email: "fawazfar@github.com",
      permissions: 1,
    )

    new_invitation = RepositoryInvitation.new(
      repository: @repo,
      inviter: @inviter,
      email: "fawazfar@github.com",
      permissions: 1,
    )

    refute new_invitation.valid?
    assert_includes new_invitation.errors[:email], "has already been invited"
  end
end

class RepositoryInvitationTest < GitHub::TestCase
  include NewsiesHelper
  include FineGrainedPermissionsTestHelper
  include DogstatsTestHelpers
  include HydroTestHelpers

  fixtures do
    @invitee = create(:user)
    @inviter = create(:user, plan: :micro)
    @other_member = create(:user)
    @organization = create(:business_plus_organization)
    @org_repo = create(:repository, owner: @organization)
    @repo = create(:repository, owner: @inviter)
    @team = create(:team, organization: @organization)
    @team.add_repository @org_repo, :pull
    @public_repo = create(:public_repository, owner: @inviter)
    @invitation = create(:repository_invitation,
      invitee: @invitee,
      inviter: @inviter,
      repository: @public_repo,
      permissions: 1,
    )
    @other_repo = create(:repository, name: "other-repo", owner: @inviter)
    create(:repository_invitation,
      invitee: @invitee,
      inviter: @inviter,
      repository: @other_repo,
      permissions: 1,
    )

    @business = create(:business)
    @business.add_organization(@organization)
    @organization.reload

    @internal_repo = create(:internal_repository, owner: @organization)
    @internal_repo.allow_private_repository_forking(actor: @organization.owner)

    @internal_repo_fork = create(:fork_repository, forker: @organization.admin, fork_repo: @internal_repo)
  end

  context "sponsorship_repository relation" do
    test "returns the sponsorship_repository with the same repository, invitee as sponsor, and inviter as sponsorable" do
      tier = create(:sponsors_tier, :approved_sponsors_listing, :with_repository)
      repo = tier.repository
      sponsorable = tier.sponsorable
      sponsor = create(:sponsorship, tier: tier, sponsorable: sponsorable).sponsor
      sponsorship_repository = create(:sponsorship_repository, sponsor: sponsor, sponsors_tier: tier,
        sponsorable: sponsorable, repository: repo)


      invitation = create(:repository_invitation,
        invitee: sponsor,
        inviter: sponsorable,
        repository: repo,
        permissions: 1,
      )

      assert_equal sponsorship_repository, invitation.sponsorship_repository
    end
  end

  context "::excluding_expired" do
    test "returns a relation without expired invitations" do
      expired_invitation = T.let(nil, T.nilable(RepositoryInvitation))
      Timecop.freeze(Time.zone.now - GitHub.invitation_expiry_period.days - 1.day) do
        expired_invitation = create(
          :repository_invitation,
          repository: @repo,
          inviter: @inviter,
          invitee: create(:user)
        )
      end

      result = RepositoryInvitation.excluding_expired
      refute_includes result, expired_invitation
      assert_includes result, @invitation
    end
  end

  context "::invite_to_repo" do
    test "does not send a confirmation when invitations are disabled" do
      GitHub.stubs(:repo_invites_enabled?).returns(false)
      RepositoryInvitation.invite_to_repo(@other_member, @inviter, @public_repo)
      assert_includes @public_repo.members, @other_member
      refute_includes @public_repo.invitees, @other_member
    end

    test "sends a confirmation when invitations are enabled" do
      GitHub.stubs(:repo_invites_enabled?).returns(true)
      RepositoryInvitation.invite_to_repo(@other_member, @inviter, @public_repo)
      refute_includes @public_repo.members, @other_member
      assert_includes @public_repo.invitees, @other_member
    end

    test "does not send a confirmation when the invitee is already a member of a team of the org", skip_enterprise: true do
      @team.add_member @other_member

      RepositoryInvitation.invite_to_repo(@other_member, @org_repo.owner, @org_repo)
      assert_includes @org_repo.members, @other_member
      refute_includes @org_repo.invitees, @other_member
    end

    test "does not send a confirmation when the invitee is already a member of the org", skip_enterprise: true do
      @organization.add_member @other_member

      RepositoryInvitation.invite_to_repo(@other_member, @org_repo.owner, @org_repo)
      assert_includes @org_repo.members, @other_member
      refute_includes @org_repo.invitees, @other_member
    end

    test "sends a confirmation when the invitee is not a member of the org", skip_enterprise: true do
      refute @organization.find_direct_or_team_member_by_login(@other_member.login)

      RepositoryInvitation.invite_to_repo(@other_member, @org_repo.owner, @org_repo)
      refute_includes @org_repo.members, @other_member
      assert_includes @org_repo.invitees, @other_member
    end

    test "does not send an invite when members cannot invite outside collaborators" do
      GitHub.stubs(:repo_invites_enabled?).returns(true)
      @organization.plan = GitHub::Plan.business_plus
      @organization.add_member @other_member
      @organization.disallow_members_can_invite_outside_collaborators(actor: @organization, force: true)
      refute @organization.members_can_invite_outside_collaborators?

      @org_repo.organization.plan = GitHub::Plan.business_plus
      @org_repo.add_member(@other_member, action: :admin)

      hash = RepositoryInvitation.invite_to_repo(@invitee, @other_member, @org_repo)

      refute hash[:success]
      collaborators_word = @organization.business&.emu_repository_collaborators_enabled? ? "repository collaborators" : GitHub.outside_collaborators_flavor
      assert_equal hash[:errors].messages.values.join(", "), "Only organization owners can invite #{collaborators_word}"

      refute_includes @org_repo.members, @invitee
      refute_includes @org_repo.invitees, @invitee
    end

    test "does not send the invite when the integration has org admin permissions and invites are restricted to enterprise owners" do
      GitHub.stubs(:repo_invites_enabled?).returns(true)
      @organization.plan = GitHub::Plan.business_plus
      @business.enterprise_admins_only_can_invite_outside_collaborators(actor: @organization)

      @org_repo.organization.plan = GitHub::Plan.business_plus

      app = create(:integration)
      installation = make_integration_installation(
        integration: app,
        target: @organization,
        permissions: { "organization_administration" => :write, "administration" => :write },
      )

      hash = RepositoryInvitation.invite_to_repo(@invitee, installation.bot, @org_repo)

      refute hash[:success]
      collaborators_word = @organization.business&.emu_repository_collaborators_enabled? ? "repository collaborators" : GitHub.outside_collaborators_flavor
      assert_equal hash[:errors].messages.values.join(", "), "Only enterprise owners can invite #{collaborators_word}"
      refute_includes @org_repo.members, @invitee
      refute_includes @org_repo.invitees, @invitee
    end

    test "does send invite if integration has write administration permission and members cannot invite outside collaborators" do
      GitHub.stubs(:repo_invites_enabled?).returns(true)
      @organization.plan = GitHub::Plan.business_plus
      @organization.disallow_members_can_invite_outside_collaborators(actor: @organization, force: true)
      refute @organization.members_can_invite_outside_collaborators?

      @org_repo.organization.plan = GitHub::Plan.business_plus

      app = create(:integration)
      installation = make_integration_installation(
        integration: app,
        target: @organization,
        permissions: { "organization_administration" => :write, "administration" => :write },
      )

      hash = RepositoryInvitation.invite_to_repo(@invitee, installation.bot, @org_repo)

      assert hash[:success]
      refute_includes @org_repo.members, @invitee
      assert_includes @org_repo.invitees, @invitee
    end

    test "does not send invite if integration does not have write administration permission and members cannot invite outside collaborators" do
      GitHub.stubs(:repo_invites_enabled?).returns(true)
      @organization.plan = GitHub::Plan.business_plus
      @organization.disallow_members_can_invite_outside_collaborators(actor: @organization, force: true)
      refute @organization.members_can_invite_outside_collaborators?

      @org_repo.organization.plan = GitHub::Plan.business_plus

      app = create(:integration)
      installation = make_integration_installation(
        integration: app,
        target: @organization,
        permissions: { "organization_administration" => :read },
      )

      hash = RepositoryInvitation.invite_to_repo(@invitee, installation.bot, @org_repo)

      refute hash[:success]
      assert_equal hash[:errors].messages.values.join(", "), "Only organization owners can invite outside collaborators"

      refute_includes @org_repo.members, @invitee
      refute_includes @org_repo.invitees, @invitee
    end

    test "does not send an invite when repo is an internal fork and user is not a member of the business" do
      GitHub.stubs(:repo_invites_enabled?).returns(true)

      hash = RepositoryInvitation.invite_to_repo(@invitee, @internal_repo_fork.owner, @internal_repo_fork)

      refute hash[:success]
      assert_equal hash[:errors].messages.values.join(", "), "Users outside of the enterprise account cannot be invited to a private or internal fork"
    end

    test "sends an invite when repo is an internal fork and user member of the business" do
      GitHub.stubs(:repo_invites_enabled?).returns(true)

      @organization.add_member(@invitee)

      hash = RepositoryInvitation.invite_to_repo(@invitee, @internal_repo_fork.owner, @internal_repo_fork)

      assert hash[:success]
      assert_includes @internal_repo_fork.members, @invitee
      refute_includes @internal_repo_fork.invitees, @invitee
    end

    test "does not send an invite when repo is an internal fork and business member is flagged as collaborator" do
      GitHub.stubs(:repo_invites_enabled?).returns(true)
      GitHub.stubs(:restrict_contractors_from_default_access_to_internal_repos?).returns(true)
      invitee = create(:user, :contractor)

      @organization.add_member(invitee)

      hash = RepositoryInvitation.invite_to_repo(invitee, @internal_repo_fork.owner, @internal_repo_fork)

      refute hash[:success]
      assert_equal hash[:errors].messages.values.join(", "), "Users outside of the enterprise account cannot be invited to a private or internal fork"
    end

    test "sends an invite when repo is an internal fork, business member is flagged as collaborator and has direct access over the root" do
      GitHub.stubs(:repo_invites_enabled?).returns(true)
      GitHub.stubs(:restrict_contractors_from_default_access_to_internal_repos?).returns(true)
      invitee = create(:user, :contractor)

      @organization.add_member(invitee)
      @internal_repo_fork.root.add_member(invitee)

      hash = RepositoryInvitation.invite_to_repo(invitee, @internal_repo_fork.owner, @internal_repo_fork)

      assert hash[:success]
      assert_includes @internal_repo_fork.members, invitee
      refute_includes @internal_repo_fork.invitees, invitee
    end

    test "sends an invite when repo is an internal fork and user is a member of the business" do
      GitHub.stubs(:repo_invites_enabled?).returns(true)

      @organization.add_member(@invitee)

      hash = RepositoryInvitation.invite_to_repo(@invitee, @internal_repo_fork.owner, @internal_repo_fork)

      assert hash[:success]
      assert_includes @internal_repo_fork.members, @invitee
      refute_includes @internal_repo_fork.invitees, @invitee
    end

    test "sends an invite when repo is an internal fork and user is a collaborator on the root" do
      GitHub.stubs(:repo_invites_enabled?).returns(true)

      @internal_repo.add_member(@invitee, action: :write)

      hash = RepositoryInvitation.invite_to_repo(@invitee, @internal_repo_fork.owner, @internal_repo_fork)

      assert hash[:success]
      assert_includes @internal_repo_fork.invitees, @invitee
      refute_includes @internal_repo_fork.members, @invitee
    end

    test "does not add a collaborator when members cannot invite outside collaborators" do
      GitHub.stubs(:repo_invites_enabled?).returns(false)
      @organization.plan = GitHub::Plan.business_plus
      @organization.add_member @other_member
      @organization.disallow_members_can_invite_outside_collaborators(actor: @organization, force: true)
      refute @organization.members_can_invite_outside_collaborators?

      @org_repo.organization.plan = GitHub::Plan.business_plus
      @org_repo.add_member(@other_member, action: :admin)

      hash = RepositoryInvitation.invite_to_repo(@invitee, @other_member, @org_repo)

      refute hash[:success]
      collaborators_word = @organization.business&.emu_repository_collaborators_enabled? ? "repository collaborators" : GitHub.outside_collaborators_flavor
      assert_equal hash[:errors].messages.values.join(", "), "Only organization owners can add #{collaborators_word}"

      refute_includes @org_repo.members, @invitee
      refute_includes @org_repo.invitees, @invitee
    end

    test "invites when members cannot invite outside collaborators but inviter is org admin" do
      GitHub.stubs(:repo_invites_enabled?).returns(false)
      @organization.disallow_members_can_invite_outside_collaborators(actor: @organization)
      @org_repo.reload

      RepositoryInvitation.invite_to_repo(@invitee, @org_repo.owner, @org_repo)

      assert_includes @org_repo.members, @invitee
      refute_includes @org_repo.invitees, @invitee
    end

    test "does not send the invite when the user cannot administer the org's business and invites are restricted to enterprise owners" do
      GitHub.stubs(:repo_invites_enabled?).returns(false)
      @business.enterprise_admins_only_can_invite_outside_collaborators(actor: @organization)
      @org_repo.reload

      hash = RepositoryInvitation.invite_to_repo(@invitee, @org_repo.owner, @org_repo)

      refute hash[:success]
      collaborators_word = @organization.business&.emu_repository_collaborators_enabled? ? "repository collaborators" : GitHub.outside_collaborators_flavor
      # Note the error message respects the repo_invites_enabled setting. Here we say "add" instead of "invite"
      assert_equal hash[:errors].messages.values.join(", "), "Only enterprise owners can add #{collaborators_word}"
      refute_includes @org_repo.members, @invitee
      refute_includes @org_repo.invitees, @invitee
    end

    test "does send the invite when the user can administer the org's business and invites are restricted to enterprise owners" do
      GitHub.stubs(:repo_invites_enabled?).returns(false)
      @business.enterprise_admins_only_can_invite_outside_collaborators(actor: @organization)
      @business.add_owner(@inviter, actor: @inviter)
      @organization.add_admin(@inviter)
      @org_repo.reload

      RepositoryInvitation.invite_to_repo(@invitee, @inviter, @org_repo)

      assert_includes @org_repo.members, @invitee
      refute_includes @org_repo.invitees, @invitee
    end

    test "does send the invite when the user can administer the org and invites are restricted to enterprise owners, but no enterprise is found" do
      GitHub.stubs(:repo_invites_enabled?).returns(false)
      @business.enterprise_admins_only_can_invite_outside_collaborators(actor: @organization)
      @business.add_owner(@inviter, actor: @inviter)
      @organization.add_admin(@inviter)
      @org_repo.reload

      # Simulate an org that has been removed from a business
      RepositoryInvitation::OutsideCollabCheck.any_instance.stubs(:org_has_business?).returns(false)

      RepositoryInvitation.invite_to_repo(@invitee, @inviter, @org_repo)

      assert_includes @org_repo.members, @invitee
      refute_includes @org_repo.invitees, @invitee
    end

    test "when org invites are off it allows invites of org members" do
      @organization.disallow_members_can_invite_outside_collaborators(actor: @organization)
      @organization.add_member @other_member

      RepositoryInvitation.invite_to_repo(@other_member, @org_repo.owner, @org_repo)

      assert_includes @org_repo.members, @other_member
      refute_includes @org_repo.invitees, @other_member
    end

    test "queues a job to send a status message to VSS", skip_enterprise: true do
      @org_repo.owner.business = create(:business, :volume_licensed)
      create(:licensing_bundled_license_assignment, business_id: @org_repo.owner.business.id, email: @invitee.email)
      create(:licensing_bundled_license_assignment, business_id: @org_repo.owner.business.id, email: @invitee.email)

      assert_enqueued_jobs 2, only: Licensing::SendVssStatusMessageJob do
        RepositoryInvitation.invite_to_repo(@invitee, @org_repo.owner, @org_repo)
      end
    end

    test "does not create invite for emu", skip_enterprise: true do
      emu = create(:emu)
      assert_no_changes -> { RepositoryInvitation.count } do
        result = RepositoryInvitation.invite_to_repo(emu, @inviter, @public_repo)
        assert_equal ["EMU cannot be invited."], result[:errors].messages[:base]
      end
    end
  end

  context "trade_controls_restrictions" do
    test "can't create an invite if public repo owned by fully trade restricted organization" do
      @organization.trade_controls_restriction.full!

      invitation = build(:repository_invitation,
        invitee: @invitee,
        inviter: @inviter,
        repository: @org_repo,
      )

      refute invitation.valid?
      assert_match TradeControls::Notices.notice_as_plaintext(:org_invite_restricted), invitation.errors[:base].first
    end

    test "can create an invite if public repo owned by partially trade restricted organization" do
      @organization.trade_controls_restriction.partial!

      invitation = build(:repository_invitation,
        invitee: @invitee,
        inviter: @inviter,
        repository: @org_repo,
      )

      assert invitation.valid?
    end

    test "can create an invite if public repo is fork of trade restricted org public repo" do
      forked_repo = create(:fork_repository, forker: @inviter, fork_repo: @org_repo)

      @organization.trade_controls_restriction.full!

      invitation = build(:repository_invitation,
        invitee: @invitee,
        inviter: @inviter,
        repository: forked_repo,
      )

      assert invitation.valid?
    end

    test "trade controls restricted user can't create an invitation to a private repo" do
      private_repo = create(:private_repository, owner: @inviter)
      @inviter.trade_controls_restriction.full!

      invitation = build(:repository_invitation,
        invitee: @invitee,
        inviter: @inviter,
        repository: private_repo,
      )

      refute invitation.valid?
      assert_match TradeControls::Notices.notice_as_plaintext(:org_invite_restricted), invitation.errors[:base].first
    end

    test "trade controls restricted org can't create an invitation to a private repo" do
      private_repo = create(:private_repository, owner: @organization)
      @organization.trade_controls_restriction.full!

      invitation = build(:repository_invitation,
        invitee: @invitee,
        inviter: @inviter,
        repository: private_repo,
       )

      refute invitation.valid?
      assert_match TradeControls::Notices.notice_as_plaintext(:org_invite_restricted), invitation.errors[:base].first
    end
  end

  context "::invite_to_repo_with_confirmation" do
    test "invites a member to a repo" do
      RepositoryInvitation.invite_to_repo_with_confirmation(@other_member, @inviter, @public_repo)
      assert_includes @public_repo.invitees, @other_member
    end

    test "does not invite a member if validation fails" do
      @public_repo.stubs(:can_add_user?).returns(false)
      RepositoryInvitation.invite_to_repo_with_confirmation(@other_member, @inviter, @public_repo)
      refute_includes @public_repo.invitees, @other_member
    end

    test "generates an audit log entry" do
      GitHub.dogstats.stubs(:increment)
      GitHub.dogstats.expects(:increment).with("repository_invitation", tags: ["action:create", "role:write"])

      events = subscribe "repository_invitation.create"
      invite = RepositoryInvitation.invite_to_repo_with_confirmation(@other_member, @inviter, @public_repo)
      expected_payload = {
        repo_invitation_id: invite[:invitation].id,
        org: @public_repo.organization,
        business: @public_repo.business,
        inviter: @inviter.login,
        inviter_id: @inviter.id,
        invitee: @other_member.login,
        invitee_id: @other_member.id,
        repo: @public_repo.name_with_owner,
        repo_id: @public_repo.id,
        public_repo: @public_repo.public?,
      }
      assert event = events.pop, "No event was created."
      assert_equal "repository_invitation.create", event.name
      assert_equal expected_payload, event.payload
    end

    test "duplicate invitations not allowed" do
      result = RepositoryInvitation.invite_to_repo_with_confirmation(@other_member, @inviter, @public_repo)

      assert_includes @public_repo.invitees, @other_member
      assert result[:invitation]
      assert result[:success]

      result = RepositoryInvitation.invite_to_repo_with_confirmation(@other_member, @inviter, @public_repo)
      refute result[:success]
      assert_equal ["User has already been invited"], result[:errors].messages[:base]

      # Race condition can be triggered while checking this and inserting the user
      # See https://github.com/github/github/issues/80771
      @public_repo.stubs(:can_add_user?).returns(true)

      result = RepositoryInvitation.invite_to_repo_with_confirmation(@other_member, @inviter, @public_repo)
      refute result[:success]
      assert_equal ["has already been invited"], result[:errors].messages[:invitee_id]

      # Raised when validation succeeds but unique index check fails
      RepositoryInvitation.any_instance.stubs(:save!).raises(ActiveRecord::RecordNotUnique.new("message"))
      new_result = RepositoryInvitation.invite_to_repo_with_confirmation(@other_member, @inviter, @public_repo)
      refute new_result[:success]
      assert_equal ["has already been invited"], new_result[:errors].messages[:invitee_id]
    end

    test "can invite with a custom role" do
      org = create(:business_plus_organization)
      repo = create(:private_repository, owner: org)
      custom_role = create(:custom_repository_role, :with_extra_permissions, owner_id: org.id, owner_type: "Organization", base_role_id: Role.maintain_role.id)

      result = RepositoryInvitation.invite_to_repo_with_confirmation(@other_member, repo.owner, repo, action: custom_role.name)

      assert_includes repo.invitees, @other_member
      assert result[:invitation]
      assert result[:success]
    end

    test "will not invite with a different org's custom role" do
      org = create(:business_plus_organization)
      other_org = create(:business_plus_organization)
      repo = create(:private_repository, owner: org)
      custom_role = create(:custom_repository_role, :with_extra_permissions, owner_id: other_org.id, owner_type: "Organization", base_role_id: Role.maintain_role.id)

      result = RepositoryInvitation.invite_to_repo_with_confirmation(@other_member, @inviter, repo, action: custom_role.name)

      refute_includes @public_repo.invitees, @other_member
      refute result[:invitation]
      refute result[:success]
    end
  end

  context "::invite_to_repo_without_confirmation" do
    test "adds a member to a repo without an invitation" do
      RepositoryInvitation.invite_to_repo_without_confirmation(
        @other_member,
        @inviter,
        @public_repo,
      )
      assert_includes @public_repo.members, @other_member
    end

    test "does not add a member without meeting 2fa requirements" do
      @org_repo.stubs(:two_factor_requirement_met_by?).with(@other_member).returns(false)
      RepositoryInvitation.invite_to_repo_without_confirmation(
        @other_member,
        @inviter,
        @org_repo,
      )
      refute_includes @org_repo.members, @other_member
    end

    test "does not add a member without meeting 2fa methods restritions" do
      @org_repo.stubs(:disallowed_two_factor_method_used_by?).with(@other_member).returns(true)
      RepositoryInvitation.invite_to_repo_without_confirmation(
        @other_member,
        @inviter,
        @org_repo,
      )
      refute_includes @org_repo.members, @other_member
    end
  end

  context ".cancel_all_invitations_involving" do
    test "only cancels invitations involving the given repository IDs" do
      assert @public_repo.has_invitation_for?(@invitee)
      assert @other_repo.has_invitation_for?(@invitee)

      RepositoryInvitation.cancel_all_invitations_involving(
        repo_ids: @public_repo.id, user: @invitee,
      )

      refute @public_repo.has_invitation_for?(@invitee), "should have cancelled invitation"
      assert @other_repo.has_invitation_for?(@invitee), "should not have cancelled invitation"
    end

    test "cancels invitations when the user is the inviter" do
      assert @public_repo.has_invitation_for?(@invitee)
      assert @other_repo.has_invitation_for?(@invitee)

      RepositoryInvitation.cancel_all_invitations_involving(
        repo_ids: @public_repo.id, user: @inviter,
      )

      refute @public_repo.has_invitation_for?(@invitee), "should have cancelled invitation"
      assert @other_repo.has_invitation_for?(@invitee), "should not have cancelled invitation"
    end

    test "cancels invitations for multiple repositories" do
      assert @public_repo.has_invitation_for?(@invitee)
      assert @other_repo.has_invitation_for?(@invitee)

      RepositoryInvitation.cancel_all_invitations_involving(
        repo_ids: [@public_repo.id, @other_repo.id], user: @invitee,
      )

      refute @public_repo.has_invitation_for?(@invitee), "should have cancelled invitation"
      refute @other_repo.has_invitation_for?(@invitee), "should not have cancelled invitation"
    end
  end

  context "#accept!" do
    test "adds the invitee to an org's private repo as long as the org has seats available" do
      org = create(:organization, seats: 5, plan: "business")
      3.times { org.add_member(create(:user)) }
      repo = create(:private_repository, owner: org)

      user = create(:user)
      invite = create(:repository_invitation, repository: repo, invitee: user)

      assert invite.accept!
      assert_includes repo.members, user

      # Allows user to accept invitations to other private repos
      other_repo = create(:private_repository, owner: org)
      invite = create(:repository_invitation, repository: other_repo, invitee: user)
      assert invite.accept!
      assert_includes other_repo.members, user
    end

    test "adds the invitee to the repo" do
      @invitation.accept!
      assert_includes @public_repo.members, @invitee
    end

    test "adds the bot created invitee to the repo" do
      repository = create(:repository, owner: @inviter)

      installation = make_integration_installation(
        repository: repository,
        permissions: { "administration" => :write },
      )

      invitation = create(:repository_invitation,
        repository: repository,
        invitee_id: @invitee.id,
        inviter_id: installation.bot.id,
        permissions: 2,
      )

      invitation.accept!

      assert_includes repository.members, @invitee
    end

    test "generates an audit log entry" do
      events = subscribe "repository_invitation.accept"
      @invitation.accept!
      expected_payload = {
        repo_invitation_id: @invitation.id,
        org: @public_repo.organization,
        business: @public_repo.business,
        inviter: @inviter.login,
        inviter_id: @inviter.id,
        invitee: @invitee.login,
        invitee_id: @invitee.id,
        repo: @public_repo.name_with_owner,
        repo_id: @public_repo.id,
        public_repo: @public_repo.public?,
      }
      assert event = events.pop, "No event was created."
      assert_equal "repository_invitation.accept", event.name
      assert_equal expected_payload, event.payload
    end

    test "generates an audit log entry for an outside collaborator" do
      refute @organization.user_is_outside_collaborator?(@other_member)
      refute @organization.members.include?(@other_member)
      org_repo_invite = create(:repository_invitation,
        invitee: @other_member,
        inviter: @org_repo.owner,
        repository: @org_repo,
        permissions: 1)

      events = subscribe "org.add_outside_collaborator"
      org_repo_invite.accept!
      expected_payload = {
        inviter: @org_repo.owner.login,
        inviter_id: @org_repo.owner.id,
        org: @organization.login,
        org_id: @organization.id,
        repo: @org_repo.name,
        repo_id: @org_repo.id,
        public_repo: @org_repo.public?,
        permission: "write",
        invitee: @other_member.login,
        invitee_id: @other_member.id,
        invitation_email: @other_member.email,
        }
      assert event = events.pop, "No event was created."
      assert_equal "org.add_outside_collaborator", event.name
      assert_equal expected_payload, event.payload
    end

    test "does not generate an org audit log entry if invitee is already an outside collaborator" do
      @org_repo.add_member(@other_member)
      assert @organization.user_is_outside_collaborator?(@other_member)

      second_org_repo = create(:repository, owner: @organization)
      org_repo_invite = create(:repository_invitation,
        invitee: @other_member,
        inviter: @org_repo.owner,
        repository: @org_repo,
        permissions: 1)
      events = subscribe "org.add_outside_collaborator"
      org_repo_invite.accept!
      assert_empty events
    end

    test "does not generate an org audit log entry if repository does not belong to org" do
      events = subscribe "org.add_outside_collaborator"
      @invitation.accept!

      assert_empty events
    end

    test "prevents user from accepting invite if it has expired" do
      Timecop.freeze(Time.new(2019, 1, 1, 0, 0, 0)) do
        @invitation.update(created_at: (GitHub.invitation_expiry_period + 1).days.ago)
        assert @invitation.invite_expired?
        accept = @invitation.accept!

        refute accept
        refute RepositoryInvitation.exists? @invitation.id
      end
    end

    if GitHub.sponsors_enabled?
      test "does not prevent user from accepting invite if the invitation came from a sponsorship, even if it is past the expiry period" do
        travel_to(Time.new(2019, 1, 1, 0, 0, 0)) do
          tier = create(:sponsors_tier, :approved_sponsors_listing, :with_repository)
          repo = tier.repository
          sponsorable = tier.sponsorable
          sponsor = create(:sponsorship, tier: tier, sponsorable: sponsorable).sponsor
          sponsorship_repo = create(:sponsorship_repository, sponsor: sponsor, sponsors_tier: tier,
            sponsorable: sponsorable, repository: repo)


          invitation = create(:repository_invitation,
            invitee: sponsor,
            inviter: sponsorable,
            repository: repo,
            permissions: 1,
          )
          invitation.update(created_at: (GitHub.invitation_expiry_period + 1).days.ago)
          refute invitation.invite_expired?

          events = subscribe "repository_invitation.accept"
          invitation.accept!
          expected_payload = {
            repo_invitation_id: invitation.id,
            inviter: sponsorable.login,
            inviter_id: sponsorable.id,
            invitee: sponsor.login,
            invitee_id: sponsor.id,
            repo: repo.name_with_owner,
            repo_id: repo.id,
            public_repo: repo.public?,
            org: repo.organization&.login,
            org_id: repo.organization&.id,
            business: repo.business,
          }

          assert event = events.pop, "No event was created."
          assert_equal "repository_invitation.accept", event.name
          assert_equal expected_payload, event.payload
        end
      end
    end

    test "works with a custom role" do
      GitHub.dogstats.stubs(:increment)
      GitHub.dogstats.expects(:increment).with("repository_invitation", tags: ["action:create", "role:custom_role"])
      org = create(:business_plus_organization)
      repo = create(:private_repository, owner: org)
      custom_role = create(:custom_repository_role, :with_extra_permissions, owner_id: org.id, owner_type: "Organization", base_role_id: Role.maintain_role.id)

      invitation = create(:repository_invitation,
        repository: repo,
        invitee_id: @invitee.id,
        inviter_id: org.owner.id,
        permissions: nil,
        role_id: custom_role.id
      )

      invitation.accept!

      assert_includes repo.members, @invitee
      assert_equal repo.direct_role_for(@invitee), custom_role.name.to_sym
    end

    test "allows specifying acceptor for email invitation" do
      invitation = create(:repository_invitation, :email)
      repo = invitation.repository

      assert invitation.accept!(acceptor: @invitee)
      assert_includes repo.members, @invitee
    end

    test "does not allow accepting user invitation with different acceptor" do
      invitation = create(:repository_invitation)
      repo = invitation.repository

      refute invitation.accept!(acceptor: @invitee)
      refute_includes repo.members, @invitee
    end
  end

  context "#reject!" do
    test "deletes the invitation" do
      @invitation.reject!
      refute_includes @public_repo.repository_invitations, @invitation
    end

    test "generates an audit log entry" do
      events = subscribe "repository_invitation.reject"
      @invitation.reject!
      expected_payload = {
        repo_invitation_id: @invitation.id,
        org: @public_repo.organization,
        business: @public_repo.business,
        inviter: @inviter.login,
        inviter_id: @inviter.id,
        invitee: @invitee.login,
        invitee_id: @invitee.id,
        repo: @public_repo.name_with_owner,
        repo_id: @public_repo.id,
        public_repo: @public_repo.public?,
      }
      assert event = events.pop, "No event was created."
      assert_equal "repository_invitation.reject", event.name
      assert_equal expected_payload, event.payload
    end

    test "queues a job to send VSS a status message", skip_enterprise: true do
      invitation = create(:repository_invitation,
        repository: @org_repo,
        invitee_id: @invitee
      )
      @org_repo.owner.business = create(:business, :volume_licensed)
      create(:licensing_bundled_license_assignment, business_id: @org_repo.owner.business.id, email: @invitee.email)
      create(:licensing_bundled_license_assignment, business_id: @org_repo.owner.business.id, email: @invitee.email)
      invitation = RepositoryInvitation.find invitation.id

      assert_enqueued_jobs 2, only: Licensing::SendVssStatusMessageJob do
        invitation.reject!
      end
    end
  end

  context "#cancel!" do
    test "cancels an invitation if the actor can administer the repo" do
      @invitation.cancel!(actor: @inviter)

      refute_includes @public_repo.repository_invitations, @invitation
    end

    test "instruments an audit log entry" do
      events = subscribe "repository_invitation.cancel"
      @invitation.cancel!(actor: @inviter)

      expected_payload = {
        repo_invitation_id: @invitation.id,
        org: @public_repo.organization,
        business: @public_repo.business,
        inviter: @inviter.login,
        inviter_id: @inviter.id,
        invitee: @invitee.login,
        invitee_id: @invitee.id,
        repo: @public_repo.name_with_owner,
        repo_id: @public_repo.id,
        public_repo: @public_repo.public?,
        actor: @inviter.login,
        actor_id: @inviter.id,
      }

      assert event = events.pop, "No event was created."
      assert_equal "repository_invitation.cancel", event.name
      assert_equal expected_payload, event.payload
    end

    test "fails if the actor cannot administer the repo" do
      @invitation.cancel!(actor: @other_member)

      assert_includes @public_repo.repository_invitations, @invitation
    end
  end

  context "#permissions_string" do
    test "returns the correct permission" do
      assert_equal @invitation.permission_string, "write"
    end
  end

  context "notifications" do
    test "sends newsies notification" do
      new_user = create(:user)
      enable_notifications_for_user(new_user)

      invitation = create(:repository_invitation,
        invitee: new_user,
        inviter: @inviter,
        repository: @public_repo,
        permissions: 1,
      )

      only = [Newsies::DeliverNotificationsJob]
      perform_enqueued_jobs(only: only) { RepositoryCollabInvitationJob.perform_now(invitation.id) }

      assert_delivered_web_notification(new_user, invitation, "invitation")
    end

    test "sends newsies notification for a private repository" do
      new_user = create(:user)
      enable_notifications_for_user(new_user)

      invitation = create(:repository_invitation,
        invitee: new_user,
        inviter: @inviter,
        repository: create(:private_repository),
        permissions: 1,
      )

      only = [Newsies::DeliverNotificationsJob]
      perform_enqueued_jobs(only: only) { RepositoryCollabInvitationJob.perform_now(invitation.id) }

      assert_delivered_web_notification(new_user, invitation, "invitation")
    end

    test "#notifications_thread returns RepositoryInvitation" do
      assert_equal @invitation, @invitation.notifications_thread
    end

    test "#notifications_list returns Repository" do
      assert_equal @public_repo, @invitation.notifications_list
    end

    test "#notifications_author returns inviter" do
      assert_equal @inviter, @invitation.notifications_author
    end

    context "cleans up notifications after destroy" do
      test "removes notification_subscriptions record" do
        summary = GitHub.newsies.web.rollup_summary_from_repository_invitation(@invitation)

        Newsies::NotificationEntry.insert(@invitee.id, summary)
        assert_equal GitHub.newsies.web.count(@invitee), 1

        @invitation.destroy
        assert_equal GitHub.newsies.web.count(@invitee), 0
      end

      test "removes saved threads" do
        summary = GitHub.newsies.web.rollup_summary_from_repository_invitation(@invitation)
        Newsies::NotificationEntry.insert(@invitee.id, summary)

        GitHub.newsies.web.save_thread(@invitee, @invitation)
        assert_equal GitHub.newsies.web.count_saved(@invitee), 1

        @invitation.destroy
        assert_equal GitHub.newsies.web.count_saved(@invitee), 0
      end

      # In rare cases (see #106287) the invitee may not exist in the users table
      test "does not error if invitee no longer exists" do
        summary = GitHub.newsies.web.rollup_summary_from_repository_invitation(@invitation)
        Newsies::NotificationEntry.insert(@invitee.id, summary)

        GitHub.newsies.web.save_thread(@invitee, @invitation)
        assert_equal GitHub.newsies.web.count_saved(@invitee), 1

        @invitation.invitee.delete
        @invitation.reload
        @invitation.destroy
        assert_equal GitHub.newsies.web.count_saved(@invitee), 1
      end
    end

    context "cleans up notifications after accept" do
      test "removes notification_subscriptions record" do
        summary = GitHub.newsies.web.rollup_summary_from_repository_invitation(@invitation)
        Newsies::NotificationEntry.insert(@invitee.id, summary)

        assert_equal GitHub.newsies.web.count(@invitee), 1

        @invitation.accept!
        assert_equal GitHub.newsies.web.count(@invitee), 0
      end

      test "removes saved threads" do
        summary = GitHub.newsies.web.rollup_summary_from_repository_invitation(@invitation)
        Newsies::NotificationEntry.insert(@invitee.id, summary)

        GitHub.newsies.web.save_thread(@invitee, @invitation)
        assert_equal GitHub.newsies.web.count_saved(@invitee), 1

        @invitation.accept!
        assert_equal GitHub.newsies.web.count_saved(@invitee), 0
      end
    end
  end

  context "#readable_by?" do
    test "can be read by an admin of the repository" do
      assert @invitation.repository.adminable_by?(@inviter), "Expected the @inviter to admin the repository"
      assert @invitation.readable_by?(@inviter)
    end

    test "can be read by the invitee themselves" do
      assert @invitation.readable_by?(@invitee)
    end

    test "can be read by an actor with administration read granular permissions" do
      installation = make_integration_installation(repository: @invitation.repository, permissions: { "administration" => :read })
      assert @invitation.readable_by?(installation)
    end
  end

  context "#set_permissions" do
    test "`setter` is required to be present" do
      exception = assert_raises(ArgumentError) do
        @invitation.set_permissions(:admin, nil)
      end
      assert_equal("setter is required!", exception.message)
    end

    test "random users cannot set permissions for repos they do not have admin on" do
      rando = create(:user)
      exception = assert_raises(RepositoryInvitation::InsufficientAbilities) do
        @invitation.set_permissions(:admin, rando)
      end
      assert_match(/id: #{rando.id}.* lacks the ability to set :admin/, exception.message)
    end

    {
      :read => :read?,
      :write => :write?,
      :admin => :admin?,
      "read" => :read?,
      "write" => :write?,
      "admin" => :admin?,
      "pull" => :read?,
      "push" => :write?,
    }.each do |permission, predicate|
      test "properly maps #{permission.inspect} to #{predicate}" do
        @invitation.set_permissions(permission, @invitation.repository.owner)
        assert_predicate @invitation.reload, predicate
      end
    end

    test "setting triage permission" do
      invitee = create(:user)
      invitation = create(:repository_invitation,
        invitee: invitee,
        inviter: @organization,
        repository: @org_repo,
        permissions: 1,
      )
      assert invitation.set_permissions("triage", @organization.admin)
      assert invitation.reload.triage?
      assert invitation.accept!
      assert_equal :triage, @org_repo.async_action_or_role_level_for(invitee).sync
    end

    test "setting triage permission on an org's private fork of a different org's repository" do
      other_org = create(:business_plus_organization)
      invitee = create(:user)
      org_owned_fork = create(:fork_repository, forker: other_org.admin, fork_repo: @org_repo, organization: other_org)
      invitation = create(:repository_invitation,
        invitee: invitee,
        inviter: other_org.admin,
        repository: org_owned_fork,
        permissions: 1,
      )

      assert invitation.set_permissions("triage", other_org.admin)
      assert invitation.reload.triage?
      assert invitation.accept!
      assert_equal :triage, org_owned_fork.async_action_or_role_level_for(invitee).sync
    end

    test "setting maintain permission" do
      invitee = create(:user)
      invitation = create(:repository_invitation,
        invitee: invitee,
        inviter: @organization,
        repository: @org_repo,
        permissions: 1,
      )
      assert invitation.set_permissions("maintain", @organization.admin)
      assert invitation.reload.maintain?
      assert invitation.accept!
      assert_equal :maintain, @org_repo.async_action_or_role_level_for(invitee).sync
    end

    test "setting maintain permission on an org's private fork of a different org's repository" do
      other_org = create(:business_plus_organization)
      invitee = create(:user)
      org_owned_fork = create(:fork_repository, forker: other_org.admin, fork_repo: @org_repo, organization: other_org)
      invitation = create(:repository_invitation,
        invitee: invitee,
        inviter: other_org.admin,
        repository: org_owned_fork,
        permissions: 1,
      )

      assert invitation.set_permissions("maintain", other_org.admin)
      assert invitation.reload.maintain?
      assert invitation.accept!
      assert_equal :maintain, org_owned_fork.async_action_or_role_level_for(invitee).sync
    end

    test "setting custom role" do
      custom_role = create_custom_role(role_name: "foo 🌴 bar", role_description: "waahhh ⚠️  ", owner: @organization)
      invitee = create(:user)
      invitation = create(:repository_invitation,
        invitee: invitee,
        inviter: @organization,
        repository: @org_repo,
        permissions: 1,
      )
      assert invitation.set_permissions(custom_role.name, @organization.admin)
      assert_equal invitation.reload.role_id, custom_role.id
      assert invitation.accept!
      assert_equal custom_role.name.to_sym, @org_repo.async_action_or_role_level_for(invitee).sync
    end

    test "setting custom role on an org's private fork of a different org's repository" do
      other_org = create(:business_plus_organization)
      other_custom_role = create_custom_role(role_name: "foo 🌴 bar 2", role_description: "waahhh ⚠️  ", owner: other_org)
      invitee = create(:user)
      org_owned_fork = create(:fork_repository, forker: other_org.admin, fork_repo: @org_repo, organization: other_org)
      invitation = create(:repository_invitation,
        invitee: invitee,
        inviter: other_org.admin,
        repository: org_owned_fork,
        permissions: 1,
      )

      assert invitation.set_permissions(other_custom_role.name, other_org.admin)
      assert_equal invitation.reload.role_id, other_custom_role.id
      assert invitation.accept!
      assert_equal other_custom_role.name.to_sym, org_owned_fork.async_action_or_role_level_for(invitee).sync
    end

    test "setting read permission below org base role" do
      other_org = create(:business_plus_organization)
      repo = create(:repository, owner: other_org)

      # read: 0, write: 1, admin: 2
      # invitation with admin permission
      invitee = create(:user)
      invitation = create(:repository_invitation,
        invitee: invitee,
        inviter: other_org,
        repository: repo,
        permissions: 2,
      )

      # invitation with maintain permission
      invitee2 = create(:user)
      invitation2 = create(:repository_invitation,
        invitee: invitee2,
        inviter: other_org,
        repository: repo,
        role_id: Role.maintain_role.id,
      )

      other_org.update_default_repository_permission("write", actor: other_org.admin)

      other_org.reload
      invitee.reload

      assert invitation.set_permissions("read", other_org.admin)
      assert invitation.reload.read?
      assert invitation.accept!
      assert_equal :read, repo.async_action_or_role_level_for(invitee).sync

      assert invitation2.set_permissions("read", other_org.admin)
      assert invitation2.reload.read?
      assert invitation2.accept!
      assert_equal :read, repo.async_action_or_role_level_for(invitee2).sync
    end

    test "setting maintain permission below org base role" do
      other_org = create(:business_plus_organization)
      repo = create(:repository, owner: other_org)

      # read: 0, write: 1, admin: 2
      # invitation with read permission
      invitee = create(:user)
      invitation = create(:repository_invitation,
        invitee: invitee,
        inviter: other_org,
        repository: repo,
        permissions: 0,
      )

      # invitation with triage permission
      invitee2 = create(:user)
      invitation2 = create(:repository_invitation,
        invitee: invitee2,
        inviter: other_org,
        repository: repo,
        role_id: Role.triage_role.id,
      )

      other_org.update_default_repository_permission("admin", actor: other_org.admin)

      other_org.reload
      invitee.reload

      assert invitation.set_permissions("maintain", other_org.admin)
      assert invitation.reload.maintain?
      assert invitation.accept!
      assert_equal :maintain, repo.async_action_or_role_level_for(invitee).sync

      assert invitation2.set_permissions("maintain", other_org.admin)
      assert invitation2.reload.maintain?
      assert invitation2.accept!
      assert_equal :maintain, repo.async_action_or_role_level_for(invitee2).sync
    end

    test "setting custom role below org base role" do
      other_org = create(:business_plus_organization)
      repo = create(:repository, owner: other_org)
      custom_role = create_custom_role(role_name: "foo 🌴 bar", role_description: "waahhh ⚠️  ", owner: other_org, base_role: :read)

      # read: 0, write: 1, admin: 2
      # invitation with write permission
      invitee = create(:user)
      invitation = create(:repository_invitation,
        invitee: invitee,
        inviter: other_org,
        repository: repo,
        permissions: 1,
      )

      # invitation with triage permission
      invitee2 = create(:user)
      invitation2 = create(:repository_invitation,
        invitee: invitee2,
        inviter: other_org,
        repository: repo,
        role_id: Role.triage_role.id,
      )

      other_org.update_default_repository_permission("write", actor: other_org.admin)

      other_org.reload
      invitee.reload

      assert invitation.set_permissions(custom_role.name, other_org.admin)
      assert_equal invitation.reload.role_id, custom_role.id
      assert invitation.accept!
      assert_equal custom_role.name.to_sym, repo.async_action_or_role_level_for(invitee).sync

      assert invitation2.set_permissions(custom_role.name, other_org.admin)
      assert_equal invitation2.reload.role_id, custom_role.id
      assert invitation2.accept!
      assert_equal custom_role.name.to_sym, repo.async_action_or_role_level_for(invitee2).sync
    end

    test "changing from custom role to system role below org default" do
      other_org = create(:business_plus_organization)
      repo = create(:repository, owner: other_org)
      custom_role = create_custom_role(role_name: "foo 🌴 bar", role_description: "waahhh ⚠️  ", owner: other_org, base_role: :maintain)

      # invitation with custom role
      invitee = create(:user)
      invitation = create(:repository_invitation,
        invitee: invitee,
        inviter: other_org,
        repository: repo,
        role_id: custom_role.id,
      )

      # invitation with custom role
      invitee2 = create(:user)
      invitation2 = create(:repository_invitation,
        invitee: invitee2,
        inviter: other_org,
        repository: repo,
        role_id: custom_role.id,
      )

      other_org.update_default_repository_permission("write", actor: other_org.admin)

      other_org.reload
      invitee.reload

      assert invitation.set_permissions("maintain", other_org.admin)
      assert invitation.reload.maintain?
      assert invitation.accept!
      assert_equal :maintain, repo.async_action_or_role_level_for(invitee).sync

      assert invitation2.set_permissions("read", other_org.admin)
      assert invitation2.reload.read?
      assert invitation2.accept!
      assert_equal :read, repo.async_action_or_role_level_for(invitee2).sync
    end

    test "raises error when custom role doesn't exist or is from a different org" do
      other_org = create(:business_plus_organization)
      repo = create(:repository, owner: other_org)
      custom_role = create_custom_role(role_name: "🌴 bar", role_description: "waahhh ⚠️  ", owner: @organization)
      other_custom_role = create_custom_role(role_name: "vacation 🌴", role_description: "waahhh ⚠️  ", owner: other_org, base_role: :maintain)

      # invitation with write permission
      invitee = create(:user)
      invitation = create(:repository_invitation,
        invitee: invitee,
        inviter: other_org,
        repository: repo,
        permissions: 1,
      )

      assert_raises ArgumentError do
        invitation.set_permissions(custom_role.name, other_org.admin)
      end

      assert_equal invitation.permissions, "write"

      assert_raises ArgumentError do
        invitation.set_permissions("vocation 🌴", other_org.admin)
      end

      assert_equal invitation.permissions, "write"
    end

    test "raises error when setting invalid permission" do
      invitee = create(:user)
      invitation = create(:repository_invitation,
        invitee: invitee,
        inviter: @organization,
        repository: @org_repo,
        permissions: :write,
      )
      assert_raises ArgumentError do
        invitation.set_permissions(:blah, @organization.admin)
      end

      assert_equal invitation.permissions, "write"
    end
  end

  context "rate limits" do
    if GitHub.rate_limiting_enabled?
      test "limits how many invitations can be created in a period of time for the same repo" do
        GitHub.stubs(:repository_invitation_rate_limit).returns(1)

        Timecop.freeze do
          create(:repository_invitation, repository: @repo) # create one to hit the limit

          invitation = build(:repository_invitation, repository: @repo)
          refute_predicate invitation, :valid?
          assert_includes invitation.errors[:rate_limit], "exceeded"
        end
      end

      test "increments Datadog counter when rate limit is hit" do
        GitHub.stubs(:repository_invitation_rate_limit).returns(0)

        invitation = build(:repository_invitation, repository: @repo)
        refute invitation.valid?

        assert_dogstats_increment 1, "repository_invitations.rate_limit_exceeded"
      end

      test "ignores the rate limit when 'ignore_rate_limit' is set to true" do
        GitHub.stubs(:repository_invitation_rate_limit).returns(0)

        invitation = build(:repository_invitation, repository: @repo)
        invitation.ignore_rate_limit = true

        assert_predicate invitation, :valid?
      end

      test "respects the rate limit when 'ignore_rate_limit' is set to false" do
        GitHub.stubs(:repository_invitation_rate_limit).returns(0)

        invitation = build(:repository_invitation, repository: @repo)
        invitation.ignore_rate_limit = false

        refute_predicate invitation, :valid?
        assert_includes invitation.errors[:rate_limit], "exceeded"
      end

      test "raises if you try to ignore the rate limit after an invitation is created" do
        invitation = create(:repository_invitation, repository: @repo)

        assert_raises RuntimeError, "Can't ignore the rate limit on persisted invitations" do
          invitation.ignore_rate_limit = true
        end
      end

      test "ignores rate limit when inviting org members" do
        org = create(:organization)
        org_member = create(:user)
        org.add_member(org_member)
        org_repo = create(:repository, owner: org)
        GitHub.stubs(:repository_invitation_rate_limit).returns(1)

        Timecop.freeze do
          create(:repository_invitation, repository: org_repo)

          invitation = build(:repository_invitation, repository: org_repo, invitee: org_member)
          assert_predicate invitation, :valid?
        end
      end

      test "ignores rate limit when repo has the rate limit overridden" do
        RepositoryInvitationRateLimitOverride.override!(@repo.id)
        GitHub.stubs(:repository_invitation_rate_limit).returns(1)

        Timecop.freeze do
          create(:repository_invitation, repository: @repo)

          invitation = build(:repository_invitation, repository: @repo)
          assert_predicate invitation, :valid?
        end
      end
    else
      test "does not rate limit creation per repository" do
        GitHub.stubs(:repository_invitation_rate_limit).returns(1)

        Timecop.freeze do
          create(:repository_invitation, repository: @repo)

          invitation = build(:repository_invitation, repository: @repo)
          assert_predicate invitation, :valid?
        end
      end
    end
  end

  context "token" do
    test "does not generate token if no email is present" do
      invitation = RepositoryInvitation.new(
        repository: @repo,
        inviter: @inviter,
        invitee: @invitee,
        permissions: 1,
      )

      assert invitation.valid?
      refute_predicate invitation.token, :present?
      refute_predicate invitation.hashed_token, :present?
    end

    test "generates token if email is present" do
      invitation = RepositoryInvitation.new(
        repository: @repo,
        inviter: @inviter,
        email: "fawazfarid@github.com",
        permissions: 1,
      )

      assert invitation.valid?
      assert_predicate invitation.token, :present?
      assert_predicate invitation.hashed_token, :present?
    end

    test "only stores the hashed token" do
      persisted_invitation = create(:repository_invitation,
        repository: @repo,
        inviter: @inviter,
        invitee: nil,
        email: "fawazfarid@github.com",
        permissions: 1,
      )

      invitation = RepositoryInvitation.find(persisted_invitation.id)
      refute_predicate invitation.token, :present?
      assert_predicate invitation.hashed_token, :present?
    end

    test "allows the token to be reset" do
      invitation = create(:repository_invitation,
        repository: @repo,
        inviter: @inviter,
        invitee: nil,
        email: "fawazfarid@github.com",
        permissions: 1,
      )

      old_token = invitation.token
      invitation.reset_token

      refute_equal old_token, invitation.token
      assert_equal invitation, RepositoryInvitation.find_by_token(invitation.token)
    end
  end

  context ".batch_enqueue_update_repo_permissions" do
    test "enqueues 2 jobs to update the 2 invitations based on the batch size of 1" do
      admin = @organization.admins.first
      invitations = [
        create(:repository_invitation,
          invitee: create(:user),
          inviter: @inviter,
          repository: @org_repo,
          permissions: :triage,
        ),
        create(:repository_invitation,
          invitee: create(:user),
          inviter: @inviter,
          repository: @org_repo,
          permissions: :triage,
        )
      ]

      BatchUpdateInvitationRepoPermissionsJob.expects(:perform_later).twice

      only = [BatchUpdateInvitationRepoPermissionsJob]
      perform_enqueued_jobs(only: only) do
        RepositoryInvitation.batch_enqueue_update_repo_permissions(invitations: invitations, setter: admin,
          action: :maintain, batch_size: 1)
      end
    end
  end

  context "licensing snapshots", skip_enterprise: true do
    test "publishes license snapshot messages when an private repository invitation is created, updated, and destroyed if the owner is business owned" do
      business = create(:business)
      organization = create(:organization, business: business)
      repository = create(:private_repository, owner: organization)

      reset_hydro # clear any messages that were sent during setup

      perform_enqueued_jobs(only: Licensing::SnapshotLicensesJob) do
        invitation = create(
          :repository_invitation,
          repository: repository,
          inviter: organization.admins.first,
          invitee: @invitee,
        )

        assert_hydro_messages(count: 1, schema: "github.billing.v0.LicenseSnapshot")

        invitation.update(created_at: 1.year.from_now)

        assert_hydro_messages(count: 2, schema: "github.billing.v0.LicenseSnapshot")

        invitation.destroy

        assert_hydro_messages(count: 3, schema: "github.billing.v0.LicenseSnapshot")
      end
    end

    test "does not publish license snapshot messages when a the repository is deleted" do
      business = create(:business)
      organization = create(:organization, business: business)
      repository = create(:private_repository, owner: organization)

      invitation = create(:repository_invitation,
        repository: repository,
        inviter: organization.admins.first,
        invitee: @invitee,
      )
      repository.delete
      invitation.reload
      reset_hydro # clear any messages that were sent during setup

      perform_enqueued_jobs(only: Licensing::SnapshotLicensesJob) do
        invitation.update(created_at: 1.year.from_now)
        invitation.destroy
      end

      assert_hydro_messages(count: 0, schema: "github.billing.v0.LicenseSnapshot")
    end

    test "does not publish license snapshot messages for public repository invitations" do
      business = create(:business)
      organization = create(:organization, business: business)
      repository = create(:public_repository, owner: organization)

      reset_hydro # clear any messages that were sent during setup

      perform_enqueued_jobs(only: Licensing::SnapshotLicensesJob) do
        invitation = create(
          :repository_invitation,
          repository: repository,
          inviter: organization.admins.first,
          invitee: @invitee,
        )
        invitation.update(created_at: 1.year.from_now)
        invitation.destroy
      end

      assert_hydro_messages(count: 0, schema: "github.billing.v0.LicenseSnapshot")
    end

    test "does not publish license snapshot events if the owner is not business owned" do
      organization = create(:organization)
      repository = create(:private_repository, owner: organization)

      reset_hydro # clear any messages that were sent during setup

      perform_enqueued_jobs(only: Licensing::SnapshotLicensesJob) do
        invitation = create(
          :repository_invitation,
          repository: repository,
          inviter: organization.admins.first,
          invitee: @invitee,
        )
        invitation.update(created_at: 1.year.from_now)
        invitation.destroy
      end

      assert_hydro_messages(count: 0, schema: "github.billing.v0.LicenseSnapshot")
    end
  end

  context "Updating bundled license assignments on invitation acceptance", skip_enterprise: true do
    test "queues Licensing::SetUserFromEmailsOnBundledLicenseAssignmentJob job when org business has volume_license_enabled" do
      business = create(:business, :volume_licensed)
      organization = create(:organization, business: business)
      repository = create(:public_repository, owner: organization)

      invitation = create(
        :repository_invitation,
        repository: repository,
        inviter: organization.admins.first,
        invitee: @invitee,
      )

      # Make sure the invitee starts out as not a member of the org.
      refute organization.direct_or_team_member?(@invitee)

      assert_enqueued_with job: Licensing::SetUserFromEmailsOnBundledLicenseAssignmentJob, queue: "licensing" do
        invitation.accept!
      end
    end

    test "links bundled license assignment to user that accepts invitiations if email matches" do
      email = "foo@example.com"
      business = create(:business, :volume_licensed)
      organization = create(:organization, business: business)
      repository = create(:public_repository, owner: organization)
      assignment = create(:licensing_bundled_license_assignment, business: business, email: email, user: nil)

      invitation = create(
        :repository_invitation,
        repository: repository,
        inviter: organization.admins.first,
        invitee: nil,
        email: email
      )

      perform_enqueued_jobs only: Licensing::SetUserFromEmailsOnBundledLicenseAssignmentJob do
        invitation.accept!(acceptor: @invitee)
      end

      assert_equal @invitee, assignment.reload.user
    end

    test "does nothing if invite business does not have volume licensing enabled" do
      business = create(:business)
      organization = create(:organization, business: business)
      repository = create(:public_repository, owner: organization)

      invitation = create(
        :repository_invitation,
        repository: repository,
        inviter: organization.admins.first,
        invitee: @invitee,
      )

      # Make sure the invitee starts out as not a member of the org.
      refute organization.direct_or_team_member?(@invitee)

      assert_no_enqueued_jobs only: Licensing::SetUserFromEmailsOnBundledLicenseAssignmentJob, queue: "billing" do
        invitation.accept!
      end
    end
  end

  context "#same_action?" do
    test "returns true if action corresponds to the invitation's permission" do
      # permissions: 2 => admin
      invitation = create(:repository_invitation, repository: @repo, permissions: 2)
      assert invitation.same_action?(action: "admin")
    end

    test "returns false if action doesn't match the invitation's permission" do
      # permissions: 2 => admin
      invitation = create(:repository_invitation, repository: @repo, permissions: 2)
      refute invitation.same_action?(action: "read")
    end

    test "returns true if action corresponds to invitation's [default] role" do
      invitation = create(:repository_invitation, repository: @org_repo, role: Role.write_role)
      assert invitation.same_action?(action: "write")
    end

    test "can convert pull/push to read/write" do
      invitation = create(:repository_invitation, repository: @org_repo, role: Role.write_role)
      assert invitation.same_action?(action: "push")

      invitation = create(:repository_invitation, repository: @org_repo, role: Role.read_role)
      assert invitation.same_action?(action: "pull")
    end

    test "returns false if given an invalid permission value" do
      invitation = create(:repository_invitation, repository: @org_repo, role: Role.write_role)
      refute invitation.same_action?(action: "not-it")
    end

    test "works with system role" do
      # permissions: 4 => maintain
      invitation = create(:repository_invitation, repository: @org_repo, permissions: 4)
      assert invitation.same_action?(action: "maintain")
    end

    test "returns true if action corresponds to the invitation's role" do
      custom_role = create_custom_role(owner: @organization, base_role: :write)
      invitation = create(:repository_invitation, repository: @org_repo, role: custom_role)
      assert invitation.same_action?(action: custom_role.name)
    end

    test "returns false if comparing with the name of another custom role" do
      custom_role1 = create_custom_role(owner: @organization, base_role: :write)
      custom_role2 = create_custom_role(owner: @organization, base_role: :write)
      invitation = create(:repository_invitation, repository: @org_repo, role: custom_role1)
      refute invitation.same_action?(action: custom_role2.name)
    end

    test "returns false if comparing a custom role to its base role" do
      custom_role = create_custom_role(owner: @organization, base_role: :write)
      invitation = create(:repository_invitation, repository: @org_repo, role: custom_role)
      refute invitation.same_action?(action: custom_role.base_role.name)
    end
  end

  context "#failed_reason" do
    test "returns nil if the invitation has not expired" do
      assert_nil @invitation.failed_reason
    end

    test "returns correct reason if invitation has expired" do
      @invitation.update! created_at: (GitHub.invitation_expiry_period + 5).days.ago
      assert_equal "expired", @invitation.failed_reason
    end
  end

  context "#failed_reason_description" do
    test "returns nil if the invitation has not expired" do
      assert_nil @invitation.failed_reason_description
    end

    test "returns correct failure description if invitation has expired" do
      @invitation.update! created_at: (GitHub.invitation_expiry_period + 5).days.ago
      assert_equal \
        "Invitation expired. User did not accept this invite for #{GitHub.invitation_expiry_period} days",
        @invitation.failed_reason_description
    end
  end

  context "for workspace repositories" do
    test "they don't expire while the invitee is a collaborator on the advisory" do
      advisory = create(:draft_repository_advisory, :with_workspace, repository: @public_repo)
      advisory.add_collaborator(@invitee)
      invitation = RepositoryInvitation.find_by!(invitee_id: @invitee.id, repository_id: advisory.workspace_repository.id)
      invitation.update(created_at: (GitHub.invitation_expiry_period + 1).days.ago)

      refute invitation.invite_expired?
      advisory.send(:grant, @invitee, :read)
      assert invitation.invite_expired?
    end
  end if GitHub.repository_advisories_enabled?
end

class RepositoryInvitationInviteToRepoByEmailTest < GitHub::TestCase
  fixtures do
    @invitee = create(:user)
    @inviter = create(:user)
    @repo = create(:repository, owner: @inviter)
    @org = create(:organization, admin: @inviter, plan: "business_plus", seats: 5)
    @org_member = create(:user)
    @org.add_member(@org_member)

    @email = "fawazfarid@github.com"
  end

  setup do
    deliveries.clear
  end

  def deliveries
    ActionMailer::Base.deliveries
  end

  test "creates an invitation with invitee when existing user email is verified", skip_enterprise: true do
    @invitee.emails.last.verify!
    result = RepositoryInvitation.invite_to_repo_by_email(@invitee.email, @inviter, @repo)
    assert_equal result[:invitation].invitee, @invitee
  end

  test "creates an invitation with a token and email if user email is unverified" do
    alternative_email = "fawazfarid@alternative.com"
    create(:user_email, user: @invitee, email: alternative_email)
    result = RepositoryInvitation.invite_to_repo_by_email(@invitee.emails.last, @inviter, @repo)

    assert @invitee.emails.last.unverified?
    assert result[:invitation].email?
    assert_predicate result[:invitation].hashed_token, :present?
    assert_equal result[:invitation].email, alternative_email
  end

  test "creates an invitation with a token and email if email is a non-existing user" do
    result = RepositoryInvitation.invite_to_repo_by_email(@email, @inviter, @repo)
    assert_predicate result[:invitation].hashed_token, :present?
    assert_equal result[:invitation].email, @email
  end

  test "queues invited to repo by email email if email is a non-existing user" do
    assert_performed_with job: ApplicationDeliveryJob, queue: ApplicationDeliveryJob.queue_name do
      RepositoryInvitation.invite_to_repo_by_email(@email, @inviter, @repo)
    end

    email_delivered = deliveries.shift
    assert_equal "#{@inviter} invited you to #{@repo.name_with_owner}", email_delivered.subject
  end

  test "does not create a new invitation if email invitation exists" do
    create(:repository_invitation,
      inviter: @inviter,
      invitee: nil,
      email: @email,
      repository: @repo,
      permissions: 1,
    )
    assert_no_changes -> { RepositoryInvitation.count } do
      RepositoryInvitation.invite_to_repo_by_email(@email, @inviter, @repo)
    end
  end

  test "create a new invitation if inviter is org admin and org does not allow outside collaborator by members" do
    @org.disallow_members_can_invite_outside_collaborators(actor: @org, force: true)
    refute @org.members_can_invite_outside_collaborators?
    private_repo = create(:private_repository, owner: @org)

    assert_changes -> { RepositoryInvitation.count } do
      RepositoryInvitation.invite_to_repo_by_email(@email, @inviter, private_repo)
    end
  end

  test "does not create a new invitation if inviter is org member and org does not allow outside collaborator by members" do
    @org.disallow_members_can_invite_outside_collaborators(actor: @org, force: true)
    refute @org.members_can_invite_outside_collaborators?
    private_repo = create(:private_repository, owner: @org)

    assert_no_changes -> { RepositoryInvitation.count } do
      RepositoryInvitation.invite_to_repo_by_email(@email, @org_member, private_repo)
    end
  end

  test "creates a new invitation if inviter is org member and org allows outside collaborator invite by members" do
    private_repo = create(:private_repository, owner: @org)

    assert_changes -> { RepositoryInvitation.count } do
      RepositoryInvitation.invite_to_repo_by_email(@email, @org_member, private_repo)
    end
  end

  test "sends a VSS status message if the email matches any bundled licensing assignments and the repository is owned by a volume license_business", skip_enterprise: true do
    private_repository = create(:private_repository, owner: @org)
    @org.business = create(:business, :volume_licensed)
    create(:licensing_bundled_license_assignment, business_id: @org.business.id, email: @email)
    create(:licensing_bundled_license_assignment, business_id: @org.business.id, email: @email)

    assert_enqueued_jobs 2, only: Licensing::SendVssStatusMessageJob do
      RepositoryInvitation.invite_to_repo_by_email(@email, @inviter, private_repository)
    end
  end

  context ".can_invite_with_email?" do
    test "when the owner is an organization and the repo is private and there are no seats available" do
      org = create(:organization, plan: "business_plus", seats: 5)
      repo = create(:private_repository, owner: org)
      5.times { org.add_member(create(:user)) }

      refute RepositoryInvitation.can_invite_with_email?(repo, org.admins.first)
      assert_includes repo.errors[:seat_limit], "You must purchase at least one more seat to invite this user as a collaborator."
    end

    test "when the owner is an organization, repo is private, there are no seats available, and inviter is a collaborator" do
      org = create(:organization, plan: "business_plus", seats: 5)
      repo = create(:private_repository, owner: org)
      collab = create(:user)
      repo.add_member(collab, action: :admin)
      5.times { org.add_member(create(:user)) }

      refute RepositoryInvitation.can_invite_with_email?(repo, collab)
      assert_includes repo.errors[:base], "Unable to invite user as a collaborator."
    end

    test "error when inviter is org member of org that doesn't allow outside collaborators invite by members" do
      org = create(:organization, plan: "business_plus", seats: 5)
      org.disallow_members_can_invite_outside_collaborators(actor: org, force: true)
      refute org.members_can_invite_outside_collaborators?

      member = create(:user)
      org.add_member(member)
      repo = create(:private_repository, owner: org)

      refute RepositoryInvitation.can_invite_with_email?(repo, member)
      verb = GitHub.repo_invites_enabled? ? "invite" : "add"
      collaborators_word = org.business&.emu_repository_collaborators_enabled? ? "repository collaborators" : GitHub.outside_collaborators_flavor
      assert_includes repo.errors[:base], "Only organization owners can #{verb} #{collaborators_word}"
    end

    test "return true when inviter is org member of org that does allow outside collaborators invite by members" do
      org = create(:organization, plan: "business_plus", seats: 5)

      member = create(:user)
      org.add_member(member)
      repo = create(:private_repository, owner: org)

      assert RepositoryInvitation.can_invite_with_email?(repo, member)
      assert_empty repo.errors[:base]
    end
  end
end
