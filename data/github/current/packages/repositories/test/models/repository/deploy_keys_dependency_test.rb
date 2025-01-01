# typed: true
# frozen_string_literal: true

require "test_helper"

class DeployKeysDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @user_owned_repo = create(:repository)

    @standalone_org = create(:organization)
    @standalone_org_repo = create(:repository, owner: @standalone_org)

    @business = create(:business)
    @business_owned_org = create(:organization, business: @business)
    @business_owned_org_repo = create(:repository, owner: @business_owned_org)
    @business.clear_deploy_key_policy(actor: @user)
  end

  context "#deploy_keys_disabled_by_policy_with_policy_source" do
    context "repo owned by user" do
      # In MT mode, user owned repos are still tied to the business
      # so we skip this test in MT mode
      test "repo owned by plain old user (non-emu, non GHES)", skip_enterprise: true, skip_in_multitenant_mode: true do
        disabled, source = @user_owned_repo.deploy_keys_disabled_by_policy_with_policy_source
        refute disabled
        assert_nil source
      end

      context "ghes", enterprise_only: true do
        test "enterprise has policy unset" do
          disabled, source = @user_owned_repo.deploy_keys_disabled_by_policy_with_policy_source
          refute disabled
          assert_nil source
        end

        test "enterprise has policy enabled" do
          GitHub.global_business.enable_deploy_key_policy(actor: @user)
          disabled, source = @user_owned_repo.deploy_keys_disabled_by_policy_with_policy_source
          refute disabled
          assert_nil source
        end

        test "enterprise has policy disabled" do
          GitHub.global_business.disable_deploy_key_policy(actor: @user)
          disabled, source = @user_owned_repo.deploy_keys_disabled_by_policy_with_policy_source
          assert disabled
          assert_equal GitHub.global_business.name, source
        end
      end

      context "emu owned repo", skip_with_all_emus: true, skip_enterprise: true do
        test "emu business has policy unset" do
          emu_user = create(:emu)
          emu_user.enterprise_managed_business.clear_deploy_key_policy(actor: @user)
          emu_user_owned_repo = create(:repository, owner: emu_user)
          disabled, source = emu_user_owned_repo.deploy_keys_disabled_by_policy_with_policy_source
          refute disabled
          assert_nil source
        end

        test "emu business has policy enabled" do
          emu_user = create(:emu)
          emu_user_owned_repo = create(:repository, owner: emu_user)
          emu_user.enterprise_managed_business.enable_deploy_key_policy(actor: @user)
          disabled, source = emu_user_owned_repo.deploy_keys_disabled_by_policy_with_policy_source
          refute disabled
          assert_nil source
        end

        test "emu business has policy disabled" do
          emu_user = create(:emu)
          emu_user_owned_repo = create(:repository, owner: emu_user)
          emu_user.enterprise_managed_business.disable_deploy_key_policy(actor: @user)
          disabled, source = emu_user_owned_repo.deploy_keys_disabled_by_policy_with_policy_source
          assert disabled
          assert_equal emu_user.enterprise_managed_business.name, source
        end

        test "new emu business has policy disabled" do
          emu_user = create(:emu, business: create(:business, :enterprise_managed, :with_deploy_key_policy_disabled))
          biz_owned_org_repo = create(:repository, owner: emu_user)

          disabled, source = biz_owned_org_repo.deploy_keys_disabled_by_policy_with_policy_source
          assert disabled
          assert_equal emu_user.enterprise_managed_business.name, source
        end
      end
    end

    context "repo owned by standalone org", skip_enterprise: true, skip_in_multitenant_mode: true do
      # reminder: when the underyling policy is "unset"
      # we default to _enable_ by default
      # this only applies to existing organizations
      # any organizations that are created after the feature is enabled, will be explicitly disabled
      test "policy unset on the org" do
        disabled, source = @standalone_org_repo.deploy_keys_disabled_by_policy_with_policy_source

        assert @standalone_org.deploy_key_policy_unset?
        refute disabled
        assert_nil source
      end

      test "policy enabled on the org" do
        @standalone_org.enable_deploy_key_policy(actor: @user)
        disabled, source = @standalone_org_repo.deploy_keys_disabled_by_policy_with_policy_source
        refute disabled
        assert_nil source
      end

      test "policy disabled on the org" do
        @standalone_org.disable_deploy_key_policy(actor: @user)
        disabled, source = @standalone_org_repo.deploy_keys_disabled_by_policy_with_policy_source
        assert disabled
        assert_equal @standalone_org.display_login, source
      end
    end

    context "repo owned by business owned org" do
      # reminder: when the underyling policy is "unset"
      # we default to _enable_ by default
      # this only applies to existing organizations
      # any organizations that are created after the feature is enabled, will be explicitly disabled
      context "policy unset on the org" do
        # policy unset on the business essentially means "orgs have control"
        # so in this test, we expect the "source" to be the org
        test "policy unset on the business" do
          disabled, source = @business_owned_org_repo.deploy_keys_disabled_by_policy_with_policy_source
          refute disabled
          assert_nil source
        end

        test "policy enabled on the business" do
          @business.enable_deploy_key_policy(actor: @user)
          disabled, source = @business_owned_org_repo.deploy_keys_disabled_by_policy_with_policy_source
          refute disabled
          assert_nil source
        end

        # in this case, we are inheritting the
        # disabled policy from the business, so we expect "source" to be the business
        test "policy disabled on the business" do
          @business.disable_deploy_key_policy(actor: @user)
          disabled, source = @business_owned_org_repo.deploy_keys_disabled_by_policy_with_policy_source
          assert disabled
          assert_equal @business.name, source
        end

        test "policy disabled on a new business" do
          biz = create(:business)
          biz_owned_org = create(:organization, :with_deploy_key_policy_disabled, business: biz)
          biz_owned_org_repo = create(:repository, owner: biz_owned_org)
          disabled, source = biz_owned_org_repo.deploy_keys_disabled_by_policy_with_policy_source
          assert disabled
          assert_equal biz.name, source
        end unless GitHub.single_business_environment?
      end

      context "policy enabled on the org" do
        # reminder: when the underyling policy is "unset"
        # we default to _enable_ by default
        # this only applies to existing organizations
        # any organizations that are created after the feature is enabled, will be explicitly disabled
        test "policy unset on the business" do
          @business_owned_org.enable_deploy_key_policy(actor: @user)
          disabled, source = @business_owned_org_repo.deploy_keys_disabled_by_policy_with_policy_source
          refute disabled
          assert_nil source
        end

        # this is a valid test case - the policies can reach this state by:
        # 1. the business has the policy unset
        # 2. one of the orgs has the policy enabled
        # 3. the business admin later on enables the policy outright on the business level
        test "policy enabled on the business" do
          @business_owned_org.enable_deploy_key_policy(actor: @user)
          @business.enable_deploy_key_policy(actor: @user)
          disabled, source = @business_owned_org_repo.deploy_keys_disabled_by_policy_with_policy_source
          refute disabled
          assert_nil source
        end

        # this is also a valid test case - the policies can reach this state by:
        # 1. the business has the policy unset
        # 2. one of the orgs has the policy enabled
        # 3. the business admin later on disables the policy outright on the business level
        # in this case, we expect the "source" to be the business since it takes precendence
        test "policy disabled on the business" do
          @business_owned_org.enable_deploy_key_policy(actor: @user)
          @business.disable_deploy_key_policy(actor: @user)
          disabled, source = @business_owned_org_repo.deploy_keys_disabled_by_policy_with_policy_source
          assert disabled
          assert_equal @business.name, source
        end

        test "policy disabled on a new business" do
          biz = create(:business)
          biz_owned_org = create(:organization, :with_deploy_key_policy_disabled, business: biz)
          biz_owned_org_repo = create(:repository, owner: biz_owned_org)

          biz_owned_org.enable_deploy_key_policy(actor: @user)

          disabled, source = biz_owned_org_repo.deploy_keys_disabled_by_policy_with_policy_source
          assert disabled
          assert_equal biz.name, source
        end unless GitHub.single_business_environment?
      end

      context "policy disabled on the org" do
        test "policy disabled on a new business if the FF is enabled" do
          biz = create(:business)
          biz_owned_org = create(:organization, :with_deploy_key_policy_disabled, business: biz)
          biz_owned_org_repo = create(:repository, owner: biz_owned_org)
          disabled, source = biz_owned_org_repo.deploy_keys_disabled_by_policy_with_policy_source
          assert disabled
          assert_equal biz.name, source
        end unless GitHub.single_business_environment?

        # reminder: when the underyling policy is "unset"
        # we default to _disabled_ by default
        test "policy unset on the business" do
          @business_owned_org.disable_deploy_key_policy(actor: @user)
          disabled, source = @business_owned_org_repo.deploy_keys_disabled_by_policy_with_policy_source
          assert disabled
          assert_equal @business_owned_org.display_login, source
        end

        # this is a valid test case - the policies can reach this state by:
        # 1. the business has the policy unset
        # 2. one of the orgs has the policy disabled
        # 3. the business admin later on enables the policy outright on the business level
        test "policy enabled on the business" do
          @business_owned_org.disable_deploy_key_policy(actor: @user)
          @business.enable_deploy_key_policy(actor: @user)
          disabled, source = @business_owned_org_repo.deploy_keys_disabled_by_policy_with_policy_source
          refute disabled
          assert_nil source
        end

        # this is also a valid test case - the policies can reach this state by:
        # 1. the business has the policy unset
        # 2. one of the orgs has the policy disabled
        # 3. the business admin later on disables the policy outright on the business level
        # in this case, we expect the "source" to be the business since it takes precendence
        test "policy disabled on the business" do
          @business_owned_org.disable_deploy_key_policy(actor: @user)
          @business.disable_deploy_key_policy(actor: @user)
          disabled, source = @business_owned_org_repo.deploy_keys_disabled_by_policy_with_policy_source
          assert disabled
          assert_equal @business.name, source
        end
      end
    end
  end
end

class MultiTenantDeployKeysDependencyTest < GitHub::TestCase
  fixtures do
    @emu_user = create(:emu, business: create(:business, :enterprise_managed, :with_deploy_key_policy_disabled))
    @business = @emu_user.enterprise_managed_business
    on_multi_tenant_enterprise(tenant: @business) do
      @org = create(:organization, :with_deploy_key_policy_disabled, business: @business)
      @org_repo = create(:repository, owner: @org)
    end
  end

  setup do
    GitHub::CurrentTenant.set(@business)
  end

  teardown do
    GitHub::CurrentTenant.remove
  end

  context "policy disabled on the org" do
    test "policy disabled on a new business" do
      disabled, source = @org_repo.deploy_keys_disabled_by_policy_with_policy_source
      assert disabled
      assert_equal @business.name, source
    end
  end

  context "policy enabled on the org" do
    test "policy disabled on a new business" do
      @org.enable_deploy_key_policy(actor: @emu_user)

      disabled, source = @org_repo.deploy_keys_disabled_by_policy_with_policy_source
      assert disabled
      assert_equal @business.name, source
    end
  end

  context "repo owned by business owned org" do
    test "policy disabled on a new business" do
      disabled, source = @org_repo.deploy_keys_disabled_by_policy_with_policy_source
      assert disabled
      assert_equal @business.name, source
    end
  end
end unless GitHub.single_business_environment?
