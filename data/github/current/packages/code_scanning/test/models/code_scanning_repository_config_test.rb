# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryCodeScanningConfigTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @user = create(:paid_user)
    @staff_user = create(:staff_admin_user)
    @org = create(:organization, admin: @user)
    @private_org_repo = create(:private_repository, owner: @org)
    @public_org_repo = create(:public_repository, owner: @org)
  end

  context "#code_scanning_upload_endpoint_available?" do
    test "returns true if the endpoint is globally and per repo enabled" do
      assert CodeScanningRepositoryConfig.new(@private_org_repo).code_scanning_upload_endpoint_available?
    end

    test "returns false if the endpoint is disabled for the repo" do
      CodeScanningRepositoryConfig.new(@private_org_repo).disable_code_scanning_upload_endpoint(actor: @user)

      refute CodeScanningRepositoryConfig.new(@private_org_repo).code_scanning_upload_endpoint_available?
    end
  end

  context "#code_scanning_severity_choice" do
    test "default severity is error" do
      assert_equal Configurable::CodeScanning::SEVERITY_CHOICE_ERRORS, CodeScanningRepositoryConfig.new(@public_org_repo).code_scanning_severity_choice
    end

    test "setting severity choice works" do
      CodeScanningRepositoryConfig.new(@public_org_repo).set_code_scanning_severity_choice(choice: Configurable::CodeScanning::SEVERITY_CHOICE_ERRORS_AND_WARNINGS, actor: @user)
      assert_equal Configurable::CodeScanning::SEVERITY_CHOICE_ERRORS_AND_WARNINGS, CodeScanningRepositoryConfig.new(@public_org_repo).code_scanning_severity_choice

      CodeScanningRepositoryConfig.new(@public_org_repo).set_code_scanning_severity_choice(choice: Configurable::CodeScanning::SEVERITY_CHOICE_ALL, actor: @user)
      assert_equal Configurable::CodeScanning::SEVERITY_CHOICE_ALL, CodeScanningRepositoryConfig.new(@public_org_repo).code_scanning_severity_choice
    end

    test "wrong choice does not overwrite config" do
      CodeScanningRepositoryConfig.new(@public_org_repo).set_code_scanning_severity_choice(choice: Configurable::CodeScanning::SEVERITY_CHOICE_ERRORS_AND_WARNINGS, actor: @user)
      assert_equal Configurable::CodeScanning::SEVERITY_CHOICE_ERRORS_AND_WARNINGS, CodeScanningRepositoryConfig.new(@public_org_repo).code_scanning_severity_choice

      CodeScanningRepositoryConfig.new(@public_org_repo).set_code_scanning_severity_choice(choice: "invalid value", actor: @user)
      assert_equal Configurable::CodeScanning::SEVERITY_CHOICE_ERRORS_AND_WARNINGS, CodeScanningRepositoryConfig.new(@public_org_repo).code_scanning_severity_choice
    end
  end
end
