# typed: true
# frozen_string_literal: true

require "test_helper"

class Organization::DeployKeyPolicyDependencyTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, login: "owner")
    @business = create(:business, owners: [@owner])
  end

  context "standalone" do
    test "new org has deploy key policy disabled" do
      standalone_org = create(:organization, :with_deploy_key_policy_disabled, admin: @owner)

      refute standalone_org.deploy_key_policy_unset?
      refute standalone_org.deploy_key_policy_enabled?
      assert standalone_org.deploy_key_policy_disabled?
    end
  end

  context "enterprise" do
    test "new org has deploy key policy inherited from business if policy is set to enable", skip_enterprise: true do
      @business.enable_deploy_key_policy(actor: @owner)
      org = create(:organization, admin: @owner, business: @business)

      refute org.deploy_key_policy_unset?
      assert org.deploy_key_policy_enabled?
      refute org.deploy_key_policy_disabled?
    end

    test "new org has deploy key policy disabled if business has policy set to disable" do
      @business.disable_deploy_key_policy(actor: @owner)
      org = create(:organization, :with_deploy_key_policy_disabled, admin: @owner, business: @business)

      refute org.deploy_key_policy_unset?
      refute org.deploy_key_policy_enabled?
      assert org.deploy_key_policy_disabled?
    end

    test "new org has deploy key policy disabled if business has policy set to no policy" do
      @business.clear_deploy_key_policy(actor: @owner)
      org = create(:organization, :with_deploy_key_policy_disabled, admin: @owner, business: @business)
      refute org.deploy_key_policy_unset?
      refute org.deploy_key_policy_enabled?
      assert org.deploy_key_policy_disabled?
    end
  end
end
