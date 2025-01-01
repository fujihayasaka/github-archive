# typed: true
# frozen_string_literal: true

require "test_helper"

class DependabotAlertsDependencyTest < GitHub::TestCase
  fixtures do
    GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
    @user = create(:user, login: "org-admin")
    @business = if GitHub.global_business
      GitHub.global_business.add_owner(@user, actor: @user)
      GitHub.global_business
    else
      create(:business, owners: [@user])
    end
  end

  context "#enable_security_alerts_for_new_repos" do
    test "propagates during organization creation" do
      @business.enable_security_alerts_for_new_repos(actor: @user)

      org_attrs = {
        company_name: @business.name,
        login: "new-org",
        admin_logins: [@user.login],
        billing_email: "admin@github.com",
        seats: 20,
      }

      result = Organization::Creator.perform(@user,
          GitHub::Plan.free,
          org_attrs,
          business_owned: true,
          business: @business)

      assert result.success?
      org = result.organization

      assert org.security_alerts_enabled_for_new_repos?
    end
  end
end
