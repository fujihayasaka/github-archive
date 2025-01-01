# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryCanAddUserTest < GitHub::TestCase
  fixtures do
    @adder = create(:user)
    @addee = create(:user)
  end

  test "returns true when the owner is a user and the repository is public" do
    trade_restricted_repository = create(:repository, owner: @adder)
    @adder.trade_controls_restriction.full!

    assert trade_restricted_repository.can_add_user?(@addee, @adder)
  end

  test "returns false when the owner is a user and the repository is private" do
    trade_restricted_repository = create(:private_repository, owner: @adder)
    @adder.trade_controls_restriction.full!

    refute trade_restricted_repository.can_add_user?(@addee, @adder)
  end

  test "returns true when the owner is a partially trade restricted organization and repository is public" do
    trade_restricted_org = create(:organization)
    trade_restricted_repository = create(:repository, owner: trade_restricted_org)
    trade_restricted_org.trade_controls_restriction.partial!
    trade_restricted_org.add_member(@adder)
    trade_restricted_org.update_member(@adder, action: :admin)

    assert trade_restricted_repository.can_add_user?(@addee, @adder)
  end

  test "returns false when the owner is a partially trade restricted organization and repository is private" do
    trade_restricted_org = create(:organization)
    trade_restricted_repository = create(:private_repository, owner: trade_restricted_org)
    trade_restricted_org.trade_controls_restriction.full!
    trade_restricted_org.add_member(@adder)
    trade_restricted_org.update_member(@adder, action: :admin)

    refute trade_restricted_repository.can_add_user?(@addee, @adder)
  end

  test "returns false when the owner is a fully trade restricted organization and repository is public" do
    trade_restricted_org = create(:organization)
    trade_restricted_repository = create(:repository, owner: trade_restricted_org)
    trade_restricted_org.trade_controls_restriction.full!
    trade_restricted_org.add_member(@adder)
    trade_restricted_org.update_member(@adder, action: :admin)

    refute trade_restricted_repository.can_add_user?(@addee, @adder)
  end

  test "returns false when the owner is a fully trade restricted organization and repository is private" do
    trade_restricted_org = create(:organization)
    trade_restricted_repository = create(:private_repository, owner: trade_restricted_org)
    trade_restricted_org.trade_controls_restriction.full!
    trade_restricted_org.add_member(@adder)
    trade_restricted_org.update_member(@adder, action: :admin)

    refute trade_restricted_repository.can_add_user?(@addee, @adder)
  end

  test "returns false when repo is a private fork and the root owner is trade restricted organization" do
    trade_restricted_org = create(:organization)
    trade_restricted_org.allow_private_repository_forking(actor: @adder)
    trade_restricted_repository = create(:private_repository, owner: trade_restricted_org)
    trade_restricted_org.add_member(@adder)
    trade_restricted_org.update_member(@adder, action: :admin)
    forked_repo = create(:fork_repository, forker: @adder, fork_repo: trade_restricted_repository)
    trade_restricted_org.trade_controls_restriction.full!
    forked_repo.reload

    refute forked_repo.can_add_user?(@addee, @adder)
  end

  test "returns true when repo is a private fork and the root owner is trade restricted organization" do
    trade_restricted_org = create(:organization)
    trade_restricted_org.allow_private_repository_forking(actor: @adder)
    trade_restricted_repository = create(:repository, owner: trade_restricted_org)
    trade_restricted_org.add_member(@adder)
    trade_restricted_org.update_member(@adder, action: :admin)
    forked_repo = create(:fork_repository, forker: @adder, fork_repo: trade_restricted_repository)
    trade_restricted_org.trade_controls_restriction.full!

    assert forked_repo.can_add_user?(@addee, @adder)
  end

  test "when the addee is trade restricted and the repository is private" do
    @adder.update(plan: GitHub::Plan.pro)
    repo = create(:private_repository, owner: @adder)
    @addee.trade_controls_restriction.full!

    refute repo.can_add_user?(@addee, @adder)
  end

  test "when the addee is trade restricted and the repository is public" do
    repo = create(:repository, owner: @adder)
    @addee.trade_controls_restriction.full!

    assert repo.can_add_user?(@addee, @adder)
  end

  test "returns false when the addee is not 2FA compliant, true if no check_2fa" do
    no_2fa_user = create(:user)
    totp_user = create(:user)
    owner = create(:user, :two_factor_enabled)
    org = create(:organization, admin: owner)
    repo = create(:repository, owner: org)
    org.enable_two_factor_required(actor: owner)
    org.add_disallowed_two_factor_method(method: :totp, actor: owner)

    refute repo.can_add_user?(no_2fa_user, owner)
    refute repo.can_add_user?(totp_user, owner)
    assert repo.can_add_user?(no_2fa_user, owner, check_2fa: false)
    assert repo.can_add_user?(totp_user, owner, check_2fa: false)
  end

  test "when the adder is the owner" do
    repo = create(:repository, owner: @adder)
    assert repo.can_add_user?(@addee, @adder)
  end

  context "when the adder is not the repo owner" do
    test "and they are an org admin" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      org.add_member @adder, action: :admin
      assert repo.can_add_user?(@addee, @adder)
    end
    test "and they are an not an org admin" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      org.add_member @adder
      refute repo.can_add_user?(@addee, @adder)
      assert_includes repo.errors[:base], "You cannot administer this repository"
    end
  end

  context "when the addee has an outstanding invitation", skip_enterprise: true do
    test "without the :already_invited arg" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      org.add_member @adder, action: :admin
      RepositoryInvitation.invite_to_repo(@addee, @adder, repo)
      refute repo.can_add_user?(@addee, @adder)
      assert_includes repo.errors[:base], "User has already been invited"
    end
    test "with the :already_invited arg set to false" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      org.add_member @adder, action: :admin
      RepositoryInvitation.invite_to_repo(@addee, @adder, repo)
      refute repo.can_add_user?(@addee, @adder, already_invited: false)
      assert_includes repo.errors[:base], "User has already been invited"
    end
    test "with the :already_invited arg set to true" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      org.add_member @adder, action: :admin
      RepositoryInvitation.invite_to_repo(@addee, @adder, repo)
      assert repo.can_add_user?(@addee, @adder, already_invited: true)
    end
  end

  test "when the adder has been blocked" do
    blocked_adder = create(:user)
    blocker_addee = create(:user)
    blocker_addee.block(blocked_adder)
    repo = create(:repository, owner: blocked_adder)
    refute repo.can_add_user?(blocker_addee, blocked_adder)
    assert_includes repo.errors[:base], "User has blocked you"
  end

  if GitHub.spamminess_check_enabled?
    test "when the adder is spammy" do
      spammy_adder = create(:user, spammy: true)
      addee = create(:user)
      repo = create(:repository, owner: spammy_adder)

      refute repo.can_add_user?(addee, spammy_adder)
      assert_includes repo.errors[:base], "User could not be added"
    end
  end

  context "when the addee has been blocked" do
    test "they cannot be added to a repo by an org admin" do
      owner = create(:user, login: "monalisa")
      admin = create(:user, login: "nimda")
      blocked_user = create(:user, login: "hacker")
      user = create(:user, login: "resu")

      org = create(:organization, admin: owner, creator: owner)
      org.add_member(admin, action: :admin)

      # note - repo is owned by org
      repo = create(:repository, owner: org)

      # should be able to add regular user
      assert repo.can_add_user?(user, org)
      assert repo.can_add_user?(user, owner)

      owner.block(blocked_user)

      # should not be able to add blocked user
      refute repo.can_add_user?(blocked_user, org)
      assert_includes repo.errors[:base], "User is blocked"
      refute repo.can_add_user?(blocked_user, owner)
      assert_includes repo.errors[:base], "User is blocked"
      refute repo.can_add_user?(blocked_user, admin)
      assert_includes repo.errors[:base], "User is blocked"
    end

    test "they cannot be added to a repo by an outside collaborator admin" do
      owner = create(:user, login: "monalisa")
      outside_collaborator_admin = create(:user, login: "outside-collaborator-admin")
      blocked_user = create(:user, login: "hacker")
      user = create(:user, login: "resu")

      org = create(:organization, admin: owner, creator: owner)

      # note - repo is owned by org
      repo = create(:repository, owner: org)

      # outside collaborator is admin on the repo
      repo.add_member(outside_collaborator_admin, action: :admin)

      owner.block(blocked_user)

      assert repo.can_add_user?(user, outside_collaborator_admin)
      refute repo.can_add_user?(blocked_user, outside_collaborator_admin)
      assert_includes repo.errors[:base], "User is blocked"
    end
  end

  test "when the addee has been suspended" do
    repo = create(:repository, owner: @adder)
    @addee.suspend("reasons")
    refute repo.can_add_user?(@addee, @adder)
    assert_includes repo.errors[:base], "User is suspended"
  end

  test "when the addee has been suspended during an import migration" do
    repo = create(:repository, owner: @adder)
    @addee.suspend("reasons")
    GitHub.importing do
      assert repo.can_add_user?(@addee, @adder)
    end
  end

  test "when the addee is already a member" do
    repo = create(:repository, owner: @adder)
    repo.add_member(@addee)
    refute repo.can_add_user?(@addee, @adder)
    assert_includes repo.errors[:base], "User is already a collaborator"
  end

  test "when the addee is the owner" do
    repo = create(:repository, owner: @adder)
    refute repo.can_add_user?(@adder, @adder)
    assert_includes repo.errors[:base], "Repository owner cannot be a collaborator"
  end

  test "when the addee is an org" do
    repo = create(:repository, owner: @adder)
    org = create(:organization)
    refute repo.can_add_user?(org, @adder)
    assert_includes repo.errors[:base], "Only users can be collaborators"
  end

  test "returns false when the addee is a user being transformed into an org" do
    repo = create(:repository, owner: @adder)
    Organization.start_transform(@addee)
    assert Organization.transforming?(@addee)
    refute repo.can_add_user?(@addee, @adder)
    assert_includes repo.errors[:base], "Users being transformed into organizations cannot be added as collaborators"
  end

  test "when the owner is a user and the action flag is not :write" do
    repo = create(:repository, owner: @adder)
    refute repo.can_add_user?(@addee, @adder, action: :admin)
    assert_includes repo.errors[:base], "You can only give write access to user-owned repositories"
  end

  test "when the owner is an organization and the repo is private and there are no seats available" do
    org = create(:organization, plan: "business", seats: 5)
    repo = create(:private_repository, owner: org)
    org.add_member @adder, action: :admin
    4.times { org.add_member(create(:user)) }
    refute org.has_seat_for?(@addee)
    refute repo.can_add_user?(@addee, @adder)
    assert_includes repo.errors[:seat_limit], "You must purchase at least one more seat to add this user as a collaborator."
  end

  test "when the owner is an organization and the repo is private and there are no seats available for the pending cycle" do
    org = create(:organization, plan: "business", seats: 7)
    repo = create(:private_repository, owner: org)
    org.add_member @adder, action: :admin
    4.times { org.add_member(create(:user)) }

    create :billing_pending_plan_change,
      user: org,
      actor: org,
      seats: 5

    refute org.has_seat_for?(@addee, pending_cycle: true)
    refute repo.can_add_user?(@addee, @adder)
    assert_includes repo.errors[:base], "You must cancel your pending seat downgrade to add this user as a collaborator."
  end

  context "when the adder is a bot installation" do
    test "and repo is writable by the installation" do
      repo = create(:repository, owner: @adder)
      installation = make_integration_installation(name: "Bot", repository: repo, permissions: {
        "administration" => :write,
      })

      assert repo.can_add_user?(@addee, installation.bot)
    end

    test "and repo is not writable by the installation" do
      repo = create(:repository, owner: @adder)

      installation = make_integration_installation(name: "Bot", repository: repo, permissions: {
        "administration" => :read,
      })

      refute repo.can_add_user?(@addee, installation.bot)
    end
  end

  context "when the repository is an advisory workspace" do
    context "when the adder is not the repo owner" do
      test "and they are an org admin" do
        org = create(:organization)
        repo = create(:repository, owner: org)
        advisory = create(:repository_advisory, :with_workspace, { repository: repo })

        org.add_member @adder, action: :admin
        assert advisory.workspace_repository.can_add_user?(@addee, @adder)
      end

      test "and they are a SecurityManger" do
        org = create(:organization)
        repo = create(:repository, owner: org)
        advisory = create(:repository_advisory, :with_workspace, { repository: repo })

        security_team = create(:security_manager_team, organization: org)
        security_team.add_member(@adder)
        assert advisory.workspace_repository.can_add_user?(@addee, @adder)
      end

      test "and they are a VulnerabilityReporter" do
        org = create(:organization)
        repo = create(:repository, owner: org)
        advisory = create(:pending_pvd_repo_advisory, :with_workspace, { repository: repo, author: @adder })

        assert advisory.workspace_repository.can_add_user?(@addee, @adder)
      end

      test "and they are a regular advisory collaborator" do
        org = create(:organization)
        repo = create(:repository, owner: org)
        advisory = create(:repository_advisory, :with_workspace, { repository: repo })

        advisory.add_collaborator @adder
        refute advisory.workspace_repository.can_add_user?(@addee, @adder)
        assert_includes advisory.workspace_repository.errors[:base], "You cannot manage this advisory workspace"
      end
    end

    test "when the owner is an organization and the repo is private and there are no seats available" do
      org = create(:organization, plan: "business", seats: 5, admin: @adder)
      repo = create(:private_repository, owner: org)
      advisory = create(:repository_advisory, :with_workspace, { repository: repo })
      4.times { org.add_member(create(:user)) }

      assert_equal false, org.has_seat_for?(@addee)
      assert_equal true, advisory.workspace_repository.can_add_user?(@addee, @adder)
    end

    test "when the owner is an organization and the repo is private and there are no seats available for the pending cycle" do
      org = create(:organization, plan: "business", seats: 7, admin: @adder)
      repo = create(:private_repository, owner: org)
      advisory = create(:repository_advisory, :with_workspace, { repository: repo })
      4.times { org.add_member(create(:user)) }
      create(:billing_pending_plan_change, user: org, actor: org, seats: 5)

      assert_equal false, org.has_seat_for?(@addee, pending_cycle: true)
      assert_equal true, advisory.workspace_repository.can_add_user?(@addee, @adder)
    end
  end

  unless GitHub.single_business_environment?
    test "when the owner is an organization belonging to a business and the repo is private" do
      org = create(:organization, admins: [@adder], public_members: [create(:user)])
      repo = create(:private_repository, owner: org)
      bus = create(:business, seats: 2, organizations: [org])
      org.reload

      refute repo.can_add_user?(@addee, @adder)
      assert_includes repo.errors[:seat_limit], "You must purchase at least one more seat to add this user as a collaborator."

      create(:enterprise_agreement, business: bus, seats: 1)

      assert repo.reload.can_add_user?(@addee, @adder)
    end
  end
end
