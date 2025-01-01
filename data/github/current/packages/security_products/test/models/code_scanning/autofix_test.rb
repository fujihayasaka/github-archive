# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/code_scanning/review_test_helpers"

module CodeScanning
  class AutofixTest < GitHub::TestCase

    fixtures do
      GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
      @business = create(:global_business)
      @org = create(:organization)
      @user = create(:user)
      @private_repo = create(:private_repository, owner: @org, from_example: :simple)
      @public_repo = create(:public_repository, owner: @org, from_example: :simple)
    end

    setup do
      GitHub.stubs(:code_scanning_enabled?).returns(true)
      CodeScanning::Autofix.stubs(:available_in_environment?).returns(true)
      disable_feature_flag(:code_scanning_suggested_all_queries)
    end

    context "is_rule_supported?" do
      test "returns true if rule is supported" do
        assert CodeScanning::Autofix.is_rule_supported?(@private_repo, "CodeQL", "js/xss")
      end

      test "returns false if rule is not supported" do
        refute CodeScanning::Autofix.is_rule_supported?(@private_repo, "CodeQL", "rule2")
      end

      test "returns false if tool is not supported" do
        refute CodeScanning::Autofix.is_rule_supported?(@private_repo, "NotSupported", "rule2")
      end

      test "returns true if all_queries FF is enabled" do
        enable_feature_flag(:code_scanning_suggested_all_queries)
        assert CodeScanning::Autofix.is_rule_supported?(@private_repo, "CodeQL", "rule2")
      end
    end

    context "suggested_fixes_for_alerts" do
      test "suggested_fixes_for_alerts returns an empty hash if no alerts have been given" do
        fixes = CodeScanning::Autofix.suggested_fixes_for_alerts(@private_repo, [])

        assert_empty fixes
      end

      test "suggested_fixes_for_alerts returns suggested fixes for given alerts" do
        ts_alert_fixes = { 1 => Turboscan::Proto::SuggestedFixAlert.new(suggested_fix: Turboscan::Proto::SuggestedFix.new) }
        expected_fixes = { 1 => ts_alert_fixes[1].suggested_fix }
        stub_ts_suggested_fixes_response(ts_alert_fixes)

        fixes = CodeScanning::Autofix.suggested_fixes_for_alerts(@private_repo, [1])

        # We peel off the fix alerts and just return the suggested fixes.
        assert_equal expected_fixes, fixes
      end

      test "suggested_fixes_for_alerts does not return empty, or outdated fixes" do
        ts_alert_fixes = {
          1 => Turboscan::Proto::SuggestedFixAlert.new(suggested_fix: Turboscan::Proto::SuggestedFix.new),
          2 => Turboscan::Proto::SuggestedFixAlert.new(suggested_fix: nil),
          3 => Turboscan::Proto::SuggestedFixAlert.new(suggested_fix: Turboscan::Proto::SuggestedFix.new(outdated: true)),
        }
        expected_fixes = {
          1 => ts_alert_fixes[1].suggested_fix,
        }
        stub_ts_suggested_fixes_response(ts_alert_fixes)

        fixes = CodeScanning::Autofix.suggested_fixes_for_alerts(@private_repo, [1, 2, 3])

        # Only the first alert is returned
        assert_equal expected_fixes, fixes
      end

      test "suggested_fixes_for_alerts returns an empty hash if turboscan didn't return any data" do
        stub_ts_suggested_fixes_response_empty

        fixes = CodeScanning::Autofix.suggested_fixes_for_alerts(@private_repo, [1])

        assert_empty fixes
      end
    end

    context ".enabled_for_tool?" do
      test "return true for CodeQL if autofix_codeql is enabled" do
        @org.mark_advanced_security_as_purchased_for_entity(actor: @org.admins.first)
        @private_repo.enable_advanced_security(actor: @org.admins.first)

        assert CodeScanning::Autofix.enabled_for_tool?(@private_repo, "CodeQL")
      end

      test "return false for CodeQL if autofix_codeql is not enabled" do
        CodeScanningRepositoryConfig.new(@private_repo).disable_code_scanning_autofix_settings(actor: @org.admins.first)
        refute CodeScanning::Autofix.enabled_for_tool?(@private_repo, "CodeQL")
      end

      test "return true for supported third party tool" do
        @org.mark_advanced_security_as_purchased_for_entity(actor: @org.admins.first)
        @private_repo.enable_advanced_security(actor: @org.admins.first)

        assert CodeScanning::Autofix.enabled_for_tool?(@private_repo, "ESLint")
      end

      test "return false for unsupported third party tool" do
        refute CodeScanning::Autofix.enabled_for_tool?(@private_repo, "Not Supported")
      end
    end

    def stub_ts_suggested_fixes_response(fixes)
      GitHub::Turboscan::SuggestedFixes.stubs(:suggested_fix).returns(
        Twirp::ClientResp.new(
          data: Turboscan::Proto::GetSuggestedFixResponse.new({
            suggested_fix_alerts: fixes
          })
        )
      )
    end

    def stub_ts_suggested_fixes_response_empty
      GitHub::Turboscan::SuggestedFixes.stubs(:suggested_fix).returns(
        Twirp::ClientResp.new
      )
    end
  end
end
