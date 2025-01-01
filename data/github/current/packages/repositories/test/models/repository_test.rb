# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryTest < GitHub::TestCase
  include HydroTestHelpers
  include RepositoriesTestHelper
  include EnvironmentTestHelper
  self.these_tests_are_order_dependent_and_yearn_to_be_random

  fixtures do
    @mojombo  = create(:user, login: "mojombo2", plan: "medium")
    @defunkt  = create(:user, login: "defunkt",  plan: "medium")
    @pj       = create(:user, login: "pj",       plan: "medium")
    @maddox   = create(:user, login: "maddox")
    @admin    = create(:user, login: "d12")
    @admin_2  = create(:user, login: "iolsen")
    @member   = create(:user, login: "member")

    @outside_collaborator = create(:user)

    @org = create(:organization, business: create(:business))
    @org.add_admin(@admin)
    @org.add_admin(@admin_2)
    @org.add_member(@member, action: :read)

    @grit     = create(:repository, name: "grit",     owner: @mojombo)
    @ambition = create(:private_repository, name: "ambition", owner: @defunkt)
    @simple   = create(:repository, name: "simple",   owner: @defunkt)
    @facebox  = create(:repository, name: "facebox",  owner: @defunkt)
    @internal = create(:internal_repository, owner: @org)
    @internal.allow_private_repository_forking(actor: @admin)
    create(:collaborator, collaborator: @outside_collaborator, repository: @internal)

    create :user_email, user: @mojombo, email: "tom@mojombo.com"
    create :user_email, user: @defunkt, email: "chris@ozmm.org"
    create :user_email, user: @pj,      email: "pjhyett@gmail.com"
    User.create_ghost

    if GitHub.enterprise?
      @biz = Business.first
    else
      @biz = create(:business, name: "Salsa, Inc", owners: [@maddox], seats: 20)
    end
    @biz_org = create(:organization, plan: GitHub::Plan.business_plus, admins: [@maddox], business: @biz)
  end

  setup do
    @grit.update_default_branch("master")
  end

  context "ordered_by_array_index scope" do
    test "sorts by the given repo ID order" do
      sorted_repo_ids = [@ambition.id, @grit.id, @facebox.id, @simple.id]

      result = Repository.ordered_by_array_index(sorted_repo_ids)
        .where(id: sorted_repo_ids)

      assert_equal [@ambition, @grit, @facebox, @simple], result
    end
  end

  context "#with_names_with_owners" do
    test "returns matching repositories" do
      nwos = [
        @grit.nwo,
        @simple.nwo,
        @internal.nwo.upcase, # We test with an upcased NWO too to make sure the lookup is case-insensitive.
      ]

      results = Repository.with_names_with_owners(nwos)

      assert_equal nwos.size, results.size
      assert_includes results, @grit
      assert_includes results, @simple
      assert_includes results, @internal
    end

    test "supports both unique owner login and display owner login scoped to current tenant" do
      on_multi_tenant_enterprise do
        user1 = create(:emu, login: "mtodd")
        business1 = user1.enterprise_managed_business

        user2 = create(:emu, login: "mtodd")
        business2 = user2.enterprise_managed_business

        repo1 =  create(:repository, owner: user1, name: "repo1")
        repo2 =  create(:repository, owner: user2, name: "repo1")

        refute_equal(business1, business2)

        GitHub::CurrentTenant.set(business1)
        repos = Repository.with_names_with_owners(["mtodd_#{business1.shortcode}/repo1"]).to_a
        assert_equal [repo1], repos
        repos = Repository.with_names_with_owners(["mtodd/repo1"]).to_a
        assert_equal [repo1], repos
        repos = Repository.with_names_with_owners(["mtodd/repo1", "mtodd_#{business1.shortcode}/repo1"]).to_a
        assert_equal [repo1], repos

        GitHub::CurrentTenant.set(business2)
        repos = Repository.with_names_with_owners(["mtodd_#{business2.shortcode}/repo1"]).to_a
        assert_equal [repo2], repos
        repos = Repository.with_names_with_owners(["mtodd/repo1"]).to_a
        assert_equal [repo2], repos
        repos = Repository.with_names_with_owners(["mtodd/repo1", "mtodd_#{business2.shortcode}/repo1"]).to_a
        assert_equal [repo2], repos
      ensure
        GitHub::CurrentTenant.remove
      end
    end
  end

  context "#owner_default_new_repo_branch" do
    test "returns the github default branch setting when owner is missing" do
      @grit.owner.delete
      assert_equal Configurable::DefaultNewRepoBranch.recommended_name,
        @grit.owner_default_new_repo_branch
    end

    test "returns the github default branch setting for user-owned repo when user has no setting" do
      @mojombo.clear_default_new_repo_branch(actor: @mojombo)
      assert_equal @mojombo, @grit.owner
      assert_equal Configurable::DefaultNewRepoBranch.recommended_name,
        @grit.owner_default_new_repo_branch
    end

    test "returns the user owner's default branch setting" do
      @mojombo.set_default_new_repo_branch("pickles", actor: @mojombo)
      assert_equal @mojombo, @grit.owner
      assert_equal "pickles", @grit.owner_default_new_repo_branch
    end

    test "returns the github default branch setting for org-owned repo when org has no setting" do
      @org.clear_default_new_repo_branch(actor: @admin)
      assert_equal_owner @org, @internal.owner
      assert_equal Configurable::DefaultNewRepoBranch.recommended_name,
        @internal.owner_default_new_repo_branch
    end

    test "returns the org owner's default branch setting" do
      @org.set_default_new_repo_branch("pickles", actor: @admin)
      assert_equal_owner @org, @internal.owner
      assert_equal "pickles", @internal.owner_default_new_repo_branch
    end

    test "returns the github default branch setting for a business org-owned repo when business and org have no setting" do
      @biz_org.clear_default_new_repo_branch(actor: @maddox)
      @biz.clear_default_new_repo_branch(actor: @maddox)
      biz_org_repo = create(:repository, owner: @biz_org)
      assert_equal Configurable::DefaultNewRepoBranch.recommended_name,
        biz_org_repo.owner_default_new_repo_branch
    end

    test "returns the business's default branch setting for a business org-owned repo when org does not have setting itself" do
      @biz_org.clear_default_new_repo_branch(actor: @maddox)
      @biz.set_default_new_repo_branch("pickles", actor: @maddox)
      biz_org_repo = create(:repository, owner: @biz_org)
      assert_equal "pickles", biz_org_repo.owner_default_new_repo_branch
    end

    test "returns the org's default branch setting for a business org-owned repo when org has setting itself and business setting is not enforced" do
      biz_org_repo = create(:repository, owner: @biz_org)
      @biz_org.set_default_new_repo_branch("org-setting", actor: @maddox)
      @biz.set_default_new_repo_branch("business-setting", actor: @maddox, enforce: false)
      assert_equal "org-setting", biz_org_repo.owner_default_new_repo_branch
    end

    test "returns the business's default branch setting for a business org-owned repo when org has setting itself but business setting is enforced" do
      biz_org_repo = create(:repository, owner: @biz_org)
      @biz_org.set_default_new_repo_branch("org-setting", actor: @maddox)
      @biz.set_default_new_repo_branch("business-setting", actor: @maddox, enforce: true)
      assert_equal "business-setting", biz_org_repo.owner_default_new_repo_branch
    end

    context "snapshot_license_state callback" do
      test "enqueues SnapshotLicensesJob on billing environments", skip_unless: :billing_enabled? do
        biz_org_repo = create(:repository, owner: @biz_org, active: true)
        assert_enqueued_jobs 1, only: Licensing::SnapshotLicensesJob do
          biz_org_repo.update(active: false)
        end
      end

      test "does not enqueue SnapshotLicensesJob on Proxima" do
        on_multi_tenant_enterprise do
          biz_org_repo = create(:repository, owner: @biz_org)
          assert_no_enqueued_jobs only: Licensing::SnapshotLicensesJob do
            biz_org_repo.update(active: false)
          end
        end
      end

      test "does not enqueue SnapshotLicensesJob on GHES" do
        on_enterprise do
          biz_org_repo = create(:repository, owner: @biz_org)
          assert_no_enqueued_jobs only: Licensing::SnapshotLicensesJob do
            biz_org_repo.update(active: false)
          end
        end
      end
    end

    if GitHub.single_business_environment?
      test "returns the global business setting for a user-owned repository" do
        @mojombo.clear_default_new_repo_branch(actor: @mojombo)
        @biz.set_default_new_repo_branch("business-setting", actor: @maddox)
        user_repo = create(:repository, owner: @mojombo)
        assert_equal "business-setting", user_repo.owner_default_new_repo_branch
      end

      test "returns the global business setting for a user-owned repository when user has setting but business's is enforced" do
        @mojombo.set_default_new_repo_branch("user-setting", actor: @mojombo)
        @biz.set_default_new_repo_branch("business-setting", actor: @maddox, enforce: true)
        user_repo = create(:repository, owner: @mojombo)
        assert_equal "business-setting", user_repo.owner_default_new_repo_branch
      end
    end
  end

  context "owner_login" do
    test "writes the login of the owner on creation for organization owners" do
      repository = create(:repository, owner: @org)

      assert_equal @org.login, repository.owner_display_login
    end

    test "writes the login of the owner on creation for user owners" do
      repository = create(:repository, owner: @mojombo)

      assert_equal @mojombo.login, repository.owner_display_login
    end

    test "should update when transferring a repository" do
      repository = create(:repository, owner: @defunkt)

      repository.transfer_ownership_to(@admin, actor: @defunkt)

      assert_equal @admin.login, repository.reload.owner_display_login
    end

    test "should update when owner login changes" do
      repository = create(:repository)
      user = repository.owner

      user.rename!("paolo")

      assert_equal "paolo", repository.reload.owner_display_login
    end

    test "should update if restoring from deletion and the owner login changed in the meantime" do
      repository = create(:repository)
      user = repository.owner

      GitRPC::Client.any_instance.stubs(:gitbackups_restore).with do |spec|
        GitHub::GitbackupsTestHelper.restore_from_example(spec)
      end

      repository.remove(user, synchronous: true)
      user.rename!("alma")
      Repository.restore(repository.id, actor: user)

      assert_equal "alma", repository.reload.owner_display_login
    end

    test "direct changes to owner_id reflect change in login" do
      new_owner = create(:user)

      repository = create(:repository)
      repository.update(owner: new_owner)

      assert_equal new_owner.login, repository.reload.owner_display_login
    end

    test "defers to owner.slug if not set" do
      repository = create(:repository)
      repository.update_columns(owner_login: nil) # no callbacks

      assert_equal repository.owner.to_s, repository.owner_display_login
    end

    test "does not fail when user has been deleted" do
      repository = create(:repository)
      repository.owner.destroy
      repository.update_columns(owner_login: nil) # no callbacks
      repository = Repository.find(repository.id)

      assert_nil repository.owner_login
    end
  end

  context "#name_with_owner_for_api" do
    test "returns name_with_owner for non multi tenant environments", skip_enterprise: true do
      user = create :emu
      repo = create :repository, owner: user
      assert_equal repo.name_with_owner, repo.name_with_display_owner
      assert_equal repo.name_with_owner, repo.name_with_owner_for_api
    end

    test "return name_with_owner for multi tenant internal calls", skip_enterprise: true do
      on_multi_tenant_enterprise do
        GitHub.stubs(:proxima_internal_api_unique_logins_required?).returns(true)
        user = create :emu

        GitHub::CurrentTenant.set(user.enterprise_managed_business)

        repo = create :repository, owner: user
        refute_equal repo.name_with_owner, repo.name_with_display_owner
        assert_equal repo.name_with_owner, repo.name_with_owner_for_api
      end
    end

    test "returns name_with_display_owner for multi tenant non-internal calls", skip_enterprise: true do
      on_multi_tenant_enterprise do
        user = create :emu
        repo = create :repository, owner: user

        GitHub::CurrentTenant.set(user.enterprise_managed_business)

        refute_equal repo.name_with_owner, repo.name_with_display_owner
        assert_equal repo.name_with_display_owner, repo.name_with_owner_for_api
      end
    end

    test "returns unique name_with_owner for multi tenant non-internal calls when use: :unique", skip_enterprise: true do
      on_multi_tenant_enterprise do
        user = create :emu
        repo = create :repository, owner: user

        GitHub::CurrentTenant.set(user.enterprise_managed_business)

        refute_equal repo.name_with_owner, repo.name_with_display_owner
        assert_equal repo.name_with_display_owner, repo.name_with_owner_for_api
        assert_equal repo.name_with_owner, repo.name_with_owner_for_api(use: :unique)
      end
    end

    test "returns display name_with_owner for multi tenant non-internal calls when use: :display", skip_enterprise: true do
      on_multi_tenant_enterprise do
        user = create :emu
        repo = create :repository, owner: user

        GitHub::CurrentTenant.set(user.enterprise_managed_business)

        refute_equal repo.name_with_owner, repo.name_with_display_owner
        assert_equal repo.name_with_display_owner, repo.name_with_owner_for_api
        assert_equal repo.name_with_display_owner, repo.name_with_owner_for_api(use: :display)
      end
    end
  end

  context "#readonly_name_with_owner_for_api" do
    test "returns name_with_owner for non multi tenant environments", skip_enterprise: true do
      user = create :emu
      repo = create :repository, owner: user
      assert_equal repo.name_with_owner, repo.name_with_display_owner
      assert_equal repo.name_with_owner, repo.readonly_name_with_owner_for_api
    end

    test "return name_with_owner for multi tenant internal calls", skip_enterprise: true do
      on_multi_tenant_enterprise do
        GitHub.stubs(:proxima_internal_api_unique_logins_required?).returns(true)
        user = create :emu

        GitHub::CurrentTenant.set(user.enterprise_managed_business)

        repo = create :repository, owner: user
        refute_equal repo.name_with_owner, repo.name_with_display_owner
        assert_equal repo.name_with_owner, repo.readonly_name_with_owner_for_api
      end
    end

    test "returns name_with_display_owner for multi tenant non-internal calls", skip_enterprise: true do
      on_multi_tenant_enterprise do
        user = create :emu
        repo = create :repository, owner: user

        GitHub::CurrentTenant.set(user.enterprise_managed_business)

        refute_equal repo.name_with_owner, repo.name_with_display_owner
        assert_equal repo.name_with_display_owner, repo.readonly_name_with_owner_for_api
      end
    end

    test "returns unique name_with_owner for multi tenant non-internal calls when :unique true", skip_enterprise: true do
      on_multi_tenant_enterprise do
        user = create :emu
        repo = create :repository, owner: user

        GitHub::CurrentTenant.set(user.enterprise_managed_business)

        refute_equal repo.name_with_owner, repo.name_with_display_owner
        assert_equal repo.name_with_display_owner, repo.readonly_name_with_owner_for_api
        assert_equal repo.name_with_owner, repo.readonly_name_with_owner_for_api(use: :unique)
      end
    end
  end

  context "#readonly_name_with_display_owner" do
    test "returns name_with_owner for non multi tenant environments", skip_enterprise: true do
      user = create :emu
      repo = create :repository, owner: user
      assert_equal repo.name_with_owner, repo.name_with_display_owner
      assert_equal repo.name_with_owner, repo.readonly_name_with_display_owner
    end

    test "return name_with_display_owner for multi tenant internal calls", skip_enterprise: true do
      on_multi_tenant_enterprise do
        user = create :emu

        GitHub::CurrentTenant.set(user.enterprise_managed_business)

        repo = create :repository, owner: user
        refute_equal repo.name_with_owner, repo.name_with_display_owner
        assert_equal repo.name_with_display_owner, repo.readonly_name_with_display_owner
      end
    end
  end

  context "#valid_branch?" do
    test "true when given a branch name that exists in the repository" do
      example_repo :simple, @grit
      assert @grit.valid_branch?(@grit.default_branch)
    end

    test "false when given a branch name that doesn't exist in the repository" do
      example_repo :simple, @grit
      refute @grit.valid_branch?("ThisBranchDoesNotExist")
    end

    test "true when given a sha that exists in the repository" do
      example_repo :simple, @grit
      assert @grit.valid_branch?("cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24")
    end

    test "true when given a short sha that exists in the repository" do
      example_repo :simple, @grit
      assert @grit.valid_branch?("cdf4526")
    end

    test "false when given a sha that doesn't exist in the repository" do
      example_repo :simple, @grit
      refute @grit.valid_branch?("f8081c2c6ff13d59d146dd901ad09f3bf4e4972c")
    end
  end

  test "deletes branch rename when repository is purged" do
    example_repo :mojombo_grit, @grit
    rename = create(:repository_branch_rename, repository: @grit, old_name: "master")

    assert_difference("RepositoryBranchRename.count", -1) do
      perform_enqueued_jobs(only: DestroyDependentRecordsJob) do
        rename.repository.remove(@member, synchronous: true)
        rename.repository.purge(synchronous: true)
      end
    end

    refute RepositoryBranchRename.exists?(rename.id)
  end

  context "templates and clones" do
    test "deletes repository clones when template repo is deleted" do
      template_repo = create(:repository, template: true)
      repo_clone = create(:repository_clone, template_repository: template_repo)

      template_repo.remove(template_repo.owner, synchronous: true)

      assert_difference("RepositoryClone.count", -1) do
        perform_enqueued_jobs(only: [DeleteDependentRecordsJob]) { template_repo.purge(synchronous: true) }
      end

      refute RepositoryClone.exists?(repo_clone.id)
    end

    test "deletes repository clone when clone repo is deleted" do
      clone_repo = create(:repository)
      repo_clone = create(:repository_clone, clone_repository: clone_repo)

      assert_difference("RepositoryClone.count", -1) do
        clone_repo.destroy
      end

      refute RepositoryClone.exists?(repo_clone.id)
    end
  end

  context "#disabled_access_reason" do
    test "returns reason record when type matches class name" do
      repo = create(:repository)
      reason = create(:disabled_access_reason, flagged_item_type: "Repository",
                      flagged_item_id: repo.id)

      assert_equal reason, repo.disabled_access_reason
    end

    test "returns reason record when type is lowercase class name" do
      repo = create(:repository)
      reason = create(:disabled_access_reason, flagged_item_type: "repository",
                      flagged_item_id: repo.id)

      assert_equal reason, repo.disabled_access_reason
    end

    test "returns nil when repo has no disabled access reason" do
      repo = create(:repository)
      assert_nil repo.disabled_access_reason
    end
  end

  test "deletes CloseIssueReferences on destroy" do
    ref = create(:close_issue_reference)

    repo = ref.issue_repository
    repo.remove(repo.owner, synchronous: true)

    assert_difference("CloseIssueReference.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { repo.purge(synchronous: true) }
    end

    refute CloseIssueReference.exists?(ref.id)
  end

  unless GitHub.enterprise?
    test "github/github can never be public" do
      github = create(:organization, login: "github")
      repo   = create(:private_repository, name: "github", owner: github)

      GitHub.reset_never_public_network_ids

      assert !repo.public?

      repo.public = true
      repo.save

      assert !repo.public?
    end
  end

  test "can't end in .git" do
    assert_valid @grit
    @grit.name = "newgrit.git"
    @grit.save
    assert_equal "newgrit", @grit.name
  end

  test "can't end in .wiki" do
    assert_valid @grit
    @grit.name = "newgrit.wiki"
    assert !@grit.valid?
  end

  %w( . .. followers following repositories ).each do |name|
    test "can't use #{name.inspect} as the name" do
      assert_valid @grit
      @grit.name = name
      assert !@grit.valid?
    end
  end

  test "name must be unique" do
    repo  = create(:repository)
    assert repo.valid?

    repo2 = build(:repository, owner: repo.owner, name: repo.name + "-extra")
    assert repo2.valid?

    repo3 = build(:repository, owner: repo.owner, name: repo.name)
    assert !repo3.valid?
  end

  context "disabled?" do
    test "returns true when user is trade restricted and repo is private" do
      ofac_user = create(:paid_user)
      repo = create(:private_repository, owner: ofac_user)
      ofac_user.trade_controls_restriction.full!

      assert repo.disabled?
    end

    test "returns true when the viewer is trade restricted and viewing a non-flagged org's private repo" do
      org = create(:organization)
      viewer = org.admins.first
      viewer.trade_controls_restriction.full!

      repo = create(:private_repository, owner: org)

      assert repo.disabled?(viewer: viewer)
    end

    test "returns false when the viewer is not trade restricted and viewing a non-flagged orgs's private repo" do
      org = create(:organization)
      viewer = org.admins.first

      repo = create(:private_repository, owner: org)

      refute repo.disabled?(viewer: viewer)
    end

    test "returns true when the viewer is not trade restricted and viewing a tier_1 flagged orgs's private repo" do
      org = create(:organization)

      viewer = org.admins.first

      repo = create(:private_repository, owner: org)
      org.trade_controls_restriction.tier_1!

      assert repo.disabled?(viewer: viewer)
    end

    test "returns false when the viewer is not trade restricted and viewing a tier_0 flagged orgs's private repo" do
      org = create(:organization)

      viewer = org.admins.first

      repo = create(:private_repository, owner: org)
      org.trade_controls_restriction.tier_0!

      refute repo.disabled?(viewer: viewer)
    end

    test "returns false when the actor is not set and not trade restricted on a non-flagged user's private repo" do
      org = create(:organization)
      repo = create(:private_repository, owner: org)

      assert_equal  User.ghost, repo.actor
      refute_predicate repo, :disabled?
    end
  end

  context "async_disabled?" do
    test "it is false on a private repo with enabled user" do
      user = create :user
      repo = create(:private_repository, owner: user)

      refute repo.async_disabled?.sync
    end

    test "it is false on a private repo with disabled user" do
      user = create :user
      repo = create(:private_repository, owner: user)

      user.disable!

      refute repo.async_disabled?.sync
    end

    test "it is false on a private repo with an enabled org" do
      org = create :organization
      repo = create(:private_repository, owner: org)

      refute repo.async_disabled?.sync
    end

    test "it is false on a private repo with disabled org" do
      # private repos are free now, and are no longer disabled with billing locks
      org = create :organization
      repo = create(:private_repository, owner: org)

      org.disable!

      refute repo.async_disabled?.sync
    end

    test "it is false for a public repo on a disabled org" do
      org = create :organization
      repo = create(:public_repository, owner: org)

      org.disable!

      refute repo.async_disabled?.sync
    end

  end

  context "description" do
    test "valid descriptions are valid" do
      [nil, "boom", "some description", "®hø∂å∂ is my fave techno dj"].each do |desc|
        repo = build(:repository, owner: @maddox, description: desc)
        assert repo.valid?, "repo should be valid but #{repo.errors.full_messages}"
      end
    end

    test "cannot have control characters" do
      repo = build(:repository, owner: @maddox, description: "some descripton")
      ["\x10", "\00"].each do |str|
        repo.description = "#{repo.description}#{str}"
        refute repo.valid?, "should be invalid with #{repo.description.inspect}"
        assert_equal "control characters are not allowed", repo.errors[:description].first
      end
    end

    test "new descriptions cannot be longer than max character length" do
      repo = build(:repository, owner: @maddox, description: "a" * (::Repository::DESCRIPTION_CHAR_LIMIT + 1))
      refute repo.valid?, "should be invalid with #{repo.description.inspect}"
      # The 350 is set by the `::Repository::DESCRIPTION_CHAR_LIMIT` constant. If the constant is changed,
      # this test will fail, since the 350 character limit was chosen to match the UI formatting limit used
      # in `TextHelper.formatted_repo_description`.
      assert_equal "cannot be more than 350 characters", repo.errors[:description].first
    end

    test "existing descriptions longer than max character length do not cause validation errors" do
      repo = build(:repository, owner: @maddox, description: "a" * (::Repository::DESCRIPTION_CHAR_LIMIT + 1))
      repo.save(validate: false)
      repo.name = "new-name"
      assert repo.save, "should still be able to save repository with invalid description length"
    end

    test "emojis are valid" do
      description = "🎉 some description"

      repo = build(:repository, owner: @maddox, description: description)
      assert repo.valid?
    end

    test "legacy repos with invalid descriptions are okay" do
      repo = create(:repository, owner: @maddox, description: "legacy")
      [GRIN_EMOJI, "\x10"].each do |invalid|
        repo.update_column :description, "legacy #{invalid}"
        assert repo.valid?, "should be valid with description #{repo.description}"
        repo.name = "new-name"
        assert repo.save, "should still be able to save repository with invalid description"
      end
    end

    test "forking a legacy repo with an invalid description scrubs out bad characters" do
      repo = create(:repository, owner: @maddox, description: "legacy")
      repo.update_column :description, "legacy \x10"
      repo.reload
      forked_repo = create(:fork_repository, forker: @defunkt, fork_repo: repo)
      assert_valid forked_repo
      assert_equal "legacy ", forked_repo.description
    end

    test "renders as HTML" do
      repo = build(:repository, description: "with :smile: emoji and links https://github.com")
      result = Nokogiri::HTML.parse(repo.description_html)

      assert_includes repo.description_html, "😄"
      assert_equal "https://github.com", result.at_css("a").content
      assert_equal "https://github.com", result.at_css("a")["href"]
    end

    test "renders as truncated HTML" do
      repo = build(:repository, description: "https://github.com :tada: and a bunch of other stuff")

      short_html = repo.short_description_html(limit: 25)
      assert_equal short_html, repo.async_short_description_html(limit: 25).sync

      refute_includes short_html, "other stuff"
      assert_match(/…$/, short_html)

      result = Nokogiri::HTML.parse(short_html)
      assert_nil result.at_css("a")
      assert_includes short_html, "🎉"
    end
  end

  test "event_context returns serialized repository" do
    context = @ambition.event_context

    assert_equal @ambition.name_with_owner, context[:repo]
    assert_equal @ambition.id, context[:repo_id]
  end

  test "enqueues manifest initialization job when repository is unarchived", skip_enterprise: true do
    assert @grit.dependency_graph_enabled?

    @grit.set_archived(synchronous: true)

    @grit.unset_archived(synchronous: true)

    assert_equal @grit.archived?, false

    assert_enqueued_with job: RepositoryDependencyManifestInitializationJob, args: ->(job_args) do
      [@grit.id] == job_args
    end
  end

  context "starred_repo_count" do
    test "increments_stargazer_count_correctly" do
      @ambition.add_member(@pj)
      assert_difference(-> { @ambition.reload.stargazer_count }) do
        @pj.star(@ambition)
      end

      assert_difference(-> { @ambition.reload.stargazer_count }, -1) do
        @pj.unstar(@ambition)
      end
    end
  end


  test "cant be created without a user" do
    assert Repository.create(name: "oogler")
  end

  test "has error when pre-receive hook fails" do
    Repository::TemplateInitializer.any_instance.stubs(:perform).raises(Git::Ref::HookFailed.new("stdout from a failing hook"))
    result = Repository.handle_creation(@defunkt, @defunkt.display_login, { name: "oogler" })
    assert_equal "stdout from a failing hook", result.repository.template_hook_failure
  end

  test "repo hooks with filters name != `web`" do
    repo = create(:repository, name: "rails", owner: @defunkt)

    @hook = create :hook, :web,
      active: true,
      installation_target: repo,
      config: { "url" => "http://example.com", "secret" => "donottell", "address" => "user@github.com" },
      events: %w(push),
      creator: @user
    assert_equal repo.hooks.length, 1
    hook = repo.hooks.first
    hook.name = "email"
    hook.save!
    repo.hooks.reload
    assert_equal repo.hooks.length, 0
  end

  test "normalizes the project name" do
    user = create(:user)
    repo = create(:repository, name: "Merb Core", owner: user)
    assert_equal "Merb-Core", repo.name
    repo = create(:repository, name: "Ambition", owner: user)
    assert_equal "Ambition", repo.name
    repo = create(:repository, name: "Linux-2.6", owner: user)
    assert_equal "Linux-2.6", repo.name
  end

  test "name must be uniq" do
    repo = Repository.new(name: "rails", owner: @defunkt, expected_creation: true)
    assert repo.save

    repo = Repository.new(name: "rails", owner: @defunkt, expected_creation: true)
    assert !repo.save
    assert repo.errors[:name].any?
  end

  test "normalized name still must be uniq" do
    repo = create(:repository, name: "Rails JS", owner: @defunkt)
    assert repo.save
    assert_equal "Rails-JS", repo.name

    repo = Repository.new(name: "Rails JS", owner: @defunkt)
    assert !repo.save
    assert repo.errors[:name].any?
  end

  test "destroying works" do
    @grit.owner.star @grit
    assert @grit.stargazer_count > 0
    Search::ClusterStatus.new.enable_code_search_indexing
    @grit.remove(@defunkt, synchronous: true)

    assert_enqueued_with(job: RemoveFromSearchIndexJob,
                         args: ["commit", @grit.id])
    assert_enqueued_with(job: RemoveFromSearchIndexJob,
                         args: ["repository", @grit.id])
    assert_enqueued_with(job: RemoveFromSearchIndexJob,
                         args: ["bulk_issues", @grit.id])
    assert_enqueued_with(job: RemoveFromSearchIndexJob,
                         args: ["bulk_discussions", @grit.id])
    assert_enqueued_with(job: RemoveFromSearchIndexJob,
                         args: ["bulk_pull_requests", @grit.id])

    if GitHub.use_elastomer_code_search?
      assert_enqueued_with(job: RemoveFromSearchIndexJob,
                           args: ["code", @grit.id])
    else
      code_job_matcher = ->(job_args) do
        job_args[:job] == RemoveFromSearchIndexJob &&
          job_args[:args][0] == "code" &&
          job_args[:args][1] == @grit.id
      end
      assert_no_enqueued_jobs(only: code_job_matcher)
    end
  end

  test "destroying removes stale subscriptions" do
    list_subscriber = create(:user)
    GitHub.newsies.subscribe_to_list(list_subscriber, @grit)
    assert GitHub.newsies.subscription_status(list_subscriber, @grit).subscribed?

    only = [ClearAbilitiesJob, Newsies::DeleteAllForListJob, RemoveFromSearchIndexJob]
    perform_enqueued_jobs(only: only) do
      only = [ClearAbilitiesJob, Newsies::DeleteAllForListJob, RemoveFromSearchIndexJob]
      perform_enqueued_jobs(only: only) do
        @grit.destroy!
      end
    end

    refute GitHub.newsies.subscription_status(list_subscriber, @grit).subscribed?
  end

  test "knows who can admin" do
    org = create :organization, plan: "bronze"
    repo = create(:private_repository, owner: org)
    team = create :team, organization: org, permission: "push"
    status = team.add_repository(repo, "admin")
    assert status.success?, status.status.to_s
    team.add_member @defunkt
    assert repo.pullable_by?(@defunkt)
    assert repo.pushable_by?(@defunkt)
    assert repo.adminable_by?(@defunkt)
    refute repo.pullable_by?(@mojombo)
  end

  test "knows who can pull when legacy permissions are greater than direct permissions" do
    org = create :organization, plan: "bronze"
    repo = create(:private_repository, owner: org)
    team = create :team, organization: org, permission: "admin"
    status = team.add_repository(repo, "pull")
    assert status.success?, status.status.to_s
    team.add_member @defunkt
    assert repo.pullable_by?(@defunkt)
    refute repo.pushable_by?(@defunkt)
    refute repo.adminable_by?(@defunkt)
  end

  test "knows who can push when legacy permissions are greater than direct permissions" do
    org = create :organization, plan: "bronze"
    repo = create(:private_repository, owner: org)
    team = create :team, organization: org, permission: "admin"
    status = team.add_repository(repo, "push")
    assert status.success?, status.status.to_s
    team.add_member @defunkt
    assert repo.pullable_by?(@defunkt)
    assert repo.pushable_by?(@defunkt)
    refute repo.adminable_by?(@defunkt)
  end

  test "knows who can push when legacy permissions are lesser than direct permissions" do
    org = create :organization, plan: "bronze"
    repo = create(:private_repository, owner: org)
    team = create :team, organization: org, permission: "pull"
    status = team.add_repository(repo, "push")
    assert status.success?, status.status.to_s
    team.add_member @defunkt
    assert repo.pullable_by?(@defunkt)
    assert repo.pushable_by?(@defunkt)
    refute repo.adminable_by?(@defunkt)
  end

  test "validates gitignore templates" do
    repo = Repository.new(name: "rails1", owner: @defunkt, auto_init: true, gitignore_template: "Python", expected_creation: true)
    assert repo.save
    assert !repo.errors.any?
    assert_equal "Python", repo.gitignore_template

    repo = Repository.new(name: "rails2", owner: @defunkt, auto_init: true, gitignore_template: "foo", expected_creation: true)
    assert !repo.save
    assert repo.errors[:gitignore_template].any?
  end

  test "validates license templates" do
    repo = Repository.new(name: "rails1", owner: @defunkt, auto_init: true, license_template: "mit", expected_creation: true)
    assert repo.save
    assert !repo.errors.any?
    assert_equal "mit", repo.license_template

    repo = Repository.new(name: "rails2", owner: @defunkt, auto_init: true, license_template: "foo", expected_creation: true)
    assert !repo.save
    assert repo.errors[:license_template].any?
  end

  test "is always present" do
    assert Repository.new.present?
  end

  test "is never blank" do
    refute Repository.new.blank?
  end

  test "is empty when not on disk" do
    assert Repository.new.empty?
  end

  context "#writable? and #async_writable?" do
    test "returns true if not locked or archived" do
      repo = create(:repository)
      assert_predicate repo, :writable?
      assert repo.async_writable?.sync
    end

    test "returns false if the repo is locked" do
      repo = create(:repository)
      repo.lock!("moving")

      refute_predicate repo, :writable?
      refute repo.async_writable?.sync
    end

    test "returns false if the repo is locked on migration" do
      repo = create(:repository)
      repo.lock_for_migration

      refute_predicate repo, :writable?
      refute repo.async_writable?.sync
    end

    test "returns false if the repo is archived" do
      repo = create(:repository)
      repo.set_archived

      refute_predicate repo, :writable?
      refute repo.async_writable?.sync
    end

    test "returns false if the repo's access is disabled" do
      repo = create(:repository)
      repo.access.disable("size", repo.owner, dmca_takedown: "http://foobar.com")

      refute_predicate repo, :writable?
      refute repo.async_writable?.sync
    end

    test "returns false if the repo is public and owned by trade control restricted organization" do
      flagged_owner = create(:organization)
      repo          = create(:repository, owner: flagged_owner)

      flagged_owner.trade_controls_restriction.full!

      refute_predicate repo, :writable?
      refute repo.async_writable?.sync
    end
  end

  test "is not adminable by an organization" do
    org = create(:organization)
    repo = create(:repository, owner: org)

    refute repo.adminable_by?(org)
  end

  test "#flipper_id returns the correct ID" do
    assert_equal "Repository:#{@grit.id}", @grit.flipper_id
    assert_equal "Repository:#{@facebox.id}", @facebox.flipper_id
  end

  test ".organization_member_private_forks scope does not include public repositories" do
    org = create(:organization)
    org.allow_private_repository_forking(actor: org.admins.first)

    member = create(:user)
    org.add_member(member)
    repo = create(:public_repository, owner: org)
    member_fork = create(:fork_repository, forker: member, fork_repo: repo)

    # Public forks of organization repositories do not set `organization_id` at
    # this time so I'm having to force to get the test to fail the way I expect
    # it to. The test should pass after I add the `private` scope to it.
    member_fork.update(organization_id: org.id)

    refute_includes Repository.organization_member_private_forks(org, [member]), member_fork
  end

  test ".with_organization scope excludes repos with no linked organization" do
    org = create(:organization)
    org.allow_private_repository_forking(actor: org.admins.first)

    public_with_org = create(:repository, owner: org)
    private_with_org = create(:private_repository, owner: org)
    create(:fork_repository, forker: org.admin, fork_repo: public_with_org)
    private_fork = create(:fork_repository, forker: org.admin, fork_repo: private_with_org)
    # repository without an org
    create(:repository)

    repos_with_an_organization = Repository.with_organization

    expected_repos = [
      public_with_org,
      private_with_org,
      private_fork,
      @internal, # Repository created in the fixtures under an organization
    ]
    assert_same_elements expected_repos, repos_with_an_organization
  end

  context ".excluding_organization_ids scope" do
    test "includes Repos that aren't in the supplied list" do
      fake_excluded_org_id = 1
      included_org = create(:organization)
      included_repo = create(:repository, owner: included_org)

      results = Repository.excluding_organization_ids([fake_excluded_org_id])

      assert_includes results, included_repo
    end

    test "excludes Repos that are in the supplied list" do
      excluded_org = create(:organization)
      excluded_repo = create(:repository, owner: excluded_org)

      results = Repository.excluding_organization_ids([excluded_org.id])

      refute_includes results, excluded_repo
    end

    test "includes Repos that don't belong to an Organization" do
      fake_excluded_org_id = 1
      repo_without_org = create(:repository)
      repo_without_org.update_columns(organization_id: nil)

      results = Repository.excluding_organization_ids([fake_excluded_org_id])

      assert_includes results, repo_without_org
    end
  end

  context "#private=" do
    test "sets made_public_at to nil when privatized" do
      repo = create(:repository, made_public_at: 3.days.ago)
      refute_nil repo.made_public_at

      repo.private = true
      repo.save!
      assert_nil repo.reload.made_public_at
    end

    test "sets made_public_at to current time when publicized" do
      user = create(:user, plan: "medium")
      repo = create(:private_repository, owner: user)
      assert_nil repo.made_public_at

      Timecop.freeze(2016, 9, 13, 12) do
        repo.private = false
        repo.save!
        assert_equal Time.now, repo.reload.made_public_at
      end
    end
  end

  test "public repo starts with its made_public_at set to its creation time" do
    Timecop.freeze(2014, 8, 10) do
      repo = create(:repository)
      assert_equal DateTime.new(2014, 8, 10), repo.made_public_at,
          "made_public_at should be set on the instance"
      assert_equal DateTime.new(2014, 8, 10), repo.reload.made_public_at,
          "made_public_at should be persisted in the database"
    end
  end

  context "#public=" do
    test "sets made_public_at to nil when privatized" do
      repo = create(:repository, made_public_at: 3.days.ago)
      refute_nil repo.made_public_at

      repo.public = false
      repo.save!
      assert_nil repo.reload.made_public_at
    end

    test "sets made_public_at to current time when publicized" do
      user = create(:user, plan: "medium")
      repo = create(:private_repository, owner: user)
      assert_nil repo.made_public_at

      Timecop.freeze(2016, 9, 13, 12) do
        repo.public = true
        repo.save!
        assert_equal DateTime.new(2016, 9, 13, 12), repo.reload.made_public_at
      end
    end
  end

  [GitRPC::InvalidRepository, GitRPC::RepositoryOffline.new("host", "path"), GitRPC::ConnectionError, Repository::RpcDependency::UnroutedError, GitHub::DGit::UnroutedError, GitRPC::Timeout].each do |e|
    test "Repository#online? is false when #{e} happens" do
      @simple.rpc.stubs(:online?).raises(e)
      refute @simple.online?
    end
  end

  test "it can have one import" do
    import = create(:import)
    repository = create(:repository, name: "foobar", owner: create(:user))

    repository.import = import
    repository.save!
    assert_equal repository.import, import
  end

  test "creation is rate limited by the creating user when rate limiting is enabled" do
    enable_content_creation_rate_limiting
    owner = create(:user, login: "the-owner")
    creator = create(:user, login: "the-creator")

    expected_errors = [GitHub::RateLimitedCreation::ERROR_MESSAGE]
    limit = 2

    with_cache_enabled do
      Timecop.freeze do
        GitHub::RateLimitedCreation.use_custom_limits(user_repo_minute: limit) do
          2.times { create(:repository, owner: owner, created_by_user_id: creator) }

          # Different owner, same creator should fail if feature flag is enabled
          repo = Repository.new(name: "nope", owner: create(:user), created_by_user_id: creator)
          refute_predicate repo, :valid?
          assert_equal expected_errors, repo.errors.full_messages

          # Same owner, new creator should succeed
          repo = Repository.new(name: "yep", owner: owner, created_by_user_id: create(:user))
          assert_predicate repo, :valid?
        end
      end
    end
  end

  test "creation is not rate limited by the creating user when rate limiting is disabled" do
    disable_content_creation_rate_limiting
    owner = create(:user, login: "the-owner")
    creator = create(:user, login: "the-creator")

    expected_errors = [GitHub::RateLimitedCreation::ERROR_MESSAGE]
    limit = 2

    with_cache_enabled do
      Timecop.freeze do
        GitHub::RateLimitedCreation.use_custom_limits(user_repo_minute: limit) do
          2.times { create(:repository, owner: owner, created_by_user_id: creator) }

          # Different owner, same creator should fail if feature flag is enabled
          repo = Repository.new(name: "nope", owner: create(:user), created_by_user_id: creator)
          assert_predicate repo, :valid?

          # Same owner, new creator should succeed
          repo = Repository.new(name: "yep", owner: owner, created_by_user_id: create(:user))
          assert_predicate repo, :valid?
        end
      end
    end
  end

  context ".open_issue_and_pr_counts" do
    if GitHub.spamminess_check_enabled?
      test "returns counts for non spammy open issues and prs from a list of repository ids" do
        spammy_user = create(:user, login: "spammy")
        create(:issue, user: spammy_user, repository: @simple)
        2.times { create(:issue, repository: @simple) }
        create(:issue, repository: @simple, state: :closed)
        create(:pull_request, :disable_disk_access, repository: @simple, user: @defunkt)

        perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) do
          spammy_user.mark_as_spammy hard_flag: true
        end

        counts = Repository.open_issue_and_pr_counts(repository_ids: [@simple.id])

        assert_equal 2, counts[[@simple.id, false]]
        assert_equal 1, counts[[@simple.id, true]]
      end
    end
  end

  context ".full_network_counts_for" do
    test "returns counts for active repositories within the network of a given set of repo source ids" do
      repo_one = create(:repository)
      forked_repo = create(:fork_repository, forker: @defunkt, fork_repo: repo_one)
      repo_two = create(:repository)

      counts = Repository.full_network_counts_for(
        source_ids: [repo_one.source_id, repo_two.source_id, forked_repo.source_id],
      )

      assert_equal 1, counts[repo_one.source_id]
      assert_equal 1, counts[forked_repo.source_id]
      assert_equal 0, counts[repo_two.source_id]
    end
  end

  context ".public_fork_counts_for_public_roots_for" do
    test "returns counts for public forks from public roots of a given set of repo network ids" do
      repo_one = create(:repository)
      forked_repo = create(:fork_repository, forker: @defunkt, fork_repo: repo_one)
      repo_two = create(:private_repository, owner: @defunkt)
      private_fork = create(:fork_repository, forker: @defunkt, fork_repo: repo_two)

      counts = Repository.public_fork_counts_for_public_roots_for(
        network_ids: [
          repo_one.network_id,
          repo_two.network_id,
          forked_repo.network_id,
          private_fork.network_id,
        ],
      )

      assert_equal 1, counts[repo_one.id]
      assert_nil counts[forked_repo.id]
      assert_nil counts[repo_two.id]
      assert_nil counts[private_fork.id]
    end
  end

  context "#id_based_url" do
    test "returns a full URL by default" do
      with_global_host_name("github.com") do
        assert_equal "https://github.com/#{@simple.owner_id}/#{@simple.id}", @simple.id_based_url
      end
    end

    test "can omit the host from the URL" do
      with_global_host_name("github.com") do
        assert_equal "/#{@simple.owner_id}/#{@simple.id}", @simple.id_based_url(include_host: false)
      end
    end

    test "returns a URL with a bare github.com domain when invoked from review-lab" do
      GitHub.stubs(:dynamic_lab?).returns(true)

      with_global_host_name("lerebear.review-lab.github.com") do
        assert_equal "https://github.com/#{@simple.owner_id}/#{@simple.id}", @simple.id_based_url
      end
    end
  end

  context "orchestration publishes v1.Created" do
    test "should publish Created event" do
      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        repository = create(:repository, :full_creation)

        assert_hydro_messages(count: 1, schema: "github.repositories.v1.Created")
        assert_hydro_published(
          CreateRepositoryOrchestration.build_hydro_event_message(repository.id).merge({
            repository: Hydro::EntitySerializer.repository(repository)
          }),
          schema: "github.repositories.v1.Created"
        )
      end
    end

    test "should not publish Created event" do
      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        repository = create(:repository)

        assert_hydro_messages(count: 0, schema: "github.repositories.v1.Created")
      end
    end
  end

  context "#restorable?" do
    test "new repositories are restorable? == true" do
      r = Repository.new(name: "rails", owner: @defunkt)
      assert r.restorable?
    end

    test "if repositories set restorable = false, it is reflected" do
      r = Repository.new(name: "rails", owner: @defunkt)
      r.restorable = false
      refute r.restorable?
    end
  end

  context "#feature_enabled_for_repo_or_owner?" do
    test "a repo without an owner returns feature enablement for repo" do
      r = Repository.new

      r.stubs(:feature_enabled?).with(:foo).returns(false)
      refute r.feature_enabled_for_repo_or_owner?(:foo)

      r.stubs(:feature_enabled?).with(:foo).returns(true)
      assert r.feature_enabled_for_repo_or_owner?(:foo)
    end
  end
end

class EMURepositoryTest < GitHub::TestCase
  include HydroTestHelpers
  self.these_tests_are_order_dependent_and_yearn_to_be_random

  fixtures do
    @emu_user = create(:emu, login: "mojombo2")
    @enterprise = @emu_user.enterprise_managed_business
    @owner = @enterprise.owners.first

    @member = create(:emu, login: "member", business: @enterprise)

    @org = create(:organization, business: @enterprise, admin: @owner)
    @org.add_member(@member)

    @emu_user_repo = create(:repository, name: "grit", owner: @emu_user)
    @org_repo = create(:internal_repository, owner: @org)
  end

  setup do
    GitHub.flipper[:discard_stratocaster_fanout].disable
    @emu_user_repo.update_default_branch("master")
  end

  context "enterprise business checks" do
    test "is_enterprise_managed returns true for organization repo" do
      assert_predicate @org_repo, :is_enterprise_managed?
    end

    test "is_enterprise_managed returns true for user repo" do
      assert_predicate @emu_user_repo, :is_enterprise_managed?
    end

    test "enterprise_managed_business returns emu business for organization repo" do
      assert_equal @enterprise, @org_repo.enterprise_managed_business
    end

    test "enterprise_managed_business returns emu business for user repo" do
      assert_equal @enterprise, @emu_user_repo.enterprise_managed_business
    end
  end

  context "#can_have_public_pages?" do
    test "true for regular user public repo" do
      assert create(:repository).can_have_public_pages?
    end

    test "true for regular user private repo" do
      assert create(:private_repository).can_have_public_pages?
    end

    test "true for regular org public repo" do
      org = create(:organization)
      assert create(:private_repository, owner: org).can_have_public_pages?
    end

    test "true for regular org private repo" do
      org = create(:organization)
      assert create(:private_repository, owner: org).can_have_public_pages?
    end

    test "true for regular org internal repo" do
      org = create(:enterprise_linked_organization)
      assert create(:internal_repository, owner: org).can_have_public_pages?
    end

    test "false for regular user public repo" do
      refute create(:repository, owner: @emu_user).can_have_public_pages?
    end

    test "false for regular user private repo" do
      refute create(:private_repository, owner: @emu_user).can_have_public_pages?
    end

    test "false for regular org public repo" do
      refute create(:private_repository, owner: @org).can_have_public_pages?
    end

    test "false for regular org private repo" do
      refute create(:private_repository, owner: @org).can_have_public_pages?
    end

    test "false for regular org internal repo" do
      refute create(:internal_repository, owner: @org).can_have_public_pages?
    end
  end
end unless GitHub.single_business_environment?
