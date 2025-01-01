# typed: true
# frozen_string_literal: true
require "test_helper"

class IntegrationManifestTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @user_with_name_clash = create(:user, login: "testerino")
    @valid_input = JSON.generate({
      "version" => "v1",
      "url" => "https://example.com",
      "hook_attributes" => {
        "url" => "https://example.com/events",
      },
      "redirect_url" => "https://example.com/complete",
    })

    @invalid_version_input = JSON.generate({
      "version" => "v2",
      "url" => "https://example.com",
      "hook_attributes" => {
        "url" => "https://example.com/events",
      },
      "redirect_url" => "https://example.com/complete",
    })

    @invalid_permission_action_input = JSON.generate({
      "version" => "v1",
      "url" => "https://example.com",
      "hook_attributes" => {
        "url" => "https://example.com/events",
      },
      "default_permissions" => {
        "single_file": "read, write",
      },
      "redirect_url" => "https://example.com/complete",
    })

    @valid_input_with_setup = JSON.generate({
      "url" => "https://example.com",
      "setup_url" => "https://example.com/setup",
      "setup_on_update" => true,
      "hook_attributes" => {
        "url" => "https://example.com/events",
      },
      "redirect_url" => "https://example.com/complete",
    })
    @manifest_input_with_single_file_name = JSON.generate({
      "url" => "https://example.com",
      "single_file_name" => ".github/config.yml",
      "hook_attributes" => {
        "url" => "https://example.com/events",
      },
      "redirect_url" => "https://example.com/complete",
      "default_permissions" => {
        "single_file": "write",
      },
    })
    @manifest_input_with_user_provisioning = JSON.generate({
      "url" => "https://example.com",
      "default_permissions" => {
        "user_provisioning": "write",
      },
      "redirect_url" => "https://example.com/complete",
      "setup_url" => "https://example.com/setup",
    })

    @manifest_input_without_hook_attributes = JSON.generate({
      "version" => "v1",
      "url" => "https://example.com",
      "redirect_url" => "https://example.com/complete",
    })

    # This is invalid, because the single file name permission
    # needs to be set when a single_file_name is provided
    @valid_json_invalid_integration = JSON.generate({
      "version" => "v1",
      "url" => "https://example.com",
      "hook_attributes" => {
        "url" => "https://example.com/events",
      },
      "redirect_url" => "https://example.com/complete",
      "single_file_name" => ".github/config.yml",
    })

    @manifest_input_with_callback_url = JSON.generate({
      "url" => "https://example.com",
      "callback_url" => "https://example.com/auth/github/callback",
      "redirect_url" => "https://example.com/complete",
    })

    @manifest_input_with_multiple_callback_urls = JSON.generate({
      "url" => "https://example.com",
      "callback_urls" => [
        "https://classroom.github.com/auth/github/callback"
      ],
      "redirect_url" => "https://example.com/complete",
    })

    @manifest_input_with_request_oauth_on_install = JSON.generate({
      "url" => "https://example.com",
      "callback_urls" => [
        "https://classroom.github.com/auth/github/callback"
      ],
      "request_oauth_on_install" => true,
      "redirect_url" => "https://example.com/complete",
    })

    @manifest_input_with_default_events = JSON.generate({
      "version" => "v1",
      "url" => "https://example.com",
      "hook_attributes" => {
        "url" => "https://example.com/events",
      },
      "default_events" => [
        "issues"
      ],
      "default_permissions" => {
        "issues": "read",
      },
      "redirect_url" => "https://example.com/complete",
    })

    @manifest_input_with_integrator_events = JSON.generate({
      "version" => "v1",
      "url" => "https://example.com",
      "hook_attributes" => {
        "url" => "https://example.com/events",
      },
      "default_events" => [
        "meta"
      ],
      "default_permissions" => {
        "metadata": "read",
      },
      "redirect_url" => "https://example.com/complete",
    })
  end

  context "validation" do
    test "valid attributes" do
      manifest = build(:integration_manifest, data: @valid_input)
      manifest.valid?
      assert_equal [], manifest.errors.full_messages
    end

    test "with invalid version" do
      manifest = build(:integration_manifest, data: @invalid_version_input)
      manifest.valid?
      assert_includes manifest.errors.full_messages, "v2 is not a member of [\"v1\"]."
    end

    test "missing required attributes" do
      manifest = build(:integration_manifest, data: JSON.generate({}))
      refute manifest.valid?
      assert manifest.errors.full_messages.any? { |message| message =~ /weren't supplied/ }
    end

    test "invalid attributes" do
      manifest = build(:integration_manifest, data: JSON.generate({ "wat": "no" }))
      refute manifest.valid?
      assert_includes manifest.errors.full_messages, '"wat" is not a permitted key.'
    end

    test "invalid permission actions" do
      manifest = build(:integration_manifest, data: @invalid_permission_action_input)
      refute_predicate manifest, :valid?
      assert_includes manifest.errors.full_messages, "Permission 'single_file' has an invalid action: 'read, write'."
    end

    test "invalid hook_attributes" do
      manifest = build(:integration_manifest, data: JSON.generate({
        "name" => "My App",
        "url" => "https://example.com",
        "hook_attributes" => {
          "secret": "12345",
          "insecure_ssl": "0",
        },
        "redirect_url" => "https://example.com/complete",
      }))
      refute manifest.valid?
      assert_includes manifest.errors.full_messages, '"insecure_ssl", "secret" are not permitted keys.'
      assert_includes manifest.errors.full_messages, '"url" wasn\'t supplied.'
    end

    test "empty hook_attributes" do
      manifest = build(:integration_manifest, data: JSON.generate({
        "name" => "My App",
        "url" => "https://example.com",
        "hook_attributes" => {},
        "redirect_url" => "https://example.com/complete",
      }))
      refute manifest.valid?
      assert manifest.errors.full_messages.any? { |message| message =~ /wasn't supplied/ }
    end

    test "no hook_attributes" do
      manifest = build(:integration_manifest, data: JSON.generate({
        "name" => "My App",
        "url" => "https://example.com",
        "redirect_url" => "https://example.com/complete",
      }))
      assert_predicate manifest, :valid?
    end

    test "with invalid JSON" do
      manifest = build(:integration_manifest, data: "not JSON")

      refute manifest.valid?
      assert_includes manifest.errors.full_messages, "The manifest is not valid JSON"
    end

    test "with nothing" do
      manifest = build(:integration_manifest, data: nil)

      refute manifest.valid?
      assert_includes manifest.errors.full_messages, "The manifest is not valid JSON"
    end

    test "fails when there is a user with the same name" do
      manifest = build(:integration_manifest, data: @valid_input, name: @user_with_name_clash.login)

      refute manifest.valid?
      assert_includes manifest.errors.full_messages, "Name is reserved for the account @#{@user_with_name_clash.login}"
    end

    test "invalid redirect_url" do
      manifest = build(:integration_manifest, data: JSON.generate({
        "version" => "v1",
        "url" => "https://example.com",
        "hook_attributes" => {
          "url" => "https://example.com/events",
        },
        "redirect_url" => "javascri\rpT://example.com/callback%0aalert(document.domain)//",
      }))

      refute_predicate manifest, :valid?
      assert_includes manifest.errors.full_messages, "redirect_url must be a valid URL"
    end

    test "invalid redirect_url with reserved query params" do
      manifest = build(:integration_manifest, data: JSON.generate({
        "version" => "v1",
        "url" => "https://example.com",
        "hook_attributes" => {
          "url" => "https://example.com/events",
        },
        "redirect_url" => "http://example.com?code=12345",
      }))

      refute_predicate manifest, :valid?
      assert_includes manifest.errors.full_messages, "redirect_url must be a valid URL"
    end

    test "valid JSON, but invalid integration" do
      manifest = build(:integration_manifest, data: @valid_json_invalid_integration)
      refute_predicate manifest, :valid?
      assert_includes manifest.errors.full_messages, "Default permissions access to single file is required."
    end
  end

  context "create_integration!" do
    test "works" do
      manifest = IntegrationManifest.create(
        owner: @user,
        creator: @user,
        name: "My app",
        data: @valid_input,
      )
      assert manifest.valid?

      integration, _ = manifest.create_integration!

      assert_equal "My app", integration.name
      assert_equal "https://example.com", integration.url
      assert_equal "https://example.com/events", integration.hook.url

      assert_predicate integration.hook, :active?
    end

    test "creates apps with private visibility by default" do
      input = JSON.generate({
        "version" => "v1",
        "url" => "https://example.com",
        "hook_attributes" => {
          "url" => "https://example.com/events",
        },
        "redirect_url" => "https://example.com/complete",
      })

      manifest = IntegrationManifest.create(
        owner: @user,
        creator: @user,
        name: "My app",
        data: input,
      )
      assert manifest.valid?

      integration, _ = manifest.create_integration!

      assert_predicate integration, :private_visibility?
    end

    test "creates apps with private visibility when specified" do
      input = JSON.generate({
        "version" => "v1",
        "url" => "https://example.com",
        "hook_attributes" => {
          "url" => "https://example.com/events",
        },
        "redirect_url" => "https://example.com/complete",
        "public" => false
      })

      manifest = IntegrationManifest.create(
        owner: @user,
        creator: @user,
        name: "My app",
        data: input,
      )
      assert manifest.valid?

      integration, _ = manifest.create_integration!

      assert_predicate integration, :private_visibility?
    end

    test "creates apps with public visibility when specified" do
      input = JSON.generate({
        "version" => "v1",
        "url" => "https://example.com",
        "hook_attributes" => {
          "url" => "https://example.com/events",
        },
        "redirect_url" => "https://example.com/complete",
        "public" => true
      })

      manifest = IntegrationManifest.create(
        owner: @user,
        creator: @user,
        name: "My app",
        data: input,
      )
      assert manifest.valid?

      integration, _ = manifest.create_integration!

      assert_predicate integration, :public_visibility?
    end

    test "works for setup_url and setup_on_update" do
      manifest = IntegrationManifest.create(
        owner: @user,
        creator: @user,
        name: "My app",
        data: @valid_input_with_setup,
      )
      assert manifest.valid?

      integration, pem = manifest.create_integration!

      assert_equal "https://example.com/setup", integration.setup_url
      assert_equal true, integration.setup_on_update
    end

    test "works for single_file_name" do
      manifest = IntegrationManifest.create(
        owner: @user,
        creator: @user,
        name: "My app",
        data: @manifest_input_with_single_file_name,
      )
      assert manifest.valid?

      integration, pem = manifest.create_integration!

      assert_equal ".github/config.yml", integration.single_file_name
    end

    test "works for user_provisioning", enterprise_only: true do
      manifest = IntegrationManifest.create(
        owner: @user,
        creator: @user,
        name: "My app with user provisioning",
        data: @manifest_input_with_user_provisioning,
      )
      assert manifest.valid?

      integration, pem = manifest.create_integration!

      assert_predicate integration, :persisted?
    end

    test "works when no hook attributes are provided" do
      manifest = IntegrationManifest.create(
        owner: @user,
        creator: @user,
        name: "My app",
        data: @manifest_input_without_hook_attributes,
      )
      assert_predicate manifest, :valid?

      integration, _ = manifest.create_integration!

      assert_equal "My app", integration.name
      assert_equal "https://example.com", integration.url
      assert_nil integration.hook
    end

    test "works when 'callback_url' is provided" do
      manifest = IntegrationManifest.create(
        owner: @user,
        creator: @user,
        name: "My app",
        data: @manifest_input_with_callback_url,
      )

      assert_predicate manifest, :valid?

      integration, _ = manifest.create_integration!

      assert_equal "My app", integration.name
      assert_equal "https://example.com", integration.url

      assert_nil integration.read_attribute(:callback_url)
      assert_same_elements ["https://example.com/auth/github/callback"], integration.application_callback_urls.map(&:url)
    end

    test "works when callback_urls are provided" do
      manifest = IntegrationManifest.create(
        owner: @user,
        creator: @user,
        name: "My app",
        data: @manifest_input_with_multiple_callback_urls,
      )

      assert_predicate manifest, :valid?

      integration, _ = manifest.create_integration!

      assert_equal "My app", integration.name
      assert_equal "https://example.com", integration.url

      assert_nil integration.read_attribute(:callback_url)
      assert_same_elements ["https://classroom.github.com/auth/github/callback"], integration.application_callback_urls.map(&:url)
    end

    test "works when request_oauth_on_install is provided" do
      manifest = IntegrationManifest.create(
        owner: @user,
        creator: @user,
        name: "My app",
        data: @manifest_input_with_request_oauth_on_install,
      )

      assert_predicate manifest, :valid?

      integration, _ = manifest.create_integration!

      assert_predicate integration, :request_oauth_on_install?
    end

    test "works when default_events are provided" do
      manifest = IntegrationManifest.create(
        owner: @user,
        creator: @user,
        name: "My app",
        data: @manifest_input_with_default_events,
      )

      assert_predicate manifest, :valid?

      integration, _ = manifest.create_integration!

      assert_equal "My app", integration.name
      assert_equal "https://example.com", integration.url

      assert_nil integration.read_attribute(:callback_url)
      assert_equal 1, integration.versions.length

      version = integration.versions.first
      assert_equal 1, version.default_event_records.length

      event = version.default_event_records.first
      assert_equal "issues", event.name
    end

    test "works when default_events containing INTEGRATOR_EVENTS are provided" do
      manifest = IntegrationManifest.create(
        owner: @user,
        creator: @user,
        name: "My app",
        data: @manifest_input_with_integrator_events,
      )

      assert_predicate manifest, :valid?

      integration, _ = manifest.create_integration!

      assert_equal "My app", integration.name
      assert_equal "https://example.com", integration.url

      assert_nil integration.read_attribute(:callback_url)
      assert_equal 1, integration.versions.length

      events = integration.hook.events
      assert_equal 1, events.length
      assert_equal "meta", events.first
    end
  end

  context "#readable_by?" do
    test "returns true without an actor" do
      manifest = create(:integration_manifest)
      assert manifest.readable_by?(nil)
    end
  end
end
