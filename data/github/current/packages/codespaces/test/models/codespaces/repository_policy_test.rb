# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesRepositoryPolicyTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @user = create(:user)
    @user_public_repo = create(:repository, owner: @user)
    @user_archived_repo = create(:repository, owner: @user, maintained: false)
    @user_private_repo = create(:private_repository, owner: @user)

    @user_org = create(:organization)
    @user_org_public_repo = create(:repository, owner: @user_org)
    @user_org_private_repo = create(:private_repository, owner: @user_org)
    @user_org.add_member(@user)
    @user_with_org_access = create(:user)
    @user_org.add_member(@user_with_org_access)

    # Set up a user with access to an org-owned private repo
    @admin_user = create(:user)
    @another_user_with_org_access = create(:user)
    @non_codespace_org_user = create(:user)
    @org_codespaces_enabled = create(:codespaces_enterprise_organization, admin: @admin_user)
    @org_codespaces_enabled.allow_private_repository_forking(actor: @admin_user, policy: Configurable::AllowPrivateRepositoryForking::EVERYWHERE)
    @org_codespaces_enabled.add_member(@user_with_org_access)
    @org_codespaces_enabled.add_member(@another_user_with_org_access)
    @user_with_org_but_not_org_creator_access = create(:user)
    @org_codespaces_enabled.add_member(@user_with_org_but_not_org_creator_access)
    Codespaces::OrgPolicy.grant_billing_permission!(@user_with_org_access, @org_codespaces_enabled)
    Codespaces::OrgPolicy.grant_billing_permission!(@another_user_with_org_access, @org_codespaces_enabled)

    @org_codespaces_enabled_private_repo = create(:private_repository, owner: @org_codespaces_enabled)

    @rando_public_repo = create(:repository)
    @rando_private_repo = create(:private_repository)

    @rando_org_public_repo = create(:org_owned_repository)
    @rando_org_private_repo = create(:org_owned_private_repository)

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

    # Set up org with a legacy restricted plan
    # List of other legacy plans can be found in config/plans.yml
    @user_org_on_restricted_plan_member = create(:user, login: "gold")
    @org_on_restricted_plan = create(:organization, plan: GitHub::Plan.gold, admin: @admin_user)
    @org_on_restricted_plan.add_member(@user_org_on_restricted_plan_member)

    @org_codespace = create(:codespace, owner: @user_with_org_access, repository: @org_codespaces_enabled_private_repo)
    disable_feature_flag(:codespaces_billing_free)
  end

  context "#can_attempt_create?", skip_enterprise: true do
    test "allows all public repositories" do
      assert Codespaces::RepositoryPolicy.async_with_prefill(@user, @user_public_repo).sync.can_attempt_create?
      assert Codespaces::RepositoryPolicy.async_with_prefill(@user, @rando_public_repo).sync.can_attempt_create?
      assert Codespaces::RepositoryPolicy.async_with_prefill(@user, @user_org_public_repo).sync.can_attempt_create?
      assert Codespaces::RepositoryPolicy.async_with_prefill(@user, @rando_org_public_repo).sync.can_attempt_create?
    end

    test "allows private repositories the user owns" do
      assert Codespaces::RepositoryPolicy.async_with_prefill(@user, @user_private_repo).sync.can_attempt_create?
    end

    test "disallows org-owned private repositories by default" do
      refute Codespaces::RepositoryPolicy.async_with_prefill(@user, @user_org_private_repo).sync.can_attempt_create?
    end

    test "allows org-owned private repositories when the user has access to it and codespaces are enabled for the org" do
      assert Codespaces::RepositoryPolicy.async_with_prefill(
        @user_with_org_access,
        @org_codespaces_enabled_private_repo,
      ).sync.can_attempt_create?
    end

    test "disallows org-owned private repositories when the user has access to it and codespaces are enabled for the org but IP allow list is enabled on the org" do
      # Only orgs support IP allow lists so we need to use an org-owned repository.
      assert Codespaces::RepositoryPolicy.async_with_prefill(
        @user_with_org_access,
        @org_codespaces_enabled_private_repo,
      ).sync.can_attempt_create?

      # Enable IP allow list
      create :ip_allowlist_entry, :org, owner: @org_codespaces_enabled
      @org_codespaces_enabled.enable_ip_allowlist actor: @admin_user
      assert @org_codespaces_enabled.ip_allowlist_enabled?

      refute Codespaces::RepositoryPolicy.async_with_prefill(
        @user_with_org_access,
        @org_codespaces_enabled_private_repo.reload,
      ).sync.can_attempt_create?
    end

    test "disallows org-owned private repositories when the user has access to it and codespaces are enabled for the org but IP allow list is enabled on the business" do
      # Only orgs support IP allow lists so we need to use an org-owned repository.
      assert Codespaces::RepositoryPolicy.async_with_prefill(
        @user_with_org_access,
        @org_codespaces_enabled_private_repo,
      ).sync.can_attempt_create?

      # Enable IP allow list
      create :ip_allowlist_entry, :business, owner: @org_codespaces_enabled.business
      @org_codespaces_enabled.business.enable_ip_allowlist actor: @admin_user
      assert @org_codespaces_enabled.ip_allowlist_enabled_on_business?

      refute Codespaces::RepositoryPolicy.async_with_prefill(
        @user_with_org_access,
        @org_codespaces_enabled_private_repo.reload,
      ).sync.can_attempt_create?
    end

    test "allows collaborator-owned private repositories they can push to" do
      collaborator_private_repo = create(:private_repository)
      collaborator_private_repo.add_member(@user)

      assert Codespaces::RepositoryPolicy.async_with_prefill(@user, collaborator_private_repo).sync.can_attempt_create?
    end

    test "disallows private repositories they can't see" do
      rando_org_private_repo = create(:org_owned_private_repository)

      refute Codespaces::RepositoryPolicy.async_with_prefill(@user, @rando_private_repo).sync.can_attempt_create?
      refute Codespaces::RepositoryPolicy.async_with_prefill(@user, rando_org_private_repo).sync.can_attempt_create?
    end

    test "disallows archived repositories" do
      refute Codespaces::RepositoryPolicy.async_with_prefill(@user, @user_archived_repo).sync.can_attempt_create?
    end

    test "allows collab-enabled forks of an org-owned private repository" do
      @private_org_fork_pr.fork_collab_allowed!
      assert Codespaces::RepositoryPolicy.async_with_prefill(@another_user_with_org_access, @private_org_fork, pull_request: @private_org_fork_pr).sync.can_attempt_create?
    end

    test "allows collab-disabled forks of an org-owned private repository" do
      assert Codespaces::RepositoryPolicy.async_with_prefill(@another_user_with_org_access, @private_org_fork, pull_request: @private_org_fork_pr).sync.can_attempt_create?
    end

    test "disallows advisory workspaces" do
      repo = create(:repository, owner: @user)
      advisory = create(:repository_advisory, :with_workspace, repository: repo, author: @user)
      refute Codespaces::RepositoryPolicy.async_with_prefill(@user, advisory.workspace_repository).sync.can_attempt_create?
    end

    context "allows outside collaborators from creating codespaces" do
      test "when all users and collaborators are allowed" do
        @org_codespaces_enabled.update_organization_codespaces_user_limit(
          Configurable::OrganizationCodespacesUserLimit::ALL_USERS_AND_OUTSIDE_COLLABORATORS, actor: @admin_user)
        collaborator = create(:user)
        repos = [@org_codespaces_enabled_private_repo, @shared_org_private_repo]
        repos.each do |repo|
          repo.reload # pick up the config change above
          repo.add_member(collaborator)
          assert Codespaces::RepositoryPolicy.async_with_prefill(
            collaborator, repo).sync.can_attempt_create?
        end
      end

      test "on public repos when collaborator have direct access" do
        @org_codespaces_enabled.update_organization_codespaces_user_limit(
          Configurable::OrganizationCodespacesUserLimit::ALL_USERS, actor: @admin_user)
        collaborator = create(:user)

        repo = create(:repository, owner: @org_codespaces_enabled)
        repo.reload # pick up the config change above
        repo.add_member(collaborator)
        assert Codespaces::RepositoryPolicy.async_with_prefill(
          collaborator, repo).sync.can_attempt_create?
      end

      test "in org user allowlist" do
        @org_codespaces_enabled.update_organization_codespaces_user_limit(
          Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS, actor: @admin_user)
        collaborator = create(:user)
        repos = [@org_codespaces_enabled_private_repo, @shared_org_private_repo]

        Codespaces::OrgPolicy.grant_billing_permission!(collaborator, @org_codespaces_enabled)
        repos.each do |repo|
          repo.reload # pick up the config change above
          repo.add_member(collaborator)
          assert Codespaces::RepositoryPolicy.async_with_prefill(
            collaborator, repo).sync.can_attempt_create?
        end
      end
    end

    context "with codespaces access through org access, rather than workspaces feature flag" do
      test "allows a fork of an org-owned private repository" do
        @private_org_fork_pr.fork_collab_allowed!
        assert Codespaces::RepositoryPolicy.async_with_prefill(@user_with_org_access, @private_org_fork, pull_request: @private_org_fork_pr).sync.can_attempt_create?
      end

      test "allows creation on another member's fork of an org-owned private repository (collab-enabled)" do
        @private_org_fork_pr.fork_collab_allowed!
        assert Codespaces::RepositoryPolicy.async_with_prefill(@another_user_with_org_access, @private_org_fork, pull_request: @private_org_fork_pr).sync.can_attempt_create?
      end

      test "allows creation on another member's fork of an org-owned private repository (collab-disabled)" do
        assert Codespaces::RepositoryPolicy.async_with_prefill(@another_user_with_org_access, @private_org_fork, pull_request: @private_org_fork_pr).sync.can_attempt_create?
      end
    end

    test "it defers to org policy async_can_use_codespaces?" do
      Codespaces::OrgPolicy.any_instance.expects(:async_can_use_codespaces?).once.returns(Promise.resolve(true))
      policy = Codespaces::RepositoryPolicy.async_with_prefill(
        @user_with_org_access,
        @org_codespaces_enabled_private_repo,
      ).sync
      policy.can_attempt_create?
    end
  end

  context "#can_see_codespaces_for_pull_request?" do
    test "with feature flag enabled allows for all public repositories, including legacy plans" do
      GitHub.stubs(:enterprise?).returns(false) # rubocop:todo GitHub/DontStubEnterpriseInTests
      pr_options = { base: "master", head: "patch-1" }
      user_org_on_restricted_plan_public_repo = create(:repository, owner: @org_on_restricted_plan)

      assert Codespaces::RepositoryPolicy.async_with_prefill(@user, @user_public_repo, pull_request: PullRequest.create_for(@user_public_repo, pr_options)).sync.can_see_codespaces_for_pull_request?
      assert Codespaces::RepositoryPolicy.async_with_prefill(@user, @rando_public_repo, pull_request: PullRequest.create_for(@rando_public_repo, pr_options)).sync.can_see_codespaces_for_pull_request?
      assert Codespaces::RepositoryPolicy.async_with_prefill(@user, @user_org_public_repo, pull_request: PullRequest.create_for(@user_org_public_repo, pr_options)).sync.can_see_codespaces_for_pull_request?
      assert Codespaces::RepositoryPolicy.async_with_prefill(@user, @rando_org_public_repo, pull_request: PullRequest.create_for(@rando_org_public_repo, pr_options)).sync.can_see_codespaces_for_pull_request?
      assert Codespaces::RepositoryPolicy.async_with_prefill(@user_org_on_restricted_plan_member, user_org_on_restricted_plan_public_repo, pull_request: PullRequest.create_for(user_org_on_restricted_plan_public_repo, pr_options)).sync.can_see_codespaces_for_pull_request?
    end

    test "allows org-owned private repositories" do
      GitHub.stubs(:enterprise?).returns(false) # rubocop:todo GitHub/DontStubEnterpriseInTests
      pr_options = { base: "master", head: "patch-1" }
      assert Codespaces::RepositoryPolicy.async_with_prefill(@user_with_org_access, @shared_org_private_repo, pull_request: PullRequest.create_for(@shared_org_private_repo, pr_options)).sync.can_see_codespaces_for_pull_request?
    end

    test "allows collab-enabled private fork PRs" do
      GitHub.stubs(:enterprise?).returns(false) # rubocop:todo GitHub/DontStubEnterpriseInTests
      @private_org_fork_pr.fork_collab_allowed!
      assert Codespaces::RepositoryPolicy.async_with_prefill(@another_user_with_org_access, @private_org_fork_pr.head_repository, pull_request: @private_org_fork_pr).sync.can_see_codespaces_for_pull_request?
    end

    test "disallows collab-disabled private fork PRs" do
      GitHub.stubs(:enterprise?).returns(false) # rubocop:todo GitHub/DontStubEnterpriseInTests
      @private_org_fork_pr.fork_collab_denied!
      refute Codespaces::RepositoryPolicy.async_with_prefill(@another_user_with_org_access, @private_org_fork_pr.head_repository, pull_request: @private_org_fork_pr).sync.can_see_codespaces_for_pull_request?
    end
  end

  context "#can_attempt_create?(allow_forking: false)", skip_enterprise: true do
    test "return true if the user can create without forking" do
      assert Codespaces::RepositoryPolicy.async_with_prefill(@user, @user_public_repo).sync.can_attempt_create?(allow_forking: false)
      assert Codespaces::RepositoryPolicy.async_with_prefill(@user, @user_private_repo).sync.can_attempt_create?(allow_forking: false)
      assert Codespaces::RepositoryPolicy.async_with_prefill(@user_with_org_access, @org_codespaces_enabled_private_repo).sync.can_attempt_create?(allow_forking: false)
      @private_org_fork_pr.fork_collab_allowed!
      assert Codespaces::RepositoryPolicy.async_with_prefill(@another_user_with_org_access, @private_org_fork, pull_request: @private_org_fork_pr).sync.can_attempt_create?(allow_forking: false)
    end

    test "return false if the user would need to fork" do
      refute Codespaces::RepositoryPolicy.async_with_prefill(@user, @rando_public_repo).sync.can_attempt_create?(allow_forking: false)
      @private_org_fork_pr.fork_collab_denied!
      refute Codespaces::RepositoryPolicy.async_with_prefill(@another_user_with_org_access, @private_org_fork, pull_request: @private_org_fork_pr).sync.can_attempt_create?(allow_forking: false)
    end
  end

  context "#can_attempt_start?" do
    test "on a public repository, a random user can start a codespace" do
      user = create(:user)

      assert Codespaces::RepositoryPolicy.async_with_prefill(user, @user_public_repo).sync.can_attempt_start?
    end

    test "on a private repo, a random user can't start a codespace" do
      user = create(:user)

      refute Codespaces::RepositoryPolicy.async_with_prefill(user, @rando_private_repo).sync.can_attempt_start?
    end

    test "on a private org repo, org members who do not have org access can start codespaces" do
      assert Codespaces::RepositoryPolicy.async_with_prefill(@user_with_org_but_not_org_creator_access, @org_codespaces_enabled_private_repo).sync.can_attempt_start?
    end

    test "on a private org repo, org members who have org access can start codespaces" do
      assert Codespaces::RepositoryPolicy.async_with_prefill(@user_with_org_access, @org_codespaces_enabled_private_repo).sync.can_attempt_start?
    end

    test "on an org owned public repo, a random user can start a codespace" do
      user = create(:user)
      org_codespaces_enabled_public_repo = create(:public_repository, owner: @org_codespaces_enabled)


      assert Codespaces::RepositoryPolicy.async_with_prefill(user, org_codespaces_enabled_public_repo).sync.can_attempt_start?
    end

    test "disallows advisory workspaces" do
      repo = create(:repository, owner: @user)
      advisory = create(:repository_advisory, :with_workspace, repository: repo, author: @user)
      refute Codespaces::RepositoryPolicy.async_with_prefill(@user, advisory.workspace_repository).sync.can_attempt_start?
    end

    context "enterprise disabled" do
      test "on an org owned private repo, a random user can start a codespace" do
        @org_codespaces_disabled = create(:enterprise_linked_organization, admin: @admin_user)
        Codespaces::BusinessDelegator.new(@org_codespaces_disabled.business).disable_codespaces!
        org_codespaces_disabled_private_repo = create(:private_repository, owner: @org_codespaces_disabled)

        refute Codespaces::RepositoryPolicy.async_with_prefill(@admin_user, org_codespaces_disabled_private_repo).sync.can_attempt_start?
      end
    end

    test "it defers to org policy async_can_use_codespaces?" do
      Codespaces::OrgPolicy.any_instance.expects(:async_can_use_codespaces?).once.returns(Promise.resolve(true))
      policy = Codespaces::RepositoryPolicy.async_with_prefill(
        @user_with_org_access,
        @org_codespaces_enabled_private_repo,
      ).sync
      policy.can_attempt_start?
    end
  end

  context "#read_only_codespace_required?" do
    test "on a public repository, a random user can only create a read only codespace" do
      user = create(:user)

      assert Codespaces::RepositoryPolicy.async_with_prefill(user, @user_public_repo).sync.read_only_codespace_required?
    end

    test "on a private repo, a random user can't create a read only codespace" do
      user = create(:user)

      refute Codespaces::RepositoryPolicy.async_with_prefill(user, @rando_private_repo).sync.read_only_codespace_required?
    end

    test "on a private org repo, org members who do not have org access can create read-only codespaces" do
      assert Codespaces::RepositoryPolicy.async_with_prefill(@user_with_org_but_not_org_creator_access, @org_codespaces_enabled_private_repo).sync.read_only_codespace_required?
    end

    test "on a private org repo, org members who have org access can not only create read-only codespaces" do
      refute Codespaces::RepositoryPolicy.async_with_prefill(@user_with_org_access, @org_codespaces_enabled_private_repo).sync.read_only_codespace_required?
    end

    test "on an org owned public repo, a random user can only create a read only codespace" do
      user = create(:user)
      org_codespaces_enabled_public_repo = create(:public_repository, owner: @org_codespaces_enabled)


      assert Codespaces::RepositoryPolicy.async_with_prefill(user, org_codespaces_enabled_public_repo).sync.read_only_codespace_required?
    end
  end

  context "#async_billable_owner" do
    context "when the billable owner is a user" do
      test "user creates readonly codespace on other-user-owned fork of an org-owned public repo where the user is not a member" do
        org = create(:codespaces_organization)

        public_repo = create(:repository, owner: org)

        user = create(:user)

        other_user = create(:user)
        other_user_forked_repo = create(:fork_repository, forker: other_user, fork_repo: public_repo)

        assert_equal user, Codespaces::RepositoryPolicy.async_with_prefill(user, other_user_forked_repo).sync.billable_owner
      end

      test "user creates readonly codespace on org-owned public repo without codespaces permissions from org" do
        org = create(:team_org)

        user = create(:user)
        org.add_member(user)

        public_repo = create(:repository, owner: org)

        assert_equal user, Codespaces::RepositoryPolicy.async_with_prefill(user, public_repo).sync.billable_owner
      end

      test "user creates readonly codespaces on user-owned public repo" do
        user = create(:user)
        other_user = create(:user)

        public_repo = create(:repository, owner: other_user)

        assert_equal user, Codespaces::RepositoryPolicy.async_with_prefill(user, public_repo).sync.billable_owner
      end

      test "(fork or non-fork) private org-owned repository & user cannot bill to org" do
        # set up org
        org = create(:codespaces_organization, :user_owned)
        org.allow_private_repository_forking(actor: org.admins.first)

        # Set up user
        user = create(:user)
        org.add_member(user)

        # set up org-owned private repos
        private_repo = create(:private_repository, owner: org)
        private_repo.add_member_without_validation_or_notifications(user)
        other_repo = create(:repository)
        other_repo.add_member_without_validation_or_notifications(org)
        private_forked_repo = create(:fork_repository, forker: org.admins.first, fork_repo: other_repo, organization: org)
        private_forked_repo.update!(public: false)

        # Ensure forked repo owner is org
        assert_equal org, private_forked_repo.owner

        # Ensure user cannot bill to org
        assert_equal user, Codespaces::RepositoryPolicy.async_with_prefill(user, private_repo).sync.billable_owner
        assert_equal user, Codespaces::RepositoryPolicy.async_with_prefill(user, private_forked_repo).sync.billable_owner
      end

      test "(fork or non-fork) public org-owned repository & user cannot bill to org" do
        # set up org
        org = create(:team_org)

        # Set up user
        user = create(:user)
        org.add_member(user)

        # set up org-owned repos
        repo = create(:repository, owner: org)
        forked_repo = create(:fork_repository, forker: user, fork_repo: repo, organization: org)

        # Ensure forked repo owner is org
        assert_equal forked_repo.owner, org

        # Ensure user cannot bill to org
        assert_equal user, Codespaces::RepositoryPolicy.async_with_prefill(user, repo).sync.billable_owner
        assert_equal user, Codespaces::RepositoryPolicy.async_with_prefill(user, forked_repo).sync.billable_owner
      end

      test "non-forked, user-owned repository" do
        user = create(:user)
        codespace = create(:codespace, owner: user)
        assert_equal user, Codespaces::RepositoryPolicy.async_with_prefill(user, codespace.repository).sync.billable_owner
      end

      test "non-forked, user-owned [public or private] repository" do
        user = create(:user)
        codespace = create(:codespace, owner: user, enable_org_access: false)
        assert_equal user, Codespaces::RepositoryPolicy.async_with_prefill(user, codespace.repository).sync.billable_owner
      end

      test "user-owned fork of an org-owned private repository & user cannot bill to org" do
        # set up org
        org = create(:team_org)
        org.allow_private_repository_forking(actor: org.admins.first)

        # set up user
        user = create(:user)
        org.add_member(user)

        # set up org-owned repo
        private_repo = create(:private_repository, owner: org)
        private_repo.add_member_without_validation_or_notifications(user)

        # fork repo & ensure user cannot bill to org
        repo = create(:fork_repository, forker: user, fork_repo: private_repo)

        assert_equal Codespaces::RepositoryPolicy.async_with_prefill(user, repo).sync.billable_owner, user
      end
    end

    context "when the billable owner is an organization" do
      test "user-owned fork of an org-owned private repository & user can bill to org" do
        # set up org
        org = create(:codespaces_organization, plan: GitHub::Plan.business)
        org.allow_private_repository_forking(actor: org.admins.first)

        # set up user
        user = create(:user)
        org.add_member(user)
        Codespaces::OrgPolicy.grant_billing_permission!(user, org)

        # set up org-owned private repo
        private_repo = create(:private_repository, owner: org)
        private_repo.add_member_without_validation_or_notifications(user)

        # fork repo & ensure user can bill to org
        repo = create(:fork_repository, forker: user, fork_repo: private_repo)

        assert_equal org, Codespaces::RepositoryPolicy.async_with_prefill(user, repo).sync.billable_owner
      end

      test "forked, user-owned repository, org-owned/private parent repository, accessed by collaborating user" do
        org_user_1 = create(:user)
        org_user_2 = create(:user)
        org = create(:codespaces_organization, plan: GitHub::Plan.business)
        org.allow_private_repository_forking(actor: org.admins.first)
        org.add_member(org_user_1)
        org.add_member(org_user_2)
        repo = create(:fork_repository, forker: org_user_1, fork_repo: create(:private_repository, owner: org))
        repo.add_member_without_validation_or_notifications(org_user_2)
        Codespaces::OrgPolicy.grant_billing_permission!(org_user_2, org)
        codespace = create(:codespace, owner: org_user_2, repository: repo)

        assert_equal org, Codespaces::RepositoryPolicy.async_with_prefill(org_user_2, repo).sync.billable_owner
      end

      test "private org-owned & user CAN bill to org" do
        @owner = create(:emu, :owner)
        @enterprise = @owner.enterprise_managed_business
        user = create(:emu, business: @enterprise)

        # set up org
        org = create(:codespaces_organization, plan: GitHub::Plan.business, business: @enterprise)
        org.add_member(user)
        Codespaces::OrgPolicy.grant_billing_permission!(user, org)

        # set up org-owned private repos
        private_repo = create(:private_repository, owner: org)
        private_repo.add_member_without_validation_or_notifications(user)

        # Ensure user cannot bill to org
        assert_equal org, Codespaces::RepositoryPolicy.async_with_prefill(user, private_repo).sync.billable_owner
      end

      test "(fork or non-fork) (private or public) org-owned repository & user CAN bill to org" do
        # set up org
        org = create(:codespaces_enterprise_organization)

        org.allow_private_repository_forking(actor: org.admins.first)

        # Set up user
        user = create(:user)
        org.add_member(user)
        Codespaces::OrgPolicy.grant_billing_permission!(user, org)

        # set up org-owned repos
        public_repo = create(:repository, owner: org)
        public_repo.add_member_without_validation_or_notifications(org)
        private_repo = create(:private_repository, owner: org)
        private_repo.add_member_without_validation_or_notifications(user)
        public_forked_repo = create(:fork_repository, forker: org.admins.first, fork_repo: create(:repository, owner: org), organization: org)
        private_forked_repo = create(:fork_repository, forker: org.admins.first, fork_repo: create(:repository), organization: org)
        private_forked_repo.update!(public: false)

        # Ensure forked repo owner is org
        assert_equal private_forked_repo.owner, org
        assert_equal public_forked_repo.owner, org

        #public_repo
        assert_equal org, Codespaces::RepositoryPolicy.async_with_prefill(user, private_repo).sync.billable_owner
        assert_equal org, Codespaces::RepositoryPolicy.async_with_prefill(user, private_forked_repo).sync.billable_owner
        assert_equal org, Codespaces::RepositoryPolicy.async_with_prefill(user, public_repo).sync.billable_owner
        assert_equal org, Codespaces::RepositoryPolicy.async_with_prefill(user, public_forked_repo).sync.billable_owner
      end

      test "user creates readonly codespace on org-owned private repo" do
        org = create(:codespaces_enterprise_organization)

        user = create(:user)
        org.add_member(user)
        Codespaces::OrgPolicy.grant_billing_permission!(user, org)

        private_repo = create(:private_repository, owner: org)
        private_repo.add_member_without_validation_or_notifications(user, action: :read)

        assert_equal org, Codespaces::RepositoryPolicy.async_with_prefill(user, private_repo).sync.billable_owner
      end

      test "user creates readonly codespace on org-owned public repo" do
        org = create(:codespaces_enterprise_organization)

        user = create(:user)
        org.add_member(user)
        Codespaces::OrgPolicy.grant_billing_permission!(user, org)

        public_repo = create(:repository, owner: org)

        assert_equal org, Codespaces::RepositoryPolicy.async_with_prefill(user, public_repo).sync.billable_owner
      end

      test "user creates readonly codespace on other-user-owned fork of an org-owned public repo where the user is a member of the org with codespaces permissions" do
        org = create(:codespaces_enterprise_organization)

        public_repo = create(:repository, owner: org)

        user = create(:user)
        org.add_member(user)
        Codespaces::OrgPolicy.grant_billing_permission!(user, org)

        other_user = create(:user)
        other_user_forked_repo = create(:fork_repository, forker: other_user, fork_repo: public_repo)

        assert_equal org, Codespaces::RepositoryPolicy.async_with_prefill(user, other_user_forked_repo).sync.billable_owner
      end

      test "user-owned fork of an org-owned public repository where user can bill to org" do
        org = create(:codespaces_enterprise_organization)

        public_repo = create(:repository, owner: org)

        user = create(:user)
        org.add_member(user)
        Codespaces::OrgPolicy.grant_billing_permission!(user, org)

        forked = create(:fork_repository, forker: user, fork_repo: public_repo)

        assert_equal org, Codespaces::RepositoryPolicy.async_with_prefill(user, forked).sync.billable_owner
      end

    end

    context "when the billable owner is nil" do
      test "billable owner returns nil when repo doesn't exist" do
        assert_nil Codespaces::RepositoryPolicy.async_with_prefill(@user, nil).sync.billable_owner
      end

      test "private org-owned repository & enterprised-managed user cannot bill to org" do
        @owner = create(:emu, :owner)
        @enterprise = @owner.enterprise_managed_business
        user = create(:emu, business: @enterprise)

        # set up org
        org = create(:organization, business: @enterprise)
        org.add_member(user)

        # set up org-owned private repos
        private_repo = create(:private_repository, owner: org)
        private_repo.add_member_without_validation_or_notifications(user)

        # Ensure user cannot bill to org
        assert_nil Codespaces::RepositoryPolicy.async_with_prefill(user, private_repo).sync.billable_owner
      end

    end

    test "sets datadog metric" do
      user = create(:user)

      Codespaces::RepositoryPolicy.async_with_prefill(user, @user_public_repo).sync.can_attempt_start?

      timings = GitHub.dogstats.distributions("codespaces.repository_policy.async_billable_owner.latency")
      assert_operator timings.count, :>=, 1
    end
  end

  context "#can_modify_codespace_repo_settings?" do
    test "returns false when repository is nil" do
      refute Codespaces::RepositoryPolicy.async_with_prefill(@user, nil).sync.can_modify_codespace_repo_settings?
    end

    test "returns false unable to bill" do
      Codespaces::RepositoryPolicy.any_instance.stubs(:can_bill?).returns(false)
      refute Codespaces::RepositoryPolicy.async_with_prefill(@user, @user_public_repo).sync.can_modify_codespace_repo_settings?
    end

    test "returns false when user is not an admin" do
      member = create(:user)
      @user_org.add_member(member)

      refute Codespaces::RepositoryPolicy.async_with_prefill(member, @user_org_public_repo).sync.can_modify_codespace_repo_settings?
    end

    test "returns true" do
      assert Codespaces::RepositoryPolicy.async_with_prefill(@user, @user_public_repo).sync.can_modify_codespace_repo_settings?
    end
  end

  test "calculating the repository policy for a codespace created from the fork of a PR" do
    repo = create(:repository, from_example: :simple)

    ref = repo.heads.create("topic", repo.heads.find("master").target, repo.owner)
    pull = PullRequest.create_for(
      repo,
      title: "PR into base",
      body: "fork me",
      head: ref.name,
      base: "master",
      user: repo.owner,
    )

    user = create(:user)
    forked_repo = create(:fork_repository, forker: user, fork_repo: repo)
    codespace = create(:codespace, owner: user, repository: forked_repo, pull_request: pull)

    refute_nil Codespaces::RepositoryPolicy.async_with_prefill(user, codespace.repository, pull_request: codespace.pull_request).sync
  end

  context "#read_only_and_forkable?" do
    test "true for a private org repo where org members can't push, but can fork" do
      assert Codespaces::RepositoryPolicy.async_with_prefill(@user_with_org_but_not_org_creator_access, @org_codespaces_enabled_private_repo).sync.read_only_and_forkable?
    end

    test "true for a private org repo where org members can't push or fork" do
      @org_codespaces_enabled_private_repo.block_private_repository_forking(actor: @admin_user)
      refute Codespaces::RepositoryPolicy.async_with_prefill(@user_with_org_but_not_org_creator_access, @org_codespaces_enabled_private_repo).sync.read_only_and_forkable?
    end

    test "false on a private org repo where an org member can push" do
      refute Codespaces::RepositoryPolicy.async_with_prefill(@user_with_org_access, @org_codespaces_enabled_private_repo).sync.read_only_and_forkable?
    end

    test "true for an org owned public repo where a random user that can't push" do
      user = create(:user)
      org_codespaces_enabled_public_repo = create(:public_repository, owner: @org_codespaces_enabled)


      assert Codespaces::RepositoryPolicy.async_with_prefill(user, org_codespaces_enabled_public_repo).sync.read_only_and_forkable?
    end
  end

  context "#disabled_by_business?" do
    test "false without a repo" do
      refute Codespaces::RepositoryPolicy.async_with_prefill(@user, nil).sync.disabled_by_business?
    end

    test "false if repo owned by user" do
      repo = create(:repository, owner: @user)

      refute Codespaces::RepositoryPolicy.async_with_prefill(@user, repo).sync.disabled_by_business?
    end

    test "false if repo is public" do
      org = create(:enterprise_linked_organization)
      repo = create(:public_repository, owner: org)
      assert org.business
      assert repo.public?
      Codespaces::BusinessDelegator.new(org.business).disable_codespaces!
      refute Codespaces::RepositoryPolicy.async_with_prefill(@user, repo).sync.disabled_by_business?
    end

    test "false if org isn't part of a business" do
      non_business_org = create(:organization, business: nil)
      org_codespaces_enabled_repo = create(:private_repository, owner: non_business_org)
      refute non_business_org.business
      refute Codespaces::RepositoryPolicy.async_with_prefill(@user, org_codespaces_enabled_repo).sync.disabled_by_business?
    end

    test "true - is disabled" do
      business_org = create(:enterprise_linked_organization)
      org_codespaces_enabled_repo = create(:private_repository, owner: business_org)
      assert business_org.business
      Codespaces::BusinessDelegator.new(business_org.business).disable_codespaces!

      assert Codespaces::RepositoryPolicy.async_with_prefill(@user, org_codespaces_enabled_repo).sync.disabled_by_business?
    end
  end

  test "allows codespaces usage on free org when org isn't billable owner" do
    user = create(:user)
    org = create(:free_org)
    assert_equal "free", org.plan.name
    repo = create(:public_repository, owner: org)
    assert Codespaces::RepositoryPolicy.async_with_prefill(user, repo).sync.allowed?
  end
end unless GitHub.enterprise?
