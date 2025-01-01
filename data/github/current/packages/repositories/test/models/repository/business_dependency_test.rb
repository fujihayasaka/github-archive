# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryBusinessDependencyTest < GitHub::TestCase
  fixtures do
    @maddox = create(:user, login: "maddox")
    @biz = create(:business, name: "Salsa, Inc", owners: [@maddox], seats: 20)
    @biz_org  = create(:organization, plan: GitHub::Plan.business_plus, admins: [@maddox], business: @biz)

    on_multi_tenant_enterprise do
      @emu_owner = create :emu
      @emu_business = @emu_owner.enterprise_managed_business
      @emu_org = create :organization, business: @emu_business, admin: @emu_owner
      @emu_org_repo = create :repository, owner: @emu_org
      @emu_user_repo = create :repository, owner: @emu_owner
    end
  end

  context "internal_visibility_business_id" do
    test "returns correct value for internal repo" do
      repo = create(:internal_repository, owner: @biz_org, public: false)
      assert_equal :internal, repo.visibility.to_sym
      assert_equal repo.visibility, Repository::INTERNAL_VISIBILITY
      assert_equal @biz.id, repo.internal_visibility_business_id
    end

    test "returns nil for public and private repos in a business" do
      repo = create(:private_repository, owner: @biz_org)
      assert_nil repo.internal_visibility_business_id

      assert repo.set_permission(:public)
      assert_equal repo.visibility, Repository::PUBLIC_VISIBILITY
      assert_nil repo.internal_visibility_business_id
    end

    test "returns nil for repos not in a business" do
      repo = create(:public_repository, owner: @maddox)
      assert_equal repo.visibility, Repository::PUBLIC_VISIBILITY
      assert_nil repo.internal_visibility_business_id

      assert repo.set_permission(:private)
      assert_equal repo.visibility, Repository::PRIVATE_VISIBILITY
      assert_nil repo.internal_visibility_business_id
    end
  end

  context "emus internal visibility" do
    test "returns correct value for internal repo in emu" do
      emu = create :emu, :owner, login: "owner-emu"
      business = emu.enterprise_managed_business
      org = create :organization, plan: GitHub::Plan.business_plus, admins: [emu], business: business

      repo = create(:internal_repository, owner: org, public: false)

      assert_equal :internal, repo.visibility.to_sym
      assert_equal repo.visibility, Repository::INTERNAL_VISIBILITY
      assert_equal business.id, repo.internal_visibility_business_id
    end unless GitHub.single_business_environment?
  end

  context "business_owner" do
    test "returns the business owner when available" do
      repo = create(:repository, owner: @biz_org)
      assert_equal @biz, repo.business_owner
    end

    test "returns nil when not available" do
      repo = create(:repository, owner: @maddox)
      assert_nil repo.business_owner
    end
  end unless GitHub.single_business_environment?

  context "tenant_id" do
    test "returns business id for repo in Proxima" do
      on_multi_tenant_enterprise(tenant: @emu_business) do
        assert_equal @emu_business.id, @emu_org_repo.tenant_id
      end
    end

    test "returns nil for repo in GHEC EMU Org" do
      repo = create(:private_repository, owner: @biz_org)
      refute repo.tenant_id
    end

    test "returns nil for user-owner repo" do
      repo = create(:repository)
      refute repo.tenant_id
    end
  end

  context "resolve_tenant" do
    test "returns business for org-owned repo in Proxima" do
      on_multi_tenant_enterprise(tenant: @emu_business) do
        # with tenant context
        assert_equal @emu_business, @emu_org_repo.resolve_tenant

        # without tenant context
        GitHub::CurrentTenant.remove
        assert_nil GitHub::CurrentTenant.get
        assert_nil @emu_org_repo.reload.owner
        assert_nil @emu_org_repo.organization

        assert_equal @emu_business, @emu_org_repo.resolve_tenant
      end
    end

    test "returns business for user repo in Proxima" do
      on_multi_tenant_enterprise(tenant: @emu_business) do
        # with tenant context
        assert_equal @emu_business, @emu_user_repo.resolve_tenant

        # without tenant context
        GitHub::CurrentTenant.remove
        assert_nil GitHub::CurrentTenant.get
        assert_nil @emu_user_repo.reload.owner

        assert_equal @emu_business, @emu_user_repo.resolve_tenant
      end
    end
  end
end
