# typed: true
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
      agent = build(:integration_agent, url: "", app_type: "agent")
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
      integration = create(:integration, :with_agent, default_permissions: { Integration::CopilotDependency::COPILOT_PERMISSION => "read" })
      authorization = create(:github_application_authorization, user: user, application: integration)
      integrations = IntegrationAgent.integrations_authorized_for_user(user)
      assert_equal 1, integrations.size
      assert_equal integration, integrations.first
    end

    test "requires agent configuration when copilot_extendable is enabled" do
      user = create(:user)
      integration = create(:integration, :with_agent, default_permissions: { Integration::CopilotDependency::COPILOT_PERMISSION => "read" })
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

      create(:integration_version, integration: integration, default_permissions: { Integration::CopilotDependency::COPILOT_PERMISSION => "read" })
      integration.reload # reload to get the latest version

      integrations = IntegrationAgent.integrations_installed_for_target(installation.target)
      assert_empty integrations
    end

    test "finds installed integrations that have required permission" do
      integration = create(:integration, :with_agent, default_permissions: { Integration::CopilotDependency::COPILOT_PERMISSION => "read" })
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

      create(:integration_version, integration: integration, default_permissions: { Integration::CopilotDependency::COPILOT_PERMISSION => "read" })
      integration.reload # reload to get the latest version

      integrations = IntegrationAgent.integrations_installed_for_orgs([installation.target])
      assert_empty integrations
    end

    test "finds installed integrations with fgp enabled" do
      integration = create(:integration, :with_agent, default_permissions: { Integration::CopilotDependency::COPILOT_PERMISSION => "read" })
      installation = create(:integration_installation, integration: integration)
      integration2 = create(:integration, :with_agent, default_permissions: { Integration::CopilotDependency::COPILOT_PERMISSION => "read" })
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
      integration = create(:integration, :with_agent, default_permissions: { Integration::CopilotDependency::COPILOT_PERMISSION => "read" })
      create(:integration, :with_agent)
      create(:integration, :with_agent, :private, default_permissions: { Integration::CopilotDependency::COPILOT_PERMISSION => "read" })

      results = IntegrationAgent.public_integrations
      assert_equal 1, results.count
      assert_equal integration, results.first
    end
  end

  context "#skill_data" do
    test "allows empty skill_data" do
      GitHub.flipper[:copilot_extension_skills_enabled].enable
      agent = build(:integration_agent, skill_data: [], app_type: "skill")
      assert_predicate agent, :valid?, "Expected valid? to be true, instead found errors: #{agent.errors.full_messages}"
    end

    test "name is required" do
      GitHub.flipper[:copilot_extension_skills_enabled].enable
      agent = build(:integration_agent, skill_data: [{ name: "", description: "description", url: "https://example.com", parameters: "{\"type\": \"object\"}", return_type: "string" }], app_type: "skill")
      refute agent.valid?
      assert_equal agent.errors[:skill], ["name cannot be blank"]
    end

    test "name cannot be longer than 50 characters" do
      GitHub.flipper[:copilot_extension_skills_enabled].enable
      long_name = "a" * 51
      agent = build(:integration_agent, skill_data: [{ name: long_name, description: "description", url: "https://example.com", parameters: "{\"type\": \"object\"}", return_type: "string" }], app_type: "skill")
      refute agent.valid?
      assert_equal agent.errors[:skill], ["name cannot be longer than 50 characters"]
    end

    test "name cannot be longer than 50 characters and cannot have special characters" do
      GitHub.flipper[:copilot_extension_skills_enabled].enable
      long_name = "a" * 51 + " @2"
      agent = build(:integration_agent, skill_data: [{ name: long_name, description: "description", url: "https://example.com", parameters: "{\"type\": \"object\"}", return_type: "string" }], app_type: "skill")
      refute agent.valid?
      assert_equal agent.errors[:skill], ["name cannot be longer than 50 characters", "name must only contain a-z, A-Z, 0-9, underscores, or dashes"]
    end

    test "name cannot have a whitespace" do
      GitHub.flipper[:copilot_extension_skills_enabled].enable
      agent = build(:integration_agent, skill_data: [{ name: "test l", description: "description", url: "https://example.com", parameters: "{\"type\": \"object\"}", return_type: "string" }], app_type: "skill")
      refute agent.valid?
      assert_equal agent.errors[:skill], ["name must only contain a-z, A-Z, 0-9, underscores, or dashes"]
    end

    test "name cannot have special characters" do
      GitHub.flipper[:copilot_extension_skills_enabled].enable
      agent = build(:integration_agent, skill_data: [{ name: "test@2", description: "description", url: "https://example.com", parameters: "{\"type\": \"object\"}", return_type: "string" }], app_type: "skill")
      refute agent.valid?
      assert_equal agent.errors[:skill], ["name must only contain a-z, A-Z, 0-9, underscores, or dashes"]
    end

    test "name with valid characters" do
      GitHub.flipper[:copilot_extension_skills_enabled].enable
      agent = build(:integration_agent, skill_data: [{ name: "hello", description: "description", url: "https://example.com", parameters: "{\"type\": \"object\"}", return_type: "string" }], app_type: "skill")
      assert_predicate agent, :valid?, "Expected valid? to be true, instead found errors: #{agent.errors.full_messages}"
    end

    test "description is required" do
      GitHub.flipper[:copilot_extension_skills_enabled].enable
      agent = build(:integration_agent, skill_data: [{ name: "name", description: "", url: "https://example.com", parameters: "{\"type\": \"object\"}", return_type: "string" }], app_type: "skill")
      refute agent.valid?
      assert_equal agent.errors[:skill], ["description cannot be blank"]
    end

    test "description cannot be more than 300 characters" do
      GitHub.flipper[:copilot_extension_skills_enabled].enable
      long_description = "a" * 301
      agent = build(:integration_agent, skill_data: [{ name: "name", description: long_description, url: "https://example.com", parameters: "{\"type\": \"object\"}", return_type: "string" }], app_type: "skill")
      refute agent.valid?
      assert_equal agent.errors[:skill], ["description cannot be longer than 300 characters"]
    end

    test "url is required" do
      GitHub.flipper[:copilot_extension_skills_enabled].enable
      agent = build(:integration_agent, skill_data: [{ name: "name", description: "description", url: "", parameters: "{\"type\": \"object\"}", return_type: "string" }], app_type: "skill")
      refute agent.valid?
      assert_equal agent.errors[:url], ["Config must contain a URL"]
    end

    test "parameters is required" do
      GitHub.flipper[:copilot_extension_skills_enabled].enable
      agent = build(:integration_agent, skill_data: [{ name: "name", description: "description", url: "https://example.com", parameters: "", return_type: "string" }], app_type: "skill")
      refute agent.valid?
      assert_equal agent.errors[:skill], ["parameters cannot be blank"]
    end

    test "parameters cannot be longer than 1000 characters and be valid json" do
      GitHub.flipper[:copilot_extension_skills_enabled].enable
      long_string = "a" * 1001
      agent = build(:integration_agent, skill_data: [{ name: "name", description: "description", url: "https://example.com", parameters: long_string, return_type: "string" }], app_type: "skill")
      refute agent.valid?
      assert_equal agent.errors[:skill], ["parameters cannot be longer than 1000 characters and currently has 1003 characters", "parameters must be valid JSON"]
    end

    test "skill plugin cannot have more than 8000 characters" do
      GitHub.flipper[:copilot_extension_skills_enabled].enable
      long_string = "a" * 8005
      agent = build(:integration_agent, skill_data: [{ name: long_string, description: "description", url: "https://example.com", parameters: "{\"type\": \"object\"}", return_type: "string" }], app_type: "skill")
      refute agent.valid?
      assert_equal agent.errors[:skills], ["cannot have more than 8000 characters and currently has 8161 characters"]
    end

    test "skill plugin cannot have more than five skills" do
      GitHub.flipper[:copilot_extension_skills_enabled].enable
      skill = { name: "name", description: "description", url: "https://example.com", parameters: "{\"type\": \"object\"}", return_type: "string" }
      skills = [skill, skill, skill, skill, skill, skill]
      agent = build(:integration_agent, skill_data: skills, app_type: "skill")
      refute agent.valid?
      assert_equal agent.errors[:skills], ["cannot have more than 5 skills"]
    end

    test "skills cannot have more than 5 properties" do
      GitHub.flipper[:copilot_extension_skills_enabled].enable

      parameters = {
        type: "object",
        properties: {
          prop1: { type: "string", description: "Property 1" },
          prop2: { type: "string", description: "Property 2" },
          prop3: { type: "string", description: "Property 3" },
          prop4: { type: "string", description: "Property 4" },
          prop5: { type: "string", description: "Property 5" },
          prop6: { type: "string", description: "Property 6" }
        }
      }.to_json

      agent = build(:integration_agent, skill_data: [{ name: "hello", description: "description", url: "https://example.com", parameters: parameters, return_type: "string" }], app_type: "skill")
      refute agent.valid?
      assert_equal agent.errors[:skill], ["parameters cannot have more than 5 properties"]
    end
  end

  context "app_type" do
    test "Removes copilot tag from listing when app type is disabled" do
      agent = create(:integration_agent, app_type: "agent")
      integration = create(:integration, integration_agent: agent, default_permissions: { Integration::CopilotDependency::COPILOT_PERMISSION => "read" })
      listing = create(:marketplace_listing, listable: integration, copilot_app: true)
      agent.update!(app_type: "disabled")

      refute listing.reload.copilot_app?, "Expected listing to not be a copilot app"
    end

    test "Adds copilot tag to listing when app type is enabled" do
      agent = create(:integration_agent, app_type: "disabled")
      integration = create(:integration, integration_agent: agent, default_permissions: { Integration::CopilotDependency::COPILOT_PERMISSION => "read" })
      listing = create(:marketplace_listing, listable: integration, copilot_app: false)
      agent.update!(app_type: "agent")

      assert listing.reload.copilot_app?, "Expected listing to be a copilot app"
    end

    test "Ignores app type when it's a skill" do
      GitHub.flipper[:copilot_extension_skills_enabled].enable
      agent = create(:integration_agent, app_type: "disabled")
      integration = create(:integration, integration_agent: agent, default_permissions: { Integration::CopilotDependency::COPILOT_PERMISSION => "read" })
      listing = create(:marketplace_listing, listable: integration, copilot_app: false)
      agent.update!(app_type: "skill")

      refute listing.reload.copilot_app?, "Expected listing to not be a copilot app after changing to skill"
    end
  end
end
