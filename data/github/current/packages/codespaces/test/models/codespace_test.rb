# typed: true
# frozen_string_literal: true

require "test_helper"
require "diet_earthsmoke"

class CodespaceTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    GitHub.flipper[:codespaces_local_target_url_valid].disable

    @monalisa = create(:paid_user, name: "monalisa")
    @repo = create(:repository, name: "test-repo", owner: @monalisa, from_example: :pull_request_source)

    @pull_request = create(:pull_request, repository: @repo, base_repository: @repo, head_repository: @repo, head_ref: "master-merged-topic")

    @codespace = create(:codespace, owner: @monalisa, repository: @repo, ref: @repo.default_branch)

    @destroyable_codespace = create(:codespace, owner: @monalisa, billable_owner: @monalisa)
    @destroyable_codespace.deprovisioning!

    @forker = create(:user, login: "forker")
    @source = create(:repository, owner: @monalisa, from_example: :pull_request_source)
    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :pull_request_fork)

    @pull_request_from_fork = PullRequest.create_for(
        @source,
        title: "PR from fork into base",
        body: "fork me",
        head: "#{@forker.name}:master-plus-one-commit",
        base: "master",
        user: @forker
    )

    # Organization that PPE and Dev enviroments are restricted to
    # Configured in lib/apps/internal/workspaces.rb
    @bookish_potato = create(:organization, login: "bookish-potato")
    @bookish_potato_repo = create(:repository, owner: @bookish_potato)

    @user = create(:user)
    @user_public_repo = create(:repository, owner: @user)
    @user_private_repo = create(:private_repository, owner: @user)
    @user_org = create(:organization)
    @user_org_public_repo = create(:repository, owner: @user_org)
    @user_org_private_repo = create(:private_repository, owner: @user_org)
    @user_org.add_member(@user)
    @org_member_push_access = create(:user)
    @user_org.add_member(@org_member_push_access)
    @user_org.allow_private_repository_forking(actor: @org_member_push_access)
    @user_org.allow_private_repository_forking(actor: @user)
    @user_org_public_repo.add_member(@org_member_push_access, action: :write)
    @user_org_private_repo.add_member(@org_member_push_access, action: :write)

    # Set up source/fork for forking tests
    @second_forker = create(:user, login: "forker2")
    @fork_source = create(:repository, owner: @user)
    @forked_repo = create(:fork_repository, forker: @forker, fork_repo: @source)
    @fork_of_fork = create(:fork_repository, forker: @forker, fork_repo: @fork)
    @user_fork = create(:fork_repository, forker: @user, fork_repo: @source)

    # org forks
    @user_org_public_repo_fork = create(:fork_repository, forker: @forker, fork_repo: @user_org_public_repo)
    @user_org_public_fork_root_push_access = create(:fork_repository, forker: @org_member_push_access, fork_repo: @user_org_public_repo)
    @user_org_private_repo_fork = create(:fork_repository, forker: @user, fork_repo: @user_org_private_repo)
    @user_org_private_repo_fork_root_push_access = create(:fork_repository, forker: @org_member_push_access, fork_repo: @user_org_private_repo)

    make_trusted_oauth_apps_owner
    @integration = create(:codespaces_integration)
  end

  setup do
    Codespace.deletion_reasons.each_value do |reason|
      reason_flag = "codespaces_pause_deletions_#{reason}".to_sym
      GitHub.flipper[reason_flag].disable
    end
  end

  context "#owner" do
    test "must be present to create a codespace" do
      codespace = build(:codespace, :unprovisioned, owner: nil, repository: @repo)

      refute_predicate codespace, :valid?
      assert_includes codespace.errors[:owner], "can't be blank"

      codespace.owner = @monalisa
      assert_predicate codespace, :valid?
    end
  end

  context "#repository" do
    test "allows for direct fork collab access by parent repo maintainer" do
      @pull_request_from_fork.fork_collab_allowed!

      codespace = build(:unpushable_codespace, owner: @monalisa, repository: @fork, pull_request: @pull_request_from_fork)

      assert_predicate codespace, :valid?
    end

    test "can be private and owned by another user, if a collaborator" do
      org = create(:organization)
      public_org_repo = create(:repository, owner: org)

      codespace = build(:codespace, owner: @monalisa, repository: public_org_repo)
      assert_predicate codespace, :valid?

      private_user_repo = create(:private_repository)
      private_user_repo.add_member(@monalisa)
      assert private_user_repo.pushable_by?(@monalisa)

      codespace = build(:codespace, owner: @monalisa, repository: private_user_repo)
      assert_predicate codespace, :valid?
    end

    test "can be private and org-owned and billed to collaborator" do
      private_org_repo = create(:private_repository, owner: create(:organization))
      private_org_repo.add_member(@monalisa)
      codespace = build(:codespace, owner: @monalisa, repository: private_org_repo, enable_org_access: false)

      assert private_org_repo.pushable_by?(@monalisa)
      refute Codespaces::OrgPolicy.new(user: @monalisa, org: private_org_repo.organization).async_can_bill?.sync
      assert_predicate codespace, :valid?
    end
  end

  context "#name" do
    test "must be a valid VSCS name" do
      codespace = build(:codespace, name: "owner-repo-my/branch-abcdef")
      refute_predicate codespace, :valid?
      assert_includes codespace.errors[:name], "is invalid"

      long_repo_name = "verbose" * 15
      codespace.name = "owner-#{long_repo_name}-master-abcdef"
      refute_predicate codespace, :valid?
      assert_includes codespace.errors[:name], "is invalid"
    end

    test "is generated automatically" do
      display_name = "display name"
      Codespaces::GenerateDisplayName.stubs(:call).returns(display_name)

      owned_codespace = build(:codespace)
      assert_predicate owned_codespace, :valid?
      assert owned_codespace.name.start_with?("display-name-")
    end

    test "must not start with a dash" do
      display_name = "-display name"
      Codespaces::GenerateDisplayName.stubs(:call).returns(display_name)

      codespace = build(:codespace)
      assert_predicate codespace, :valid?
      assert codespace.name.start_with?("display-name-")
    end

    test "is unique" do
      display_name = "display name"
      Codespaces::GenerateDisplayName.stubs(:call).returns(display_name)

      duplicate_1 = create(:codespace)
      assert duplicate_1.name.start_with?("display-name-")

      duplicate_2 = create(:codespace)
      assert duplicate_2.name.start_with?("display-name-")
      refute_equal duplicate_1.name, duplicate_2.name
    end

    test "raises an error if a unique name cannot be generated within max attempts" do
      Codespace.stub_const(:MAX_NAME_GENERATION_ATTEMPTS, 0) do
        assert_raises ArgumentError do
          create(:codespace, owner: @monalisa, repository: @repo)
        end
      end
    end

    context "with new record" do
      test "is truncated to fit the max length constraint with MAX_NAME_LENGTH" do
        display_name = "y" * 48
        Codespaces::GenerateDisplayName.stubs(:call).returns(display_name)

        codespace = build(:codespace)
        assert_predicate codespace, :valid?

        assert_match /\Ay+\-[a-z0-9]+\z/, codespace.name # Validate no unexpected characters like an extra hyphen in suffix
        assert_operator codespace.name.size, :<=, Codespace::MAX_NAME_LENGTH
      end
    end

    context "with existing record" do
      test "is truncated to fit the max length constraint with MAX_NAME_LENGTH_EXISTING_RECORD" do
        repo = create(:repository, name: "yyyyy", owner: @monalisa)
        codespace = create(:codespace, repository: repo, owner: @monalisa)

        # Setting a name with length > MAX_NAME_LENGTH and less than MAX_NAME_LENGTH_EXISTING_RECORD
        codespace.name = "monalisa-#{"y" * 51}"

        assert_predicate codespace, :valid?
        assert_operator codespace.name.size, :>, Codespace::MAX_NAME_LENGTH
        assert_operator codespace.name.size, :<, Codespace::MAX_NAME_LENGTH_EXISTING_RECORD
      end
    end

    context "with port suffix" do
      test "is less than the maximum length of the DNS label" do
        dns_max_label_length = 63
        max_port_suffix = "-65535"

        repo = create(:repository, name: "y" * 100, owner: @monalisa)
        codespace = build(:codespace, repository: repo, owner: @monalisa)
        assert_predicate codespace, :valid?

        assert_operator (codespace.name + max_port_suffix).size, :<=, dns_max_label_length
      end
    end

    test "replaces characters that are invalid for a domain name" do
      display_name = "display name"
      Codespaces::GenerateDisplayName.stubs(:call).returns(display_name)
      codespace = build(:codespace)
      assert_predicate codespace, :valid?
      assert codespace.name.start_with?("display-name")
    end

    context "Halloween fun" do
      test "generates spooky display names" do
        Timecop.freeze(DateTime.new(2023, 10, 31)) do
          codespace = build(:codespace)
          assert_predicate codespace, :valid?

          first, second, *_rest = codespace.name.split("-")
          assert_includes Codespaces::GenerateDisplayName::SPOOKY_ADJECTIVES, first
          assert_includes Codespaces::GenerateDisplayName::SPOOKY_NOUNS.dup << "spooky", second
        end
      end

      test "generates spooky display names leading up to Halloween" do
        Timecop.freeze(DateTime.new(2023, 10, 25)) do
          codespace = build(:codespace)
          assert_predicate codespace, :valid?

          first, second, *_rest = codespace.name.split("-")
          assert_includes Codespaces::GenerateDisplayName::SPOOKY_ADJECTIVES, first
          assert_includes Codespaces::GenerateDisplayName::SPOOKY_NOUNS.dup << "spooky", second
        end
      end

      test "generates spooky display names only in the period leading up to Halloween" do
        Timecop.freeze(DateTime.new(2023, 12, 31)) do # HAPPY NEW YEAR!! 🎉
          codespace = build(:codespace)
          assert_predicate codespace, :valid?

          first, second, *_rest = codespace.name.split("-")
          refute_includes Codespaces::GenerateDisplayName::SPOOKY_ADJECTIVES, first
          refute_includes Codespaces::GenerateDisplayName::SPOOKY_NOUNS.dup << "spooky", second
        end
      end
    end
  end

  context "#sku_name" do
    test "must be a valid sku_name" do
      assert_raises ArgumentError do
        codespace = build(:codespace, sku_name: :fakeyFakey)
        refute_predicate codespace, :valid?
        assert_includes codespace.errors[:sku_name], "is invalid"
      end
    end

    test "validates sku_name presence in existing records" do
      codespace = create(:codespace)
      codespace.sku_name = nil
      refute_predicate codespace, :valid?
      assert_includes codespace.errors[:sku_name], "can't be blank"
    end

    test "is set when valid sku name is passed to create" do
      sku_name = Codespace.sku_names.keys.sample
      codespace = build(:codespace, sku_name: sku_name)
      assert_predicate codespace, :valid?
      assert_equal codespace.sku_name, sku_name
    end
  end

  context "billable_owner" do
    test "uses billable_owner association" do
      org = create(:codespaces_organization, admin: @monalisa)

      plan_owner = create(:codespaces_organization, admin: @monalisa)
      decoupled_plan = create(:codespace_plan, vscs_target: :local)

      codespace = create(:codespace, owner: @user, billable_owner: org)

      assert_equal codespace.billing_entry.billable_owner, codespace.billable_owner
    end
  end

  context "billing_entry" do
    test "is not required to save an unprovisioned codespace" do
      codespace = build :codespace, state: "provisioning", guid: nil
      assert_nil codespace.billing_entry
      assert codespace.valid?
    end

    test "has its fields set from the codespaces's owner, guid, and plan name" do
      codespace = create :codespace
      entry = codespace.billing_entry
      refute_nil entry

      assert_predicate entry, :valid?
      assert_equal entry.billable_owner, codespace.billable_owner
      assert_equal entry.codespace_owner, codespace.owner
      assert_equal entry.codespace_guid, codespace.guid
      assert_equal entry.codespace_plan_name, codespace.plan.name
      assert_equal entry.repository, codespace.repository
    end

    test "does not get set when a billing_entry exists" do
      codespace = create :codespace, environment_data: nil
      original_entry = codespace.billing_entry
      refute_nil original_entry

      assert codespace.update(guid: SecureRandom.uuid)
      updated_entry = codespace.reload.billing_entry

      assert_equal original_entry.billable_owner, updated_entry.billable_owner
      assert_equal original_entry.codespace_owner, updated_entry.codespace_owner
      assert_equal original_entry.codespace_guid, updated_entry.codespace_guid
      assert_equal original_entry.codespace_plan_name, updated_entry.codespace_plan_name
      assert_equal original_entry.repository, updated_entry.repository
    end

    test "differentiating the codespace owner from the billable owner" do
      user = create(:user)
      org = create(:codespaces_organization, plan: GitHub::Plan.business)
      repo = create(:repository, owner: org)
      codespace = create(:codespace, owner: user, repository: repo, billable_owner: org)
      billing_entry = codespace.billing_entry

      assert_equal org, codespace.billable_owner
      assert_equal codespace.billable_owner, billing_entry.billable_owner
    end

    test "includes the copilot_workspace_id if present" do
      cw = create(:copilot_workspace)
      assert cw.billing_entry.copilot_workspace_id
    end
  end

  context "#to_param" do
    test "is the codespace name" do
      assert_equal @codespace.name, @codespace.to_param
    end
  end

  context "#pinned_to_commit?" do
    test "is false if codespaces is tied to an actual ref" do
      codespace = build(:codespace, repository: @repo, ref: "master")
      assert_predicate codespace, :valid?

      refute_predicate codespace, :pinned_to_commit?
    end

    test "is true if the codespace ref is actually a commit SHA" do
      commit_sha = @repo.commits.find("a270ea0fdfba2bd5a33934e5184784cddce87f38").oid
      codespace = build(:codespace, repository: @repo, ref: commit_sha)

      assert_predicate codespace, :valid?
      assert_predicate codespace, :pinned_to_commit?
    end

    test "is true if the ref is the commit's abbreviated SHA" do
      abbreviated_ref_sha = @repo.commits.find("a270ea0fdfba2bd5a33934e5184784cddce87f38").abbreviated_oid
      codespace = build(:codespace, repository: @repo, ref: abbreviated_ref_sha)

      assert_predicate codespace, :valid?
      assert_predicate codespace, :pinned_to_commit?
    end

    test "is true if the ref is a shortened form of a commit's SHA" do
      shortened_commit_sha = @repo.commits.find("a270ea0fdfba2bd5a33934e5184784cddce87f38").oid.slice(0..15)
      codespace = build(:codespace, repository: @repo, ref: shortened_commit_sha)

      assert_predicate codespace, :valid?
      assert_predicate codespace, :pinned_to_commit?
    end

    test "returns false if ref is not a valid SHA (less than 7 characters) but starts with the same hash characters as a commit" do
      too_short_commit_sha = @repo.commits.find("a270ea0fdfba2bd5a33934e5184784cddce87f38").oid.slice(0..5)
      codespace = build(:codespace, repository: @repo, ref: too_short_commit_sha)

      assert_predicate codespace, :valid?
      refute_predicate codespace, :pinned_to_commit?
    end

    test "is false if the ref is a valid SHA but not a shortened form of a commit" do
      codespace = build(:codespace, repository: @repo, ref: "df0ae072a")

      assert_predicate codespace, :valid?
      refute_predicate codespace, :pinned_to_commit?
    end
  end

  context "#location" do
    test "must have a location set for creation" do
      codespace = build(:codespace, repository: @repo, location: nil)

      refute_predicate codespace, :valid?
      assert_includes codespace.errors[:location], "can't be blank"

      codespace.location = "uswest2"
      assert_predicate codespace, :valid?
    end
  end

  context ".visible_to", skip_enterprise: true do
    test "returns codespaces for public repos but not private repos the user lost access to" do
      owner = create(:user)
      codespace = create(:codespace, repository: @repo, owner: owner)
      public_repo = create(:repository)
      other_codespace = create(:codespace, repository: public_repo, owner: owner)

      visible = owner.codespaces.visible_to(owner)
      assert_equal 2, visible.count
      assert_includes visible, codespace
      assert_includes visible, other_codespace

      @repo.toggle_visibility(actor: @monalisa)
      @repo.remove_member(owner)

      visible = owner.codespaces.visible_to(owner)
      assert_equal 1, visible.count
      refute_includes visible, codespace
      assert_includes visible, other_codespace
    end

    test "doesn't return codespaces where the repository has been deleted" do
      visible = @monalisa.codespaces.visible_to(@monalisa)
      assert_equal 1, visible.count
      assert_includes visible, @codespace

      @repo.destroy

      visible = @monalisa.codespaces.visible_to(@monalisa)
      assert_equal 0, visible.count
    end

    test "doesn't include codespaces that are `deprovisioning` in case the job fails" do
      visible = @monalisa.codespaces.visible_to(@monalisa)
      assert_equal 1, visible.count
      assert_includes visible, @codespace

      @codespace.deprovision!

      visible = @monalisa.codespaces.visible_to(@monalisa)
      assert_equal 0, visible.count
    end

    test "doesn't include codespaces for orgs in which you have lost the codespace flag" do
      org = create(:codespaces_organization)
      org_private_repo = create(:private_repository, owner: org)
      org_user = create(:user)
      org.add_member(org_user)

      codespace = create(:codespace, owner: org_user, repository: org_private_repo, enable_org_access: true)

      visible = org_user.codespaces.visible_to(org_user)
      assert_equal 1, visible.count
      assert_includes visible, codespace

      org.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS, actor: org.owner)
      Codespaces::OrgPolicy.revoke_billing_permission!(org_user, org)

      visible = org_user.codespaces.visible_to(org_user)
      assert_equal 0, visible.count
    end

    test "doesn't include codespaces that are no longer billable" do
      org = create(:codespaces_organization, plan: GitHub::Plan.business)
      org_private_repo = create(:private_repository, owner: org)
      org_user = create(:user)
      org.add_member(org_user)

      codespace = create(:codespace, owner: org_user, repository: org_private_repo)
      visible = org_user.codespaces.visible_to(org_user)
      assert_equal 1, visible.count
      assert_includes visible, codespace

      org.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::DISABLED, actor: org.admins.first)

      visible = org_user.codespaces.visible_to(org_user)
      assert_equal 0, visible.count
    end

    test "excludes copilot workspace codespaces" do
      owner = create(:user)
      owner.enable_feature :copilot_workspace

      cw_codespace = create(:copilot_workspace, owner: owner)

      codespace = create(:codespace, repository: @repo, owner: owner)
      public_repo = create(:repository)
      other_codespace = create(:codespace, repository: public_repo, owner: owner)

      visible = owner.codespaces.visible_to(owner)
      assert_equal 2, visible.count
      assert_includes visible, codespace
      assert_includes visible, other_codespace
      refute_includes visible, cw_codespace
    end
  end

  context "#accessible?", skip_enterprise: true do
    test "checks that the codespace is billable and creatable" do
      private_repo = create(:private_repository)
      user = create(:user)
      codespace = create(:codespace, owner: user, repository: private_repo)

      assert codespace.accessible?

      private_repo.remove_member(user)

      refute codespace.accessible?
    end

    context "when billable_owner is a user" do
      test "returns true when accessible" do
        org = create(:codespaces_organization, :members_only, :user_owned, plan: GitHub::Plan.business)
        repo = create(:repository, owner: org)

        user = create(:user)
        codespace = create(:codespace, owner: user, repository: repo, enable_org_access: false,)

        assert_equal codespace.billable_owner, user
        assert codespace.accessible?
      end

      test "returns false when repo owner is deleted" do
        org = create(:organization, plan: GitHub::Plan.business)
        repo = create(:repository, owner: org)
        user = create(:user)
        codespace = create(:codespace, owner: user, repository: repo, enable_org_access: false)

        assert codespace.accessible?
        org.destroy!
        refute codespace.reload.accessible?
      end

      test "returns false when codespace owner is deleted" do
        org = create(:codespaces_organization, plan: GitHub::Plan.business)
        repo = create(:repository, owner: org)
        user = create(:user)
        codespace = create(:codespace, owner: user, repository: repo, enable_org_access: true)

        assert codespace.accessible?
        user.delete
        codespace.reload
        assert_nil codespace.owner
        assert_equal org, codespace.billable_owner
        refute codespace.accessible?
      end
    end

    context "when the repository is org-owned" do
      test "returns true when when access is enabled" do
        user = create(:user)
        org = create(:codespaces_organization, :org_owned, plan: GitHub::Plan.business, admin: user)
        repo = create(:org_owned_private_repository, owner: org)
        repo.add_member(user)

        codespace = create(:codespace, owner: user, repository: repo)

        assert codespace.accessible?
      end

      test "returns false when when access is disabled" do
        user = create(:user)
        org = create(:codespaces_organization, :org_owned, :members_only, plan: GitHub::Plan.business, admin: user)
        repo = create(:org_owned_private_repository, owner: org)
        repo.add_member(user)

        codespace = create(:codespace, owner: user, repository: repo, enable_org_access: false)
        org.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::DISABLED, actor: org.owner)

        refute codespace.accessible?
      end

      test "returns false when when access is disabled even if the codespace would be user-owned" do
        user = create(:user)
        org = create(:codespaces_organization, :user_owned, :disabled, plan: GitHub::Plan.business, admin: user)
        repo = create(:org_owned_private_repository, owner: org)
        repo.add_member(user)

        codespace = create(:codespace, owner: user, repository: repo, enable_org_access: false)

        refute codespace.accessible?
      end
    end
  end

  context "#writable_by?", skip_enterprise: true do
    test "only allows the codespace owner" do
      rando = create(:user)
      codespace = create(:codespace, repository: @repo, owner: @repo.owner)

      assert codespace.writable_by?(@repo.owner)
      refute codespace.writable_by?(rando)
    end

    test "requires that the owner maintain read access to the repository" do
      collaborator = create(:user)
      codespace = create(:codespace, repository: @repo, owner: collaborator)
      assert codespace.writable_by?(collaborator)

      @repo.toggle_visibility(actor: @monalisa)
      @repo.remove_member(collaborator)
      refute codespace.writable_by?(collaborator)
    end

    test "owner maintains write access to the repository when not a member, if repo is still readable" do
      collaborator = create(:user)
      codespace = create(:codespace, repository: @repo, owner: collaborator)
      assert codespace.writable_by?(collaborator)

      @repo.remove_member(collaborator)

      assert @repo.public?
      assert codespace.writable_by?(collaborator)
    end

    test "owner loses write access to the repository when not a member, if repo not readable" do
      collaborator = create(:user)
      codespace = create(:codespace, repository: @repo, owner: collaborator)
      @repo.update!(public: false)

      assert codespace.writable_by?(collaborator)

      @repo.remove_member(collaborator)

      refute codespace.writable_by?(collaborator)
    end
  end

  context "#moniker" do
    test "returns the PR's permalink if attached to a pull request" do
      codespace = create(:codespace, repository: @repo, pull_request: @pull_request)

      assert_equal @pull_request.permalink, codespace.moniker
    end

    test "returns the commit permalink if the codespace is pinned to a commit" do
      codespace = create(:codespace, repository: @repo, ref: "a270ea0fdfba2bd5a33934e5184784cddce87f38")
      assert_predicate codespace, :pinned_to_commit?

      commit = @repo.commits.find("a270ea0fdfba2bd5a33934e5184784cddce87f38")
      assert_equal commit.permalink, codespace.moniker
    end

    test "returns the ref's tree page if not using the repo's default branch" do
      codespace = create(:codespace, repository: @repo, ref: "master-forward-2")

      tree_page = "#{@repo.permalink}/tree/master-forward-2"
      assert_equal tree_page, codespace.moniker
    end

    test "returns the repo overview page if created from the default branch" do
      codespace = create(:codespace, repository: @repo, ref: @repo.default_branch)

      assert_equal @repo.permalink, codespace.moniker
    end
  end

  context "#create_type" do
    test "returns pull_request if attached to a pull request" do
      codespace = create(:codespace, repository: @repo, pull_request: @pull_request)

      assert_equal "pull_request", codespace.create_type
    end

    test "returns commit if the codespace is pinned to a commit" do
      codespace = create(:codespace, repository: @repo, ref: "a270ea0fdfba2bd5a33934e5184784cddce87f38")
      assert_predicate codespace, :pinned_to_commit?

      assert_equal "commit", codespace.create_type
    end

    test "returns branch if not using the repo's default branch" do
      codespace = create(:codespace, repository: @repo, ref: "master-forward-2")

      assert_equal "branch", codespace.create_type
    end

    test "returns default if created from the default branch" do
      codespace = create(:codespace, repository: @repo, ref: @repo.default_branch)

      assert_equal "default", codespace.create_type
    end
  end

  context "#branch" do
    test "returns the PR's branch if attached to a pull request" do
      codespace = create(:codespace, repository: @repo, pull_request: @pull_request)

      assert_equal @pull_request.head_ref_name, codespace.branch
    end

    test "returns nil codespace is pinned to a commit" do
      codespace = create(:codespace, repository: @repo, ref: "a270ea0fdfba2bd5a33934e5184784cddce87f38")
      assert_predicate codespace, :pinned_to_commit?

      assert_nil codespace.branch
    end

    test "returns the ref if ref is a branch" do
      branch = "sweet-new-feature"
      codespace = create(:codespace, repository: @repo, ref: branch)

      assert_equal branch, codespace.branch
    end
  end

  context "#last_used_at" do
    test "is initially set to the creation time" do
      now = Time.current
      travel_to(now) do
        codespace = create(:codespace)
        assert_equal now.to_i, codespace.last_used_at.to_i
      end
    end

    test "falls back to `created_at` for existing codespaces without a last_used_at" do
      @codespace.update_column :last_used_at, nil
      assert_nil @codespace.reload.read_attribute(:last_used_at)

      refute_nil @codespace.created_at
      assert_equal @codespace.created_at, @codespace.last_used_at
    end
  end

  context "#state" do
    test "describes the current state" do
      assert_equal "pending", build(:codespace, :unprovisioned).state
      assert_equal "provisioned", @codespace.state
    end

    test "provisioned is exclusive to codespaces with a guid" do
      codespace = build(:codespace, :unprovisioned)
      assert_nil codespace.guid

      %w(pending provisioning failed).each do |allowed_state|
        codespace = build(:codespace, :unprovisioned, state: allowed_state)
        assert_predicate codespace, :valid?
      end

      codespace = build(:codespace, state: "provisioned", guid: nil)
      refute_predicate codespace, :valid?
      assert_includes codespace.errors[:state], "must not be 'provisioned' without a guid"

      codespace = build(:codespace, state: "provisioned")
      %w(pending provisioning failed).each do |disallowed_state|
        codespace.state = disallowed_state
        refute_predicate codespace, :valid?
        assert_includes codespace.errors[:state], "must be 'provisioned' or 'deprovisioned' for codespace with a guid"
      end

      codespace.state = "provisioned"
      assert_predicate codespace, :valid?
    end
  end

  context "#create", skip_enterprise: true do
    test "fires an instrumentation event", skip_enterprise: true do
      codespace = create(:codespace, :unprovisioned)
      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        codespace: Hydro::EntitySerializer.codespace(codespace),
        actor: Hydro::EntitySerializer.user(codespace.owner),
        billable_owner_in_dunning_cycle: false,
        billing_plan_owner: Hydro::EntitySerializer.codespace_billable_owner(codespace.billable_owner)
      }

      assert_hydro_published(message, schema: "github.codespaces.v0.CodespaceCreated")
    end

    test "does not fire a repository changed event on creation" do
      GlobalInstrumenter.expects(:instrument).once.with("codespaces.created", anything)
      GlobalInstrumenter.expects(:instrument).never.with(Codespaces::Events::CODESPACE_REPOSITORY_CHANGED, anything)
      create(:codespace, repository: @user_public_repo, owner: @user)
    end

    test "instruments audit log: codespaces.create event" do
      events = subscribe "codespaces.create"

      codespace = create(:codespace, :unprovisioned)

      expected_payload = {
        codespace_id: codespace.id,
        location: codespace.location,
        name: codespace.name,
        oid: codespace.oid,
        org: nil,
        owner: codespace.owner.login,
        owner_id: codespace.owner.id,
        pull_request_id: nil,
        ref: codespace.ref,
        sku_name: codespace.sku_name,
        user_id: codespace.owner.id,
        user: codespace.owner.login,
        repo: codespace.repository.nwo,
        repo_id: codespace.repository.id,
        public_repo: codespace.repository.public?,
        devcontainer_path: codespace.devcontainer_path,
        machine_type: codespace.sku&.display_name,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end
  end

  context "#destroy" do
    test "codespaces with a guid are soft deletable" do
      assert_predicate @codespace, :soft_deletable?
    end

    test "copilot workspaces with a guid are NOT soft deletable" do
      refute_predicate create(:copilot_workspace), :soft_deletable?
    end

    test "task cloud environments with a guid are soft deletable" do
      assert_predicate create(:task_cloud_environment), :soft_deletable?
    end

    test "aborts destroy when codespace is not deprovisioning" do
      refute @codespace.destroy
    end

    test "it allows destroy when the codespace is deprovisioning" do
      assert @destroyable_codespace.destroy
    end

    test "fires an instrumentation event", skip_enterprise: true do
      @destroyable_codespace.destroy

      message = {
        codespace: Hydro::EntitySerializer.codespace(@destroyable_codespace),
      }
      assert_hydro_published(message, schema: "github.codespaces.v0.CodespaceDestroyed")
    end

    test "instruments audit log: codespaces.destroy event for soft delete" do
      events = subscribe "codespaces.destroy"

      @destroyable_codespace.soft_delete

      expected_payload = {
        codespace_id: @destroyable_codespace.id,
        location: @destroyable_codespace.location,
        name: @destroyable_codespace.name,
        oid: @destroyable_codespace.oid,
        org: nil,
        owner: @destroyable_codespace.owner.login,
        owner_id: @destroyable_codespace.owner.id,
        pull_request_id: nil,
        ref: @destroyable_codespace.ref,
        sku_name: @destroyable_codespace.sku_name,
        user_id: @destroyable_codespace.owner.id,
        user: @destroyable_codespace.owner.login,
        repo: @destroyable_codespace.repository.nwo,
        repo_id: @destroyable_codespace.repository.id,
        public_repo: @destroyable_codespace.repository.public?,
        devcontainer_path: @destroyable_codespace.devcontainer_path,
        machine_type: @destroyable_codespace.sku&.display_name,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload

      # show that the actual destroy will not send the event again
      @destroyable_codespace.destroy
      refute events.pop
    end
  end

  # Behavior closely mirrors #destroy
  context "#soft_delete" do
    test "aborts soft_delete when codespace is not deprovisioning" do
      refute @codespace.soft_delete
      refute @codespace.reload.deleted?
      refute_hydro_messages(schema: "github.codespaces.v0.CodespaceSoftDeleted")
    end

    test "it allows soft_delete when the codespace is deprovisioning" do
      assert @destroyable_codespace.soft_delete
      assert @destroyable_codespace.reload.deleted?
    end

    test "it allows soft_delete of anan orphaned codespace" do
      @destroyable_codespace.owner.delete
      @destroyable_codespace.reload

      assert @destroyable_codespace.soft_delete
      assert @destroyable_codespace.reload.deleted?
    end

    test "fires an instrumentation event", skip_enterprise: true do
      @destroyable_codespace.soft_delete

      message = {
        codespace: Hydro::EntitySerializer.codespace(@destroyable_codespace),
        reason: Codespace.deletion_reasons[:user_requested],
      }
      assert_hydro_published(message, schema: "github.codespaces.v0.CodespaceSoftDeleted")
    end

    test "instruments audit log: codespaces.destroy event" do
      events = subscribe "codespaces.soft_deleted"

      @destroyable_codespace.soft_delete

      expected_payload = {
        codespace_id: @destroyable_codespace.id,
        location: @destroyable_codespace.location,
        name: @destroyable_codespace.name,
        oid: @destroyable_codespace.oid,
        org: nil,
        owner: @destroyable_codespace.owner.login,
        owner_id: @destroyable_codespace.owner.id,
        pull_request_id: nil,
        ref: @destroyable_codespace.ref,
        sku_name: @destroyable_codespace.sku_name,
        user_id: @destroyable_codespace.owner.id,
        user: @destroyable_codespace.owner.login,
        repo: @destroyable_codespace.repository.nwo,
        repo_id: @destroyable_codespace.repository.id,
        public_repo: @destroyable_codespace.repository.public?,
        reason: "user_requested",
        devcontainer_path: @destroyable_codespace.devcontainer_path,
        machine_type: @destroyable_codespace.sku&.display_name,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "doesn't delete if killswitch flag for reason is set" do
      GitHub.flipper[:codespaces_pause_deletions_inaccessible].enable
      refute @destroyable_codespace.soft_delete(Codespace.deletion_reasons[:inaccessible])
      refute @destroyable_codespace.reload.deleted?
    end

    test "deletes if killswitch flag is set, but for a different reason" do
      GitHub.flipper[:codespaces_pause_deletions_inaccessible].enable
      assert @destroyable_codespace.soft_delete(Codespace.deletion_reasons[:org_downgrade])
      assert @destroyable_codespace.reload.deleted?
    end

    test "details of skipped deletion are logged" do
      GitHub.flipper[:codespaces_pause_deletions_inaccessible].enable
      GitHub.logger.expects(:info).with(
        "Codespaces Soft Delete Paused",
        "gh.codespaces.codespace_id" => @destroyable_codespace.id,
        "gh.codespaces.codespace_guid" => @destroyable_codespace.guid,
        "gh.codespaces.deletion_reason" => Codespace.deletion_reasons[:inaccessible],
        "code.namespace" => "Codespace",
        "code.function" => "soft_delete",
      )
      refute @destroyable_codespace.soft_delete(Codespace.deletion_reasons[:inaccessible])
      refute @destroyable_codespace.reload.deleted?
    end
  end

  context ".deleted" do
    test "returns only deleted codespaces" do
      create(:codespace, :deleted)
      refute_empty Codespace.deleted.select(&:deleted?)
    end
  end

  context ".active" do
    test "returns only active codespaces" do
      assert_empty Codespace.active.select(&:deleted?)
    end
  end

  context ".restorable?" do
    test "is restorable after being soft-deleted" do
      @destroyable_codespace.soft_delete
      assert @destroyable_codespace.restorable?
    end

    test "is not restorable if it was never available" do
      @destroyable_codespace.soft_delete
      environment_data = @destroyable_codespace.environment_data.to_h
      environment_data["state"] = Codespaces::Vscs::State::FAILED
      @destroyable_codespace.update_attribute(:environment_data, Codespaces::Environment::Type.new.cast_value(environment_data.to_json))
      refute_predicate @destroyable_codespace, :restorable?
    end
  end

  context "#deprovision!" do
    test "updates state to deprovisioning" do
      @codespace.deprovision!
      assert_predicate @codespace, :deprovisioning?
    end

    test "can update state to deprovisioning when environment data is invalid" do
      environment_data = @codespace.environment_data.to_h
      environment_data["id"] = "Blorg"
      @codespace.update_attribute(:environment_data, Codespaces::Environment::Type.new.cast_value(environment_data.to_json))

      @codespace.deprovision!
      assert_predicate @codespace, :deprovisioning?
    end

    test "schedules a delete job" do
      assert_enqueued_with(job: CodespacesDeleteJob, args: [{ codespace: @codespace }]) do
        @codespace.deprovision!
      end
    end
  end

  context "codespaces from forked pull requests as the forker" do
    test "successfully creates a codespace from a pull request in different repos" do
      pr_codespace = build(:codespace, owner: @forker, repository: @fork, pull_request: @pull_request_from_fork)
      assert_predicate pr_codespace, :valid?
    end
  end

  context "#export_branch_exists?" do
    test "returns false if the branch does not exist" do
      refute @codespace.export_branch_exists?
    end

    test "returns false if the repo has been deleted" do
      @codespace.repository.delete
      refute @codespace.export_branch_exists?
    end

    test "returns true if the branch exists" do
      ref = @repo.heads.find_or_build("master")
      export_ref = @repo.heads.create(@codespace.export_branch_name, ref.target, @monalisa)

      assert @codespace.export_branch_exists?

      export_ref.delete(@monalisa)
    end
  end

  context "#export!", skip_enterprise: true do
    test "requires a provisioned codespace for export!" do
      refute create(:codespace, :unprovisioned).export!(nil)
    end

    test "updates last_export_start_at when provisioned and no existing export branch" do
      codespace = create(:codespace)
      assert_changes -> { codespace.last_export_start_at } do
        codespace.export!(nil)
      end
    end

    test "schedules a background export" do
      codespace = create(:codespace)
      assert_enqueued_with(job: CodespacesExportJob) do
        codespace.export!(nil)
      end
    end

    test "raises an exception when codespace has a pending async operation" do
      create(:codespaces_async_operation, codespace: @codespace)
      assert_raises Codespaces::AsyncOperation::PendingError do
        @codespace.export!(nil)
      end
    end
  end

  context "#exported!" do
    test "requires a provisioned codespace for exported!" do
      refute create(:codespace, :unprovisioned, last_export_start_at: Time.now).exported!
    end

    test "updates last_export_end_at when provisioned" do
      codespace = create(:codespace)
      codespace.exporting!
      assert_changes -> { codespace.last_export_end_at } do
        codespace.exported!
      end
    end
  end

  context "#exporting?" do
    test "false when we've not started an export" do
      refute create(:codespace).exporting?
    end

    test "true when we start an export" do
      codespace = create(:codespace)
      codespace.exporting!
      assert codespace.exporting?
    end

    test "false once we have exported" do
      codespace = create(:codespace)
      codespace.exporting!
      assert codespace.exporting?

      travel 1.second
      codespace.exported!
      refute codespace.exporting?
    end
  end

  context "#exported?" do
    test "false if we've never exported" do
      refute create(:codespace).exported?
    end

    test "false if we've never finished exporting" do
      codespace = create(:codespace)
      codespace.exporting!
      refute codespace.exported?
    end

    test "true when we've exported" do
      codespace = create(:codespace)
      codespace.exporting!
      travel 1.second
      codespace.exported!
      assert codespace.exported?
    end

    test "false if we export again" do
      codespace = create(:codespace)
      codespace.exporting!
      travel 1.second
      codespace.exported!
      travel 1.second
      codespace.exporting!
      refute codespace.exported?
    end
  end

  context "#delete_export_branch" do
    test "does nothing when there is no export branch" do
      assert_nothing_raised do
        @codespace.delete_export_branch
      end
    end

    test "deletes existing export branch when there is one" do
      codespace = create(:codespace)
      repo = codespace.repository
      example_repo :pull_request_source, repo
      with_export_branch(codespace) do
        assert repo.heads.find(codespace.export_branch_name)&.exist?
        codespace.delete_export_branch
        refute repo.heads.find(codespace.export_branch_name)&.exist?
      end
    end
  end

  context "#fresh_export_exists?" do
    test "returns false if `last_export_end_at` is nil" do
      with_export_branch(@codespace) do
        refute @codespace.fresh_export_exists?
      end
    end

    test "returns false if the export branch does not exist" do
      @codespace.touch(:last_export_end_at)
      refute @codespace.fresh_export_exists?
    end

    test "returns true if our export exists and the codespace has not been used since it was exported" do
      @codespace.touch(:last_used_at, time: 5.minutes.ago)
      @codespace.touch(:last_export_end_at)
      with_export_branch(@codespace) do
        assert @codespace.fresh_export_exists?
      end
    end

    test "returns true if our export exists and for some reason we never tracked last_used_at" do
      @codespace.touch(:last_export_end_at)
      with_export_branch(@codespace) do
        assert @codespace.fresh_export_exists?
      end
    end

    test "returns false if our export exists but the codespace has been used since it was exported" do
      @codespace.touch(:last_used_at)
      @codespace.touch(:last_export_end_at, time: 1.minute.ago)
      with_export_branch(@codespace) do
        refute @codespace.fresh_export_exists?
      end
    end
  end

  context "#stuck_provisioning?" do
    test "returns true if it's been 5 minutes since creation and the codespaces is provisioning" do
      codespace = create(:codespace, :provisioning, created_at: 5.minutes.ago)
      assert codespace.stuck_provisioning?
    end

    test "returns true if it's been 5 minutes since creation and the codespaces is pending" do
      codespace = create(:codespace, :unprovisioned, created_at: 5.minutes.ago)
      assert codespace.stuck_provisioning?
    end

    test "returns false if it's been < 5 minutes since creation and the codespaces is provisioning" do
      codespace = create(:codespace, :provisioning)
      refute codespace.stuck_provisioning?
    end

    test "returns false if it's been < 5 minutes since creation and the codespaces is pending" do
      codespace = create(:codespace, :unprovisioned)
      refute codespace.stuck_provisioning?
    end

    test "returns false for a provisioned codespace" do
      codespace = create(:codespace, created_at: 10.minutes.ago)
      refute codespace.stuck_provisioning?
    end

    test "returns false if it hasn't been persisted" do
      codespace = build(:codespace)

      refute codespace.stuck_provisioning?
    end
  end

  context "#never_available?" do
    test "returns true if the vscs state is provisioning" do
      codespace = create(:codespace, :provisioning_in_vscs)
      assert codespace.never_available?
    end

    test "returns true if the vscs state is failed" do
      codespace = create(:codespace, :failed_in_vscs)
      assert codespace.never_available?
    end

    test "returns false for provisioned codespaces" do
      codespace = create(:codespace)
      refute codespace.never_available?
    end

    test "returns true when codespace has no environment_data" do
      codespace = Codespace.new
      assert codespace.never_available?
    end

  end

  context "#mark_used!" do
    test "updates last_used_at" do
      @codespace.save # saving so a sku_name gets set
      @codespace.mark_used!

      assert_changes -> { @codespace.last_used_at } do
        Timecop.travel(10.minutes) do
          @codespace.mark_used!
        end
      end
    end
  end

  context "instrument_connect" do
    test "instruments audit log: codespaces.connect event" do
      events = subscribe "codespaces.connect"

      @codespace.save # saving so a sku_name gets set
      @codespace.instrument_connect

      expected_payload = {
        codespace_id: @codespace.id,
        location: @codespace.location,
        name: @codespace.name,
        oid: @codespace.oid,
        org: nil,
        owner: @codespace.owner.login,
        owner_id: @codespace.owner.id,
        pull_request_id: nil,
        ref: @codespace.ref,
        sku_name: @codespace.sku_name,
        user_id: @codespace.owner.id,
        user: @codespace.owner.login,
        repo: @codespace.repository.nwo,
        repo_id: @codespace.repository.id,
        public_repo: @codespace.repository.public?,
        devcontainer_path: @codespace.devcontainer_path,
        machine_type: @codespace.sku&.display_name,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end
  end

  context ".for_organization" do
    test "looks up codespaces by organization" do
      subject_org = create(:codespaces_credit_card_organization, admin: @monalisa)

      not_subject_org = create(:codespaces_credit_card_organization, admin: @monalisa)

      cs_for_org = create(:codespace, repository: create(:private_repository, owner: subject_org), billable_owner: subject_org)
      cs_not_for_org = create(:codespace, repository: create(:private_repository, owner: not_subject_org), billable_owner: not_subject_org)

      assert_equal Codespace.for_organization(subject_org), [cs_for_org]
    end
  end

  context "#ref" do
    test "supports emoji" do
      ref = "🔮-branch"
      codespace = create(:codespace, ref: ref)
      codespace.reload
      assert_equal ref, codespace.ref
    end
  end

  def with_export_branch(codespace)
    begin
      repository = codespace.repository
      export_branch = codespace.export_branch_name
      ref = repository.heads.find_or_build("master")
      export_ref = repository.heads.create(export_branch, ref.target, @monalisa)
      yield
    ensure
      repository.heads.find(export_branch)&.delete(@monalisa)
    end
  end

  context "#environment_data" do
    test "allows nil environment_data" do
      codespace = build(:codespace, environment_data: nil)
      assert codespace.valid?
      assert_nil codespace.environment_data
    end

    test "uses a Codespaces::Environment object" do
      codespace = build(:codespace, environment_data: { id: "some-id" })
      assert_kind_of Codespaces::Environment, codespace.environment_data
    end

    test "requires the environment id to match the codespace guid if environment_data is present" do
      codespace = build(:codespace, environment_data: { id: "some-id", updated: Time.now.iso8601 })
      refute codespace.valid?
      codespace = create(:codespace)
      codespace.environment_data = { id: codespace.guid }
      assert codespace.valid?
    end

    test "setting environment_data updates environment_data_updated_at" do
      codespace = create(:codespace)
      assert_changes -> { codespace.environment_data_updated_at } do
        codespace.update(environment_data: { id: codespace.guid })
      end
    end

    test "only environment_data changes update environment_data_updated_at" do
      guid = SecureRandom.hex(18)
      codespace = create(:codespace, guid: guid, environment_data: { id: guid })
      assert codespace.environment_data_updated_at
      assert_no_changes -> { codespace.environment_data_updated_at } do
        codespace.update(environment_data: { id: guid })
      end
    end

    test "reading blank environment_data triggers background job to backfill", skip_enterprise: true do
      codespace = create(:codespace, environment_data: nil)
      assert_enqueued_with(job: Codespaces::BackfillEnvironmentDataJob) do
        codespace.environment_data
      end
    end

    test "validating a codespace does not trigger backfills" do
      assert_no_enqueued_jobs(only: Codespaces::BackfillEnvironmentDataJob) do
        create(:codespace, environment_data: nil)
      end
    end
  end

  context "#display_branch" do
    test "it gives priority to the environment's current branch" do
      codespace = build(:codespace, environment_data: { git_status: { branch: "sweet-branch" } })
      assert_equal "sweet-branch", codespace.display_branch
    end

    test "it falls back on the environment's current commit id if no current branch" do
      codespace = build(:codespace, environment_data: { git_status: { commit: "commit-id-here" } })
      assert_equal "commit-id-here", codespace.display_branch
    end

    test "it falls back on the codespace's originating ref if no environment data is available" do
      codespace = build(:codespace)
      assert_equal codespace.ref, codespace.display_branch
    end
  end

  context "#commits_diverged?" do
    test "returns false if there's no additional commit data" do
      codespace = build(:codespace, environment_data: {})
      refute codespace.commits_diverged?
    end
    test "returns true if commits are ahead" do
      codespace = build(:codespace, environment_data: { git_status: { "ahead" => 1 } })
      assert codespace.commits_diverged?
    end

    test "returns true if commits are behind" do
      codespace = build(:codespace, environment_data: { git_status: { "behind" => 1 } })
      assert codespace.commits_diverged?
    end
  end

  context "#vscs_target" do
    test "accepts nil and defaults to production" do
      codespace = create(:codespace)
      codespace.vscs_target = nil
      assert_equal codespace.vscs_target, :production
    end

    test "converts to symbol" do
      vscs_target = "development"
      codespace = build(:codespace, vscs_target: vscs_target)
      assert_equal codespace.vscs_target, :development
    end

    test "throws error if vscs target is local and vscs target url is invalid" do
      GitHub.flipper[:codespaces_local_target_url_valid].enable
      codespace = build(:codespace, vscs_target: :local, vscs_target_url: "http://localhost:8080")
      refute_predicate codespace, :valid?
      assert_includes codespace.errors[:vscs_target_url], "must be a valid local target URL"
    end

    test "creates record if vscs target is local and vscs target url is valid" do
      GitHub.flipper[:codespaces_local_target_url_valid].enable
      codespace = build(:codespace, vscs_target: :local, vscs_target_url: "https://codespaces.servicebus.windows.net/monalisa")
      assert_predicate codespace, :valid?
      assert_equal codespace.vscs_target, :local
    end
  end

  context "#devcontainer_path" do
    test "defaults to nil" do
      codespace = build(:codespace)
      assert_nil codespace.devcontainer_path
    end

    test "does not allow invalid values" do
      [
        "devcontainer",
        ".devcontainer/json.json",
        ".devcontainer/a/b/devcontainer.json",
        "a1b2c3.json",
        "..devcontainer.json"
      ].each do |path|
        codespace = build(:codespace, devcontainer_path: path)
        refute codespace.valid?
      end
    end

    test "saves valid values" do
      codespace = build(:codespace, devcontainer_path: ".devcontainer/test/devcontainer.json")
      assert_equal ".devcontainer/test/devcontainer.json", codespace.devcontainer_path
    end
  end

  context "#vscode_url" do
    test "generates correct protocol handler url" do
      codespace = create(:codespace, name: "my-codespace-xyz")
      assert_equal "vscode://github.codespaces/connect?name=my-codespace-xyz&windowId=_blank", codespace.vscode_url
    end
  end

  context "#jetbrains_url" do
    test "generates correct protocol handler url" do
      codespace = create(:codespace, name: "my-codespace-xyz")
      assert_equal "jetbrains-gateway://connect#type=codespaces&codespaceName=my-codespace-xyz", codespace.jetbrains_url
    end
  end

  context ".can_be_deprovisioned_by_user" do
    test "returns expected codespaces" do
      user = create(:user)
      codespace = create(:codespace, owner: user)
      assert_equal 1, Codespace.can_be_deprovisioned_by_user(user).size
      create(:codespace, state: :deprovisioning, owner: user)
      codespace_with_unpushed_changes = create(:codespace, owner: user, environment_data: { git_status: { branch: "master", ahead: 1, hasUnpushedChanges: true } })
      codespace_with_uncommitted_changes = create(:codespace, owner: user, environment_data: { git_status: { branch: "master", ahead: 1, hasUncommittedChanges: true } })
      results = Codespace.can_be_deprovisioned_by_user(user)
      assert_equal [codespace], results
    end
  end

  context "#web_portal_url" do
    test "accounts for vscs_target" do
      prod_codespace = create(:codespace, vscs_target: :production)
      latest_prod_codespace = create(:codespace, vscs_target: :latestprod)
      ppe_codespace = create(:codespace, vscs_target: :ppe)
      latest_ppe_codespace = create(:codespace, vscs_target: :latestppe)
      dev_codespace = create(:codespace, vscs_target: :development)
      latest_dev_codespace = create(:codespace, vscs_target: :latestdev)
      canary_codespace = create(:codespace, vscs_target: :canary)
      local_codespace = create(:codespace, vscs_target: :local, vscs_target_url: "https://codespaces.servicebus.windows.net/monalisa")

      assert prod_codespace.web_portal_url.ends_with?(".github.dev")
      assert prod_codespace.web_portal_url.starts_with?("https://")

      assert latest_prod_codespace.web_portal_url.ends_with?(".latest.github.dev")
      assert latest_prod_codespace.web_portal_url.starts_with?("https://")

      assert ppe_codespace.web_portal_url.ends_with?(".ppe.github.dev")
      assert ppe_codespace.web_portal_url.starts_with?("https://")

      assert latest_ppe_codespace.web_portal_url.ends_with?(".latest-ppe.github.dev")
      assert latest_ppe_codespace.web_portal_url.starts_with?("https://")

      assert dev_codespace.web_portal_url.ends_with?(".dev.github.dev")
      assert dev_codespace.web_portal_url.starts_with?("https://")

      assert latest_dev_codespace.web_portal_url.ends_with?(".latest-dev.github.dev")
      assert latest_dev_codespace.web_portal_url.starts_with?("https://")

      assert canary_codespace.web_portal_url.ends_with?(".canary.github.dev")
      assert canary_codespace.web_portal_url.starts_with?("https://")

      assert local_codespace.web_portal_url.ends_with?(".github.localhost:3000")
      assert local_codespace.web_portal_url.starts_with?("http://")
    end
  end

  context "#merge_environment_data!" do
    test "it handles null environment_data" do
      codespace = create(:codespace)
      codespace.update(environment_data: nil)
      codespace.merge_environment_data!({ friendlyName: "boo" })

      assert_equal "boo", codespace.reload.environment_data.friendly_name
    end

    test "it replaces existing values" do
      codespace = create_codespace_with_environment_details({ friendlyName: "hello" })
      codespace.merge_environment_data!({ friendlyName: "boo" })

      assert_equal "boo", codespace.reload.environment_data.friendly_name
    end

    test "it adds new values" do
      codespace = create_codespace_with_environment_details
      codespace.merge_environment_data!({ friendlyName: "boo" })

      assert_equal "boo", codespace.reload.environment_data.friendly_name
    end

    test "it doesn't overwrite other values" do
      codespace = create_codespace_with_environment_details({ lastStateUpdateReason: "for fun" })
      codespace.merge_environment_data!({ friendlyName: "hello" })

      assert_equal "hello", codespace.reload.environment_data.friendly_name
      assert_equal "for fun", codespace.reload.environment_data.last_state_update_reason
    end

    test "it doesn't affect other codespaces" do
      codespace_1 = create_codespace_with_environment_details({ friendlyName: "hello" })
      codespace_2 = create_codespace_with_environment_details({ friendlyName: "world" })
      codespace_1.merge_environment_data!({ friendlyName: "boo" })

      assert_equal "boo", codespace_1.reload.environment_data.friendly_name
      assert_equal "world", codespace_2.reload.environment_data.friendly_name
    end
  end

  context "#spammy?" do
    test "is not spammy when the owner and billable owner are not spammy", skip_enterprise: true do
      codespace = create(:codespace)
      refute codespace.spammy?
    end

    test "is spammy when the owner is spammy", skip_enterprise: true  do
      codespace = create(:codespace)
      codespace.owner.mark_as_spammy

      codespace.reload
      assert codespace.spammy?
    end

    test "is spammy when the billable owner is spammy", skip_enterprise: true  do
      organization = create(:organization)
      codespace = create(:codespace, billable_owner: organization)

      organization.mark_as_spammy

      codespace.reload
      assert codespace.spammy?
    end

    test "is not spammy when the owner is nil", skip_enterprise: true  do
      codespace = create(:codespace)
      codespace.owner = nil

      refute codespace.spammy?
    end
  end

  context "#ensure_no_blocking_pending_async_operation!" do
    test "doesn't raise when no related operation exists" do
      codespace = create(:codespace)
      assert_nil codespace.ensure_no_blocking_pending_async_operation!
    end

    test "raises an exception if a related operation but has no start or end time" do
      codespace = create(:codespace)
      create(:codespaces_async_operation, codespace: codespace)

      assert_raises Codespaces::AsyncOperation::PendingError do
        codespace.ensure_no_blocking_pending_async_operation!
      end
    end

    test "raises an exception if a related operation but has no end time" do
      codespace = create(:codespace)
      create(:codespaces_async_operation, :started, codespace: codespace)

      assert_raises Codespaces::AsyncOperation::PendingError do
        codespace.ensure_no_blocking_pending_async_operation!
      end
    end

    test "doesn't raise when a related operation exists but it's finished" do
      codespace = create(:codespace)
      create(:codespaces_async_operation, :finished, codespace: codespace)

      assert_nil codespace.ensure_no_blocking_pending_async_operation!
    end

    test "raises when there are both finished and an unfinished operation" do
      codespace = create(:codespace)
      create(:codespaces_async_operation, :finished, codespace: codespace)
      create(:codespaces_async_operation, :started, codespace: codespace)

      assert_raises Codespaces::AsyncOperation::PendingError do
        codespace.ensure_no_blocking_pending_async_operation!
      end
    end
  end

  context "#deletable?" do
    context "actor owns the codespace and flag is enabled" do
      test "returns true when pending" do
        codespace = create(:codespace, owner: @monalisa, repository: @repo, ref: @repo.default_branch, state: :pending, guid: nil)
        assert codespace.deletable?(@monalisa)
      end

      test "returns true when provisioning" do
        codespace = create(:codespace, owner: @monalisa, repository: @repo, ref: @repo.default_branch, state: :provisioning, guid: nil)
        assert codespace.deletable?(@monalisa)
      end

      test "returns true if stuck provisioning" do
        stuck_provisioning_codespace = create(:codespace, :stuck_provisioning, owner: @monalisa, repository: @repo, ref: @repo.default_branch)
        assert stuck_provisioning_codespace.deletable?(@monalisa)
      end
    end

    context "actor doesn't own the codespace" do
      test "returns false when pending" do
        random_user = create(:user)
        codespace = create(:codespace, owner: @monalisa, repository: @repo, ref: @repo.default_branch, state: :pending, guid: nil)
        refute codespace.deletable?(random_user)
      end

      test "returns false when provisioning" do
        random_user = create(:user)
        codespace = create(:codespace, owner: @monalisa, repository: @repo, ref: @repo.default_branch, state: :provisioning, guid: nil)
        refute codespace.deletable?(random_user)
      end

      test "returns true if stuck provisioning" do
        random_user = create(:user)
        stuck_provisioning_codespace = create(:codespace, :stuck_provisioning, owner: @monalisa, repository: @repo, ref: @repo.default_branch)
        assert stuck_provisioning_codespace.deletable?(random_user)
      end
    end
  end

  context "#retention_period" do
    test "is a Duration" do
      codespace = create(:codespace, retention_period_minutes: 70)
      assert_equal "1 hour and 10 minutes", codespace.retention_period.inspect
    end
  end

  context "#instrument_pull_request_updated" do
    test "publishes :ATTACHED_TO_PULL_REQUEST hydro event when a codespace is updated with a pull request" do
      codespace = create(:codespace, repository: @repo)
      refute codespace.pull_request

      codespace.update(pull_request: @pull_request)

      hydro_payload = hydro_messages(schema: "github.codespaces.v0.CodespaceInteraction").last
      assert_equal(:ATTACHED_TO_PULL_REQUEST, hydro_payload[:type])
    end

    test "publishes :DETACHED_FROM_PULL_REQUEST hydro event when a codespace is updated with nil pull request" do
      codespace = create(:codespace, repository: @repo, pull_request: @pull_request)
      codespace.update(pull_request: nil)

      hydro_payload = hydro_messages(schema: "github.codespaces.v0.CodespaceInteraction").last
      assert_equal(:DETACHED_FROM_PULL_REQUEST, hydro_payload[:type])
    end

    test "does not publish hydro event when a codespace updates field that is not pull_request" do
      @codespace.update(environment_data: { friendlyName: "hi" })
      refute_hydro_messages(schema: "github.codespaces.v0.CodespaceInteraction")
    end
  end

  context "#instrument_repository_changed" do
    test "instruments a repo change event when the repo is changed" do
      codespace = create(:codespace)

      GlobalInstrumenter.expects(:instrument).once.with(Codespaces::Events::CODESPACE_REPOSITORY_CHANGED, codespace: codespace)

      codespace.update(repository: @user_public_repo)
    end

    test "doesn't instruments a repo change event when the repo isn't changed" do
      codespace = create(:codespace)
      GlobalInstrumenter.expects(:instrument).never.with(Codespaces::Events::CODESPACE_REPOSITORY_CHANGED, anything)
      codespace.update(display_name: "whacky doodle dandy")
    end
  end

  def create_codespace_with_environment_details(environment_data = {})
    codespace = create(:codespace)
    codespace.update(environment_data: { id: codespace.guid, friendlyName: codespace.name }.merge(environment_data))
    codespace
  end

  test "requires a repository" do
    assert_predicate build(:codespace, repository: @repo), :valid?
    refute_predicate build(:codespace, repository: nil, display_name: "test"), :valid?
  end

  context "#auto_deletion_soon?" do
    test "returns false if no retention period" do
      refute @codespace.auto_deletion_soon?
    end

    test "returns false if retention_expires_at present but retention_period_minutes is nil" do
      @codespace.update!(retention_expires_at: 1.day.from_now, retention_period_minutes: nil)
    end

    test "returns true if less than 25% left on retention period" do
      Timecop.freeze do
        @codespace.update!(shutdown_at: 30.hours.ago, retention_period_minutes: 40.hours.in_minutes)
        assert @codespace.reload.auto_deletion_soon?
      end
    end

    test "returns true if greater than 25% left on retention period if under 24 hours" do
      Timecop.freeze do
        @codespace.update!(shutdown_at: 4.hours.ago, retention_period_minutes: 4.hours.in_minutes)
        assert @codespace.reload.auto_deletion_soon?
      end
    end

    test "returns false if greater than 25% left on retention period" do
      Timecop.freeze do
        @codespace.update!(shutdown_at: 40.hours.ago, retention_period_minutes: 80.hours.in_minutes)
        refute @codespace.reload.auto_deletion_soon?
      end
    end
  end

  context "#notify_socket_subscribers"  do
    test "does not raise an error if no owner" do
      user = create(:user)
      codespace = create(:codespace, owner: user)
      user.destroy!
      assert_nil codespace.reload.notify_socket_subscribers
    end
  end

  context "copilot_workspace" do
    context "#copilot_workspace?" do
      test "returns true if copilot_workspace_id has a non-nil value" do
        codespace = Codespace.new(copilot_workspace_id: "abc123")
        assert codespace.copilot_workspace?
      end

      test "returns false if copilot_workspace_id is nil" do
        codespace = Codespace.new(copilot_workspace_id: nil)
        refute codespace.copilot_workspace?
      end

      test "returns false if copilot_workspace_id is an empty string" do
        codespace = Codespace.new(copilot_workspace_id: "")
        refute codespace.copilot_workspace?
      end

      test "returns false if copilot_workspace_id is 'hadron'" do
        codespace = Codespace.new(copilot_workspace_id: "hadron")
        refute codespace.copilot_workspace?
      end
    end
  end
end unless GitHub.enterprise?
