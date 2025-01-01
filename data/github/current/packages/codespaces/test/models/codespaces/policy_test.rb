# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesPolicyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    disable_feature_flag(:codespaces_billing_free)
    @user_public_repo = create(:repository, owner: @user)
    @user_archived_repo = create(:repository, owner: @user, maintained: false)
    @user_private_repo = create(:private_repository, owner: @user)

    @user_org = create(:organization)
    @user_org.add_member(@user)
    @user_with_org_access = create(:user)
    @user_org.add_member(@user_with_org_access)

    # Set up a user with access to an org-owned private repo
    @admin_user = create(:user)
    @another_user_with_org_access = create(:user)
    @non_codespace_org_user = create(:user)
    @org_codespaces_enabled = create(:codespaces_organization, admin: @admin_user)
    @org_codespaces_enabled.allow_private_repository_forking(actor: @admin_user)
    @org_codespaces_enabled.add_member(@user_with_org_access)
    @org_codespaces_enabled.add_member(@another_user_with_org_access)
    @user_with_org_but_not_org_creator_access = create(:user)
    @org_codespaces_enabled.add_member(@user_with_org_but_not_org_creator_access)
    Codespaces::OrgPolicy.grant_billing_permission!(@user_with_org_access, @org_codespaces_enabled)
    Codespaces::OrgPolicy.grant_billing_permission!(@another_user_with_org_access, @org_codespaces_enabled)

    @org_codespaces_enabled_private_repo = create(:private_repository, owner: @org_codespaces_enabled)
    @org_codespaces_enabled_public_repo = create(:public_repository, owner: @org_codespaces_enabled)

    @collaborator_private_repo = create(:private_repository)
    @collaborator_private_repo.add_member(@user)

    @rando_public_repo = create(:repository)
    @rando_private_repo = create(:private_repository)

    @rando_org_public_repo = create(:org_owned_repository)
    @rando_org_private_repo = create(:org_owned_private_repository)

    @user_org_member = create(:user, login: "foo")

    @org_on_plan = create(:codespaces_organization)
    @org_on_plan.add_member(@user_org_member)

    # Set up fork from an org private repo accessible to two users with org access,
    # for testing one's ability to use codespaces on another's fork of the org repo.
    @shared_org_private_repo = create(:private_repository, owner: @org_codespaces_enabled, from_example: :pull_request_source)
    @shared_org_private_repo.add_member(@user_with_org_access)
    @shared_org_private_repo.add_member(@another_user_with_org_access)

    @private_org_fork = create(:fork_repository, forker: @user_with_org_access, fork_repo: @shared_org_private_repo, from_example: :pull_request_fork)
    metadata = { message: "foo", committer: @private_org_fork.owner }
    @private_org_fork.heads.find("master").append_commit(metadata, @private_org_fork.owner)
    @private_org_fork_pr = PullRequest.create_for(
        @shared_org_private_repo,
        title: "PR from fork into base",
        body: "fork me",
        head: "#{@user_with_org_access.name}:master",
        base: "master",
        user: @user_with_org_access
    )

    @creator_role = Role.codespace_org_creator_role

    # Set up source/fork for forking tests
    @forker = create(:user, login: "forker")
    @source = create(:repository, owner: @user, from_example: :pull_request_source)
    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :pull_request_fork)

    @pull_request_from_fork = PullRequest.create_for(
        @source,
        title: "PR from fork into base",
        body: "fork me",
        head: "#{@forker.name}:master-plus-one-commit",
        base: "master",
        user: @forker
    )

    # Set up org with a legacy restricted plan
    # List of other legacy plans can be found in config/plans.yml
    @user_org_on_restricted_plan_member = create(:user, login: "gold")
    @org_on_restricted_plan = create(:organization, plan: GitHub::Plan.gold, admin: @admin_user)
    @org_on_restricted_plan.add_member(@user_org_on_restricted_plan_member)
    @user_org_on_restricted_plan_public_repo = create(:repository, owner: @org_on_restricted_plan)
    @user_org_on_restricted_plan_private_repo = create(:private_repository, owner: @org_on_restricted_plan)

    @org_codespace = create(:codespace, owner: @user_with_org_access, repository: @org_codespaces_enabled_private_repo)
    personal_repo = create(:private_repository, owner: @user_with_org_access)
    @personal_codespace = create(:codespace, owner: @user_with_org_access, repository: personal_repo)

    @policy_group_org = create(:policy_group, owner: @user_org, name: "all repos")
    @policy_group_org_2 = create(:policy_group, owner: @user_org, name: "all repos: 2")
    create(:policy_group_membership, policy_group: @policy_group_org, target: @user_org)
    create(:policy_group_membership, policy_group: @policy_group_org_2, target: @user_org)
  end

  context "#entitlements_feature_enabled?" do
    test "disabled when actor is an org" do

      org = create :organization, plan: GitHub::Plan::FREE
      refute Codespaces::Policy.entitlements_feature_enabled?(org)
    end

    test "false when actor is nil" do
      refute Codespaces::Policy.entitlements_feature_enabled?(nil)
    end

    test "disabled when user is not on a supported plan" do
      user = create :user, plan: "gold"
      refute Codespaces::Policy.entitlements_feature_enabled?(user)
    end

    test "enabled for user with an entitlements supported plan" do
      users = [
        create(:user, plan: GitHub::Plan::FREE),
        create(:user, plan: GitHub::Plan::FREE_WITH_ADDONS),
        create(:user, plan: GitHub::Plan::PRO)
      ]
      users.each do |user|
        assert Codespaces::Policy.entitlements_feature_enabled?(user), "expected #{user.plan} to be enabled"
      end
    end

    test "false when actor plan is nil" do
      user = create(:user,  plan: "fake_plan")
      refute user.plan
      refute Codespaces::Policy.entitlements_feature_enabled?(user)
    end
  end

  context "granting and revoking access to private org codespaces" do
    test "granting access creates proper records" do
      Codespaces::OrgPolicy.grant_billing_permission!(@user_org_member, @org_on_plan)
      assert UserRole.find_by(actor: @user_org_member, target_id: @org_on_plan.id, target_type: "Organization", role: @creator_role)
    end

    test "revoking access removes proper records" do
      Codespaces::OrgPolicy.grant_billing_permission!(@user_org_member, @org_on_plan)
      Codespaces::OrgPolicy.revoke_billing_permission!(@user_org_member, @org_on_plan)
      refute UserRole.find_by(actor: @user_org_member, target_id: @org_on_plan.id, target_type: "Organization", role: @creator_role)
    end

    test "granting a role twice does not produce an error" do
      Codespaces::OrgPolicy.grant_billing_permission!(@user_org_member, @org_on_plan)
      assert_nothing_raised do
        Codespaces::OrgPolicy.grant_billing_permission!(@user_org_member, @org_on_plan)
      end
    end

    test "revoking a role that doesn't exists does not produce an error" do
      Codespaces::OrgPolicy.revoke_billing_permission!(@user_org_member, @org_on_plan)
    end
  end

  context "#codespaces_limit" do
    test "returns codespaces_per_user_sales_demo_limit for sales demo users" do
      sales_demo_user = create(:user)
      enable_feature_flag(:codespaces_per_user_sales_demo_limit, sales_demo_user)

      assert Codespaces::Policy.codespaces_limit(sales_demo_user), GitHub.codespaces_per_user_sales_demo_limit
    end

    test "returns codespaces_automated_testing_limit for testing users" do
      sales_demo_user = create(:user)
      enable_feature_flag(:codespaces_automated_testing, sales_demo_user)
      disable_feature_flag(:codespaces_per_user_sales_demo_limit, sales_demo_user)

      assert Codespaces::Policy.codespaces_limit(sales_demo_user), GitHub.codespaces_automated_testing_limit
    end

    test "consults user tier" do
      codespaces_test_user = create(:user)
      disable_feature_flag(:codespaces_developer, codespaces_test_user)
      disable_feature_flag(:codespaces_per_user_sales_demo_limit, codespaces_test_user)
      disable_feature_flag(:codespaces_automated_testing, codespaces_test_user)

      expected_tier = TrustTiers::Tier::NEUTRAL
      Codespaces::Tier.expects(:for_user).returns(TrustTiers::TierResult.new(expected_tier, "reason"))
      assert Codespaces::Policy.codespaces_limit(codespaces_test_user), 5
    end

    test "returns codespaces_creation_limit when allowed_maximum_creations policy constraint is set buf FF is disabled" do
      create(:policy_constraint, policy_group: @policy_group_org_2, maximum_value: 30, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_CREATIONS)
      result = Codespaces::Policy.codespaces_limit(@user)
      assert result, 30
    end
  end

  context "#can_receive_secrets?" do
    test "returns true if repository is pushable by owner" do
      disable_feature_flag(:disable_codespaces_secrets)
      assert Codespaces::Policy.can_receive_secrets?(@personal_codespace)
    end

    test "returns false if repository is not pushable by owner" do
      public_repo = create(:repository)
      codespace = create(:codespace, :unpushable, owner: @user_with_org_access, repository: public_repo)
      refute Codespaces::Policy.can_receive_secrets?(codespace)
    end

    test "returns false if secrets killswitch is enabled" do
      enable_feature_flag(:disable_codespaces_secrets)
      refute Codespaces::Policy.can_receive_secrets?(@personal_codespace)
    end
  end

  context "#codespace_user_spammy?", skip_enterprise: true do
    test "codespaces owned by spammy users is true" do
      user = create(:user)
      codespace = create(:codespace, owner: user)

      user.mark_as_spammy

      assert Codespaces::Policy.codespace_user_spammy?(codespace)
    end

    test "codespaces on a spammy user's repositories is true" do
      user = create(:user)
      codespace = create(:codespace, owner: user)

      user.mark_as_spammy

      assert Codespaces::Policy.codespace_user_spammy?(codespace)
    end

    test "codespaces on a spammy org's repository is true" do
      repo = create(:org_owned_repository)
      codespace = create(:codespace, repository: repo)

      assert codespace.repository.owner.is_a?(Organization)
      codespace.repository.owner.mark_as_spammy

      assert Codespaces::Policy.codespace_user_spammy?(codespace)
    end
  end
end unless GitHub.enterprise?
