# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCampaigns
  class GenerateAutofixesServiceTest < GitHub::TestCase
    fixtures do
      GitHub::Enterprise.ensure_business!

      @user = create(:user)
      @org = create(:organization, admin: @user)

      @repo1 = create(:private_repository, owner: @org, from_example: :simple)
      @repo2 = create(:private_repository, owner: @org, from_example: :simple)
    end

    setup do
      GitHub.flipper[:security_campaigns].enable(@org)
      @logical_alert_info = { @repo1.id => [1, 2], @repo2.id => [3] }
    end

    context "generate_autofixes" do
      test "calls turboscan to generate fixes" do
        CodeScanning::Autofix.stubs(:enabled_for_org?).returns(true)
        CodeScanning::Autofix.stubs(:enabled_for_repo?).returns(true)
        GitHub.flipper[:security_campaigns_autofix_generation].enable(@org)

        GitHub::Turboscan::SuggestedFixes.expects(:generate_suggested_fixes_for_repos).with(
          user_id: @org.id,
          repos: [
            Turboscan::Proto::RepoAlertNumbers.new(
              repository_id: @repo1.id,
              alert_numbers: [1, 2],
              ref_names_bytes: Array(@repo1.default_branch_ref.qualified_name.b),
            ),
            Turboscan::Proto::RepoAlertNumbers.new(
              repository_id: @repo2.id,
              alert_numbers: [3],
              ref_names_bytes: Array(@repo2.default_branch_ref.qualified_name.b),
            )]
        ).once.returns(nil)

        GenerateAutofixesService.call(@org, @logical_alert_info)
      end

      test "does nothing if org has autofix disabled" do
        CodeScanning::Autofix.stubs(:enabled_for_org?).returns(false)

        GitHub::Turboscan::SuggestedFixes.expects(:generate_suggested_fixes_for_repos).never

        GenerateAutofixesService.call(@org, @logical_alert_info)
      end

      test "does nothing if repos have autofix disabled" do
        CodeScanning::Autofix.stubs(:enabled_for_org?).returns(true)
        CodeScanning::Autofix.stubs(:enabled_for_repo?).returns(false)
        GitHub.flipper[:security_campaigns_autofix_generation].enable(@org)

        GitHub::Turboscan::SuggestedFixes.expects(:generate_suggested_fixes_for_repos).never

        GenerateAutofixesService.call(@org, @logical_alert_info)
      end

      test "does nothing if org has campaigns autofix disabled" do
        CodeScanning::Autofix.stubs(:enabled_for_org?).returns(true)
        CodeScanning::Autofix.stubs(:enabled_for_repo?).returns(true)
        GitHub.flipper[:security_campaigns_autofix_generation].disable(@org)

        GitHub::Turboscan::SuggestedFixes.expects(:generate_suggested_fixes_for_repos).never

        GenerateAutofixesService.call(@org, @logical_alert_info)
      end
    end
  end
end
