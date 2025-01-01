# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

class User::IntegrationInstallationDependencyTest < GitHub::TestCase
  include PermissionsHelper

  fixtures do
    @user = create(:user)
  end

  setup_once do
    enable_cache_storage
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    reset_cache
  end

  teardown_once do
    disable_cache_storage
  end

  context "#associated_installation_repository_ids" do
    test "returns an empty Array if User is an Organization" do
      org = create(:organization)
      create(:repository, :minimal, owner: org)

      installation = make_integration_installation(target: org, permissions: { "metadata" => :read })
      assert_empty org.associated_installation_repository_ids(installation)
    end

    test "returns an empty Array if the installation doesn't have an repository permissions" do
      installation = make_integration_installation(target: @user)
      assert_empty @user.associated_installation_repository_ids(installation)
    end

    test "returns repos both the user and the installation have access to" do
      org = create(:organization)

      private_org_repo = create(:private_repository, :minimal, owner: org)
      private_org_repo.add_member(@user)

      private_org_repo2 = create(:private_repository, :minimal, owner: org)
      private_org_repo2.add_member(@user)

      assert private_org_repo.readable_by?(@user)
      assert private_org_repo2.readable_by?(@user)

      installation = make_integration_installation(repository: private_org_repo, permissions: { "metadata" => :read })

      assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: private_org_repo.resources.metadata)
      refute_actor_and_subject_granted_in_permissions_table(actor: installation, subject: private_org_repo2.resources.metadata)

      assert_same_elements [private_org_repo.id], @user.associated_installation_repository_ids(installation)
    end

    test "caches repo IDs for org admin users", skip_enterprise: true do
      org = create(:organization)

      private_org_repo = create(:private_repository, :minimal, owner: org)
      private_org_repo2 = create(:private_repository, :minimal, owner: org)
      installation = make_integration_installation(repositories: [private_org_repo, private_org_repo2], permissions: { "metadata" => :read })
      Flipper[:installation_user_associated_repo_ids_cache].enable(installation.integration)

      admin = org.admins.first
      admin.associated_installation_repository_ids(installation)

      expected_ids = [private_org_repo.id, private_org_repo2.id]
      actual_ids = JSON.parse(GitHub.cache.get(IntegrationInstallation::UserAssociatedRepositories.cache_key(admin, installation)))
      assert_same_elements expected_ids, actual_ids
    end

    test "caches repo IDs for non-org admin users", skip_enterprise: true do
      org = create(:organization)
      refute org.adminable_by?(@user)

      private_org_repo = create(:private_repository, :minimal, owner: org)
      private_org_repo.add_member(@user)

      private_org_repo2 = create(:private_repository, :minimal, owner: org)
      installation = make_integration_installation(repositories: [private_org_repo, private_org_repo2], permissions: { "metadata" => :read })
      Flipper[:installation_user_associated_repo_ids_cache].enable(installation.integration)

      @user.associated_installation_repository_ids(installation)

      expected_ids = [private_org_repo.id]
      cached_ids = GitHub.cache.get(IntegrationInstallation::UserAssociatedRepositories.cache_key(@user, installation))
      assert cached_ids
      actual_ids = JSON.parse(cached_ids)
      assert_same_elements expected_ids, actual_ids
    end
  end

  context "#can_access_installation?" do
    test "returns true when the installation is on this user's account" do
      installation = make_integration_installation(target: @user)
      assert @user.can_access_installation?(installation)
    end

    test "returns true when the user can administer the installation target account" do
      org = create :organization, admin: @user
      installation = make_integration_installation(target: org)

      assert @user.can_access_installation?(installation)
    end

    test "returns true when the user can read any private repo that the installation has access to" do
      org = create(:organization)
      private_org_repo = create(:private_repository, :minimal, owner: org)
      private_org_repo.add_member(@user)

      assert private_org_repo.readable_by?(@user)

      installation = make_integration_installation(repository: private_org_repo, permissions: { "metadata" => :read })
      assert @user.can_access_installation?(installation)
    end

    test "returns false when the user has no access to the installation's repositories" do
      private_repo = create(:private_repository, :minimal)

      refute private_repo.readable_by?(@user)

      installation = make_integration_installation(repository: private_repo)

      refute @user.can_access_installation?(installation)
    end
  end
end
