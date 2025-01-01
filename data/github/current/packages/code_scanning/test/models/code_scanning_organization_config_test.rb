# typed: true
# frozen_string_literal: true

require "test_helper"

class CodeScanningOrganizationConfigTest < GitHub::TestCase
  fixtures do
    @user = create(:paid_user)
    @org = create(:organization, admin: @user)
  end

  context "#enable_code_scanning_autofix_settings" do
    test "default is on" do
      assert CodeScanningOrganizationConfig.new(organization: @org).code_scanning_autofix_settings_enabled?
    end

    test "disabling and enabling works" do
      CodeScanningOrganizationConfig.new(organization: @org).disable_code_scanning_autofix_settings(actor: @user)
      refute CodeScanningOrganizationConfig.new(organization: @org).code_scanning_autofix_settings_enabled?

      CodeScanningOrganizationConfig.new(organization: @org).enable_code_scanning_autofix_settings(actor: @user)
      assert CodeScanningOrganizationConfig.new(organization: @org).code_scanning_autofix_settings_enabled?
    end

    test "disabling only affects correct org" do
      other_org = create(:organization, admin: @user)

      CodeScanningOrganizationConfig.new(organization: @org).disable_code_scanning_autofix_settings(actor: @user)
      refute CodeScanningOrganizationConfig.new(organization: @org).code_scanning_autofix_settings_enabled?

      assert CodeScanningOrganizationConfig.new(organization: other_org).code_scanning_autofix_settings_enabled?
    end
  end
end
