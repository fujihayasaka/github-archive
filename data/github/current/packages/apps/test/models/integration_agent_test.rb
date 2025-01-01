# typed: false
# frozen_string_literal: true

require "test_helper"

class IntegrationAgentTest < GitHub::TestCase
  include StringFromBinaryTestHelper

  fixtures do
    GitHub.flipper[:copilot_extendable].enable
    @user = create(:user)
    @integration = create :integration, :with_active_hook
  end

  context "#integration" do
    test "requires an integration" do
      agent = IntegrationAgent.create(integration: nil, url: "https://example.com", description: "")
      refute_empty agent.errors
      assert_equal agent.errors[:integration], ["can't be blank"]
    end
  end

  context "#description" do
    test "requires a description" do
      agent = build(:integration_agent, description: nil)
      refute agent.valid?
      assert_equal agent.errors[:description], ["Config must contain a description"]
    end

    test "allows empty descriptions" do
      agent = build(:integration_agent, description: "")
      assert_predicate agent, :valid?, "Expected valid? to be true, instead found errors: #{agent.errors.full_messages}"
    end
  end

  context "#url_is_valid" do
    test "allows a valid URL" do
      agent = build(:integration_agent, url: "https://example.com")
      assert_predicate agent, :valid?, "Expected valid? to be true, instead found errors: #{agent.errors.full_messages}"
    end

    test "disallows empty URLs" do
      agent = build(:integration_agent, url: "")
      refute agent.valid?
      assert_equal agent.errors[:url], ["Config must contain a URL"]
    end

    test "disallows empty spaces at beginning of URLs" do
      agent = build(:integration_agent, url: " https://example.com")
      refute agent.valid?
      assert_equal agent.errors[:url], ["The URL should not start or end with a space"]
    end

    test "disallows empty spaces at end of URLs" do
      agent = build(:integration_agent, url: "https://example.com ")
      refute agent.valid?
      assert_equal agent.errors[:url], ["The URL should not start or end with a space"]
    end

    test "disallows invalid URLs" do
      agent = build(:integration_agent, url: "-123$%!@#@$aSd.com")
      refute agent.valid?
      assert_equal agent.errors[:url], ["The URL you've entered is not valid. Please make sure that you encode all special characters first"]
    end

    test "disallows a URL with no scheme" do
      agent = build(:integration_agent, url: "example.com")
      refute agent.valid?
      assert_equal agent.errors[:url], ["Config URL is missing a scheme"]
    end

    test "disallows a URL with a non-http scheme" do
      agent = build(:integration_agent, url: "ftp://example.com")
      refute agent.valid?
      assert_equal agent.errors[:url], ["Config URL scheme is invalid"]
    end

    test "disallows local/loopback URLs" do
      agent = build(:integration_agent, url: "http://localhost:1000")
      refute agent.valid?
      assert_equal agent.errors[:url], ["Sorry, the URL host localhost is not supported because it isn't reachable over the public Internet"]
    end

    test "disallows URLs matching DISALLOWED_HOSTS_PATTERNS" do
      agent = build(:integration_agent, url: "http://github.net")
      refute agent.valid?
      assert_equal agent.errors[:url], ["Config URL host is not allowed"]
    end

    test "allows URLs matching DISALLOWED_HOSTS_PATTERNS but are in the HOST_OVERRIDES" do
      GitHub.flipper[:copilot_agent_allow_host_override].enable
      agent = build(:integration_agent, url: "http://#{IntegrationAgent::INTERNAL_HOST_OVERRIDE.first}/agent")
      assert_predicate agent, :valid?, "Expected valid? to be true, instead found errors: #{agent.errors.full_messages}"
      assert_empty agent.errors
    end

    test "disallows URLs matching DISALLOWED_HOSTS_PATTERNS but are in the HOST_OVERRIDES without flag" do
      GitHub.flipper[:copilot_agent_allow_host_override].disable
      agent = build(:integration_agent, url: "http://#{IntegrationAgent::INTERNAL_HOST_OVERRIDE.first}/agent")
      refute agent.valid?
      assert_equal agent.errors[:url], ["Config URL host is not allowed"]
    end
  end

  context ".integrations_authorized_for_user" do
    test "finds integrations authorized for user" do
      user = create(:user)
      integration = create(:integration, :with_agent, default_permissions: { Integration::COPILOT_PERMISSION => "read" })
      authorization = create(:github_application_authorization, user: user, application: integration)
      integrations = IntegrationAgent.integrations_authorized_for_user(user)
      assert_equal 1, integrations.size
      assert_equal integration, integrations.first
    end

    test "requires agent configuration when copilot_extendable is enabled" do
      user = create(:user)
      integration = create(:integration, :with_agent, default_permissions: { Integration::COPILOT_PERMISSION => "read" })
      create(:github_application_authorization, user: user, application: integration)

      integrations = IntegrationAgent.integrations_authorized_for_user(user)
      assert_equal 1, integrations.size
      assert_equal integration, integrations.first
    end

    test "gracefully handles deleted applications" do
      user = create(:user)
      authorization = create(:github_application_authorization, user: user)
      create(:integration_agent, integration: authorization.application)

      # delete integration without triggering callbacks
      authorization.application.delete
      authorization.reload

      assert_empty IntegrationAgent.integrations_authorized_for_user(user)
    end
  end

  context ".integrations_installed_for_target" do
    test "loads the installed version, not the latest version" do
      integration = create(:integration, :with_agent)
      installation = create(:integration_installation, integration: integration)

      create(:integration_version, integration: integration, default_permissions: { Integration::COPILOT_PERMISSION => "read" })
      integration.reload # reload to get the latest version

      integrations = IntegrationAgent.integrations_installed_for_target(installation.target)
      assert_empty integrations
    end

    test "finds installed integrations that have required permission" do
      integration = create(:integration, :with_agent, default_permissions: { Integration::COPILOT_PERMISSION => "read" })
      installation = create(:integration_installation, integration: integration)
      create(:integration_installation, :with_agent) # not installed on target
      integrations = IntegrationAgent.integrations_installed_for_target(installation.target)

      assert_equal 1, integrations.size
      assert_equal integrations.first, installation.integration
    end

    test "does not finds installed integrations without permissions" do
      integration = create(:integration, :with_agent)
      installation = create(:integration_installation, integration: integration)
      create(:integration_installation, :with_agent) # not installed on target
      integrations = IntegrationAgent.integrations_installed_for_target(installation.target)

      assert_empty integrations
    end

    test "filters out integrations that have been deleted" do
      integration = create(:integration, :with_agent)
      installation = create(:integration_installation, integration: integration)
      integration.delete

      integrations = IntegrationAgent.integrations_installed_for_target(installation.target)
      assert_empty integrations
    end
  end

  context ".integrations_installed_for_orgs" do
    test "loads the installed version, not the latest version" do
      integration = create(:integration, :with_agent)
      installation = create(:integration_installation, integration: integration)

      create(:integration_version, integration: integration, default_permissions: { Integration::COPILOT_PERMISSION => "read" })
      integration.reload # reload to get the latest version

      integrations = IntegrationAgent.integrations_installed_for_orgs([installation.target])
      assert_empty integrations
    end

    test "finds installed integrations with fgp enabled" do
      integration = create(:integration, :with_agent, default_permissions: { Integration::COPILOT_PERMISSION => "read" })
      installation = create(:integration_installation, integration: integration)
      integration2 = create(:integration, :with_agent, default_permissions: { Integration::COPILOT_PERMISSION => "read" })
      installation2 = create(:integration_installation, integration: integration2)
      create(:integration_installation, :with_agent) # not installed on target

      integrations = IntegrationAgent.integrations_installed_for_orgs([installation.target, installation2.target])

      assert_equal 2, integrations.size
      assert_includes integrations, installation.integration
      assert_includes integrations, installation2.integration
    end

    test "does not finds installed integrations with fgp enabled without permissions" do
      integration = create(:integration, :with_agent)
      installation = create(:integration_installation, integration: integration)
      integration2 = create(:integration, :with_agent)
      installation2 = create(:integration_installation, integration: integration2)
      create(:integration_installation, :with_agent) # not installed on target

      integrations = IntegrationAgent.integrations_installed_for_orgs([installation.target, installation2.target])

      assert_empty integrations
    end

    test "description renders non-utf8 characters correctly" do
      ia = create(:integration_agent, description: "❤️")
      assert_equal "❤️", ia.description
    end

    test "filters out integrations that have been deleted" do
      integration = create(:integration, :with_agent)
      installation = create(:integration_installation, integration: integration)
      integration.delete

      integrations = IntegrationAgent.integrations_installed_for_orgs([installation.target])

      assert_empty integrations
    end
  end

  context ".public_integrations" do
    test "finds public configured integrations" do
      integration = create(:integration, :with_agent, default_permissions: { Integration::COPILOT_PERMISSION => "read" })
      create(:integration, :with_agent)
      create(:integration, :with_agent, :private, default_permissions: { Integration::COPILOT_PERMISSION => "read" })

      results = IntegrationAgent.public_integrations
      assert_equal 1, results.count
      assert_equal integration, results.first
    end
  end
end
