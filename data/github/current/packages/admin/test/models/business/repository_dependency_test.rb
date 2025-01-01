# typed: true
# frozen_string_literal: true

require "test_helper"

class EnterpriseManagedBusinessRepositoryDependencyTest < GitHub::TestCase

  fixtures do
    @enterprise_user = create :emu, :owner, login: "enterprise-user"
    @enterprise = @enterprise_user.enterprise_managed_business
    @owner = @enterprise.find_first_emu_owner

    enterprise_security_manager_team = create :enterprise_security_manager_team, business: @enterprise
    @enterprise_security_manager = create :user, name: "enterprise-security-manager"
    enterprise_security_manager_team.bulk_add_members(users: [@enterprise_security_manager])

    @org_admin = create :emu, business: @enterprise, login: "org-admin"
    @org = create(:organization, business: @enterprise, admin: @org_admin)

    @org_member = create :emu, business: @enterprise, login: "org-member"
    @org.add_member(@org_member)

    # Enterprise Installation Accounts
    # Enterprise installation user with GHEC org membership
    @enterprise_installation_user = create :emu, business: @enterprise, login: "installation-user"
    @enterprise_installation = create(:enterprise_installation, owner: @enterprise)

    create :enterprise_installation_user_account, \
      enterprise_installation: @enterprise_installation,
      profile_name: @enterprise_installation_user.login,
      business_user_account: @enterprise.user_accounts.find_by(user: @enterprise_installation_user)

    @org.add_member(@enterprise_installation_user)

    # scim suspended users with either be disabled or will not have an external identity record
    @suspended_user = create :emu, login: "suspended-user", business: @enterprise
    @suspended_user.external_identities.first.disable

    # Creating internal and private repositories for the EMU
    @internal_repo = create(:internal_repository, owner: @org)
    @private_repo = create(:private_repository, owner: @org)

    # Non-emu business for testing
    @non_emu_owner = create :user, login: "non-emu-owner"
    @non_emu_business = create :business, owners: [@non_emu_owner]
    @non_emu_org = create(:organization, business: @non_emu_business)

    @non_emu_user = create :user, login: "non-emu-user"
    @non_emu_org.add_member(@non_emu_user)
    @non_emu_org_repo = create(:repository, owner: @non_emu_org)
    @non_emu_user_repo = create(:repository, owner: @non_emu_user)
  end

  context "show_user_namespace_repositories?" do
    test "is false for non EMU businesses" do
      refute @non_emu_business.show_user_namespace_repositories?
    end

    test "is true for EMU businesses" do
      assert @enterprise.show_user_namespace_repositories?
    end
  end

  context "allow_unlock_user_namespace_repositories?" do
    test "is false for non EMU businesses" do
      refute @non_emu_business.allow_unlock_user_namespace_repositories?
    end

    test "is true for EMU businesses" do
      assert @enterprise.allow_unlock_user_namespace_repositories?
    end
  end

  context "can_user_unlock_user_namespace_repos?" do
    test "is false for non EMU businesses" do
      refute @non_emu_business.can_user_unlock_user_namespace_repos?(@non_emu_owner)
    end

    test "is false for wrong businesses" do
      refute @non_emu_business.can_user_unlock_user_namespace_repos?(@owner)
      refute @enterprise.can_user_unlock_user_namespace_repos?(@non_emu_owner)
    end

    test "is false for EMU business members" do
      refute @enterprise.can_user_unlock_user_namespace_repos?(@org_admin)
      refute @enterprise.can_user_unlock_user_namespace_repos?(@org_member)
    end

    test "is true for EMU business owners" do
      assert @enterprise.can_user_unlock_user_namespace_repos?(@owner)
    end

    test "is true for EMU business security managers" do
      assert @enterprise.can_user_unlock_user_namespace_repos?(@enterprise_security_manager)
    end
  end

  context "#user_namespace_repositories" do
    test "is nil for non-EMU business" do
      user_repositories = @non_emu_business.user_namespace_repositories
      assert_nil user_repositories
    end

    test "does not include org owned repositories" do
      user_repositories = @enterprise.user_namespace_repositories

      refute_includes user_repositories, @internal_repo
      refute_includes user_repositories, @private_repo
    end

    test "returns repositories owned by org members" do
      user_repo = create :repository, owner: @org_member
      expected_repos = [user_repo]

      user_repositories = @enterprise.user_namespace_repositories
      assert_same_elements expected_repos, user_repositories
    end

    test "returns repositories owned by suspended users" do
      user_repo = create :repository, owner: @suspended_user
      expected_repos = [user_repo]

      user_repositories = @enterprise.user_namespace_repositories
      assert_same_elements expected_repos, user_repositories
    end

    test "returns repositories owned by enterprise installation users" do
      user_repo = create :repository, owner: @enterprise_installation_user
      expected_repos = [user_repo]

      user_repositories = @enterprise.user_namespace_repositories
      assert_same_elements expected_repos, user_repositories
    end

    test "returns repositories owned by EMU admins" do
      user_repo = create :repository, owner: @owner
      expected_repos = [user_repo]

      user_repositories = @enterprise.user_namespace_repositories
      assert_same_elements expected_repos, user_repositories
    end

    test "returns repositories owned by org admins" do
      user_repo = create :repository, owner: @org_admin
      expected_repos = [user_repo]

      user_repositories = @enterprise.user_namespace_repositories
      assert_same_elements expected_repos, user_repositories
    end

    test "filter repositories by repository name" do
      user_repo = create :repository, owner: @org_member, name: "find_me"
      ignored_repo = create :repository, owner: @org_admin, name: "dodge_this"

      expected_repos = [user_repo]

      user_repositories = @enterprise.user_namespace_repositories(query: "find")
      assert_same_elements expected_repos, user_repositories
      refute_includes user_repositories, ignored_repo
    end

    test "filter repositories by owner name" do
      user_repo = create :repository, owner: @org_member, name: "find_me"
      ignored_repo = create :repository, owner: @org_admin, name: "dodge_this"

      expected_repos = [user_repo]

      user_repositories = @enterprise.user_namespace_repositories(query: "org-member")
      assert_same_elements expected_repos, user_repositories
      refute_includes user_repositories, ignored_repo
    end

    test "shows only active repositories by default" do
      user_repo = create :repository, owner: @org_member
      deleted_repo = create :repository, owner: @org_member
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        deleted_repo.remove(@org_member)
      end

      expected_repos = [user_repo]

      user_repositories = @enterprise.user_namespace_repositories
      assert_same_elements expected_repos, user_repositories
    end

    test "shows deleted repositories when status is :deleted" do
      user_repo = create :repository, owner: @org_member
      deleted_repo = create :repository, owner: @org_member
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        deleted_repo.remove(@org_member)
      end

      expected_repos = [deleted_repo]

      user_repositories = @enterprise.user_namespace_repositories(status: :deleted)
      assert_same_elements expected_repos, user_repositories
    end

    test "shows filtered repositories when given repository ids" do
      user_repo = create :repository, owner: @org_member
      ignored_repo = create :repository, owner: @org_member

      expected_repos = [user_repo]

      user_repositories = @enterprise.user_namespace_repositories(repository_ids: [user_repo.id])
      assert_same_elements expected_repos, user_repositories
    end

    test "sort repositories by owner login" do
      gamma = create :emu, business: @enterprise, login: "gamma"
      alpha = create :emu, business: @enterprise, login: "alpha"
      beta = create :emu, business: @enterprise, login: "beta"

      @org.add_member(gamma)
      @org.add_member(alpha)
      @org.add_member(beta)

      gamma_repo = create :repository, owner: gamma
      alpha_repo = create :repository, owner: alpha
      beta_repo = create :repository, owner: beta

      expected_repos = [
        gamma_repo,
        beta_repo,
        alpha_repo
      ]
      user_repositories = @enterprise.user_namespace_repositories(sort_field: "owner", sort_direction: "desc")
      assert_equal expected_repos, user_repositories
    end

    test "sorts repositories by updated date" do
      alpha = create :emu, business: @enterprise, login: "alpha"
      @org.add_member(alpha)

      eldest_repo = create :repository, owner: alpha
      eldest_repo.update_column :updated_at, Time.now - 20.minutes

      fresh_repo = create :repository, owner: @org_member

      elder_repo = create :repository, owner: alpha
      elder_repo.update_column :updated_at, Time.now - 10.minutes

      expected_repos = [
        fresh_repo,
        elder_repo,
        eldest_repo
      ]
      user_repositories = @enterprise.user_namespace_repositories(sort_field: "updated_at", sort_direction: "desc")
      assert_equal expected_repos, user_repositories
    end

    test "uses cached results when called multiple times with write through cache flag on" do
      enable_feature_flag(:business_write_through_cache)
      enable_cache_storage
      reset_cache

      @enterprise = Business.find(@enterprise.id)
      # Caches user repositories on page load
      assert_query_count(3) do
        @enterprise.user_namespace_repositories
      end

      # Clear memoized values
      @enterprise = Business.find(@enterprise.id)
      # Now uses the cache
      assert_query_count(1) do
        @enterprise.user_namespace_repositories
      end
    end

    test "does not use cached results when called multiple times with write through cache flag off" do
      disable_feature_flag(:business_write_through_cache)

      @enterprise = Business.find(@enterprise.id)
      # Caches user repositories on page load
      assert_query_count(3) do
        @enterprise.user_namespace_repositories
      end

      # Clear memoized values
      @enterprise = Business.find(@enterprise.id)
      # Now uses the cache
      assert_query_count(2) do
        @enterprise.user_namespace_repositories
      end
    end
  end

  context "#destroy_custom_properties" do
    test "destroys custom properties for the business" do
      create :custom_property_definition, source: @enterprise

      assert_equal 1, CustomPropertyDefinition.defined_by(@enterprise).count

      @enterprise.destroy_custom_properties

      assert_equal 0, CustomPropertyDefinition.defined_by(@enterprise).count
    end
  end

  context "Default deploy key policy" do
    test "sets to disabled for new businesses if FF is enable" do
      biz = create :business, :with_deploy_key_policy_disabled

      assert biz.deploy_key_policy_disabled?
    end
  end
end unless GitHub.single_business_environment?

class OrganizationsWithDeployKeyFilterTest < GitHub::TestCase
  fixtures do
    @org1 = create(:organization)
    @org2 = create(:organization)
    @org3 = create(:organization)
    @biz = create(:business, organizations: [@org1, @org2, @org3])
  end

  private def create_deploy_key(org)
    repo = create(:repository, owner: org)
    create(:public_key, repository: repo)
  end

  context "#organizations_with_deploy_keys_filter" do
    test "returns all organizations with deploy keys" do
      create_deploy_key(@org1)
      create_deploy_key(@org2)
      create_deploy_key(@org3)
      assert_same_elements [@org1, @org2, @org3], @biz.organizations_with_deploy_keys_filter(true)
    end

    test "returns all organizations with deploy keys when specifying an AR relation for orgs" do
      create_deploy_key(@org1)
      create_deploy_key(@org2)
      create_deploy_key(@org3)
      assert_same_elements [@org1, @org2], @biz.organizations_with_deploy_keys_filter(true, orgs: Organization.where(id: [@org1.id, @org2.id]))
    end

    test "returns subset of organizations with deploy keys" do
      create_deploy_key(@org1)
      create_deploy_key(@org3)
      assert_same_elements [@org1, @org3], @biz.organizations_with_deploy_keys_filter(true)
    end

    test "returns subset of organizations without deploy keys" do
      create_deploy_key(@org1)
      create_deploy_key(@org2)
      assert_same_elements [@org3], @biz.organizations_with_deploy_keys_filter(false)
    end

    test "returns none when no organizations have deploy keys" do
      assert_same_elements [], @biz.organizations_with_deploy_keys_filter(true)
    end
  end
end
