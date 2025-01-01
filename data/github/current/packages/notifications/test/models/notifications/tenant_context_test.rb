# typed: true
# frozen_string_literal: true

require "test_helper"

class NotificationsTenantContextTest < GitHub::TestCase
  skip_enterprise

  fixtures do
    @business = create(:business, :enterprise_managed)

    on_multi_tenant_enterprise(tenant: @business) do
      @user = create(:emu, business: @business)
      @owner = create(:organization, business: @business, admin: @user)
      @repository = create(:repository, owner: @owner)
    end
  end

  setup do
    on_multi_tenant_enterprise(tenant: @business)
  end

  test ".resolve_tenant_for_list returns tenant for repository" do
    assert_equal @business, Notifications::TenantContext.resolve_tenant_for_list(list_type: "Repository", list_id: @repository.id)
  end

  test ".resolve_tenant_for_list returns nil on unknown classes" do
    assert_nil Notifications::TenantContext.resolve_tenant_for_list(list_type: "Foo", list_id: @repository.id)
  end

  test ".resolve_tenant for repository returns business" do
    assert_equal @business, Notifications::TenantContext.resolve_tenant(@repository)
  end

  test ".resolve_tenant for organization returns business" do
    assert_equal @business, Notifications::TenantContext.resolve_tenant(@owner)
  end

  test ".resolve_tenant for user returns business" do
    assert_equal @business, Notifications::TenantContext.resolve_tenant(@user)
  end

  test ".resolve_tenant for issue returns business" do
    issue = create(:issue, repository: @repository)
    assert_equal @business, Notifications::TenantContext.resolve_tenant(issue)
  end

  test ".resolve_tenant for check run returns business" do
    check_suite = create(:check_suite, repository: @repository)
    check_run = create(:check_run, check_suite: check_suite)
    assert_equal @business, Notifications::TenantContext.resolve_tenant(check_run)
  end

  test ".resolve_tenant for gist returns business" do
    gist = create(:gist, user: @user)
    assert_equal @business, Notifications::TenantContext.resolve_tenant(gist)
  end

  test ".resolve_tenant for commint returns business" do
    repo = create(:repository, owner: @owner, from_example: :simple)
    commit = create(:commit, repository: repo)
    assert_equal @business, Notifications::TenantContext.resolve_tenant(commit)
  end
end
