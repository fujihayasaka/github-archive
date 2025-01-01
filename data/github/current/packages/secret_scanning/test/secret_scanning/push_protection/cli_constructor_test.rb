# typed: true
# frozen_string_literal: true

require "test_helper"

class CliConstructorTest < GitHub::TestCase
  include SecurityAnalysisSettingsHelper

  fixtures do
    @user = create(:paid_user)
    @repo = create(:public_repository, owner: @user)
    @org = create(:organization, login: "octo-org")
  end

  setup do
    GitHub.flipper[SecretScanning::Features::FeatureFlagHelper::FeatureFlags::READ_PUBLIC_REPO_ALERTS].enable

    @repo.stubs(:advanced_security_enabled?).returns(true)
    SecretScanning::Features::Repo::TokenScanning.new(@repo).enable(actor: @user)
    assert SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?
    @delegated_bypass_url_mappings = {
      "1" => "#{GitHub.scheme}://#{GitHub.host_domain}/#{@repo.owner.name}/#{@repo.name}/secret_scanning/exemptions/new/c2VjcmV0X3NjYW5uaW5nLS0x",
      "2" => "#{GitHub.scheme}://#{GitHub.host_domain}/#{@repo.owner.name}/#{@repo.name}/secret_scanning/exemptions/new/c2VjcmV0X3NjYW5uaW5nLS0y",
    }
    @self_bypass_url_mappings = {
      "1" => "#{GitHub.scheme}://#{GitHub.host_domain}/#{@repo.owner.name}/#{@repo.name}/security/secret-scanning/unblock-secret/1",
      "2" => "#{GitHub.scheme}://#{GitHub.host_domain}/#{@repo.owner.name}/#{@repo.name}/security/secret-scanning/unblock-secret/2",
    }
    @secrets = [
      SecretScanning::Models::Secret.new(
        type: "GITHUB_TOKEN_V2",
        fingerprint: "abcd1234",
        token_metadata: SecretScanning::Models::TokenMetadata.new(
          token_type: "GITHUB_TOKEN_V2",
          label: "GitHub Personal Access Token",
          slug: "github_token_v2",
          provider: "GitHub",
        ),
        bypass_placeholder_ksuid: "1",
        locations: [
          SecretScanning::Models::Location.new(
            commit_oid: "4f82b923b9b73ac1a644f25ad8786a55202b5c26",
            path: "foo/bar.txt",
            start_line: 1,
          )
        ]
      )
    ]
  end

  test "displays warning of additional secrets found" do
    additional_secrets = 2

    scan_result = SecretScanning::Models::SynchronousScanResult.new(secrets: @secrets, completed: true, num_secrets_found_over_limit: additional_secrets)

    expected_long_message = <<-MSG
——[ WARNING ]—————————————————————————————————————————
 #{additional_secrets} more secrets detected. Remove each secret from your commit history to view more detections.
 #{DocsUrlConfig.url_for("code-security/excluding-folders-and-files-from-secret-scanning")}
——————————————————————————————————————————————————————
    MSG

    check_self_and_delegated_bypass(expected_long_message, true, scan_result)
  end

  test "prompts user to enable secret scanning if eligible and if secrets are found" do
    public_repo = create(:public_repository, owner: @user)

    assert SecretScanning::Features::Repo::TokenScanning.new(public_repo).feature_available?
    refute SecretScanning::Features::Repo::TokenScanning.new(public_repo).enabled?

    scan_result = SecretScanning::Models::SynchronousScanResult.new(secrets: @secrets, completed: true)

    expected_long_message = <<-MSG
 (?) This repository does not have Secret Scanning enabled, but is eligible. Enable Secret Scanning to view and manage detected secrets.
 Visit the repository settings page, #{GitHub.url}#{security_analysis_settings_path(public_repo)}
    MSG

    check_self_and_delegated_bypass(expected_long_message, true, scan_result, repo: public_repo)

    # But not as someone who cannot modify security settings
    rando = create(:user)
    @repo.add_member(rando)
    refute @repo.adminable_by?(rando)

    check_self_and_delegated_bypass(expected_long_message, false, scan_result, repo: public_repo, user: rando)
  end

  test "displays scan incomplete warning for incomplete scans with secrets", skip_with_all_emus: true do
    scan_result = SecretScanning::Models::SynchronousScanResult.new(secrets: @secrets, completed: false)

    expected_long_message = <<-MSG

——[ WARNING ]—————————————————————————————————————————
 Scan incomplete: This push was large and we didn't finish on time.
 It can still contain undetected secrets.

 (?) Use the following command to find the path of the detected secret(s):
     git rev-list --objects --all | grep blobid
——————————————————————————————————————————————————————
    MSG

    check_self_and_delegated_bypass(expected_long_message, true, scan_result)
  end

  test "displays custom message when available + when secrets are found" do
    custom_msg = SecretScanning::Models::PushProtection::CustomMessage.new(owner_name: "octo-org", owner_type: "organization", message: "hello world")
    SecretScanning::Services::PushProtectionService.stubs(:get_custom_message).returns(custom_msg)

    @repo.organization = @org
    scan_result = SecretScanning::Models::SynchronousScanResult.new(secrets: @secrets, completed: true)

    expected_long_message = <<-MSG
 (?) Review a resource from your organization, octo-org:
 hello world
    MSG

    check_self_and_delegated_bypass(expected_long_message, true, scan_result)
  end

  test "does not display org custom message when not available + when secrets are found" do
    SecretScanning::Services::PushProtectionService.stubs(:get_custom_message).returns(nil)
    @repo.organization = @org
    scan_result = SecretScanning::Models::SynchronousScanResult.new(secrets: @secrets, completed: true)

    expected_long_message = "Review a resource from your organization"

    check_self_and_delegated_bypass(expected_long_message, false, scan_result)

  end

  def check_self_and_delegated_bypass(expected_long_message, should_be_included, scan_result, repo: nil, user: nil)
    repo_to_use = repo || @repo
    user_to_use = user || @user
    # First check the delegated bypass flow
    cli_constructor = SecretScanning::PushProtection::CliConstructor.new(repo_to_use, user_to_use, true)
    long_msg = cli_constructor.get_long_message(scan_result, @delegated_bypass_url_mappings)

    if should_be_included
      assert_includes long_msg, expected_long_message
    else
      refute_includes long_msg, expected_long_message
    end

    # Then check the default self bypass flow
    cli_constructor = SecretScanning::PushProtection::CliConstructor.new(repo_to_use, user_to_use, false)
    long_msg = cli_constructor.get_long_message(scan_result, @self_bypass_url_mappings)

    if should_be_included
      assert_includes long_msg, expected_long_message
    else
      refute_includes long_msg, expected_long_message
    end
  end
end
