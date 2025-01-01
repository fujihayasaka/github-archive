# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryCanUpdateProtectedBranchSettingsTest < GitHub::TestCase
  fixtures do
    @rando = create(:user)
    @repo_admin = create(:user)
    @bus_admin = create(:user)
    @org_owner = create(:user,  plan: "medium")
    @bus_repo_admin = create(:user)
    @bus_org_admin = create(:user)
    @org = create(:organization, admin: @org_owner)
    @repo = create(:repository, owner: @org)
    @repo.add_member(@repo_admin, action: :admin)
    @business_org = create(:organization, plan: "business", admin: @org_owner)
    @business_org.add_member(@bus_org_admin, action: :admin)
    @business_org.add_member(@bus_repo_admin)
    @business_org.add_member(@repo_admin)
    @business_repo = create(:private_repository, owner: @business_org)
    @business_repo.add_member(@bus_repo_admin, action: :admin)
    @business_repo.add_member(@repo_admin, action: :admin)
    @business = create :business, owners: [@bus_admin, @bus_repo_admin], organizations: [@business_org]

    GitHub.flipper[:update_protected_branches_setting].enable
  end

  setup do
    GitHub.stubs(:update_protected_branches_setting_enabled?).returns(true)
  end

  test "returns true if flag disabled" do
    GitHub.flipper[:update_protected_branches_setting].disable
    GitHub.stubs(:update_protected_branches_setting_enabled?).returns(false)

    assert @repo.can_update_protected_branches?(@rando)
  end

  test "returns false if repo admin and enabled on enterprise" do
    GitHub.flipper[:update_protected_branches_setting].disable

    @org.disallow_members_can_update_protected_branches(actor: @org_owner)
    refute @repo.can_update_protected_branches?(@repo_admin)
  end

  test "returns false if not admin" do
    refute @repo.can_update_protected_branches?(@rando)
  end

  test "returns true if repo admin and enabled for org" do
    assert @repo.can_update_protected_branches?(@repo_admin)
  end

  test "returns false if repo admin and disabled for org" do
    @org.disallow_members_can_update_protected_branches(actor: @org_owner)
    refute @repo.can_update_protected_branches?(@repo_admin)
  end

  test "returns true if org admin and disabled for org" do
    @org.disallow_members_can_update_protected_branches(actor: @org_owner)
    assert @repo.can_update_protected_branches?(@org_owner)
  end

  test "returns true if org admin and enabled for org" do
    assert @repo.can_update_protected_branches?(@org_owner)
  end

  test "returns false if just business admin and disabled for business" do
    @business.disallow_members_can_update_protected_branches(actor: @bus_admin)
    refute @business_repo.can_update_protected_branches?(@bus_admin)
  end

  test "returns false if just organization admin and disabled for business" do
    @business.disallow_members_can_update_protected_branches(force: true, actor: @bus_admin)
    refute @business_repo.can_update_protected_branches?(@org_owner)
  end

  test "returns true if business admin and repo admin and disabled for business" do
    @business.disallow_members_can_update_protected_branches(force: true, actor: @bus_admin)
    assert @business_repo.can_update_protected_branches?(@bus_repo_admin)
  end

  test "returns true if organization admin and enabled for business" do
    @business.allow_members_can_update_protected_branches(force: true, actor: @bus_admin)
    assert @business_repo.can_update_protected_branches?(@org_owner)
  end

  test "returns false if business admin and enabled for business" do
    @business.allow_members_can_update_protected_branches(force: true, actor: @bus_admin)
    refute @business_repo.can_update_protected_branches?(@bus_admin)
  end

  test "returns true if organization admin and no policy for business" do
    @business.clear_members_can_update_protected_branches(actor: @bus_admin)
    assert @business_repo.can_update_protected_branches?(@org_owner)
  end

  test "returns false if business admin and no policy for business on enterprise" do
    GitHub.flipper[:update_protected_branches_setting].disable

    @business.clear_members_can_update_protected_branches(actor: @bus_admin)
    refute @business_repo.can_update_protected_branches?(@bus_admin)
  end

  test "returns false if business admin and no policy for business" do
    @business.clear_members_can_update_protected_branches(actor: @bus_admin)
    refute @business_repo.can_update_protected_branches?(@bus_admin)
  end

  test "returns true if business admin and repo admin and no policy for business" do
    @business.clear_members_can_update_protected_branches(actor: @bus_admin)
    assert @business_repo.can_update_protected_branches?(@bus_repo_admin)
  end

  test "returns true if business admin and org admin and no policy for business" do
    @business.clear_members_can_update_protected_branches(actor: @bus_admin)
    assert @business_repo.can_update_protected_branches?(@bus_org_admin)
  end

  test "returns true if repo admin and no policy for business" do
    @business.clear_members_can_update_protected_branches(actor: @bus_admin)
    assert @business_repo.can_update_protected_branches?(@repo_admin)
  end
end
