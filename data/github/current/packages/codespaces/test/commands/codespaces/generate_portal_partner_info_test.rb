# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::GeneratePortalPartnerInfoCommandTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers
  include CodespacesRepoHelper
  include DogstatsTestHelpers

  fixtures do
    @user = create(:user)
    GitHub.flipper[:codespaces_skip_minting_cascade_token].disable
  end

  test "includes feature flags" do
    codespace = create(:codespace, owner: @user)

    Codespaces::Vscs::OWNER_FEATURE_FLAGS.each { |f| GitHub.flipper[f].disable(@user) }
    partner_info = generate_partner_info(codespace)
    assert_equal Codespaces::Vscs.feature_flags(@user), partner_info[:featureFlags]

    Codespaces::Vscs::OWNER_FEATURE_FLAGS.each { |f| GitHub.flipper[f].enable(@user) }
    partner_info = generate_partner_info(codespace)
    assert_equal Codespaces::Vscs.feature_flags(@user), partner_info[:featureFlags]
  end

  test "home indicator goes to a repo if the codespace is a repo" do
    codespace = create(:codespace)
    partner_info = generate_partner_info(codespace)
    assert_equal partner_info[:vscodeSettings][:homeIndicator][:href], "https://github.com/#{codespace.repository.nwo}"
  end

  test "home indicator goes to original PR if the codespace is a PR" do
    repo = create(:repository,  owner: @user, from_example: :pull_request_source)
    pull_request = create(:pull_request, repository: repo, base_repository: repo, head_repository: repo, head_ref: "master-merged-topic")
    codespace = create(:codespace, pull_request: pull_request)
    partner_info = generate_partner_info(codespace)
    assert_equal partner_info[:vscodeSettings][:homeIndicator][:href], "http://github.com/#{codespace.repository.nwo}/pull/#{pull_request.number}"
  end

  test "includes the GitHub token" do
    codespace = create(:codespace)
    partner_info = generate_partner_info(codespace)
    assert_equal "github_token", partner_info[:credentials][0][:token]
  end

  context "dark mode support" do
    test "does not pass a color mode if the user's color mode is set to auto" do
      @user.color_mode = ColorMode::AUTO
      codespace = build :codespace, owner: @user, state: "provisioned", name: "foobar"
      partner_info = generate_partner_info(codespace)

      # Send no theme values so VSCS can auto-determine based on system settings
      assert_nil partner_info[:vscodeSettings][:loadingScreenThemeColor]
      assert_nil partner_info[:vscodeSettings][:defaultSettings]["workbench.colorTheme"]
    end

    test "supports dark mode" do
      @user.color_mode = ColorMode::DARK
      codespace = build :codespace, owner: @user, state: "provisioned", name: "foobar"
      partner_info = generate_partner_info(codespace)

      assert_equal ColorMode::DARK.name, partner_info[:vscodeSettings][:loadingScreenThemeColor]
      assert_equal "GitHub Dark Default", partner_info[:vscodeSettings][:defaultSettings][:"workbench.colorTheme"]
    end

    test "supports light mode" do
      @user.color_mode = ColorMode::LIGHT
      codespace = build :codespace, owner: @user, state: "provisioned", name: "foobar"
      partner_info = generate_partner_info(codespace)

      assert_equal ColorMode::LIGHT.name, partner_info[:vscodeSettings][:loadingScreenThemeColor]
      assert_equal "GitHub Light Default", partner_info[:vscodeSettings][:defaultSettings][:"workbench.colorTheme"]
    end
  end

  test "uses Cascade token placeholder if cascade_token is nil and if the feature flag to fetch it is disabled" do
    codespace = build :codespace, owner: @user, state: "provisioned", name: "foobar"
    partner_info = generate_partner_info(codespace, cascade_token: nil)

    assert_equal "%CASCADE_TOKEN_PLACEHOLDER%", partner_info[:codespaceToken]
  end

  test "partner info does not use Cascade token placeholder if cascade_token is nil and if the feature flag to fetch it is enabled" do
    GitHub.flipper[:codespaces_skip_minting_cascade_token].enable(@user)
    codespace = build :codespace, owner: @user, state: "provisioned", name: "foobar"
    partner_info = generate_partner_info(codespace, cascade_token: nil)
    assert_nil partner_info[:codespaceToken]
  end

  test "partner info does not use Cascade token if the feature flag to fetch it is enabled" do
    GitHub.flipper[:codespaces_skip_minting_cascade_token].enable(@user)
    codespace = build :codespace, owner: @user, state: "provisioned", name: "foobar"
    partner_info = generate_partner_info(codespace, cascade_token: "i exist but should not be present in the partner info")
    assert_nil partner_info[:codespaceToken]
  end

  test "installs Copilot by default if the demo period is active" do
    user = create(:user)
    codespace = create(:codespace, owner: user)
    Copilot::User.any_instance.stubs(:codespaces_demo_usage_allowed?).returns(true)
    partner_info = generate_partner_info(codespace)

    extensions = partner_info[:vscodeSettings][:defaultExtensions]
    copilot = extensions.find { |x| x[:id] == Codespaces::GeneratePortalPartnerInfo::COPILOT_EXTENSION_ID }
    refute_nil copilot
  end

  test "excludes validAfter when github_token_valid_after isn't provided" do
    codespace = create(:codespace, owner: @user)
    result = generate_partner_info(codespace)
    refute result[:credentials][0][:validAfter]
  end

  test "includes validAfter when github_token_valid_after is provided" do
    codespace = create(:codespace, owner: @user)
    result = generate_partner_info(codespace, github_token_valid_after: Time.now.to_f)
    assert result[:credentials][0][:validAfter].is_a?(Float)
  end

  context "openFiles" do
    test "includes openFiles customizations" do
      repo = repo_with_devcontainer <<-JSON5
        {
          "customizations": {
            "codespaces": {
              "openFiles": ["file-a.txt", "file-b.txt"]
            }
          }
        }
      JSON5

      codespace = create(:codespace, repository: repo, ref: "master")
      partner_info = generate_partner_info(codespace)
      assert_equal ["file-a.txt", "file-b.txt"], partner_info[:workspaceCustomizations][:openFiles]
    end

    test "doesn't error if they don't exist" do
      repo = repo_with_devcontainer <<-JSON5
        {
          "image": "my-image"
        }
      JSON5

      codespace = create(:codespace, repository: repo, ref: "master")
      partner_info = generate_partner_info(codespace)
      assert_nil partner_info[:workspaceCustomizations][:openFiles]
    end

    test "doesn't error if the devcontainer can't be found" do
      codespace = create(:codespace, ref: "master", devcontainer_path: ".devcontainer/devcontainer.json")
      assert_nothing_raised do
        generate_partner_info(codespace)
      end
    end

    test "override the default startup editor when openFiles is specified" do
      repo = repo_with_devcontainer <<-JSON5
        {
          "customizations": {
            "codespaces": {
              "openFiles": ["file-a.txt", "file-b.txt"]
            }
          }
        }
      JSON5

      codespace = create(:codespace, repository: repo, ref: "master")
      partner_info = generate_partner_info(codespace)
      assert_equal "none", partner_info[:vscodeSettings][:defaultSettings][:"workbench.startupEditor"]
    end

    test "override the default startup editor when openFiles is set to nil" do
      repo = repo_with_devcontainer <<-JSON5
        {
          "customizations": {
            "codespaces": {
              "openFiles": [ ]
            }
          }
        }
      JSON5

      codespace = create(:codespace, repository: repo, ref: "master")
      partner_info = generate_partner_info(codespace)
      assert_equal [], partner_info[:workspaceCustomizations][:openFiles]
      assert_equal "none", partner_info[:vscodeSettings][:defaultSettings][:"workbench.startupEditor"]
    end

    test "keep the default startup editor if openFiles is not specified" do
      repo = repo_with_devcontainer <<-JSON5
        {
          "customizations": {
            "codespaces": { }
          }
        }
      JSON5

      codespace = create(:codespace, repository: repo, ref: "master")
      partner_info = generate_partner_info(codespace)
      assert_nil partner_info[:workspaceCustomizations][:openFiles]
      assert_equal "readme", partner_info[:vscodeSettings][:defaultSettings][:"workbench.startupEditor"]
    end
  end

  def generate_partner_info(codespace, cascade_token: "cascade_token", github_token: "github_token", github_token_valid_after: nil)
    user_settings = Codespaces::Settings.for_user(@user)
    connection = { key: "value" }
    Codespaces::GeneratePortalPartnerInfo.call(
      user: @user,
      user_settings:,
      codespace:,
      github_token:,
      github_token_valid_after:,
      cascade_token:,
      connection:,
    )
  end
end
