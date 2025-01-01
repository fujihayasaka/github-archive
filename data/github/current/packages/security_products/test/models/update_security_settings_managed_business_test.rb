# typed: true
# frozen_string_literal: true

require "test_helper"

class UpdateSecuritySettingsManagedBusinessTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers

  fixtures do
    @org = create(:organization)
    @biz = if GitHub.enterprise?
      create(:global_business)
    else
      create(:business, :enterprise_managed, organizations: [@org])
    end
    @admin = if GitHub.enterprise?
      create(:user)
    else
      create(:emu, business: @biz)
    end
  end

  setup do
    if GitHub.enterprise?
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      GitHub::Enterprise.license.stubs(:advanced_security_seats).returns(10)
    else
      @biz.mark_advanced_security_as_purchased_for_entity(actor: @admin)
      @biz.set_advanced_security_seats_for_entity(actor: @admin, seats: 10)
    end
  end

  context "when GHAS is being enabled on new EMU repositories" do
    test "it enables config on business entity" do
      params = { advanced_security_enabled_new_user_namespace_repos: "enabled" }
      err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
      assert_nil(err_msg)

      assert @biz.advanced_security_enabled_on_new_user_namespace_repos?
    end

    test "a business policy does not allow GHAS enablement" do
      @biz.stubs(:policy_allows_advanced_security_enablement?).returns(false)

      params = { advanced_security_enabled_new_user_namespace_repos: "enabled" }
      err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)

      assert_equal(
        "GitHub Advanced Security could not be enabled for new user namespace repositories because of a policy setting for the enterprise",
        err_msg
      )
    end
  end

  context "when GHAS is being disabled on new repositories" do
    test "it configures the business config setting" do
      # enable first so we can verify the disable actions actually occur
      params = { advanced_security_enabled_new_user_namespace_repos: "enabled" }
      err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
      assert_nil(err_msg)
      assert @biz.advanced_security_enabled_on_new_user_namespace_repos?

      params = { advanced_security_enabled_new_user_namespace_repos: "disabled" }
      err_msg = UpdateSecuritySettings.perform(@biz, params, actor: @admin).try(:fetch, :error, nil)
      assert_nil(err_msg)
      refute @biz.advanced_security_enabled_on_new_user_namespace_repos?
    end
  end
end
