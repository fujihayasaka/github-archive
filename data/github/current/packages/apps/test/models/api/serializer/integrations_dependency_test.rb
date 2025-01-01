# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class IntegrationSerializersTest < Api::SerializerTestCase
  fixtures do
    @user = create(:user, login: "owner")
    @org  = create(:organization, login: "org", admin: @user)
    @repo = create(:repository, :minimal, owner: @user)

    @public_user_app  = create(:integration, :with_active_hook, owner: @user, name: "App", default_permissions: { "metadata" => :read }, default_events: ["public"])
  end

  context "#authentication_token_hash" do
    context "IntegrationInstallation" do
      test "payload is valid" do
        installation  = make_integration_installation(integration: @public_user_app, target: @org)
        record, token = AuthenticationToken.create_for(installation)

        output = serialize_hash_method(:authentication_token_hash, record, token: token)
        assert output.key?("token")
        assert output.key?("expires_at")
      end

      test "payload is valid with single_file permissions" do
        multi_single_file_app = create(:integration, owner: @user, name: "MultiSingleFileApp", default_permissions: { "metadata" => :read, "single_file" => :read }, single_file_paths: ["test.md"])

        parent       = make_integration_installation(integration: multi_single_file_app, target: @user)
        installation = make_scoped_integration_installation(parent: parent, repositories: [@repo])

        record, token = AuthenticationToken.create_for(installation)

        options = {
          token:        token,
          repositories: installation.repositories,
          permissions:  installation.permissions,
          single_file:  installation.single_file_name,
          has_multiple_single_files: false,
          single_file_paths: installation.single_file_paths
        }

        output = serialize_hash_method(:authentication_token_hash, record, options)
        assert_includes output["single_file_paths"], output["single_file"]
      end
    end

    context "ScopedIntegrationInstallation" do
      test "payload is valid" do
        parent       = make_integration_installation(integration: @public_user_app, target: @user)
        installation = make_scoped_integration_installation(parent: parent, repositories: [@repo])

        record, token = AuthenticationToken.create_for(installation)

        options = {
          token:        token,
          repositories: installation.repositories,
          permissions:  installation.permissions,
        }

        output = serialize_hash_method(:authentication_token_hash, record, options)
        assert output.key?("token")
        assert output.key?("expires_at")
        assert output.key?("permissions")
        assert output.key?("repositories")
      end
    end
  end

  test "integration_hash contains client_id" do
    output = serialize_hash_method(:integration_hash, @public_user_app)

    assert_equal @public_user_app.id, output["id"]
    assert_equal @public_user_app.slug, output["slug"]
    assert_equal @public_user_app.name, output["name"]
    assert_equal @public_user_app.description, output["description"]
    assert_equal @public_user_app.url, output["external_url"]
    assert_equal @public_user_app.key, output["client_id"]
    refute_nil output["html_url"]
  end

  context "#integration_hash for enterprise owned apps" do
    test "returns an owner that looks a bit like a user" do
      app = create(:enterprise_owned_integration)
      actual_owner = app.owner

      output = serialize_hash_method(:integration_hash, app)

      refute_nil serialized_owner = output["owner"]
      assert_equal actual_owner.display_login, serialized_owner["login"]
      assert_equal actual_owner.id, serialized_owner["id"]
    end
  end

  context "with html_url values" do
    test "returns path with only the app without owner scoping" do
      GitHub.flipper[:owner_scoped_github_apps].disable
      prefix = GitHub.enterprise? ? "github-apps" : "apps"

      output = serialize_hash_method(:integration_hash, @public_user_app)
      assert output["html_url"].end_with?("#{prefix}/app")
    end

    test "returns path with owner with scoping feature enabled" do
      GitHub.flipper[:owner_scoped_github_apps].enable
      prefix = GitHub.enterprise? ? "github-apps" : "apps"

      output = serialize_hash_method(:integration_hash, @public_user_app)
      assert output["html_url"].end_with?("#{prefix}/owner/app")
    end

    if GitHub.multi_tenant_enterprise?
      test "returns the third-party app path" do
        GitHub.flipper[:owner_scoped_github_apps].enable

        synced_app = create(:synchronized_integration, name: "Synced App Test Name")
        output = serialize_hash_method(:integration_hash, synced_app)

        assert output["html_url"].end_with?("/third-party-apps/synced-app-test-name")
      end
    end
  end

  IntegrationQuery = Api::App::PlatformClient.parse(<<-'GRAPHQL')
    query($id : ID!) {
      node(id: $id) {
        ...Api::Serializer::IntegrationsDependency::IntegrationFragment
      }
    }
  GRAPHQL

  IntegrationQueryWithClientId = Api::App::PlatformClient.parse(<<-'GRAPHQL')
    query($id : ID!) {
      node(id: $id) {
        ...Api::Serializer::IntegrationsDependency::IntegrationFragmentWithClientId
      }
    }
  GRAPHQL

  test "graphql_integration_hash" do
    query = IntegrationQueryWithClientId

    results = Api::App::PlatformClient.query(query, variables: { "id": @public_user_app.global_relay_id })
    graphql_output = serialize_hash_method(:graphql_integration_hash, results.data.node, { current_integration: @public_user_app })

    rest_output = serialize_hash_method(:integration_hash, @public_user_app)

    assert_same_hash graphql_output, rest_output, "REST and GraphQL output doesn't match"
  end

  if GitHub.multi_tenant_enterprise?
    test "synchronized third party integrations reference dotcom owner" do
      GitHub.flipper[:proxima_avatar_sync].enable

      synced_app = create(:synchronized_integration)
      owner_metadata = T.must(DotcomAppOwnerMetadata.find_by(local_app: synced_app))
      expected_api_base_url = "https://api.github.com/users/#{owner_metadata.display_login}"

      expected_owner_data = {
        login: owner_metadata.display_login,
        id: 0,
        node_id: "",
        avatar_url: owner_metadata.avatar_url,
        gravatar_id: "",
        url: expected_api_base_url,
        html_url: owner_metadata.url,
        followers_url: "#{expected_api_base_url}/followers",
        following_url: "#{expected_api_base_url}/following{/other_user}",
        gists_url: "#{expected_api_base_url}/gists{/gist_id}",
        starred_url: "#{expected_api_base_url}/starred{/owner}{/repo}",
        subscriptions_url: "#{expected_api_base_url}/subscriptions",
        organizations_url: "#{expected_api_base_url}/orgs",
        repos_url: "#{expected_api_base_url}/repos",
        events_url: "#{expected_api_base_url}/events{/privacy}",
        received_events_url: "#{expected_api_base_url}/received_events",
        type: "Organization",
        site_admin: false
      }

      rest_hash = serialize_hash_method(:integration_hash, synced_app)
      assert_same_hash expected_owner_data, rest_hash["owner"].symbolize_keys
    end

    test "synchronized third party integrations hashes are the same for REST and GraphQL" do
      GitHub.flipper[:proxima_avatar_sync].enable

      synced_app = create(:synchronized_integration)
      results = Api::App::PlatformClient.query(IntegrationQuery, variables: { "id": synced_app.global_relay_id })

      graphql_output = serialize_hash_method(:graphql_integration_hash, results.data.node)
      rest_output = serialize_hash_method(:integration_hash, synced_app)

      assert_equal graphql_output.to_json, rest_output.to_json, "REST and GraphQL output doesn't match"
    end
  end

  context "#integration_installation_request_hash" do
    test "payload is valid" do
      installation_request = create(:integration_installation_request, integration: @public_user_app)

      output = serialize_hash_method(:integration_installation_request_hash, installation_request)
      assert output.key?("id")
      assert output.key?("node_id")
      assert output.key?("account")
      assert output.key?("requester")
    end
  end

  context "installation_hash" do
    test "payload" do
      target = create(:user)
      app_installation = make_integration_installation(integration: @public_user_app, target: target)

      output = serialize_hash_method(:installation_hash, app_installation)

      assert_equal app_installation.id, output["id"]
      assert_equal target.id, output.dig("account", "id")
    end

    test "returns nothing if the installation is not provided" do
      assert_nil serialize_hash_method(:installation_hash, nil)
    end

    test "returns nothing if the installation's integration is not there" do
      app_installation = make_integration_installation(integration: @public_user_app, target: create(:user))
      app_installation.integration.delete; app_installation.reload

      assert_nil app_installation.integration
      assert_nil serialize_hash_method(:installation_hash, app_installation)
    end
  end

  context "suspended installation" do
    test "suspended via integrator" do
      app_installation = make_integration_installation(integration: @public_user_app, target: create(:user))
      app_installation.suspend!; app_installation.reload

      output = serialize_hash_method(:installation_hash, app_installation)

      assert_equal output["suspended_at"], ::Api::Serializer.time(app_installation.integrator_suspended_at)
    end

    test "suspended via user" do
      target = create(:user)

      app_installation = make_integration_installation(integration: @public_user_app, target: target)
      app_installation.suspend!(user: target); app_installation.reload

      output = serialize_hash_method(:installation_hash, app_installation)

      assert_equal output["suspended_at"], ::Api::Serializer.time(app_installation.user_suspended_at)
    end
  end
end
