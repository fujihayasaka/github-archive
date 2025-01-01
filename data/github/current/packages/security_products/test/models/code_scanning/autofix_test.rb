# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/code_scanning/review_test_helpers"

module CodeScanning
  class AutofixTest < GitHub::TestCase

    ResponseMock = Struct.new(:data)
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
    end

    context ".enabled_for_repo?" do
      test "returns false if settings are not configurable" do
        CodeScanning::Autofix.stubs(:repo_settings_configurable?).returns(false)
        CodeScanningRepositoryConfig.new(@private_repo).enable_code_scanning_autofix_settings(actor: @org.admins.first)

        refute CodeScanning::Autofix.enabled_for_repo?(@private_repo)
      end

      test "returns true if settings are configurable and enabled (default)" do
        @org.mark_advanced_security_as_purchased_for_entity(actor: @org.admins.first)
        @private_repo.enable_advanced_security(actor: @org.admins.first)

        assert CodeScanning::Autofix.enabled_for_repo?(@private_repo)
      end

      test "returns false if settings are configurable but disabled" do
        @org.mark_advanced_security_as_purchased_for_entity(actor: @org.admins.first)
        @private_repo.enable_advanced_security(actor: @org.admins.first)
        CodeScanningRepositoryConfig.new(@private_repo).disable_code_scanning_autofix_settings(actor: @org.admins.first)

        refute CodeScanning::Autofix.enabled_for_repo?(@private_repo)
      end
    end

    context ".repo_settings_configurable?" do
      context "when code_scanning_autofix_public_repo is disabled", feature_disabled: :code_scanning_autofix_public_repo do
        test "returns false on GHES", enterprise_only: true do
          CodeScanning::Autofix.unstub(:available_in_environment?)
          @org.mark_advanced_security_as_purchased_for_entity(actor: @org.admins.first)
          @private_repo.enable_advanced_security(actor: @org.admins.first)

          refute CodeScanning::Autofix.repo_settings_configurable?(@private_repo)
        end

        test "returns false when the repo is public" do
          public_repo = create(:public_repository, owner: @org)

          refute CodeScanning::Autofix.repo_settings_configurable?(public_repo)
        end

        test "returns false when advanced security is disabled" do
          @org.mark_advanced_security_as_purchased_for_entity(actor: @org.admins.first)
          @private_repo.disable_advanced_security(actor: @org.admins.first)

          refute CodeScanning::Autofix.repo_settings_configurable?(@private_repo)
        end

        test "returns false when the owner is a user" do
          user = create(:user)
          user_repo = create(:private_repository, owner: user)

          refute CodeScanning::Autofix.repo_settings_configurable?(user_repo)
        end

        test "returns false for public repository when the owner is a user" do
          user_public_repo = create(:public_repository, owner: @user)

          refute CodeScanning::Autofix.repo_settings_configurable?(user_public_repo)
        end

        test "returns true when autofix is enabled for the org" do
          @org.mark_advanced_security_as_purchased_for_entity(actor: @org.admins.first)
          @private_repo.enable_advanced_security(actor: @org.admins.first)

          assert CodeScanning::Autofix.repo_settings_configurable?(@private_repo)
        end

        test "returns false when autofix is disabled for the org" do
          @org.mark_advanced_security_as_purchased_for_entity(actor: @org.admins.first)
          @private_repo.enable_advanced_security(actor: @org.admins.first)
          @org.disable_code_scanning_autofix_settings(actor: @org.admins.first)
          @private_repo.reload

          refute CodeScanning::Autofix.repo_settings_configurable?(@private_repo)
        end
      end

      context "when code_scanning_autofix_public_repo FF is enabled", feature_enabled: :code_scanning_autofix_public_repo do
        test "returns false on GHES", enterprise_only: true do
          CodeScanning::Autofix.unstub(:available_in_environment?)
          @org.mark_advanced_security_as_purchased_for_entity(actor: @org.admins.first)
          @private_repo.enable_advanced_security(actor: @org.admins.first)

          refute CodeScanning::Autofix.repo_settings_configurable?(@private_repo)
        end

        test "returns true when the repo is public" do
          public_repo = create(:public_repository, owner: @org)

          assert CodeScanning::Autofix.repo_settings_configurable?(public_repo)
        end

        test "returns false when advanced security is disabled" do
          @org.mark_advanced_security_as_purchased_for_entity(actor: @org.admins.first)
          @private_repo.disable_advanced_security(actor: @org.admins.first)

          refute CodeScanning::Autofix.repo_settings_configurable?(@private_repo)
        end

        test "returns false for private repository when the owner is a user" do
          user_repo = create(:private_repository, owner: @user)

          refute CodeScanning::Autofix.repo_settings_configurable?(user_repo)
        end

        test "returns true for public repository when the owner is a user" do
          user_public_repo = create(:public_repository, owner: @user)

          assert CodeScanning::Autofix.repo_settings_configurable?(user_public_repo)
        end

        test "returns true when autofix is enabled for the org" do
          @org.mark_advanced_security_as_purchased_for_entity(actor: @org.admins.first)
          @private_repo.enable_advanced_security(actor: @org.admins.first)

          assert CodeScanning::Autofix.repo_settings_configurable?(@private_repo)
        end

        test "returns false when autofix is disabled for the org" do
          @org.mark_advanced_security_as_purchased_for_entity(actor: @org.admins.first)
          @private_repo.enable_advanced_security(actor: @org.admins.first)
          @org.disable_code_scanning_autofix_settings(actor: @org.admins.first)
          @private_repo.reload

          refute CodeScanning::Autofix.repo_settings_configurable?(@private_repo)
        end

        test "returns true when the repo is public and org has autofix enabled" do
          @org.mark_advanced_security_as_purchased_for_entity(actor: @org.admins.first)
          @public_repo.enable_advanced_security(actor: @org.admins.first)

          assert CodeScanning::Autofix.repo_settings_configurable?(@public_repo)
        end

        test "returns false when the repo is public and org has autofix disabled" do
          @org.mark_advanced_security_as_purchased_for_entity(actor: @org.admins.first)
          @public_repo.enable_advanced_security(actor: @org.admins.first)
          @org.disable_code_scanning_autofix_settings(actor: @org.admins.first)
          @public_repo.reload

          refute CodeScanning::Autofix.repo_settings_configurable?(@public_repo)
        end
      end
    end

    context ".enabled_for_org?" do
      test "returns false if settings are not configurable" do
        CodeScanning::Autofix.stubs(:org_settings_configurable?).returns(false)
        @org.enable_code_scanning_autofix_settings(actor: @org.admins.first)

        refute CodeScanning::Autofix.enabled_for_org?(@org)
      end

      test "returns true if settings are configurable and enabled (default)" do
        @org.mark_advanced_security_as_purchased_for_entity(actor: @org.admins.first)

        assert CodeScanning::Autofix.enabled_for_org?(@org)
      end

      test "returns false if settings are configurable but disabled" do
        @org.mark_advanced_security_as_purchased_for_entity(actor: @org.admins.first)
        @org.disable_code_scanning_autofix_settings(actor: @org.admins.first)

        refute CodeScanning::Autofix.enabled_for_org?(@org)
      end
    end

    context ".allowed_by_business?" do
      test "returns false if code scanning is not enabled" do
        CodeScanning::Autofix.unstub(:available_in_environment?)
        GitHub.stubs(:code_scanning_enabled?).returns(false)

        refute CodeScanning::Autofix.allowed_by_business?(@business)
      end

      test "returns false on GHES", enterprise_only: true do
        CodeScanning::Autofix.unstub(:available_in_environment?)
        refute CodeScanning::Autofix.allowed_by_business?(@business)
      end

      test "returns false if GHAS is not purchased" do
        @business.stubs(:advanced_security_purchased?).returns(false) if GitHub.enterprise?

        refute CodeScanning::Autofix.allowed_by_business?(@business)
      end

      test "returns true if GHAS purchased" do
        @business.mark_advanced_security_as_purchased_for_entity(actor: @business.admins.first) unless GitHub.enterprise?

        assert CodeScanning::Autofix.allowed_by_business?(@business)
      end

      test "returns false if disallowed", skip_enterprise: true do
        @business.mark_advanced_security_as_purchased_for_entity(actor: @business.admins.first)
        @business.disallow_code_scanning_autofix_policy(actor: @business.admins.first)

        refute CodeScanning::Autofix.allowed_by_business?(@business)
      end
    end

    context ".policy_available?" do
      test "returns false if code scanning is not enabled" do
        CodeScanning::Autofix.unstub(:available_in_environment?)
        GitHub.stubs(:code_scanning_enabled?).returns(false)

        refute CodeScanning::Autofix.policy_available?(@business)
      end

      test "returns false on GHES", enterprise_only: true do
        CodeScanning::Autofix.unstub(:available_in_environment?)
        refute CodeScanning::Autofix.policy_available?(@business)
      end

      test "returns false if GHAS is not purchased" do
        @business.stubs(:advanced_security_purchased?).returns(false) if GitHub.enterprise?

        refute CodeScanning::Autofix.policy_available?(@business)
      end

      test "returns true if GHAS purchased" do
        @business.mark_advanced_security_as_purchased_for_entity(actor: @business.admins.first) unless GitHub.enterprise?

        assert CodeScanning::Autofix.policy_available?(@business)
      end
    end

    context ".org_settings_configurable?" do
      context "when code_scanning_autofix_public_repo is disabled", feature_disabled: :code_scanning_autofix_public_repo do
        test "returns false if code scanning is not enabled" do
          CodeScanning::Autofix.unstub(:available_in_environment?)
          GitHub.stubs(:code_scanning_enabled?).returns(false)

          refute CodeScanning::Autofix.org_settings_configurable?(@org)
        end

        test "returns false on GHES", enterprise_only: true do
          CodeScanning::Autofix.unstub(:available_in_environment?)
          refute CodeScanning::Autofix.org_settings_configurable?(@org)
        end

        test "returns false if GHAS is not purchased" do
          @org.stubs(:advanced_security_purchased?).returns(false) if GitHub.enterprise?

          refute CodeScanning::Autofix.org_settings_configurable?(@org)
        end

        test "returns true if GHAS purchased" do
          @org.mark_advanced_security_as_purchased_for_entity(actor: @org.admins.first)

          assert CodeScanning::Autofix.org_settings_configurable?(@org)
        end

        test "respects enterprise autofix policy", skip_enterprise: true do
          business = create(:business)
          org = create(:organization, business:)
          repo = create(:private_repository, owner: org, from_example: :simple)
          business.mark_advanced_security_as_purchased_for_entity(actor: business.admins.first)

          assert CodeScanning::Autofix.org_settings_configurable?(org)

          business.disallow_code_scanning_autofix_policy(actor: business.admins.first)

          refute CodeScanning::Autofix.org_settings_configurable?(org)
        end
      end

      context "when code_scanning_autofix_public_repo FF is enabled", feature_enabled: :code_scanning_autofix_public_repo do
        test "returns false if code scanning is not enabled" do
          CodeScanning::Autofix.unstub(:available_in_environment?)
          GitHub.stubs(:code_scanning_enabled?).returns(false)

          refute CodeScanning::Autofix.org_settings_configurable?(@org)
        end

        test "returns false on GHES", enterprise_only: true do
          CodeScanning::Autofix.unstub(:available_in_environment?)
          refute CodeScanning::Autofix.org_settings_configurable?(@org)
        end

        test "returns true even if GHAS is not purchased" do
          @org.stubs(:advanced_security_purchased?).returns(false) if GitHub.enterprise?

          assert CodeScanning::Autofix.org_settings_configurable?(@org)
        end

        test "returns true if GHAS purchased" do
          @org.mark_advanced_security_as_purchased_for_entity(actor: @org.admins.first)

          assert CodeScanning::Autofix.org_settings_configurable?(@org)
        end

        test "respects enterprise autofix policy", skip_enterprise: true do
          business = create(:business)
          org = create(:organization, business:)
          repo = create(:private_repository, owner: org, from_example: :simple)
          business.mark_advanced_security_as_purchased_for_entity(actor: business.admins.first)

          assert CodeScanning::Autofix.org_settings_configurable?(org)

          business.disallow_code_scanning_autofix_policy(actor: business.admins.first)

          refute CodeScanning::Autofix.org_settings_configurable?(org)
        end

        test "returns true if the org is standalone" do
          standalone_org = create(:organization)

          assert CodeScanning::Autofix.org_settings_configurable?(standalone_org)
        end
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

      test "suggested_fixes_for_alerts does not return empty, dismissed or outdated fixes" do
        ts_alert_fixes = {
          1 => Turboscan::Proto::SuggestedFixAlert.new(suggested_fix: Turboscan::Proto::SuggestedFix.new),
          2 => Turboscan::Proto::SuggestedFixAlert.new(suggested_fix: nil),
          3 => Turboscan::Proto::SuggestedFixAlert.new(suggested_fix: Turboscan::Proto::SuggestedFix.new(dismissed: true)),
          4 => Turboscan::Proto::SuggestedFixAlert.new(suggested_fix: Turboscan::Proto::SuggestedFix.new(outdated: true)),
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

    context ".generate_for_tool?" do
      test "always return true for CodeQL" do
        assert CodeScanning::Autofix.generate_for_tool?(@private_repo, "CodeQL")
      end

      test "return true for supported third-party tools when third-party tools are enabled on the repo", skip_all_features: true do
        GitHub.flipper[:code_scanning_suggested_thirdparty].enable_actor(@private_repo)

        assert CodeScanning::Autofix.generate_for_tool?(@private_repo, "ESLint")
      end

      test "return true for supported third-party tools when third-party tools are enabled on the org", skip_all_features: true do
        GitHub.flipper[:code_scanning_suggested_thirdparty].enable_actor(@org)

        assert CodeScanning::Autofix.generate_for_tool?(@private_repo, "ESLint")
      end

      test "return false for third-party tools when third-party tools are disabled on the repo", skip_all_features: true do
        GitHub.flipper[:code_scanning_suggested_thirdparty_disabled].enable_actor(@private_repo)

        refute CodeScanning::Autofix.generate_for_tool?(@private_repo, "ESLint")
      end

      test "return false for third-party tools when third-party tools are disabled on the org", skip_all_features: true do
        GitHub.flipper[:code_scanning_suggested_thirdparty_disabled].enable_actor(@org)

        refute CodeScanning::Autofix.generate_for_tool?(@private_repo, "ESLint")
      end

      test "return false for unsupported third-party tools when third-party tools are enabled on the repo", skip_all_features: true do
        GitHub.flipper[:code_scanning_suggested_thirdparty].enable_actor(@private_repo)

        refute CodeScanning::Autofix.generate_for_tool?(@private_repo, "SomeOtherTool")
      end

      test "return false for unsupported third-party tools when third-party tools are enabled on the org", skip_all_features: true do
        GitHub.flipper[:code_scanning_suggested_thirdparty].enable_actor(@org)

        refute CodeScanning::Autofix.generate_for_tool?(@private_repo, "SomeOtherTool")
      end
    end

    context "generate_pr_for_alert" do
      test "raises error if code scanning integration is not installed" do
        refute(Apps::Internal.integration(:code_scanning))

        assert_raises_with_message(RuntimeError, "Code scanning integration not installed!") do
          CodeScanning::Autofix.generate_pr_for_alert(@private_repo, @user, 1)
        end
      end

      test "raises error if Turboscan responds with error" do
        GitHub.stubs(:code_scanning_enabled?).returns(true)

        make_trusted_oauth_apps_owner
        create(:code_scanning_integration)

        assert(Apps::Internal.integration(:code_scanning))

        GitHub::Turboscan::SuggestedFixes.expects(:suggested_fix).returns(
          Twirp::ClientResp.new(data: nil, error: Twirp::Error.new(:unavailable, "unavailable")),
        )

        assert_raises_with_message(CodeScanning::AutofixError, "Something went wrong") do
          CodeScanning::Autofix.generate_pr_for_alert(@private_repo, @user, 1)
        end
      end

      test "raises error if no suggested fix is found for alert" do
        make_trusted_oauth_apps_owner
        create(:code_scanning_integration)

        GitHub::Turboscan::SuggestedFixes.expects(:suggested_fix).returns(
          Twirp::ClientResp.new(data: nil, error: nil)
        )
        assert_raises_with_message(CodeScanning::AutofixError, "No suggested fix found for alert") do
          CodeScanning::Autofix.generate_pr_for_alert(@private_repo, @user, 1)
        end
      end
    end

    def stub_ts_suggested_fixes_response(fixes)
      GitHub::Turboscan::SuggestedFixes.stubs(:suggested_fix).returns(
        ResponseMock.new(
          data: Turboscan::Proto::GetSuggestedFixResponse.new({
            suggested_fix_alerts: fixes
          })
        )
      )
    end

    def stub_ts_suggested_fixes_response_empty
      GitHub::Turboscan::SuggestedFixes.stubs(:suggested_fix).returns(
        ResponseMock.new
      )
    end
  end
end
