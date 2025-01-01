# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/secrets_test_helpers"
require "test_helpers/fake_kredz"
require "test_helpers/codespaces_network_configuration_helpers"

class CodespacesVscsClientTest < GitHub::TestCase
  include DogstatsTestHelpers
  include CodespacesPlanFixtures
  include SecretsTestHelper
  include GitHub::LoggerHelper
  include CodespacesNetworkConfigurationTestHelper

  fixtures do
    make_trusted_oauth_apps_owner
    @integration = create(:codespaces_integration)
    @user = create(:user)
    @repo = create(:repository, owner: @user, from_example: :simple)
    @dotfiles_repo = create(:repository, owner: @user, name: "dotfiles")
    @plan = Codespaces::Plan.find_by!(vscs_target: "production", location: "WestUs2")
    @default_sku_name = :standardLinux32gb

    @enterprise = create :business
    @org = create(:business_plus_organization, business: @enterprise)
    @enterprise.add_organization(@org)

    @org_admin = @org.admins.first
    @org_repo = create(:repository, owner: @org, from_example: :simple)
    @org_protected_branch = create(:protected_branch, repository: @org_repo, creator: @user, required_status_checks_enforcement_level: :non_admins)

    @policy_group = create(:policy_group, owner: @org)
    create(:policy_group_membership, policy_group: @policy_group, target: @org)

    emu = create(:emu)
    @business = emu.enterprise_managed_business

    GitHub.flipper[:codespaces_vnet_injection_beta].disable
    GitHub.flipper[:codespaces_force_no_cache_cascade_token].disable
    GitHub.flipper[:codespaces_on_vm_monitoring_killswitch].disable
    GitHub.flipper[:codespaces_skip_requesting_access_token].enable
    GitHub.flipper[:codespaces_use_raw_fuse].disable
    GitHub.flipper[:codespaces_storage_v2_disallowed].disable
    [1, 2, 3].each do |i|
      tier_flag = "codespaces_on_vm_monitoring_killswitch_tier_#{i}".to_sym
      GitHub.flipper[tier_flag].disable
    end
  end

  context "#new" do
    context "#for_storage_account" do
      test "raises error when random plan can't be found using tenant plans" do
        on_multi_tenant_enterprise(tenant: @business) do
          FakeVSOServer.reset!

          business_id = @business.id
          location = "EastUs"
          tenant_plan = create(:codespace_plan, location: location, vscs_target: "production", business_id: business_id + 1, name: "#{business_id}-location")

          assert_raises(Codespaces::Plan::PlanNotFoundForTenant) do
            client = Codespaces::VscsClient.new(resource_provider: tenant_plan.resource_provider, vscs_target: Codespaces::Vscs.default_target, for_storage_tokens: true, user: @user)
          end
        end
      end
    end
  end

  context "#fetch_cascade_token" do
    test "is cached by the plan and user" do
      FakeVSOServer.reset!

      client1 = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      token1 = client1.fetch_cascade_token(user: @user)
      client2 = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      token2 = client2.fetch_cascade_token(user: @user)

      assert_equal token1, token2
      assert_equal 1, FakeVSOServer.tokens_created.count

      assert_dogstats_increment(1, "codespaces.client.cache", tags: ["type:cascade", "result:miss"])
      assert_dogstats_increment(1, "codespaces.client.cache", tags: ["type:cascade", "result:hit"])

      new_plan = create(:codespace_plan, business_id: 1)
      client3 = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: new_plan, user: @user, resource_provider: new_plan.resource_provider)
      token3 = client3.fetch_cascade_token(
        user: @user
      )

      refute_equal token1, token3
      assert_equal 2, FakeVSOServer.tokens_created.count

      assert_dogstats_increment(2, "codespaces.client.cache", tags: ["type:cascade", "result:miss"])

      client4 = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      token4 = client4.fetch_cascade_token(user: create(:user))

      refute_equal token1, token4
      assert_equal 3, FakeVSOServer.tokens_created.count

      assert_dogstats_increment(3, "codespaces.client.cache", tags: ["type:cascade", "result:miss"])
    end

    test "expires the token cache automatically" do
      FakeVSOServer.reset!

      client1 = Codespaces::VscsClient.new(resource_provider: @plan.resource_provider, vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user)
      token1 = client1.fetch_cascade_token(user: @user)
      client2 = Codespaces::VscsClient.new(resource_provider: @plan.resource_provider, vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user)
      token2 = client2.fetch_cascade_token(user: @user)

      assert_equal token1, token2
      assert_equal 1, FakeVSOServer.tokens_created.count

      travel Codespaces::VscsClient::CASCADE_TOKEN_EXPIRATION do
        client3 = Codespaces::VscsClient.new(resource_provider: @plan.resource_provider, vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user)
        token3 = client3.fetch_cascade_token(user: @user)

        refute_equal token1, token3
        assert_equal 2, FakeVSOServer.tokens_created.count
      end
    end

    test "sets an expiration time" do
      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(resource_provider: @plan.resource_provider, vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user)
      now = Time.current

      travel_to(now) do
        client.fetch_cascade_token(user: @user)

        assert token_params = FakeVSOServer.tokens_created.first
        assert_equal Codespaces::VscsClient::CASCADE_TOKEN_EXPIRATION.from_now.to_i, token_params["expiration"]
      end
    end

    test "does not cache token when for_unscoped_deletion_or_suspension is true" do
      FakeVSOServer.reset!

      client1 = Codespaces::VscsClient.new(resource_provider: @plan.resource_provider, vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user)
      token1 = client1.fetch_cascade_token(user: @user, for_unscoped_deletion_or_suspension: true)
      client2 = Codespaces::VscsClient.new(resource_provider: @plan.resource_provider, vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user)
      token2 = client2.fetch_cascade_token(user: @user, for_unscoped_deletion_or_suspension: true)

      refute_equal token1, token2
      assert_equal 2, FakeVSOServer.tokens_created.count
    end

    test "is cached by the plan only, when for_unscoped_management is true" do
      FakeVSOServer.reset!

      client1 = Codespaces::VscsClient.new(resource_provider: @plan.resource_provider, vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user)
      token1 = client1.fetch_cascade_token(user: @user, for_unscoped_management: true)
      client2 = Codespaces::VscsClient.new(resource_provider: @plan.resource_provider, vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user)
      token2 = client2.fetch_cascade_token(user: @user, for_unscoped_management: true)
      client3 = Codespaces::VscsClient.new(resource_provider: @plan.resource_provider, vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user)
      token3 = client3.fetch_cascade_token(user: create(:user), for_unscoped_management: true)

      assert_equal token1, token2
      assert_equal token1, token3
      assert_equal 1, FakeVSOServer.tokens_created.count

      assert_dogstats_increment(1, "codespaces.client.cache", tags: ["type:unscoped_management_cascade", "result:miss"])
      assert_dogstats_increment(2, "codespaces.client.cache", tags: ["type:unscoped_management_cascade", "result:hit"])

      new_plan = create(:codespace_plan, business_id: 1)
      client4 = Codespaces::VscsClient.new(resource_provider: new_plan.resource_provider, vscs_target: Codespaces::Vscs.default_target, plan: new_plan, user: @user)
      token4 = client4.fetch_cascade_token(
        user: @user,
        for_unscoped_management: true
      )

      refute_equal token1, token4
      assert_equal 2, FakeVSOServer.tokens_created.count

      assert_dogstats_increment(2, "codespaces.client.cache", tags: ["type:unscoped_management_cascade", "result:miss"])
    end

    test "allows disabling caching" do
      FakeVSOServer.reset!

      client1 = Codespaces::VscsClient.new(resource_provider: @plan.resource_provider, vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user)
      token1 = client1.fetch_cascade_token(user: @user, cache: false)
      client2 = Codespaces::VscsClient.new(resource_provider: @plan.resource_provider, vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user)
      token2 = client2.fetch_cascade_token(user: @user, cache: false)

      refute_equal token1, token2
      assert_equal 2, FakeVSOServer.tokens_created.count
    end

    test "allows setting the token expiration time" do
      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(resource_provider: @plan.resource_provider, vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user)
      now = Time.current

      travel_to(now) do
        client.fetch_cascade_token(user: @user, expires_in: 42.minutes)

        assert token_params = FakeVSOServer.tokens_created.first
        assert_equal 42.minutes.from_now.to_i, token_params["expiration"]
      end
    end

    test "scopes cascade tokens to an environment when `environment_id` is passed" do
      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(resource_provider: @plan.resource_provider, vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user)
      environment_id = SecureRandom.uuid

      client.fetch_cascade_token(user: @user, environment_id: environment_id)

      assert token_params = FakeVSOServer.tokens_created.first
      assert_equal [environment_id], token_params["environmentIds"]
      assert_equal "write:environments", token_params["scope"]
    end

    test "cache is scoped by `environment_id`" do
      FakeVSOServer.reset!

      client = Codespaces::VscsClient.new(resource_provider: @plan.resource_provider, vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user)
      environment_id_1 = SecureRandom.uuid
      environment_id_2 = SecureRandom.uuid

      client.fetch_cascade_token(user: @user, environment_id: environment_id_1)
      assert_equal 1, FakeVSOServer.tokens_created.count

      client.fetch_cascade_token(user: @user, environment_id: environment_id_2)
      assert_equal 2, FakeVSOServer.tokens_created.count

      client.fetch_cascade_token(user: @user, environment_id: environment_id_1)
      assert_equal 2, FakeVSOServer.tokens_created.count
    end

    test "cache is scoped by `scope`" do
      FakeVSOServer.reset!

      client = Codespaces::VscsClient.new(resource_provider: @plan.resource_provider, vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user)

      client.fetch_cascade_token(user: @user, scope: "test-scope-1")
      assert_equal 1, FakeVSOServer.tokens_created.count

      client.fetch_cascade_token(user: @user, scope: "test-scope-2")
      assert_equal 2, FakeVSOServer.tokens_created.count

      client.fetch_cascade_token(user: @user, scope: "test-scope-1")
      assert_equal 2, FakeVSOServer.tokens_created.count
    end

    test "cache is scoped by `ports`" do
      FakeVSOServer.reset!

      client = Codespaces::VscsClient.new(resource_provider: @plan.resource_provider, vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user)

      client.fetch_cascade_token(user: @user, ports: [80, 443])
      assert_equal 1, FakeVSOServer.tokens_created.count

      client.fetch_cascade_token(user: @user, ports: [8080])
      assert_equal 2, FakeVSOServer.tokens_created.count

      client.fetch_cascade_token(user: @user, ports: [80, 443])
      assert_equal 2, FakeVSOServer.tokens_created.count
    end
  end

  context "#fetch_cascade_token!" do
    test "requests with hmac" do
      FakeVSOServer.reset!

      client = Codespaces::VscsClient.new(resource_provider: @plan.resource_provider, vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user)
      client.send(:fetch_cascade_token!, user: @user, expires_in: 24.hours)

      requests = FakeVSOServer.requests_for("/writeDelegates")
      assert requests.length > 0

      requests.each do |request|
        refute_nil request.env["HTTP_REQUEST_HMAC"]
        assert_nil request.env["HTTP_AUTHORIZATION"]
      end
    end

    test "request with proxima url" do
      on_multi_tenant_enterprise(tenant: @business) do
        business_id = @business.id
        location = "EastUs"
        tenant_plan = create(:codespace_plan, location: location, vscs_target: "production", business_id: business_id, name: "#{business_id}-location")
        expected_url = "/plans/#{tenant_plan.name}"

        FakeVSOServer.reset!

        client = Codespaces::VscsClient.new(resource_provider: tenant_plan.resource_provider, vscs_target: Codespaces::Vscs.default_target, plan: tenant_plan, user: @user)
        client.send(:fetch_cascade_token!, user: @user, expires_in: 24.hours)

        requests = FakeVSOServer.requests_for("#{expected_url}/writeDelegates")
        assert requests.length > 0
      end
    end
  end

  context "#fetch_cascade_token_for_delete_or_suspend!" do
    test "requests with hmac" do
      FakeVSOServer.reset!

      client = Codespaces::VscsClient.new(resource_provider: @plan.resource_provider, vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user)
      client.send(:fetch_cascade_token_for_delete_or_suspend!)

      requests = FakeVSOServer.requests_for("/deleteAllCodespaces")
      assert requests.length > 0

      requests.each do |request|
        refute_nil request.env["HTTP_REQUEST_HMAC"]
        assert_nil request.env["HTTP_AUTHORIZATION"]
      end
    end

    test "request with proxima url" do
      on_multi_tenant_enterprise(tenant: @business) do
        business_id = @business.id
        location = "EastUs"
        tenant_plan = create(:codespace_plan, location: location, vscs_target: "production", business_id: business_id, name: "#{business_id}-location")
        expected_url = "/plans/#{tenant_plan.name}"
        FakeVSOServer.reset!

        client = Codespaces::VscsClient.new(resource_provider: tenant_plan.resource_provider, vscs_target: Codespaces::Vscs.default_target, plan: tenant_plan, user: @user)
        client.send(:fetch_cascade_token_for_delete_or_suspend!)

        requests = FakeVSOServer.requests_for("#{expected_url}/deleteAllCodespaces")
        assert requests.length > 0
      end
    end
  end

  context "#fetch_management_cascade_token!" do
    test "requests with hmac" do
      FakeVSOServer.reset!

      client = Codespaces::VscsClient.new(resource_provider: @plan.resource_provider, vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user)
      client.send(:fetch_management_cascade_token!, expires_in: 42.minutes)

      requests = FakeVSOServer.requests_for("/writeCodespaces")
      assert requests.length > 0

      requests.each do |request|
        refute_nil request.env["HTTP_REQUEST_HMAC"]
        assert_nil request.env["HTTP_AUTHORIZATION"]
      end
    end

    test "request with proxima url" do
      on_multi_tenant_enterprise(tenant: @business) do
        business_id = @business.id
        location = "EastUs"
        tenant_plan = create(:codespace_plan, location: location, vscs_target: "production", business_id: business_id, name: "#{business_id}-location")
        expected_url = "/plans/#{tenant_plan.name}"

        FakeVSOServer.reset!

        client = Codespaces::VscsClient.new(resource_provider: tenant_plan.resource_provider, vscs_target: Codespaces::Vscs.default_target, plan: tenant_plan, user: @user)
        client.send(:fetch_management_cascade_token!, expires_in: 42.minutes)

        requests = FakeVSOServer.requests_for("#{expected_url}/writeCodespaces")
        assert requests.length > 0
      end
    end
  end

  context "#fetch_storage_accounts_and_tokens" do
    test "makes an HMAC request to the new billing endpoint" do
      FakeVSOServer.reset!

      accounts_and_tokens = Codespaces::VscsClient.fetch_storage_accounts_and_tokens(vscs_target: Codespaces::Vscs.default_target)

      assert_equal FakeVSOServer::TEST_SAS_TOKEN, accounts_and_tokens["anything"]

      requests = FakeVSOServer.requests_for("/api/v1/billing")
      assert_equal 1, requests.length

      requests.each do |request|
        refute_nil request.env["HTTP_REQUEST_HMAC"]
        assert_nil request.env["HTTP_AUTHORIZATION"]
      end
    end

    test "caches the tokens" do
      FakeVSOServer.reset!

      accounts_and_tokens = Codespaces::VscsClient.fetch_storage_accounts_and_tokens(vscs_target: Codespaces::Vscs.default_target)

      assert_equal FakeVSOServer::TEST_SAS_TOKEN, accounts_and_tokens["anything"]

      accounts_and_tokens = Codespaces::VscsClient.fetch_storage_accounts_and_tokens(vscs_target: Codespaces::Vscs.default_target)

      requests = FakeVSOServer.requests_for("/api/v1/billing")
      # Should still have only made a single request because the second was cached
      assert_equal 1, requests.length
    end

    test "ignores the cache if bypassed" do
      FakeVSOServer.reset!

      accounts_and_tokens = Codespaces::VscsClient.fetch_storage_accounts_and_tokens(vscs_target: Codespaces::Vscs.default_target)

      assert_equal FakeVSOServer::TEST_SAS_TOKEN, accounts_and_tokens["anything"]

      accounts_and_tokens = Codespaces::VscsClient.fetch_storage_accounts_and_tokens(vscs_target: Codespaces::Vscs.default_target, bypass_cache: true)

      requests = FakeVSOServer.requests_for("/api/v1/billing")
      # Should have made a second request since we bypassed the cache
      assert_equal 2, requests.length
    end
  end

  context "instrumentation" do
    test "ok responses" do
      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider, location: "WestUs2")

      assert_dogstats_distribution(0, "codespaces.client.vscs_api.response.latency")
      assert_dogstats_distribution(0, "codespaces.client.arm_api.response.latency")

      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "", billable_owner: @user, create_type: "default")

      assert_dogstats_distribution(1, "codespaces.client.vscs_api.response.latency", tags: ["status:200", "caller:create_environment", "location:WestUs2"])
      assert_dogstats_distribution(0, "codespaces.client.arm_api.response.latency", tags: ["status:200", "caller:fetch_cascade_token", "timeout:false"])
      assert_dogstats_distribution(0, "codespaces.client.fetch_arm_token.response.latency", tags: ["status:200", "caller:fetch_arm_token"])
    end


    test "ok responses GitHub.flipper[:codespaces_remove_arm_client].disable" do
      GitHub.flipper[:codespaces_remove_arm_client].disable

      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider, location: "WestUs2")

      assert_dogstats_distribution(0, "codespaces.client.vscs_api.response.latency")

      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "", billable_owner: @user, create_type: "default")

      assert_dogstats_distribution(1, "codespaces.client.vscs_api.response.latency", tags: ["status:200", "caller:create_environment", "location:WestUs2"])
    end

    test "uses the portal for port forwarding auth" do
      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "", billable_owner: @user, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      assert_equal GitHub.url, environment["gitHubAppUrl"]
      assert_equal GitHub.api_url, environment["gitHubApiUrl"]
      portal_host = Codespaces::Vscs.config_for_target(Codespaces::Vscs.default_target)[:web_portal_url_format] % { name: "test-codespace", second_level_domain: GitHub.codespaces_web_portal_second_level_domain }
      assert_equal "#{portal_host}/pf-signin", environment["gitHubPfsAuthEndpoint"]
    end

    test "sends the environment endpoint when creating an environment" do
      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "",  billable_owner: @user, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      assert_equal "#{GitHub.api_url}/internal/vscs/environment_webhook", environment["githubEnvironmentEndpoint"]
    end

    test "error responses" do
      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider, location: "WestUs2")

      assert_dogstats_distribution(0, "codespaces.client.vscs_api.response.latency")
      assert_dogstats_distribution(0, "codespaces.client.arm_api.response.latency")

      # We want to test test all API request code paths. First, if we call
      # basically any method, we'll try to fetch an ARM token which should
      # fail...
      FakeVSOServer.response_status = 404
      FakeVSOServer.fake_responses = [
        {
          endpoint: "/api/v1/tokens/plans/#{@plan.name}/writeDelegates",
          status: 404,
          body: { accessToken: "" }.to_json,
        }
      ]
      assert_raises Codespaces::Error do
        client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "", billable_owner: @user, create_type: "default")
      end

      FakeVSOServer.response_status = 500
      assert_raises Codespaces::Error do
        client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "", billable_owner: @user, create_type: "default")
      end
      assert_dogstats_distribution(1, "codespaces.client.vscs_api.response.latency", tags: ["status:500", "caller:create_environment", "location:WestUs2"])
    end

    test "automated tagging" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_automated_testing].enable(@user)
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "", billable_owner: @user, create_type: "default")

      assert_dogstats_distribution(1, "codespaces.client.vscs_api.response.latency", tags: ["vscs_target:#{Codespaces::Vscs.default_target}", "codespaces_automated_testing:true"])
    end
  end

  test "does not request a cascade token by default" do
    FakeVSOServer.reset!
    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

    env = client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "", billable_owner: @user, create_type: "default")
    assert_nil env&.cascade_token
  end

  test "cascade token is not fetched even when requested" do
    FakeVSOServer.reset!
    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

    env = client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "", request_cascade_token: true, billable_owner: @user, create_type: "default")
    assert_nil env&.cascade_token
  end

  test "respects a provided devstamp API URL when targeting :local" do
    devstamp_url = "https://vscstest.ngrok.io"
    client = Codespaces::VscsClient.new(
      vscs_target: :local,
      api_url: devstamp_url,
      plan: @plan,
      user: @user,
      resource_provider: @plan.resource_provider
    )
    assert_equal devstamp_url, client.api_url
  end

  test "uses the default URL when provided with a blank api_url value" do
    client = Codespaces::VscsClient.new(
      vscs_target: :local,
      api_url: "",
      plan: @plan,
      user: @user,
      resource_provider: @plan.resource_provider
    )
    assert_equal "https://online.dev.core.vsengsaas.visualstudio.com", client.api_url
  end

  test "allows for a path prefix when providing devstamp API URL and targeting :local" do
    devstamp_url = "https://vscstest.ngrok.io/elpadann/"
    with_all_http_requests_disabled do
      # This base URL is not one of our _actual_ stubs for VSCS and I don't think
      # we really want it to be so this just uses stub_request directly and then
      # validates that we made a request to this URL to ensure that a devstamp
      # URL with a partial path in it properly appends the rest of the path
      # instead of ignoring the path in the devstamp URL.
      stub_req = stub_request(:get, "https://vscstest.ngrok.io/elpadann/api/v1/environments").
        to_return(status: 200, body: "{}")

      Codespaces::VscsClient.any_instance.stubs(:fetch_cascade_token).returns({ token: "token", expiration: "" }.to_json)

      client = Codespaces::VscsClient.new(
        vscs_target: :local,
        api_url: devstamp_url,
        plan: @plan,
        user: @user,
        resource_provider: @plan.resource_provider
      )
      client.list_environments
      assert_requested(stub_req)
    end
  end

  test "create_environment logs response body on unsuccessful responses" do
    FakeVSOServer.reset!
    client = Codespaces::VscsClient.new(
      vscs_target: Codespaces::Vscs.default_target,
      plan: @plan,
      user: @user,
      resource_provider: @plan.resource_provider
    )
    FakeVSOServer.fake_responses = [
      {
        endpoint: "/environments",
        status: 409,
        body: "32",
      }
    ]

    assert_raises Codespaces::Client::BadResponseError do
      assert_logged response_body: "32" do
        client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "", billable_owner: @user, create_type: "default")
      end
    end
  end

  test "create_environment logging scrubs sensitive data" do
    FakeVSOServer.reset!
    client = Codespaces::VscsClient.new(
      vscs_target: Codespaces::Vscs.default_target,
      plan: @plan,
      user: @user,
      resource_provider: @plan.resource_provider
    )
    FakeVSOServer.fake_responses = [
      {
        endpoint: "/environments",
        status: 400,
        body: { error_message: "No can do." }.to_json,
      }
    ]

    output = capture_logs do
      assert_raises Codespaces::Client::BadResponseError do
        client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "", billable_owner: @user, create_type: "default")
      end
    end

    assert output.slice('secrets\":\"[FILTERED SECRETS]\"')
    assert output.slice('connection\":\"[FILTERED CONNECTION]\"')
    assert output.slice('response_body="{\"error_message\":\"No can do.\"}"')
  end

  test "create_environment includes secrets into the request body" do
    FakeVSOServer.reset!
    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

    client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

    environment = FakeVSOServer.environments_created.last
    assert_same_elements default_secrets(@user, repository_nwo: @repo.name_with_owner, vscs_target_url: client.api_url), environment["secrets"]
  end

  test "create_environment includes copilotWorkspaceConfig as a secret into the request body" do
    FakeVSOServer.reset!
    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
    copilot_workspace_config = {
      "featureBranchName": "test",
      "fileSyncerConfig": {
        "sessionId": "test_session_id",
        "codeline": "Development",
        "baseSha": "test-sha",
        "jwt": "token"
      }
    }

    client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default", environment_options: { "copilotWorkspaceConfig": copilot_workspace_config })
    environment = FakeVSOServer.environments_created.last
    copilot_workspace_secret = environment["secrets"].find { |s| s["type"] == Codespaces::Secret::TYPE_ENV_VAR && s["name"] == "GITHUB_COPILOT_WORKSPACE_CONFIG" }
    refute_nil copilot_workspace_secret
    assert copilot_workspace_secret["value"].include?("{\"featureBranchName\":\"test\",\"fileSyncerConfig\":{\"sessionId\":\"test_session_id\",\"codeline\":\"Development\",\"baseSha\":\"test-sha\",\"jwt\":\"token\"}}")
  end

  test "create_environment includes defaults secrets into the request body if copilotWorkspaceConfig is empty" do
    FakeVSOServer.reset!
    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

    client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default", environment_options: { "copilotWorkspaceConfig": {} })

    environment = FakeVSOServer.environments_created.last
    assert_same_elements default_secrets(@user, repository_nwo: @repo.name_with_owner, vscs_target_url: client.api_url), environment["secrets"]
    copilot_workspace_secret = environment["secrets"].find { |s| s["type"] == Codespaces::Secret::TYPE_ENV_VAR && s["name"] == "GITHUB_COPILOT_WORKSPACE_CONFIG" }
    assert_nil copilot_workspace_secret
  end

  test "create_environment includes defaults secrets into the request body if copilotWorkspaceConfig is not convertable to json" do
    FakeVSOServer.reset!
    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

    client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default", environment_options: { "copilotWorkspaceConfig": nil })

    environment = FakeVSOServer.environments_created.last
    assert_same_elements default_secrets(@user, repository_nwo: @repo.name_with_owner, vscs_target_url: client.api_url), environment["secrets"]
    copilot_workspace_secret = environment["secrets"].find { |s| s["type"] == Codespaces::Secret::TYPE_ENV_VAR && s["name"] == "GITHUB_COPILOT_WORKSPACE_CONFIG" }
    assert_nil copilot_workspace_secret
  end

  test "create_environment includes correlation_data in the request body" do
    FakeVSOServer.reset!
    client = Codespaces::VscsClient.new(
      vscs_target: Codespaces::Vscs.default_target,
      plan: @plan,
      user: @user,
      resource_provider: @plan.resource_provider
    )

    client.create_environment(
      "WestUs2",
      @repo,
      sku_name: @default_sku_name,
      name: "test-codespace",
      moniker: @repo.permalink,
      github_token: "github_token",
      billable_owner: @user,
      create_type: "default",
    )

    environment = FakeVSOServer.environments_created.last
    expected_data = {
      "billableOwnerGlobalRelayId" => @user.global_relay_id,
      "billableOwnerDatabaseId" => @user.id,
      "billableOwnerCreatedAt" => @user.created_at.utc.iso8601(3),
      "billableOwnerPlan" => @user.plan.to_s,
      "ownerGlobalRelayId" => @user.global_relay_id,
      "ownerDatabaseId" => @user.id,
      "ownerCreatedAt" => @user.created_at.utc.iso8601(3),
      "ownerPlan" => @user.plan.to_s,
      "repositoryGlobalRelayId" => @repo.global_relay_id,
      "repositoryDatabaseId" => @repo.id,
      "repositoryCreatedAt" => @repo.created_at.utc.iso8601(3),
      "repositoryPrivate" => @repo.private?,
    }
    assert_same_hash expected_data, environment["netmonCorrelationData"]
  end

  test "create_environment includes subnet_id in request body if enabled and configured through org policy" do
    test_subnet_id_string = "/test/subnet/id/string"
    user = create(:user)
    org = setup_vnet_injection_org(admin: user, subnet_id: test_subnet_id_string, regions: ["WestUs2"])
    repo = create(:repository, owner: org)

    FakeVSOServer.reset!
    client = Codespaces::VscsClient.new(
      vscs_target: Codespaces::Vscs.default_target,
      plan: @plan,
      user: user,
      resource_provider: @plan.resource_provider
    )

    client.create_environment(
      "WestUs2",
      repo,
      sku_name: @default_sku_name,
      name: "test-codespace",
      moniker: repo.permalink,
      github_token: "github_token",
      billable_owner: org,
      create_type: "default",
      secrets: [],
    )

    environment = FakeVSOServer.environments_created.last
    assert_equal test_subnet_id_string, environment["vnetInjectionSubnetId"]
  end

  context "start_environment error handling", skip_enterprise: true do
    test "it properly wraps Faraday::TimeoutError" do
      guid = SecureRandom.uuid
      FakeVSOServer.reset!
      FakeVSOServer.environments << { "id" => guid, "state" => Codespaces::Vscs::State::SHUTDOWN }
      client = Codespaces::VscsClient.new(
        vscs_target: Codespaces::Vscs.default_target,
        plan: @plan,
        user: @user,
        resource_provider: @plan.resource_provider,
      )
      client.stubs(:vscs_api_hmac_raw).raises(Faraday::TimeoutError.new("timeout"))

      assert_raises Codespaces::VscsClient::TimeoutError do
        client.start_environment(guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user)
      end
    end

    test "it raises a BadResponseError if we get a 4xx from the FE" do
      guid = SecureRandom.uuid
      FakeVSOServer.reset!
      FakeVSOServer.fake_responses = [
        {
          endpoint: "/api/v1/environments/#{guid}/start",
          status: 400,
          body: "SuperBrokenBuddy",
        }
      ]
      client = Codespaces::VscsClient.new(
        vscs_target: Codespaces::Vscs.default_target,
        plan: @plan,
        user: @user,
        resource_provider: @plan.resource_provider,
      )

      assert_raises Codespaces::Client::BadResponseError do
        client.start_environment(guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user)
      end
    end
  end

  context "start_environment conditionally sends analyticsId flag" do
    test "not set when flag is disabled" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_enable_analytics_id].disable(@user)

      codespace = create(:codespace, owner: @user)
      FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN }

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.start_environment(codespace.guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user)

      environment = FakeVSOServer.environments_started.last
      assert_nil environment["gitHubAnalyticsId"]
    end

    test "set when flag is enabled" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_enable_analytics_id].enable(@user)

      codespace = create(:codespace, owner: @user)
      FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN }

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.start_environment(codespace.guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user)

      environment = FakeVSOServer.environments_started.last
      expected_value = @user.analytics_tracking_id
      assert_equal expected_value, environment["gitHubAnalyticsId"]
    end
  end

  context "create_environment conditionally sends analyticsId flag" do
    test "create_environment does not include analyticsId as value in the request body" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_enable_analytics_id].disable(@user)
      client = Codespaces::VscsClient.new(
        vscs_target: Codespaces::Vscs.default_target,
        plan: @plan,
        user: @user,
        resource_provider: @plan.resource_provider
      )

      client.create_environment(
        "WestUs2",
        @repo,
        sku_name: @default_sku_name,
        name: "test-codespace",
        moniker: @repo.permalink,
        github_token: "github_token",
        billable_owner: @user,
        create_type: "default",
      )

      environment = FakeVSOServer.environments_created.last
      assert_nil environment["gitHubAnalyticsId"]
    end
    test "create_environment includes analyticsId as value in the request body" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_enable_analytics_id].enable(@user)
      client = Codespaces::VscsClient.new(
        vscs_target: Codespaces::Vscs.default_target,
        plan: @plan,
        user: @user,
        resource_provider: @plan.resource_provider
      )

      client.create_environment(
        "WestUs2",
        @repo,
        sku_name: @default_sku_name,
        name: "test-codespace",
        moniker: @repo.permalink,
        github_token: "github_token",
        billable_owner: @user,
        create_type: "default",
      )

      environment = FakeVSOServer.environments_created.last
      expected_data = @user.analytics_tracking_id
      assert_equal expected_data, environment["gitHubAnalyticsId"]
    end
  end

  test "create_environment sends prebuild data for repo if prebuilds are configured for repo" do
    FakeVSOServer.reset!
    oid =  @repo.heads["master"].target_oid
    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider, oid: oid, branch: "master")
    Codespaces::Prebuilds.stubs(:configured?).returns(true)

    client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, prebuild_allowed: true, create_type: "default")

    environment = FakeVSOServer.environments_created.last
    seed = environment["seed"]
    repository = environment["seed"]["repository"]

    refute_nil seed
    refute_nil repository
    refute_nil repository["prebuild_hash"]
    assert environment["experimentalFeatures"]["usePrebuiltImages"]
    assert_equal "master", repository["branch"]
    assert_equal oid, repository["commit"]
  end

  test "create_environment sends prebuild data for repo when a prebuild template exists" do
    create(:codespace_prebuild_configuration, repository: @repo, branch: @repo.default_branch)

    FakeVSOServer.reset!
    oid =  @repo.heads["master"].target_oid
    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider, oid: oid, branch: @repo.default_branch)

    client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

    environment = FakeVSOServer.environments_created.last
    seed = environment["seed"]
    repository = environment["seed"]["repository"]

    refute_nil seed
    refute_nil repository
    refute_nil repository["prebuild_hash"]
    assert_equal "master", repository["branch"]
    assert_equal oid, repository["commit"]
  end

  test "create_environment finds private dotfiles repos" do
    @user.enable_codespace_dotfiles(actor: @user)
    FakeVSOServer.reset!

    @dotfiles_repo.update(private: true)

    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

    client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

    environment = FakeVSOServer.environments_created.last
    refute_nil environment.dig("personalization", "dotfilesRepository")
  end

  test "create_environment find dotfiles from user setting" do
    @private_dotfiles_repo = create(:private_repository, owner: @user, name: "private-dotfiles")
    @user.enable_codespace_dotfiles(actor: @user)
    @user.update_codespace_dotfiles_repository(@private_dotfiles_repo.id, actor: @user)
    FakeVSOServer.reset!

    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

    client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

    environment = FakeVSOServer.environments_created.last
    assert_equal "#{GitHub.url}/#{@private_dotfiles_repo.nwo}", environment.dig("personalization", "dotfilesRepository")
  end

  test "create environment obeys dotfiles_enabled user configuration" do
    @user.disable_codespace_dotfiles(actor: @user)
    FakeVSOServer.reset!
    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

    client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

    environment = FakeVSOServer.environments_created.last
    refute environment.dig("personalization", "dotfilesRepository")
  end

  test "create_environment sends testAccount flag" do
    GitHub.flipper[:codespaces_automated_testing].disable
    FakeVSOServer.reset!
    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

    client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

    environment = FakeVSOServer.environments_created.last
    refute environment["testAccount"]

    GitHub.flipper[:codespaces_automated_testing].enable(@user)
    FakeVSOServer.reset!
    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

    client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

    environment = FakeVSOServer.environments_created.last
    assert environment["testAccount"]
  end

  test "create_environment sends processKillTracing flag" do
    GitHub.flipper[:codespaces_process_kill_tracing].disable
    FakeVSOServer.reset!
    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

    client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

    environment = FakeVSOServer.environments_created.last
    refute environment.dig("features", "processKillTracing")

    GitHub.flipper[:codespaces_process_kill_tracing].enable(@user)
    FakeVSOServer.reset!
    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

    client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

    environment = FakeVSOServer.environments_created.last
    assert environment.dig("features", "processKillTracing")
  end

  context "create_environment conditionally requests access token" do
    test "not set when flag is enabled" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_skip_requesting_access_token].enable(@user)

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default", request_cascade_token: true)
      create_request = FakeVSOServer.requests.last
      assert_equal "access=false", create_request.query_string
    end

    test "not set even when flag is disabled" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_skip_requesting_access_token].disable(@user)

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default", request_cascade_token: true)
      create_request = FakeVSOServer.requests.last
      assert_equal "access=false", create_request.query_string
    end
  end

  context "start_environment conditionally requests access token" do
    test "not set when flag is enabled" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_skip_requesting_access_token].enable(@user)

      codespace = create(:codespace, owner: @user)
      FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN }

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.start_environment(codespace.guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user, request_cascade_token: true)

      request = FakeVSOServer.requests.last
      assert_equal "access=false", request.query_string
    end

    test "not set even when flag is disabled" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_skip_requesting_access_token].disable(@user)

      codespace = create(:codespace, owner: @user)
      FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN }

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.start_environment(codespace.guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user, request_cascade_token: true)

      request = FakeVSOServer.requests.last
      assert_equal "access=false", request.query_string
    end
  end

  context "create_environment sends installPostCommitForkHook" do
    test "when user can fork the repo but not push to the repo" do
      public_repo = create(:repository, from_example: :simple)
      public_repo.heads.find_or_build("master")

      codespace = create(:codespace, :unpushable, owner: @user, repository: public_repo, ref: "master")

      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

      client.create_environment("WestUs2", public_repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      assert environment.dig("features", "installPostCommitForkHook")
    end

    test "when user has forked the repo, can't push to the repo, but can't fork the repo anymore" do
      repo = create(:repository, from_example: :simple)
      repo.heads.find_or_build("master")

      # create  fork before the codespace
      create(:fork_repository, forker: @user, fork_repo: repo)
      assert @user.has_forked?(repo)

      # make sure user can no longer create new forks
      repo.private = true
      repo.save!
      refute @user.can_fork?(repo)

      codespace = create(:codespace, :unpushable, owner: @user, repository: repo, ref: "master")

      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

      client.create_environment("WestUs2", repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      assert environment.dig("features", "installPostCommitForkHook")
    end

    test "not when user can't fork the repo" do
      unforkable_repo = create(:org_owned_private_repository)
      example_repo :simple, unforkable_repo

      codespace = create(:codespace, :unpushable, owner: @user, repository: unforkable_repo)

      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

      client.create_environment("WestUs2", unforkable_repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      refute environment.dig("features", "installPostCommitForkHook")
    end

    test "not when user can push to the repo" do
      public_repo = create(:repository, from_example: :simple)
      public_repo.heads.find_or_build("master")

      codespace = create(:codespace, owner: @user, repository: public_repo, ref: "master")

      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

      client.create_environment("WestUs2", public_repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      refute environment.dig("features", "installPostCommitForkHook")
    end
  end

  test "create_environment passes through feature flags" do
    GitHub.flipper[:codespaces_consolidate_feature_flags].enable
    FakeVSOServer.reset!

    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

    Codespaces::Vscs::OWNER_FEATURE_FLAGS.each { |f| GitHub.flipper[f].disable(@user) }
    client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, moniker: @repo.permalink, name: "test", github_token: "github_token", billable_owner: @user, create_type: "default")
    environment = FakeVSOServer.environments_created.last
    assert environment.dig("features")
    Codespaces::Vscs.feature_flags(@user).each do |key, value|
      assert_equal value, environment.dig("features", key)
    end

    Codespaces::Vscs::OWNER_FEATURE_FLAGS.each { |f| GitHub.flipper[f].enable(@user) }
    client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, moniker: @repo.permalink, name: "test", github_token: "github_token", billable_owner: @user, create_type: "default")
    environment = FakeVSOServer.environments_created.last
    assert environment.dig("features")
    Codespaces::Vscs.feature_flags(@user).each do |key, value|
      assert_equal value, environment.dig("features", key)
    end
  end

  test "create_environment passes through feature flags applied to its billable_owner" do
    GitHub.flipper[:codespaces_consolidate_feature_flags].enable
    FakeVSOServer.reset!

    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

    Codespaces::Vscs::OWNER_FEATURE_FLAGS.each { |f| GitHub.flipper[f].disable(@user) }
    Codespaces::Vscs::BILLABLE_OWNER_FEATURE_FLAGS.each { |f| GitHub.flipper[f].disable(@org) }
    client.create_environment("WestUs2", @org_repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @org_repo.permalink, github_token: "github_token", billable_owner: @org, create_type: "default")
    environment = FakeVSOServer.environments_created.last
    assert environment.dig("features")
    Codespaces::Vscs.feature_flags(@user, @org).each do |key, value|
      assert_equal value, environment.dig("features", key)
    end

    Codespaces::Vscs::OWNER_FEATURE_FLAGS.each { |f| GitHub.flipper[f].enable(@user) }
    Codespaces::Vscs::BILLABLE_OWNER_FEATURE_FLAGS.each { |f| GitHub.flipper[f].enable(@org) }
    client.create_environment("WestUs2", @org_repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @org_repo.permalink, github_token: "github_token", billable_owner: @org, create_type: "default")
    environment = FakeVSOServer.environments_created.last
    assert environment.dig("features")
    Codespaces::Vscs.feature_flags(@user, @org).each do |key, value|
      assert_equal value, environment.dig("features", key)
    end
  end

  test "start_environment passes through feature flags" do
    GitHub.flipper[:codespaces_consolidate_feature_flags].enable
    FakeVSOServer.reset!

    codespace = create(:codespace, owner: @user)
    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
    FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN }

    Codespaces::Vscs::OWNER_FEATURE_FLAGS.each { |f| GitHub.flipper[f].disable(@user) }
    client.start_environment(codespace.guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user)
    environment = FakeVSOServer.environments_started.last
    assert environment.dig("features")
    Codespaces::Vscs.feature_flags(@user).each do |key, value|
      assert_equal value, environment.dig("features", key)
    end

    Codespaces::Vscs::OWNER_FEATURE_FLAGS.each { |f| GitHub.flipper[f].enable(@user) }
    client.start_environment(codespace.guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user)
    environment = FakeVSOServer.environments_started.last
    assert environment.dig("features")
    Codespaces::Vscs.feature_flags(@user).each do |key, value|
      assert_equal value, environment.dig("features", key)
    end
  end

  test "start_environment passes through feature flags applied to its billable_owner" do
    GitHub.flipper[:codespaces_consolidate_feature_flags].enable
    FakeVSOServer.reset!

    codespace = create(:codespace, owner: @user)
    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
    FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN }

    Codespaces::Vscs::OWNER_FEATURE_FLAGS.each { |f| GitHub.flipper[f].disable(@user) }
    Codespaces::Vscs::BILLABLE_OWNER_FEATURE_FLAGS.each { |f| GitHub.flipper[f].disable(@org) }
    client.start_environment(codespace.guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @org)
    environment = FakeVSOServer.environments_started.last
    assert environment.dig("features")
    Codespaces::Vscs.feature_flags(@user, @org).each do |key, value|
      assert_equal value, environment.dig("features", key)
    end

    Codespaces::Vscs::OWNER_FEATURE_FLAGS.each { |f| GitHub.flipper[f].enable(@user) }
    Codespaces::Vscs::BILLABLE_OWNER_FEATURE_FLAGS.each { |f| GitHub.flipper[f].enable(@org) }
    client.start_environment(codespace.guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @org)
    environment = FakeVSOServer.environments_started.last
    assert environment.dig("features")
    Codespaces::Vscs.feature_flags(@user, @org).each do |key, value|
      assert_equal value, environment.dig("features", key)
    end
  end

  test "start_environment includes vnet-injection subnet id if configured and in the correct region" do
    vnet_injected_region = "WestUs2"
    test_subnet_id_string = "/test/subnet/id/string"
    user = create(:user)
    org = setup_vnet_injection_org(admin: user, subnet_id: test_subnet_id_string, regions: [vnet_injected_region])
    repo = create(:repository, owner: org)

    codespace = create(:codespace, owner: user, repository: repo, location: vnet_injected_region)

    FakeVSOServer.reset!
    FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN }

    client = Codespaces::VscsClient.new(
      vscs_target: Codespaces::Vscs.default_target,
      plan: @plan,
      user: user,
      resource_provider: @plan.resource_provider,
      location: codespace.location,
    )

    client.start_environment(
      codespace.guid,
      github_token: "github_token",
      sku_name: "basicLinux",
      repository: repo,
      billable_owner: org,
      secrets: [],
    )

    environment = FakeVSOServer.environments_started.last
    assert_equal test_subnet_id_string, environment["vnetInjectionSubnetId"]
  end

  test "start_environment raises exception when fetching vnet-injection subnet id if configured and codespace exists in wrong region" do
    vnet_injected_region = "WestUs2"
    test_subnet_id_string = "/test/subnet/id/string"
    user = create(:user)
    org = setup_vnet_injection_org(admin: user, subnet_id: test_subnet_id_string, regions: [vnet_injected_region])
    repo = create(:repository, owner: org)

    codespace = create(:codespace, owner: user, repository: repo, location: "EastUs")

    client = Codespaces::VscsClient.new(
      vscs_target: Codespaces::Vscs.default_target,
      plan: @plan,
      user: user,
      resource_provider: @plan.resource_provider,
      location: codespace.location,
    )

    assert_raises(Codespaces::VscsClient::VNetInjectionNotAvailableForRegionError) do
      client.start_environment(
        codespace.guid,
        github_token: "github_token",
        sku_name: "basicLinux",
        repository: repo,
        billable_owner: org,
        secrets: [],
      )
    end
  end

  context "create_environment conditionally sets enableOnVmSwapping feature" do
    test "set when flag is enabled" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_enable_on_vm_swap].enable(@user)

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace-with-on-vm-swapping-enabled", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      assert environment.dig("features", "enableOnVmSwapping")
    end

    test "not set when flag is disabled" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_enable_on_vm_swap].disable(@user)

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace-with-on-vm-swapping-enabled", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      refute environment.dig("features", "enableOnVmSwapping")
    end
  end

  context "start_environment conditionally sends enableOnVmSwapping flag" do
    test "set when flag is enabled" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_enable_on_vm_swap].enable(@user)

      codespace = create(:codespace, owner: @user)
      FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN }

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.start_environment(codespace.guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user)

      environment = FakeVSOServer.environments_started.last
      assert environment.dig("features", "enableOnVmSwapping")
    end

    test "not set when flag is disabled" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_enable_on_vm_swap].disable(@user)

      codespace = create(:codespace, owner: @user)
      FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN }

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.start_environment(codespace.guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user)

      environment = FakeVSOServer.environments_started.last
      refute environment.dig("features", "enableOnVmSwapping")
    end
  end

  context "create_environment conditionally sets enableProvjobd feature" do
    test "set when flag is enabled" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_enable_on_vm_monitoring].enable(@user)

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace-with-on-vm-monitoring-enabled", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      assert environment.dig("features", "enableProvjobd")
    end

    test "not set when flag is disabled" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_enable_on_vm_monitoring].disable(@user)

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace-with-on-vm-monitoring-enabled", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      refute environment.dig("features", "enableProvjobd")
    end

    test "not set when user has killswitch enabled" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_enable_on_vm_monitoring].enable(@user)
      GitHub.flipper[:codespaces_on_vm_monitoring_killswitch].enable(@user)

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace-with-on-vm-monitoring-enabled", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      refute environment.dig("features", "enableProvjobd")
    end

    test "not set when billable_owner has killswitch enabled" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_enable_on_vm_monitoring].enable(@user)
      GitHub.flipper[:codespaces_on_vm_monitoring_killswitch].enable(@org)

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace-with-on-vm-monitoring-enabled", moniker: @repo.permalink, github_token: "github_token", billable_owner: @org, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      refute environment.dig("features", "enableProvjobd")
    end

    test "not set when repo has killswitch enabled" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_enable_on_vm_monitoring].enable(@user)
      GitHub.flipper[:codespaces_on_vm_monitoring_killswitch].enable(@repo)

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace-with-on-vm-monitoring-enabled", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      refute environment.dig("features", "enableProvjobd")
    end

    test "not set when tier killswitch is enabled" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_enable_on_vm_monitoring].enable(@user)
      Codespaces::Tier.expects(:for_user).with(@user).at_least(0).returns(TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::ESTABLISHED_BILLING))
      GitHub.flipper[:codespaces_on_vm_monitoring_killswitch_tier_1].enable

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace-with-on-vm-monitoring-enabled", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      refute environment.dig("features", "enableProvjobd")
    end
  end

  context "start_environment conditionally sends enableProvjobd flag" do
    test "set when flag is enabled" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_enable_on_vm_monitoring].enable(@user)

      codespace = create(:codespace, owner: @user)
      FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN }

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.start_environment(codespace.guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user)

      environment = FakeVSOServer.environments_started.last
      assert environment.dig("features", "enableProvjobd")
    end

    test "not set when flag is disabled" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_enable_on_vm_monitoring].disable(@user)

      codespace = create(:codespace, owner: @user)
      FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN }

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.start_environment(codespace.guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user)

      environment = FakeVSOServer.environments_started.last
      refute environment.dig("features", "enableProvjobd")
    end

    test "not set when user has killswitch enabled" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_enable_on_vm_monitoring].enable(@user)
      GitHub.flipper[:codespaces_on_vm_monitoring_killswitch].enable(@user)

      codespace = create(:codespace, owner: @user)
      FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN }

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.start_environment(codespace.guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user)

      environment = FakeVSOServer.environments_started.last
      refute environment.dig("features", "enableProvjobd")
    end

    test "not set when billable_owner has killswitch enabled" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_enable_on_vm_monitoring].enable(@user)
      GitHub.flipper[:codespaces_on_vm_monitoring_killswitch].enable(@org)

      codespace = create(:codespace, owner: @user)
      FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN }

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.start_environment(codespace.guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @org)

      environment = FakeVSOServer.environments_started.last
      refute environment.dig("features", "enableProvjobd")
    end

    test "not set when repo has killswitch enabled" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_enable_on_vm_monitoring].enable(@user)
      GitHub.flipper[:codespaces_on_vm_monitoring_killswitch].enable(@repo)

      codespace = create(:codespace, owner: @user)
      FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN }

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.start_environment(codespace.guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user)

      environment = FakeVSOServer.environments_started.last
      refute environment.dig("features", "enableProvjobd")
    end

    test "not set when tier killswitch is enabled" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_enable_on_vm_monitoring].enable(@user)
      Codespaces::Tier.expects(:for_user).with(@user).at_least(0).returns(TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::ESTABLISHED_BILLING))
      GitHub.flipper[:codespaces_on_vm_monitoring_killswitch_tier_1].enable

      codespace = create(:codespace, owner: @user)
      FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN }

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.start_environment(codespace.guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user)

      environment = FakeVSOServer.environments_started.last
      refute environment.dig("features", "enableProvjobd")
    end
  end

  context "create_environment conditionally sets usePublicDevcontainerCli feature" do
    test "set when flag is enabled" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_use_public_devcontainer_cli].enable(@user)

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace-with-use-public-devcontainer-cli-enabled", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      assert environment.dig("features", "usePublicDevcontainerCli")
    end

    test "not set when flag is disabled" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_use_public_devcontainer_cli].disable(@user)

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace-with-use-public-devcontainer-cli-disabled", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      refute environment.dig("features", "usePublicDevcontainerCli")
    end
  end

  context "start_environment conditionally sends usePublicDevcontainerCli flag" do
    test "set when flag is enabled" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_use_public_devcontainer_cli].enable(@user)

      codespace = create(:codespace, owner: @user)
      FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN }

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.start_environment(codespace.guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user)

      environment = FakeVSOServer.environments_started.last
      assert environment.dig("features", "usePublicDevcontainerCli")
    end

    test "not set when flag is disabled" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_use_public_devcontainer_cli].disable(@user)

      codespace = create(:codespace, owner: @user)
      FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN }

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.start_environment(codespace.guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user)

      environment = FakeVSOServer.environments_started.last
      refute environment.dig("features", "usePublicDevcontainerCli")
    end
  end

  context "create_environment conditionally sets experimentalDevContainerLockfile feature" do
    test "set when flag is enabled" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_experimental_dev_container_lockfile].enable(@user)

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace-with-dev-container-lockfile-enabled", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      assert environment.dig("features", "experimentalDevContainerLockfile")
    end

    test "not set when flag is disabled" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_experimental_dev_container_lockfile].disable(@user)

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace-with-dev-container-lockfile-disabled", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      refute environment.dig("features", "experimentalDevContainerLockfile")
    end
  end

  context "start_environment conditionally sends experimentalDevContainerLockfile flag" do
    test "set when flag is enabled" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_experimental_dev_container_lockfile].enable(@user)

      codespace = create(:codespace, owner: @user)
      FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN }

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.start_environment(codespace.guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user)

      environment = FakeVSOServer.environments_started.last
      assert environment.dig("features", "experimentalDevContainerLockfile")
    end

    test "not set when flag is disabled" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_experimental_dev_container_lockfile].disable(@user)

      codespace = create(:codespace, owner: @user)
      FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN }

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.start_environment(codespace.guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user)

      environment = FakeVSOServer.environments_started.last
      refute environment.dig("features", "experimentalDevContainerLockfile")
    end
  end

  context "start_environment conditionally sends remountStorageAsReadWrite flag" do
    test "set when flag is enabled" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_remount_storage_as_read_write].enable(@user)

      codespace = create(:codespace, owner: @user)
      FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN }

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.start_environment(codespace.guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user)

      environment = FakeVSOServer.environments_started.last
      assert environment.dig("features", "remountStorageAsReadWrite")
    end

    test "not set when flag is disabled" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_remount_storage_as_read_write].disable(@user)

      codespace = create(:codespace, owner: @user)
      FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN }

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.start_environment(codespace.guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user)

      environment = FakeVSOServer.environments_started.last
      refute environment.dig("features", "remountStorageAsReadWrite")
    end
  end

  test "create_environment sends enableAutoPushOnStop" do
    FakeVSOServer.reset!

    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
    client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace-with-use-vscode-start-command-enabled", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default", environment_options: { "enableAutoPushOnStop": "true" })

    environment = FakeVSOServer.environments_created.last
    assert environment["enableAutoPushOnStop"], "true"
  end

  context "create_environment + useBetaComputeImage" do
    test "Beta compute image channel when flipper is on and user settings has Beta" do
      FakeVSOServer.reset!
      user = create(:user)
      GitHub.flipper[:codespaces_compute_beta_images].enable(user)
      settings = Codespaces::Settings.for_user(user)
      settings.preferred_host_image = Codespaces::Settings::PREFERRED_HOST_IMAGE_BETA
      settings.save

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: user, resource_provider: @plan.resource_provider)
      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace-with-useBetaComputeImage", moniker: @repo.permalink, github_token: "github_token", billable_owner: user, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      assert_equal "Beta", environment["preferredComputeImageChannel"]
    end

    test "Stable compute image channel when flipper is off" do
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_compute_beta_images].disable(@user)

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace-with-useBetaComputeImage", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      assert_equal "Stable", environment["preferredComputeImageChannel"]
    end

    test "Stable compute image channel when flipper is on and user settings has Stable" do
      FakeVSOServer.reset!
      user = create(:user)
      GitHub.flipper[:codespaces_compute_beta_images].enable(user)
      settings = Codespaces::Settings.for_user(user)
      settings.preferred_host_image = Codespaces::Settings::PREFERRED_HOST_IMAGE_STABLE
      settings.save

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: user, resource_provider: @plan.resource_provider)
      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace-with-useBetaComputeImage", moniker: @repo.permalink, github_token: "github_token", billable_owner: user, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      assert_equal "Stable", environment["preferredComputeImageChannel"]
    end

    test "Stable compute image channel when flipper is on and user settings has no preference saved" do
      FakeVSOServer.reset!
      user = create(:user)
      GitHub.flipper[:codespaces_compute_beta_images].enable(user)
      settings = Codespaces::Settings.for_user(user)
      settings.preferred_host_image = nil
      settings.save

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: user, resource_provider: @plan.resource_provider)
      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace-with-useBetaComputeImage", moniker: @repo.permalink, github_token: "github_token", billable_owner: user, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      assert_equal "Stable", environment["preferredComputeImageChannel"]
    end
  end

  context "start_environment + useBetaComputeImage" do
    test "Beta compute image channel when flipper is on and user settings has Beta" do
      guid = SecureRandom.uuid
      FakeVSOServer.reset!
      FakeVSOServer.environments << { "id" => guid, "state" => Codespaces::Vscs::State::SHUTDOWN }
      user = create(:user)
      GitHub.flipper[:codespaces_compute_beta_images].enable(user)
      settings = Codespaces::Settings.for_user(user)
      settings.preferred_host_image = Codespaces::Settings::PREFERRED_HOST_IMAGE_BETA
      settings.save

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: user, resource_provider: @plan.resource_provider)
      client.start_environment(guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: user)

      start_request = FakeVSOServer.requests.last
      environment = GitHub::JSON.parse(start_request.body)
      assert_equal "Beta", environment["preferredComputeImageChannel"]
    end

    test "Stable compute image channel when flipper is off" do
      guid = SecureRandom.uuid
      FakeVSOServer.reset!
      FakeVSOServer.environments << { "id" => guid, "state" => Codespaces::Vscs::State::SHUTDOWN }
      GitHub.flipper[:codespaces_compute_beta_images].disable(@user)

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.start_environment(guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user)

      start_request = FakeVSOServer.requests.last
      environment = GitHub::JSON.parse(start_request.body)
      assert_equal "Stable", environment["preferredComputeImageChannel"]
    end

    test "Stable compute image channel when flipper is on and user settings has Stable" do
      guid = SecureRandom.uuid
      FakeVSOServer.reset!
      FakeVSOServer.environments << { "id" => guid, "state" => Codespaces::Vscs::State::SHUTDOWN }
      user = create(:user)
      GitHub.flipper[:codespaces_compute_beta_images].enable(user)
      settings = Codespaces::Settings.for_user(user)
      settings.preferred_host_image = Codespaces::Settings::PREFERRED_HOST_IMAGE_STABLE
      settings.save

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: user, resource_provider: @plan.resource_provider)
      client.start_environment(guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: user)

      start_request = FakeVSOServer.requests.last
      environment = GitHub::JSON.parse(start_request.body)
      assert_equal "Stable", environment["preferredComputeImageChannel"]
    end
  end

  test "create_environment for user-owned Codespace includes [private, public] options in the request body" do
    port_privacy_settings = [Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:PRIVATE], Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:PUBLIC]]

    FakeVSOServer.reset!
    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
    client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

    environment = FakeVSOServer.environments_created.last
    assert_same_elements port_privacy_settings, environment.dig("runTimeConstraints", "allowedPortPrivacySettings")
  end

  test "create_environment for org-owned Codespace with no constraints includes [private, org, public] options in the request body" do
    port_privacy_settings = [Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:PRIVATE], Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:ORG], Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:PUBLIC]]

    FakeVSOServer.reset!
    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
    client.create_environment("WestUs2", @org_repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @org_repo.permalink, github_token: "github_token", billable_owner: @org, create_type: "default")

    environment = FakeVSOServer.environments_created.last
    assert_same_elements port_privacy_settings, environment.dig("runTimeConstraints", "allowedPortPrivacySettings")
  end

  test "create_environment for org-owned Codespace with [org] constraint includes [private, org] options in the request body" do
    create(:policy_constraint, policy_group: @policy_group, allowed_values: [Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:ORG]], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_PORT_PRIVACY_SETTINGS)
    port_privacy_settings = [Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:PRIVATE], Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:ORG]]

    FakeVSOServer.reset!
    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
    client.create_environment("WestUs2", @org_repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @org_repo.permalink, github_token: "github_token", billable_owner: @org, create_type: "default")

    environment = FakeVSOServer.environments_created.last
    assert_same_elements port_privacy_settings, environment.dig("runTimeConstraints", "allowedPortPrivacySettings")
  end

  context "create_environment + devcontainer.json" do
    test "passes through devcontainer fields" do
      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

      json_data = "{\n  \"name\": \"Custom Container Name\",\n  \"devPort\": 1234\n}\n"
      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token",
                                                  environment_options: { devcontainerPath: ".devcontainer.json", devcontainerJson: json_data, hasDevcontainerJson: true }, billable_owner: @user, create_type: "default")

      environment = FakeVSOServer.environments_created.last

      assert_equal ".devcontainer.json", environment["devcontainerPath"]
      assert environment["hasDevcontainerJson"]
      assert_equal json_data, environment["devcontainerJson"]
    end

    test "drops devcontainerJson data if it pushes us over the payload limit" do
      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

      json_data = "{\n \"name\": \"#{'$' * Codespaces::VscsClient::PAYLOAD_SIZE_LIMIT}\"\n}\n"
      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token",
                                                  environment_options: { devcontainerJson: json_data, hasDevcontainerJson: true }, billable_owner: @user, create_type: "default")

      environment = FakeVSOServer.environments_created.last

      assert environment["hasDevcontainerJson"]
      assert_nil environment["devcontainerJson"]
    end

    test "raises if we can't get below the payload limit" do
      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

      assert_raises Codespaces::VscsClient::PayloadTooLargeError do
        json_data = "{\n  \"name\": \"Custom Container Name\",\n  \"devPort\": 1234\n}\n"
        client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token",
                                                    environment_options: { somethingElse: "$" * Codespaces::VscsClient::PAYLOAD_SIZE_LIMIT, devcontainerJson: json_data, hasDevcontainerJson: true }, billable_owner: @user, create_type: "default")
      end
    end
  end

  context "create_environment experimental features" do

    test "uses other features" do
      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      assert environment["experimentalFeatures"]["customContainers"]
      assert environment["experimentalFeatures"]["queueResourceAllocation"]
    end

    test "uses prebuilds when prebuild allowed is true" do
      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

      create(:codespace_prebuild_configuration, repository: @repo)

      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, prebuild_allowed: true, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      assert environment["experimentalFeatures"]["usePrebuiltImages"]
    end

    test "don't use prebuilds when prebuilds allowed is false" do
      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

      create(:codespace_prebuild_configuration, repository: @repo)

      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, prebuild_allowed: false, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      refute environment["experimentalFeatures"]["usePrebuiltImages"]
    end

    test "does not enable prebuilt images if there is no prebuild template" do
      FakeVSOServer.reset!

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      refute environment["experimentalFeatures"]["usePrebuiltImages"]
    end

    test "uses prebuild config to determine if fast path is enabled if productize fast path flag is turned on" do

      config = create(:codespace_prebuild_configuration, repository: @repo, fast_path_enabled: true)
      config.update(devcontainer_path: ".devcontainer/devcontainer.json")

      environment_options = {}
      environment_options[:devcontainerPath] = ".devcontainer/devcontainer.json"

      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider, branch: @repo.default_branch)

      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, environment_options: environment_options, prebuild_allowed: true, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      assert environment["experimentalFeatures"]["usePrebuildFastPathIfAvailable"]
    end

    test "if productize fast path flag is enabled but no configuration exists then fast path enabled is false" do

      # create with different dev container file then codespace should be created with
      config = create(:codespace_prebuild_configuration, repository: @repo, fast_path_enabled: false)
      config.update(devcontainer_path: ".devcontainer/custom/devcontainer.json")

      environment_options = {}
      environment_options[:devcontainerPath] = ".devcontainer/devcontainer.json"

      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider, branch: @repo.default_branch)

      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, environment_options: environment_options, prebuild_allowed: true, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      assert_equal false, environment["experimentalFeatures"]["usePrebuildFastPathIfAvailable"]
    end

    test "if productize fast path flag is enabled and configuration value for fast path enabled is false then don't use fast path" do

      # create with different dev container file then codespace should be created with
      config = create(:codespace_prebuild_configuration, repository: @repo, fast_path_enabled: false)
      config.update(devcontainer_path: ".devcontainer/devcontainer.json")

      environment_options = {}
      environment_options[:devcontainerPath] = ".devcontainer/devcontainer.json"

      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider, branch: @repo.default_branch)

      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, environment_options: environment_options, prebuild_allowed: true, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      assert_equal false, environment["experimentalFeatures"]["usePrebuildFastPathIfAvailable"]
    end

    test "if productize fast path flag is enabled then make sure to take fast path enabled value from correct vscs target config" do

      # create with different dev container file then codespace should be created with
      config = create(:codespace_prebuild_configuration, repository: @repo, fast_path_enabled: false, vscs_target: :ppe)
      config1 = create(:codespace_prebuild_configuration, repository: @repo, fast_path_enabled: true, vscs_target: :production)
      config.update(devcontainer_path: ".devcontainer/devcontainer.json")
      config1.update(devcontainer_path: ".devcontainer/devcontainer.json")

      environment_options = {}
      environment_options[:devcontainerPath] = ".devcontainer/devcontainer.json"

      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: :ppe, plan: @plan, user: @user, resource_provider: @plan.resource_provider, branch: @repo.default_branch)

      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, environment_options: environment_options, prebuild_allowed: true, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      assert_equal false, environment["experimentalFeatures"]["usePrebuildFastPathIfAvailable"]
    end

    test "if productize fast path flag is enabled then make sure to take fast path enabled value from correct vscs target config even if target is nil" do

      # create with different dev container file then codespace should be created with
      config = create(:codespace_prebuild_configuration, repository: @repo, fast_path_enabled: true, vscs_target: nil)
      config.update(devcontainer_path: ".devcontainer/devcontainer.json")

      environment_options = {}
      environment_options[:devcontainerPath] = ".devcontainer/devcontainer.json"

      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider, branch: @repo.default_branch)

      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, environment_options: environment_options, prebuild_allowed: true, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      assert_equal true, environment["experimentalFeatures"]["usePrebuildFastPathIfAvailable"]
    end
  end

  context "#storagev2" do
    test "create_environment does not send v2 flag" do
      # when feature flag disabled
      GitHub.flipper[:codespaces_use_storage_v2].disable
      GitHub.flipper[:codespaces_force_storage_v2].disable
      GitHub.flipper[:codespaces_use_storage_v2_percentage_based_rollout].disable
      GitHub.flipper[:codespaces_use_storage_v2_percentage_based_rollout_buckets].disable
      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      refute environment.dig("experimentalFeatures", "useStorageV2")

      # verify feature flag sent in request body
      refute environment.dig("features", "useStorageV2")

      # when flag only enabled for user
      GitHub.flipper[:codespaces_use_storage_v2].disable(@repo)
      GitHub.flipper[:codespaces_use_storage_v2].enable(@user)
      GitHub.flipper[:codespaces_use_storage_v2_percentage_based_rollout].disable
      GitHub.flipper[:codespaces_use_storage_v2_percentage_based_rollout_buckets].disable
      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      refute environment.dig("experimentalFeatures", "useStorageV2")
      refute environment.dig("features", "useStorageV2")

      # when flag only enabled for repo
      GitHub.flipper[:codespaces_use_storage_v2].enable(@repo)
      GitHub.flipper[:codespaces_use_storage_v2].disable(@user)
      GitHub.flipper[:codespaces_use_storage_v2_percentage_based_rollout].disable
      GitHub.flipper[:codespaces_use_storage_v2_percentage_based_rollout_buckets].disable
      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      refute environment.dig("experimentalFeatures", "useStorageV2")
      refute environment.dig("features", "useStorageV2")
    end

    test "create_environment sends v2 flag" do
      # when force feature flag enabled for repo
      GitHub.flipper[:codespaces_storage_v2_disallowed].disable
      GitHub.flipper[:codespaces_force_storage_v2].enable(@repo)
      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      assert environment.dig("experimentalFeatures", "useStorageV2")

      # verify feature flag sent in request body
      assert environment.dig("features", "useStorageV2")

      # when force feature flag enabled for user
      GitHub.flipper[:codespaces_force_storage_v2].disable(@repo)
      GitHub.flipper[:codespaces_force_storage_v2].enable(@user)
      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      assert environment.dig("experimentalFeatures", "useStorageV2")
      assert environment.dig("features", "useStorageV2")

      # when force flag disabled, but v2 flag enabled for user and repo
      GitHub.flipper[:codespaces_force_storage_v2].disable
      GitHub.flipper[:codespaces_use_storage_v2].enable(@user)
      GitHub.flipper[:codespaces_use_storage_v2].enable(@repo)

      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      assert environment.dig("experimentalFeatures", "useStorageV2")
      assert environment.dig("features", "useStorageV2")

      # when the special codespaces_use_storage_v2_percentage_based_rollout feature flag is enabled for the repo and codespaces_use_storage_v2_percentage_based_rollout_buckets is enabled as well
      FakeVSOServer.reset!
      GitHub.flipper[:codespaces_use_storage_v2_percentage_based_rollout].enable(@repo)
      GitHub.flipper[:codespaces_use_storage_v2_percentage_based_rollout_buckets].enable(@user)
      GitHub.flipper[:codespaces_force_storage_v2].disable
      GitHub.flipper[:codespaces_use_storage_v2].disable


      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace01", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      assert environment.dig("experimentalFeatures", "useStorageV2")
      assert environment.dig("features", "useStorageV2")
      GitHub.flipper[:codespaces_use_storage_v2_percentage_based_rollout].disable
      GitHub.flipper[:codespaces_use_storage_v2_percentage_based_rollout_buckets].disable

    end

    test "start environment sends useStorageV2 feature as false when its not a storage v2 codespace" do
      codespace = create(:codespace, owner: @user)

      FakeVSOServer.reset!
      FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN }

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.start_environment(codespace.guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user, uses_storage_v2: false)

      environment = FakeVSOServer.environments_started.last
      refute environment.dig("features", "useStorageV2")
    end

    test "start environment sends useStorageV2 feature as true when its a storage v2 codespace" do
      codespace = create(:codespace, owner: @user)

      FakeVSOServer.reset!
      FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN }

      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.start_environment(codespace.guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user, uses_storage_v2: true)

      environment = FakeVSOServer.environments_started.last
      assert environment.dig("features", "useStorageV2")
    end

    context "#useRawFuse" do
      test "create_environment does not send useRawFuse flag" do
        GitHub.flipper[:codespaces_force_storage_v2].disable(@repo)
        GitHub.flipper[:codespaces_use_raw_fuse].disable(@repo)

        FakeVSOServer.reset!
        client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
        client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")
        environment = FakeVSOServer.environments_created.last

        refute environment.dig("experimentalFeatures", "useRawFuse")
        refute environment.dig("features", "useRawFuse")
      end

      test "create_environment does not send useRawFuse flag if raw fuse is enabled and storage v2 is disabled" do
        GitHub.flipper[:codespaces_force_storage_v2].disable
        GitHub.flipper[:codespaces_use_storage_v2].disable
        GitHub.flipper[:codespaces_storage_v2_disallowed].enable
        GitHub.flipper[:codespaces_use_raw_fuse].enable(@repo)

        FakeVSOServer.reset!
        client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
        client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")
        environment = FakeVSOServer.environments_created.last

        refute environment.dig("experimentalFeatures", "useRawFuse")
        refute environment.dig("features", "useRawFuse")
      end

      test "create_environment sends useRawFuse flag" do
        GitHub.flipper[:codespaces_force_storage_v2].enable(@repo)
        GitHub.flipper[:codespaces_use_raw_fuse].enable(@repo)

        FakeVSOServer.reset!
        client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
        client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")
        environment = FakeVSOServer.environments_created.last

        assert environment.dig("experimentalFeatures", "useRawFuse")
        assert environment.dig("features", "useRawFuse")
      end

      test "create_environment sends useRawFuse flag for test environment" do
        GitHub.flipper[:codespaces_force_storage_v2].enable(@repo)
        GitHub.flipper[:codespaces_use_raw_fuse].disable(@repo)
        GitHub.flipper[:codespaces_use_raw_fuse_ppe].enable(@repo)

        FakeVSOServer.reset!
        client = Codespaces::VscsClient.new(vscs_target: :ppe, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
        client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @user, create_type: "default")
        environment = FakeVSOServer.environments_created.last

        assert environment.dig("experimentalFeatures", "useRawFuse")
        assert environment.dig("features", "useRawFuse")
      end
    end
  end

  context "codespacesHostSetupPolicy flag" do
    test "create_environment does not send codespacesHostSetupPolicy flag" do
      # when feature flag disabled
      GitHub.flipper[:codespaces_host_setup_policy].disable
      GitHub.flipper[:codespaces_salus_beta_customers].disable
      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @org, create_type: "default")

      environment = FakeVSOServer.environments_created.last

      # verify feature flag sent in request body
      refute environment.dig("features", "codespacesHostSetupPolicy")

      # when flag only enabled for customers
      GitHub.flipper[:codespaces_host_setup_policy].disable
      GitHub.flipper[:codespaces_salus_beta_customers].enable(@org.business)
      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @org, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      refute environment.dig("features", "codespacesHostSetupPolicy")

      # when flag only enabled for feature (as killswitch)
      GitHub.flipper[:codespaces_host_setup_policy].enable
      GitHub.flipper[:codespaces_salus_beta_customers].disable(@org.business)
      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @org, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      refute environment.dig("features", "codespacesHostSetupPolicy")

      # when flag only enabled for feature (with actor targets)
      GitHub.flipper[:codespaces_host_setup_policy].enable(@org.business)
      GitHub.flipper[:codespaces_salus_beta_customers].disable(@org.business)
      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @org, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      refute environment.dig("features", "codespacesHostSetupPolicy")
    end

    test "create_environment sends v2 flag" do
      # when force feature flag enabled as killswitch
      GitHub.flipper[:codespaces_host_setup_policy].enable
      GitHub.flipper[:codespaces_salus_beta_customers].enable(@org.business)

      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @org, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      assert environment.dig("features", "codespacesHostSetupPolicy")

      # when force feature flag enabled for enterprise specifically
      GitHub.flipper[:codespaces_host_setup_policy].enable(@org.business)
      GitHub.flipper[:codespaces_salus_beta_customers].enable(@org.business)
      FakeVSOServer.reset!
      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "github_token", billable_owner: @org, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      assert environment.dig("features", "codespacesHostSetupPolicy")
    end
  end

  test "create_environment sends user tier" do
    FakeVSOServer.reset!
    client = Codespaces::VscsClient.new(
      vscs_target: Codespaces::Vscs.default_target,
      plan: @plan,
      user: @user,
      resource_provider: @plan.resource_provider
    )

    tier_result = Codespaces::Tier.for_user(@user)
    tier_name = TrustTiers::Tier.tier_name(tier_result.tier)

    client.create_environment(
      "WestUs2",
      @repo,
      sku_name: @default_sku_name,
      name: "test-codespace",
      moniker: @repo.permalink,
      github_token: "github_token",
      billable_owner: @user,
      create_type: "default",
    )

    environment = FakeVSOServer.environments_created.last
    assert_equal tier_name, environment["userTier"]
  end

  test "start_environment passes secrets and sku_name in the request body" do
    guid = SecureRandom.uuid
    FakeVSOServer.reset!
    FakeVSOServer.environments << { "id" => guid, "state" => Codespaces::Vscs::State::SHUTDOWN }
    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
    client.start_environment(guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user)

    start_request = FakeVSOServer.requests.last
    request_body = GitHub::JSON.parse(start_request.body)
    sku_name = request_body["skuName"]
    secrets = request_body["secrets"]

    assert_equal "basicLinux", request_body["skuName"]
    assert_same_elements default_secrets(@user, repository_nwo: @repo.name_with_owner, vscs_target_url: client.api_url), request_body["secrets"]
  end

  test "start_environment can never request cascade token" do
    guid = SecureRandom.uuid
    FakeVSOServer.reset!
    FakeVSOServer.environments << { "id" => guid, "state" => Codespaces::Vscs::State::SHUTDOWN }
    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
    client.start_environment(guid, github_token: "github_token", sku_name: "basicLinux", request_cascade_token: true, repository: @repo, billable_owner: @user)

    start_request = FakeVSOServer.requests.last
    assert_equal "access=false", start_request.query_string
  end

  test "start_environment sends testAccount in the request body" do
    codespace = create(:codespace, owner: @user)
    GitHub.flipper[:codespaces_automated_testing].disable
    FakeVSOServer.reset!
    FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN }
    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
    client.start_environment(codespace.guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user)

    environment = FakeVSOServer.environments_started.last
    refute environment["testAccount"]

    GitHub.flipper[:codespaces_automated_testing].enable(@user)
    client.start_environment(codespace.guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user)

    environment = FakeVSOServer.environments_started.last
    assert environment["testAccount"]
  end

  test "start_environment sends processKillTracing in the request body" do
    codespace = create(:codespace, owner: @user)
    GitHub.flipper[:codespaces_process_kill_tracing].disable
    FakeVSOServer.reset!
    FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN }
    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
    client.start_environment(codespace.guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user)

    environment = FakeVSOServer.environments_started.last
    refute environment.dig("features", "processKillTracing")

    GitHub.flipper[:codespaces_process_kill_tracing].enable(@user)
    client.start_environment(codespace.guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user)

    environment = FakeVSOServer.environments_started.last
    assert environment.dig("features", "processKillTracing")
  end

  test "start_environment for user-owned Codespace includes [private, public] options in the request body" do
    port_privacy_settings = [Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:PRIVATE], Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:PUBLIC]]

    codespace = create(:codespace, owner: @user)

    FakeVSOServer.reset!
    FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN }

    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
    client.start_environment(codespace.guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user)

    environment = FakeVSOServer.environments_started.last
    assert_same_elements port_privacy_settings, environment.dig("runTimeConstraints", "allowedPortPrivacySettings")
  end

  test "start_environment for org-owned Codespace with no constraints includes [private, org, public] options in the request body" do
    port_privacy_settings = [Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:PRIVATE], Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:ORG], Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:PUBLIC]]

    codespace = create(:codespace, owner: @user)

    FakeVSOServer.reset!
    FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN }

    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
    client.start_environment(codespace.guid, github_token: "github_token", sku_name: "basicLinux", repository: @org_repo, billable_owner: @org)

    environment = FakeVSOServer.environments_started.last
    assert_same_elements port_privacy_settings, environment.dig("runTimeConstraints", "allowedPortPrivacySettings")
  end

  test "start_environment for org-owned Codespace with [org] constraint includes [private, org] options in the request body" do
    create(:policy_constraint, policy_group: @policy_group, allowed_values: [Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:ORG]], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_PORT_PRIVACY_SETTINGS)
    port_privacy_settings = [Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:PRIVATE], Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:ORG]]

    codespace = create(:codespace, owner: @user)

    FakeVSOServer.reset!
    FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN }

    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
    client.start_environment(codespace.guid, github_token: "github_token", sku_name: "basicLinux", repository: @org_repo, billable_owner: @org)

    environment = FakeVSOServer.environments_started.last
    assert_same_elements port_privacy_settings, environment.dig("runTimeConstraints", "allowedPortPrivacySettings")
  end

  test "start_environment sends user tier with feature flag" do
    guid = SecureRandom.uuid
    FakeVSOServer.reset!
    FakeVSOServer.environments << { "id" => guid, "state" => Codespaces::Vscs::State::SHUTDOWN }
    tier_result = Codespaces::Tier.for_user(@user)
    tier_name = TrustTiers::Tier.tier_name(tier_result.tier)

    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
    client.start_environment(guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user)

    start_request = FakeVSOServer.requests.last
    request_body = GitHub::JSON.parse(start_request.body)

    assert_equal tier_name, request_body["userTier"]
  end

  context "start_environment handles autoShutdownDelayMinutes" do
    test "when auto_shutdown_delay_minutes is present it is passed" do
      guid = SecureRandom.uuid
      FakeVSOServer.reset!
      FakeVSOServer.environments << { "id" => guid, "state" => Codespaces::Vscs::State::SHUTDOWN }
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.start_environment(guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user, auto_shutdown_delay_minutes: 10)

      start_request = FakeVSOServer.requests.last
      request_body = GitHub::JSON.parse(start_request.body)

      assert_equal 10, request_body["autoShutdownDelayMinutes"]
    end

    test "when auto_shutdown_delay_minutes is nil it is not passed" do
      guid = SecureRandom.uuid
      FakeVSOServer.reset!
      FakeVSOServer.environments << { "id" => guid, "state" => Codespaces::Vscs::State::SHUTDOWN }
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.start_environment(guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @org, auto_shutdown_delay_minutes: nil)

      start_request = FakeVSOServer.requests.last
      request_body = GitHub::JSON.parse(start_request.body)

      refute request_body["autoShutdownDelayMinutes"]
    end
  end

  test "environment_options is used to passthrough additional params" do
    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

    client.create_environment(
      "WestUs2",
      @repo,
      sku_name: "extremeLinux",
      name: "test-codespace",
      moniker: @repo.permalink,
      environment_options: { fancyNewVSCSParam: "sweet" },
      github_token: "",
      billable_owner: @user,
      create_type: "default",
    )

    environment = FakeVSOServer.environments_created.last
    assert_equal "sweet", environment["fancyNewVSCSParam"]
  end

  test "environment_options overwrites autoShutdownDelayMinutes" do
    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

    client.create_environment(
      "WestUs2",
      @repo,
      sku_name: "extremeLinux",
      name: "test-codespace",
      moniker: @repo.permalink,
      environment_options: { autoShutdownDelayMinutes: 80 },
      github_token: "",
      billable_owner: @user,
      create_type: "default",
    )

    environment = FakeVSOServer.environments_created.last
    assert_equal 80, environment["autoShutdownDelayMinutes"]
  end

  test "environment_options sets autoShutdownDelayMinutes to default if not specified" do
    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

    client.create_environment(
      "WestUs2",
      @repo,
      sku_name: "extremeLinux",
      name: "test-codespace",
      moniker: @repo.permalink,
      github_token: "",
      billable_owner: @user,
      create_type: "default",
    )

    environment = FakeVSOServer.environments_created.last
    assert_equal Codespaces::VscsClient::AUTO_SHUTDOWN_MINUTES, environment["autoShutdownDelayMinutes"]
  end

  test "environment_options in create_body does not overwrite defaults" do
    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

    client.create_environment(
      "WestUs2",
      @repo,
      sku_name: "extremeLinux",
      name: "test-codespace",
      moniker: @repo.permalink,
      environment_options: { state: Codespaces::Vscs::State::SHUTDOWN },
      github_token: "",
      billable_owner: @user,
      create_type: "default",
    )

    environment = FakeVSOServer.environments_created.last
    assert_equal "test-codespace", environment["friendlyName"]
    assert_equal @repo.permalink, environment["seed"]["moniker"]
    assert_equal @repo.permalink, environment["seed"]["cloneUrl"]
  end

  test "shutdown_environment for user-owned Codespace includes [private, public] options in the request body" do
    port_privacy_settings = [Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:PRIVATE], Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:PUBLIC]]

    codespace = create(:codespace, owner: @user)

    FakeVSOServer.reset!
    FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN }

    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
    client.shutdown_environment(codespace.guid, repository: @repo, billable_owner: @user)

    suspend_request = FakeVSOServer.requests.last
    suspend_request_body = GitHub::JSON.parse(suspend_request.body.read)
    assert_same_elements port_privacy_settings, suspend_request_body.dig("runTimeConstraints", "allowedPortPrivacySettings")
  end

  test "shutdown_environment for org-owned Codespace with no constraints includes [private, org, public] options in the request body" do
    port_privacy_settings = [Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:PRIVATE], Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:ORG], Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:PUBLIC]]

    codespace = create(:codespace, owner: @user)

    FakeVSOServer.reset!
    FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN }

    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
    client.shutdown_environment(codespace.guid, repository: @org_repo, billable_owner: @org)

    suspend_request = FakeVSOServer.requests.last
    suspend_request_body = GitHub::JSON.parse(suspend_request.body.read)
    assert_same_elements port_privacy_settings, suspend_request_body.dig("runTimeConstraints", "allowedPortPrivacySettings")
  end

  test "shutdown_environment for org-owned Codespace with [org] constraint includes [private, org] options in the request body" do
    create(:policy_constraint, policy_group: @policy_group, allowed_values: [Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:ORG]], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_PORT_PRIVACY_SETTINGS)
    port_privacy_settings = [Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:PRIVATE], Codespaces::PortPrivacyPolicy::PORT_PRIVACY_SETTINGS[:ORG]]

    codespace = create(:codespace, owner: @user)

    FakeVSOServer.reset!
    FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN }

    client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
    client.shutdown_environment(codespace.guid, repository: @org_repo, billable_owner: @org)

    suspend_request = FakeVSOServer.requests.last
    suspend_request_body = GitHub::JSON.parse(suspend_request.body.read)
    assert_same_elements port_privacy_settings, suspend_request_body.dig("runTimeConstraints", "allowedPortPrivacySettings")
  end

  test "hard_delete sends the appropriate flag" do
    codespace = create(:copilot_workspace)

    FakeVSOServer.reset!
    FakeVSOServer.environments << { "id" => codespace.guid }

    client = Codespaces::VscsClient.for_codespace(codespace)
    client.hard_delete_environment(codespace.guid)

    assert_equal codespace.guid, FakeVSOServer.environments_hard_deleted.first
  end

  context "allowedImagePolicy" do
    test "create_environment for org-owned Codespace with [org] constraint does not include allowed values in the request body with disabled FF" do
      GitHub.flipper[:codespaces_enforce_image_allow_list_in_agent].disable
      create(:policy_constraint, policy_group: @policy_group, allowed_values: ["foobar"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)

      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.create_environment("WestUs2", @org_repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @org_repo.permalink, github_token: "github_token", billable_owner: @org, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      refute environment.dig("runTimeConstraints", "imageAllowList")
    end
    test "create_environment for org-owned Codespace with [org] constraint includes allowed values in the request body" do
      GitHub.flipper[:codespaces_enforce_image_allow_list_in_agent].enable
      create(:policy_constraint, policy_group: @policy_group, allowed_values: ["foobar"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)

      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.create_environment("WestUs2", @org_repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @org_repo.permalink, github_token: "github_token", billable_owner: @org, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      assert_same_elements ["foobar"], environment.dig("runTimeConstraints", "imageAllowList")
    end
    test "create_environment for org-owned Codespace with [org] constraint includes allowed values (with prefix) in the request body" do
      GitHub.flipper[:codespaces_enforce_image_allow_list_in_agent].enable
      create(:policy_constraint, policy_group: @policy_group, allowed_values: ["foobar/*"], name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_BASE_IMAGES)

      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.create_environment("WestUs2", @org_repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @org_repo.permalink, github_token: "github_token", billable_owner: @org, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      assert_same_elements ["foobar/*"], environment.dig("runTimeConstraints", "imageAllowList")
    end
  end

  context "hostSetupPolicy" do
    test "create_environment for org-owned Codespace with [org] constraint does not include host setup config in the request body with disabled FF" do
      repo = create(:private_repository, owner: @org)
      params = {
        repo: repo.name_with_owner,
        branch: "main",
        path: "host-setup.sh"
      }

      create(:policy_constraint, policy_group: @policy_group, params: params, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP)

      GitHub.flipper[:codespaces_host_setup_policy].disable
      GitHub.flipper[:codespaces_salus_beta_customers].disable

      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.create_environment("WestUs2", @org_repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @org_repo.permalink, github_token: "github_token", billable_owner: @org, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      assert_nil environment.dig("runTimeConstraints", "hostSetupConfig")
    end

    test "create_environment for org-owned Codespace with [org] constraint includes host setup config in the request body with enabled FF" do
      GitHub.flipper[:codespaces_host_setup_policy].enable
      GitHub.flipper[:codespaces_salus_beta_customers].enable

      repo = create(:private_repository, owner: @org)
      params = {
        repo: repo.name_with_owner,
        branch: "main",
        path: "host-setup.sh"
      }

      create(:policy_constraint, policy_group: @policy_group, params: params, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP)

      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      client.create_environment("WestUs2", @org_repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @org_repo.permalink, github_token: "github_token", billable_owner: @org, create_type: "default")

      environment = FakeVSOServer.environments_created.last
      config_in_vscs_response = environment.dig("runTimeConstraints", "hostSetupConfig")

      refute_nil config_in_vscs_response

      assert_equal "main", config_in_vscs_response["branch"]
      assert_equal "host-setup.sh", config_in_vscs_response["path"]

      host_setup_config = Codespaces::HostSetupPolicy.get_host_setup_config(repository: repo, billable_owner: @org)

      refute_empty host_setup_config

      assert_equal repo.name_with_owner, host_setup_config["repo"]
      assert_equal "main", host_setup_config["branch"]
      assert_equal "host-setup.sh", host_setup_config["path"]
    end

    test "create_environment for org-owned Codespace with [org] constraint includes host setup config in the request body" do
      GitHub.flipper[:codespaces_host_setup_policy].enable
      GitHub.flipper[:codespaces_salus_beta_customers].enable
      create(:codespaces_vm_secrets_integration)

      params = {
        repo: @org_repo.name_with_owner,
        branch: "main",
        path: "host-setup.sh"
      }

      create(:policy_constraint, policy_group: @policy_group, params: params, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_HOST_SETUP)

      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

      FakeKredz.with_secrets do
        client.create_environment("WestUs2", @org_repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @org_repo.permalink, github_token: "github_token", billable_owner: @org, create_type: "default")
      end

      environment = FakeVSOServer.environments_created.last
      host_setup_config = environment.dig("runTimeConstraints", "hostSetupConfig")

      refute_nil host_setup_config
      assert_equal "main", host_setup_config["branch"]
      assert_equal "host-setup.sh", host_setup_config["path"]
      assert host_setup_config["token"]
      assert host_setup_config["cloneUrl"]
    end

    test "passes secrets for host setup config" do
      app = create(:codespaces_vm_secrets_integration)

      secrets = [
        Codespaces::Secret.new(
          "HOST_SETUP_SECRET_1",
          encrypt_with_owner_next_global_id("value 1", @org, key_name: Platform::EncryptionKeys::CODESPACES_VM_SECRETS),
          @org,
          Codespaces::Secret::TYPE_HOST_SETUP,
        ),
        Codespaces::Secret.new(
          "HOST_SETUP_SECRET_2",
          encrypt_with_owner_next_global_id("value 2", @org, key_name: Platform::EncryptionKeys::CODESPACES_VM_SECRETS),
          @org,
          Codespaces::Secret::TYPE_HOST_SETUP,
        ),
      ]

      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)

      client.create_environment("WestUs2", @org_repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @org_repo.permalink, github_token: "github_token", billable_owner: @org, create_type: "default", secrets:)

      environment = FakeVSOServer.environments_created.last
      host_setup_secrets = environment["secrets"].select { |s| s["type"] == Codespaces::Secret::TYPE_HOST_SETUP }
      assert_equal 2, host_setup_secrets.length
      assert_equal ["value 1", "value 2"], host_setup_secrets.map { |s| s["value"] }.sort
    end
  end

  context "caching environment data" do
    test "it caches the environment data immediately on fetch_environment" do
      FakeVSOServer.reset!
      env = { "id" => "abcd", "state" => Codespaces::Vscs::State::SHUTDOWN }
      FakeVSOServer.environments << env
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      Codespaces::CacheEnvironmentData.expects(:call).with(env)
      client.fetch_environment!("abcd")
    end

    test "it caches the environment data in the background on list_environments" do
      FakeVSOServer.reset!
      FakeVSOServer.environments << { "id" => "abcd", "state" => Codespaces::Vscs::State::SHUTDOWN }
      FakeVSOServer.environments << { "id" => "efgh", "state" => Codespaces::Vscs::State::PROVISIONING }
      FakeVSOServer.environments << { "id" => "ijkl", "state" => Codespaces::Vscs::State::AVAILABLE }
      client = Codespaces::VscsClient.new(vscs_target: Codespaces::Vscs.default_target, plan: @plan, user: @user, resource_provider: @plan.resource_provider)
      Codespaces::CacheEnvironmentDataJob.expects(:perform_later).times(3)
      client.list_environments
    end
  end

  test "captures the caller as rollup components in response errors" do
    codespace = create(:codespace, vscs_target: Codespaces::Vscs.default_target, owner: @user)
    client = Codespaces::VscsClient.for_codespace(codespace)
    assert_expected_rollup_components = ->(error_class) {
      error = nil
      begin
        client.fetch_environment!(codespace.guid)
      rescue error_class => e
        error = e
      end

      refute_nil error
      assert_equal ["fetch_environment!"], T.cast(error, Codespaces::Client::RequestError).rollup_components
    }

    client.expects(:vscs_api_hmac_raw).returns(Faraday::Response.new(body: "BadResponse", url: "https://online.visualstudio.com/"))
    assert_expected_rollup_components.call(Codespaces::VscsClient::BadResponseError)

    client.expects(:vscs_api_hmac_raw).returns(Faraday::Response.new(body: "invalid json", status: 200, url: "https://online.visualstudio.com/"))
    assert_expected_rollup_components.call(Codespaces::VscsClient::BadResponseError)

    client.expects(:vscs_api_hmac_raw).raises(Faraday::TimeoutError.new("oh no"))
    assert_expected_rollup_components.call(Codespaces::VscsClient::TimeoutError)

    client.expects(:vscs_api_hmac_raw).raises(Faraday::ConnectionFailed.new("oh no"))
    assert_expected_rollup_components.call(Codespaces::VscsClient::ConnectionFailed)
  end

  context "redirect" do
    test "redirects subdomain of visualstudio.com" do
      follow_vso_redirects = Codespaces::FollowVsoRedirects.new(nil)
      from_url = "https://online-ppe.core.vsengsaas.visualstudio.com"
      to_url = "https://southeastasia-ppe-rel-online.core.vsengsaas.visualstudio.com"
      assert follow_vso_redirects.redirect_to_same_host?(from_url, to_url)
    end

    test "don't redirect with authorization to different domains" do
      follow_vso_redirects = Codespaces::FollowVsoRedirects.new(nil)
      from_url = "https://online-ppe.core.vsengsaas.visualstudio.com"
      to_url = "https://southeastasia-ppe-rel-online.core.vsengsaas.audiblestudio.com"
      assert !follow_vso_redirects.redirect_to_same_host?(from_url, to_url)
    end
  end

  context "constructors" do
    test ".for_unscoped_deletion_or_suspension with feature flag does not cache cascade token" do
      FakeVSOServer.reset!
      fake_cache_key = "this_is_the_cache_key"
      Codespaces::TokenCache.expects(:generate_key).never

      plan = Codespaces::Plan.last
      client = Codespaces::VscsClient.for_unscoped_deletion_or_suspension(plan, :production)
      client.list_environments
      assert_nil Codespaces::Kv.store.get(fake_cache_key).value { nil }
      assert_nil client.user

      codespace = create(:codespace, owner: @user)
      client2 = Codespaces::VscsClient.for_codespace(codespace)
      client2.list_environments

      assert_nil Codespaces::Kv.store.get(fake_cache_key).value { nil }
      assert_equal client2.user, codespace.owner
    end

    test ".for_unscoped_deletion_or_suspension infers plan location" do
      plan = Codespaces::Plan.for(vscs_target: :production, location: "EastUs")
      client = Codespaces::VscsClient.for_unscoped_deletion_or_suspension(plan, :production)
      assert_equal "EastUs", client.location
    end

    test "raises ArgumentError unless user or for_unscoped_deletion_or_suspension" do
      plan = Codespaces::Plan.last

      assert_raises ArgumentError do
        client = Codespaces::VscsClient.new(
            vscs_target: :production,
            plan: plan,
            resource_provider: T.must(plan).resource_provider,
            api_url: Codespaces::VscsApiUrl.for_target(:production),
        )
      end
    end
  end

  context ".for_prebuild" do
    test "can pass in a plan" do
      vscs_target = :production
      plan = Codespaces::Plan.for(vscs_target: vscs_target, location: "EastUs")
      client = Codespaces::VscsClient.for_prebuild(location: "WestUs2", plan: plan)
      assert_equal plan, client.plan
    end
  end

  context "#create_prebuild_instance", skip_enterprise: true do
    test "makes the appropriate request" do
      FakeVSOServer.reset!

      pool_code = "test12432"
      github_token = "secret secret"
      location = "EastUs"
      branch = "main"
      environment_options = {}
      oid = "asdfk23rjsdfjasdf"

      client = Codespaces::VscsClient.for_prebuild(location: location, branch: branch, oid: oid)
      secrets = default_secrets(nil, repository_nwo: @repo.name_with_owner, github_token: github_token, vscs_target_url: client.api_url)
      expected_payload = {
        "environment_options" => {},
        "secrets" => secrets,
      }

      client.create_prebuild_instance(
        pool_code: pool_code,
        github_token: github_token,
        location: location,
        secrets: [],
        environment_options: {},
        repository: @repo,
      )
      request = FakeVSOServer.requests.last
      request_body = GitHub::JSON.parse(request.body)
      assert_equal "PUT", request.request_method
      assert_equal "/api/v2/prebuilds/pools/#{pool_code}/instances", request.path
      assert_equal expected_payload, request_body
    end
  end

  context "#fetch_prebuild_template", skip_enterprise: true do
    test "makes the appropriate request" do
      FakeVSOServer.reset!

      template = create(:codespace_prebuild_template, repository: @repo)
      client = Codespaces::VscsClient.for_prebuild(location: template.location, branch: template.branch, oid: template.oid)

      FakeVSOServer.environments << { "id" => template.guid }
      client.fetch_prebuild_template(template.guid)

      request = FakeVSOServer.requests.last
      request_body = GitHub::JSON.parse(request.body)
      assert_equal "GET", request.request_method
      assert_equal "/api/v2/prebuilds/template/#{template.guid}", request.path
    end
  end

  context "#fetch_prebuild_available_skus!" do
    test "calls the correct endpoint when devcontainer path is defined" do
      FakeVSOServer.reset!

      repo_id = @repo.id
      location = "EastUs"
      branch = "main"
      prebuild_hash = "asdfk23rjsdfjasdf"
      devcontainer_path = ".devcontainer/devcontainer.json"

      client = Codespaces::VscsClient.for_prebuild(location: location)

      result = client.fetch_prebuild_available_skus!(repo: @repo, branch_name: branch, prebuild_hash: prebuild_hash, devcontainer_path: devcontainer_path, codespace_owner: @user)

      expected_path = "/api/v2/prebuilds/templates/skus/repo/#{repo_id}/branch/#{branch}/hash/#{prebuild_hash}/location/#{location}/devcontainerpath/#{devcontainer_path}"
      request = FakeVSOServer.requests.last

      assert_equal "GET", request.request_method
      assert_equal expected_path, request.path
      assert_includes result["devContainerPath"], devcontainer_path
      assert_includes result.keys, "templateSkus"
      assert_includes result.keys, "poolSkus"
    end

    test "calls the correct endpoint when devcontainer path is nil" do
      FakeVSOServer.reset!

      repo_id = @repo.id
      location = "EastUs"
      branch = "main"
      prebuild_hash = "asdfk23rjsdfjasdf"
      devcontainer_path = nil

      client = Codespaces::VscsClient.for_prebuild(location: location)

      result = client.fetch_prebuild_available_skus!(repo: @repo, branch_name: branch, prebuild_hash: prebuild_hash, devcontainer_path: devcontainer_path, codespace_owner: @user)

      expected_path = "/api/v2/prebuilds/templates/skus/repo/#{repo_id}/branch/#{branch}/hash/#{prebuild_hash}/location/#{location}/devcontainerpath/"
      request = FakeVSOServer.requests.last

      assert_equal "GET", request.request_method
      assert_equal expected_path, request.path
      assert_includes result.keys, "templateSkus"
      assert_includes result.keys, "poolSkus"
    end

    test "calls the correct endpoint when storage v2 is disabled" do
      repo_id = @repo.id
      location = "EastUs"
      branch = "main"
      prebuild_hash = "asdfk23rjsdfjasdf"
      devcontainer_path = ".devcontainer/devcontainer.json"
      expected_path = "/api/v2/prebuilds/templates/skus/repo/#{repo_id}/branch/#{branch}/hash/#{prebuild_hash}/location/#{location}/devcontainerpath/#{devcontainer_path}"

      GitHub.flipper[:codespaces_use_storage_v2].disable
      GitHub.flipper[:codespaces_force_storage_v2].disable
      GitHub.flipper[:codespaces_storage_v2_prebuilds].disable
      GitHub.flipper[:codespaces_use_storage_v2_percentage_based_rollout].disable
      GitHub.flipper[:codespaces_use_storage_v2_percentage_based_rollout_buckets].disable
      client = Codespaces::VscsClient.for_prebuild(location: location)

      FakeVSOServer.reset!
      result = client.fetch_prebuild_available_skus!(repo: @repo, branch_name: branch, prebuild_hash: prebuild_hash, devcontainer_path: devcontainer_path, codespace_owner: @userh)
      assert_query_parameters(expected_path, "", result)

      FakeVSOServer.reset!
      result = client.fetch_prebuild_available_skus!(repo: @repo, branch_name: branch, prebuild_hash: prebuild_hash, devcontainer_path: devcontainer_path, codespace_owner: @user, fast_path_enabled: true)
      assert_query_parameters(expected_path, "fastPathEnabled=true", result)
    end

    test "calls the correct endpoint when storage v2 is enabled" do
      repo_id = @repo.id
      location = "EastUs"
      branch = "main"
      prebuild_hash = "asdfk23rjsdfjasdf"
      devcontainer_path = ".devcontainer/devcontainer.json"
      expected_path = "/api/v2/prebuilds/templates/skus/repo/#{repo_id}/branch/#{branch}/hash/#{prebuild_hash}/location/#{location}/devcontainerpath/#{devcontainer_path}"

      GitHub.flipper[:codespaces_storage_v2_disallowed].disable
      GitHub.flipper[:codespaces_use_storage_v2].enable(@repo)
      GitHub.flipper[:codespaces_use_storage_v2].enable(@user)
      client = Codespaces::VscsClient.for_prebuild(location: location)

      FakeVSOServer.reset!
      result = client.fetch_prebuild_available_skus!(repo: @repo, branch_name: branch, prebuild_hash: prebuild_hash, devcontainer_path: devcontainer_path, fast_path_enabled: true, codespace_owner: @user)
      assert_query_parameters(expected_path, "fastPathEnabled=true&storageType=V2", result)

      FakeVSOServer.reset!
      result = client.fetch_prebuild_available_skus!(repo: @repo, branch_name: branch, prebuild_hash: prebuild_hash, devcontainer_path: devcontainer_path, codespace_owner: @user)
      assert_query_parameters(expected_path, "storageType=V2", result)

      # enabled through force storage v2 flag
      GitHub.flipper[:codespaces_use_storage_v2].disable(@repo)
      GitHub.flipper[:codespaces_use_storage_v2].disable(@user)
      GitHub.flipper[:codespaces_force_storage_v2].enable(@user)
      client = Codespaces::VscsClient.for_prebuild(location: location)

      FakeVSOServer.reset!
      result = client.fetch_prebuild_available_skus!(repo: @repo, branch_name: branch, prebuild_hash: prebuild_hash, devcontainer_path: devcontainer_path, fast_path_enabled: true, codespace_owner: @user)
      assert_query_parameters(expected_path, "fastPathEnabled=true&storageType=V2", result)
    end

    test "raises timeout errors" do
      FakeVSOServer.reset!
      repo_id = "invalidRepo"
      location = "EastUs"
      branch = "main"
      prebuild_hash = "asdfk23rjsdfjasdf"
      devcontainer_path = ".devcontainer/devcontainer.json"
      client = Codespaces::VscsClient.for_prebuild(location: location)

      # Using partial stub to avoid changing vscs_api_hmac_raw implementation
      client.stubs(:vscs_connection).raises(Faraday::TimeoutError.new("Boom!"))

      assert_raises Codespaces::Client::TimeoutError do
        client.fetch_prebuild_available_skus!(repo: @repo, branch_name: branch, prebuild_hash: prebuild_hash, devcontainer_path: devcontainer_path, codespace_owner: @user)
      end
    end

    test "raises connection failed errors" do
      FakeVSOServer.reset!
      repo_id = @repo.id
      location = "EastUs"
      branch = "main"
      prebuild_hash = "asdfk23rjsdfjasdf"
      devcontainer_path = ".devcontainer/devcontainer.json"

      client = Codespaces::VscsClient.for_prebuild(location: location)

      # Using partial stub to avoid changing vscs_api_hmac_raw implementation
      client.stubs(:vscs_connection).raises(Faraday::ConnectionFailed.new("Boom!"))

      assert_raises Codespaces::Client::ConnectionFailed do
        client.fetch_prebuild_available_skus!(repo: @repo, branch_name: branch, prebuild_hash: prebuild_hash, devcontainer_path: devcontainer_path, codespace_owner: @user)
      end
    end
  end

  context "#create_prebuild_template_organization", skip_enterprise: true do
    test "makes the request for organization" do
      FakeVSOServer.reset!

      location = "EastUs"
      name = "fakename"
      prebuild_hash = "ahahahah"
      branch = @org_repo.default_branch
      oid = "asdfk23rjsdfjasdf"
      moniker = @org_repo.permalink
      workflow_run_id = "25"
      total_time_saving = "1"
      template_size = 10.0
      container_id = "123"
      schema_version = "0"
      image_name = "image"
      template_info = {
        "total_time_saving" => total_time_saving,
        "template_size" => template_size,
        "container" => {
          "id" => container_id,
          "schema_version" => schema_version,
          "image_name" => image_name,
        },
      }
      environment_options = { "template_info" => template_info }

      create(:codespace_prebuild_configuration, repository: @org_repo, branch: branch)

      client = Codespaces::VscsClient.for_prebuild(location: location, branch: branch, oid: oid)
      result = client.create_prebuild_template(
        location: location,
        environment_options: environment_options,
        name: name,
        repo: @org_repo,
        prebuild_hash: prebuild_hash,
        moniker: moniker,
        workflow_run_id: workflow_run_id,
      )
      request = FakeVSOServer.requests.last
      request_body = GitHub::JSON.parse(request.body)
      assert_equal "POST", request.request_method
      assert_equal "/api/v2/prebuilds/templates", request.path
      repository_data = request_body["seed"]["repository"]
      assert_equal oid, repository_data["commit"]
      assert_equal moniker, repository_data["url"]
      assert_equal prebuild_hash, repository_data["prebuild_hash"]
      assert_equal @org_repo.id, repository_data["id"]
      assert_equal @org.login, repository_data["owner"]
      assert_equal name, request_body["friendlyName"]
      assert_equal moniker, request_body["seed"]["moniker"]
      assert_equal @org_repo.permalink, request_body["seed"]["cloneUrl"]
      assert_equal @org_repo.name, repository_data["name"]
      assert_equal @repo.disk_usage, repository_data["disk_usage"]
      template_data = request_body["templateInfo"]
      assert_equal total_time_saving, template_data["totalTimeSavingsInSeconds"]
      assert_equal template_size, template_data["templateSizeInGB"]
      assert_equal container_id, template_data["container"]["id"]
      assert_equal schema_version, template_data["container"]["schemaVersion"]
      assert_equal image_name, template_data["container"]["imageName"]
      assert_equal workflow_run_id, template_data["workflowRunId"]
      assert_includes result.keys, "templateId"
      assert_includes result.keys, "sasUrl"
      assert_includes result.keys, "properties"
    end
  end

  context "#create_prebuild_template", skip_enterprise: true do
    test "makes the appropriate request" do
      FakeVSOServer.reset!

      location = "EastUs"
      name = "fakename"
      prebuild_hash = "ahahahah"
      branch = @repo.default_branch
      oid = "asdfk23rjsdfjasdf"
      moniker = @repo.permalink
      workflow_run_id = "5"
      configuration_id = "1"
      total_time_saving = "1"
      template_size = 10.0
      container_id = "123"
      schema_version = "0"
      image_name = "image"
      devcontainer_path = "devcontainer.json"
      template_info = {
        "total_time_saving" => total_time_saving,
        "template_size" => template_size,
        "container" => {
          "id" => container_id,
          "schema_version" => schema_version,
          "image_name" => image_name,
        },
      }
      environment_options = { "template_info" => template_info, "devcontainer_path" => devcontainer_path }

      create(:codespace_prebuild_configuration, repository: @repo, branch: branch)

      client = Codespaces::VscsClient.for_prebuild(location: location, branch: branch, oid: oid)
      result = client.create_prebuild_template(
        location: location,
        environment_options: environment_options,
        name: name,
        repo: @repo,
        prebuild_hash: prebuild_hash,
        moniker: moniker,
        workflow_run_id: workflow_run_id,
        configuration_id: configuration_id,
      )
      request = FakeVSOServer.requests.last
      request_body = GitHub::JSON.parse(request.body)
      assert_equal "POST", request.request_method
      assert_equal "/api/v2/prebuilds/templates", request.path
      devcontainer = request_body["devcontainerPath"]
      assert_equal devcontainer_path, devcontainer
      repository_data = request_body["seed"]["repository"]
      assert_equal branch, repository_data["branch"]
      assert_equal oid, repository_data["commit"]
      assert_equal moniker, repository_data["url"]
      assert_equal prebuild_hash, repository_data["prebuild_hash"]
      assert_equal @repo.id, repository_data["id"]
      assert_equal @user.login, repository_data["owner"]
      assert_equal name, request_body["friendlyName"]
      assert_equal moniker, request_body["seed"]["moniker"]
      assert_equal @repo.permalink, request_body["seed"]["cloneUrl"]
      assert_equal @repo.name, repository_data["name"]
      assert_equal @repo.disk_usage, repository_data["disk_usage"]
      assert_equal "#{GitHub.api_url}/internal/vscs/codespaces/prebuild/instances", request_body["gitHubPrebuildInstanceEndpoint"]
      assert_equal "#{GitHub.api_url}/internal/vscs/codespaces/prebuild/templates", request_body["gitHubPrebuildTemplateEndpoint"]
      template_data = request_body["templateInfo"]
      assert_equal total_time_saving, template_data["totalTimeSavingsInSeconds"]
      assert_equal template_size, template_data["templateSizeInGB"]
      assert_equal container_id, template_data["container"]["id"]
      assert_equal schema_version, template_data["container"]["schemaVersion"]
      assert_equal image_name, template_data["container"]["imageName"]
      assert_equal workflow_run_id, template_data["workflowRunId"]
      assert_equal configuration_id, template_data["configurationId"]
      assert_includes result.keys, "templateId"
      assert_includes result.keys, "sasUrl"
      assert_includes result.keys, "properties"
    end

    test "correctly handles a local vscs target" do
      FakeVSOServer.reset!

      location = "WestUs2"
      name = "fakename"
      branch = "master"
      oid = @repo.refs.find("master").sha
      prebuild_hash = "ahahahah"
      moniker = @repo.permalink
      workflow_run_id = "21"
      total_time_saving = "1"
      template_size = 10.0
      container_id = "123"
      schema_version = "0"
      image_name = "image"
      template_info = {
        "total_time_saving" => total_time_saving,
        "template_size" => template_size,
        "container" => {
          "id" => container_id,
          "schema_version" => schema_version,
          "image_name" => image_name,
        },
      }
      environment_options = { "template_info" => template_info }
      vscs_target = :local
      vscs_target_url = "https://online.dev.core.vsengsaas.visualstudio.com"
      request_path = "/api/v2/prebuilds/templates"

      create(:codespace_prebuild_configuration, repository: @repo, branch: branch, vscs_target: vscs_target, vscs_target_url: vscs_target_url)

      client = Codespaces::VscsClient.for_prebuild(
        location: location,
        branch: branch,
        oid: oid,
        vscs_target: vscs_target,
        vscs_target_url: vscs_target_url,
      )

      client.create_prebuild_template(
        location: location,
        environment_options: environment_options,
        name: name,
        repo: @repo,
        prebuild_hash: prebuild_hash,
        moniker: moniker,
        workflow_run_id: workflow_run_id
      )
      request = FakeVSOServer.requests.last
      request_body = GitHub::JSON.parse(request.body)
      assert_equal "POST", request.request_method
      assert_equal request_path, request.path
      repository_data = request_body["seed"]["repository"]
      assert_equal branch, repository_data["branch"]
      assert_equal oid, repository_data["commit"]
      assert_equal moniker, repository_data["url"]
      refute_nil repository_data["prebuild_hash"]
      assert_equal @repo.id, repository_data["id"]
      assert_equal @user.login, repository_data["owner"]
      assert_equal name, request_body["friendlyName"]
      assert_equal moniker, request_body["seed"]["moniker"]
      template_data = request_body["templateInfo"]
      assert_equal total_time_saving, template_data["totalTimeSavingsInSeconds"]
      assert_equal template_size, template_data["templateSizeInGB"]
      assert_equal container_id, template_data["container"]["id"]
      assert_equal schema_version, template_data["container"]["schemaVersion"]
      assert_equal image_name, template_data["container"]["imageName"]
      assert_equal workflow_run_id, template_data["workflowRunId"]
      assert_equal request.url, vscs_target_url + request_path
    end

    test "correctly handles a local vscs target with more than just a domain in the url" do
      FakeVSOServer.reset!

      location = "WestUs2"
      name = "fakename"
      branch = "master"
      oid = @repo.refs.find("master").sha
      prebuild_hash = "ahahahah"
      moniker = @repo.permalink
      workflow_run_id = "3"
      total_time_saving = "1"
      template_size = 10.0
      container_id = "123"
      schema_version = "0"
      image_name = "image"
      template_info = {
        "total_time_saving" => total_time_saving,
        "template_size" => template_size,
        "container" => {
          "id" => container_id,
          "schema_version" => schema_version,
          "image_name" => image_name,
        },
      }
      environment_options = { "template_info" => template_info }
      vscs_target = :local
      vscs_target_url = "https://online.dev.core.vsengsaas.visualstudio.com/monalisa"
      request_path = "/api/v2/prebuilds/templates"

      Codespaces::VscsClient.any_instance.stubs(:fetch_cascade_token).returns({ token: "token", expiration: "" }.to_json)

      create(:codespace_prebuild_configuration, repository: @repo, branch: branch, vscs_target: vscs_target, vscs_target_url: vscs_target_url)

      client = Codespaces::VscsClient.for_prebuild(
        location: location,
        branch: branch,
        oid: oid,
        vscs_target: vscs_target,
        vscs_target_url: vscs_target_url,
      )
      assert_raises Codespaces::Client::BadResponseError do
        client.create_prebuild_template(
          location: location,
          environment_options: environment_options,
          name: name,
          repo: @repo,
          prebuild_hash: prebuild_hash,
          moniker: moniker,
          workflow_run_id: workflow_run_id
        )
      end
      request = FakeVSOServer.requests.last
      assert_equal request.url, vscs_target_url + request_path
    end

    test "includes the storage_type property when it is set" do
      FakeVSOServer.reset!

      location = "EastUs"
      name = "fakename"
      prebuild_hash = "ahahahah"
      branch = @repo.default_branch
      oid = "asdfk23rjsdfjasdf"
      moniker = @repo.permalink
      workflow_run_id = "5"
      configuration_id = "1"
      total_time_saving = "1"
      template_size = 10.0
      container_id = "123"
      schema_version = "0"
      image_name = "image"
      devcontainer_path = "devcontainer.json"
      template_info = {
        "total_time_saving" => total_time_saving,
        "template_size" => template_size,
        "container" => {
          "id" => container_id,
          "schema_version" => schema_version,
          "image_name" => image_name,
        }
      }
      storage_type = "V2"
      environment_options = { "template_info" => template_info, "devcontainer_path" => devcontainer_path, "storage_type" => storage_type }

      create(:codespace_prebuild_configuration, repository: @repo, branch: branch)

      client = Codespaces::VscsClient.for_prebuild(location: location, branch: branch, oid: oid)
      result = client.create_prebuild_template(
        location: location,
        environment_options: environment_options,
        name: name,
        repo: @repo,
        prebuild_hash: prebuild_hash,
        moniker: moniker,
        workflow_run_id: workflow_run_id,
        configuration_id: configuration_id,
      )

      request = FakeVSOServer.requests.last
      request_body = GitHub::JSON.parse(request.body)
      actual_storage_type = request_body["storageType"]
      assert_equal storage_type, actual_storage_type
    end

    test "does not include the storage_type property when it is not set" do
      FakeVSOServer.reset!

      location = "EastUs"
      name = "fakename"
      prebuild_hash = "ahahahah"
      branch = @repo.default_branch
      oid = "asdfk23rjsdfjasdf"
      moniker = @repo.permalink
      workflow_run_id = "5"
      configuration_id = "1"
      total_time_saving = "1"
      template_size = 10.0
      container_id = "123"
      schema_version = "0"
      image_name = "image"
      devcontainer_path = "devcontainer.json"
      template_info = {
        "total_time_saving" => total_time_saving,
        "template_size" => template_size,
        "container" => {
          "id" => container_id,
          "schema_version" => schema_version,
          "image_name" => image_name,
        },
      }
      environment_options = { "template_info" => template_info, "devcontainer_path" => devcontainer_path }

      create(:codespace_prebuild_configuration, repository: @repo, branch: branch)

      client = Codespaces::VscsClient.for_prebuild(location: location, branch: branch, oid: oid)
      result = client.create_prebuild_template(
        location: location,
        environment_options: environment_options,
        name: name,
        repo: @repo,
        prebuild_hash: prebuild_hash,
        moniker: moniker,
        workflow_run_id: workflow_run_id,
        configuration_id: configuration_id,
      )
      request = FakeVSOServer.requests.last
      request_body = GitHub::JSON.parse(request.body)
      refute_includes request_body.keys, "storage_type"
    end

    test "includes the storage_image_version property when it is set" do
      FakeVSOServer.reset!

      location = "EastUs"
      name = "fakename"
      prebuild_hash = "ahahahah"
      branch = @repo.default_branch
      oid = "asdfk23rjsdfjasdf"
      moniker = @repo.permalink
      workflow_run_id = "5"
      configuration_id = "1"
      total_time_saving = "1"
      template_size = 10.0
      container_id = "123"
      schema_version = "0"
      image_name = "image"
      devcontainer_path = "devcontainer.json"
      storage_image_version = "Minimal"
      template_info = {
        "total_time_saving" => total_time_saving,
        "template_size" => template_size,
        "container" => {
          "id" => container_id,
          "schema_version" => schema_version,
          "image_name" => image_name,
        },
        "storage_image_version" => storage_image_version,
      }
      storage_type = "V2"
      environment_options = { "template_info" => template_info, "devcontainer_path" => devcontainer_path, "storage_type" => storage_type }

      create(:codespace_prebuild_configuration, repository: @repo, branch: branch)

      client = Codespaces::VscsClient.for_prebuild(location: location, branch: branch, oid: oid)
      result = client.create_prebuild_template(
        location: location,
        environment_options: environment_options,
        name: name,
        repo: @repo,
        prebuild_hash: prebuild_hash,
        moniker: moniker,
        workflow_run_id: workflow_run_id,
        configuration_id: configuration_id,
      )

      request = FakeVSOServer.requests.last
      request_body = GitHub::JSON.parse(request.body)
      actual_storage_type = request_body["storageType"]
      assert_equal storage_type, actual_storage_type
      template_data = request_body["templateInfo"]
      assert_equal storage_image_version, template_data["storageImageVersion"]
    end

    test "does not include the storage_image_version property when it is not set" do
      FakeVSOServer.reset!

      location = "EastUs"
      name = "fakename"
      prebuild_hash = "ahahahah"
      branch = @repo.default_branch
      oid = "asdfk23rjsdfjasdf"
      moniker = @repo.permalink
      workflow_run_id = "5"
      configuration_id = "1"
      total_time_saving = "1"
      template_size = 10.0
      container_id = "123"
      schema_version = "0"
      image_name = "image"
      devcontainer_path = "devcontainer.json"
      template_info = {
        "total_time_saving" => total_time_saving,
        "template_size" => template_size,
        "container" => {
          "id" => container_id,
          "schema_version" => schema_version,
          "image_name" => image_name,
        }
      }
      storage_type = "V2"
      environment_options = { "template_info" => template_info, "devcontainer_path" => devcontainer_path, "storage_type" => storage_type }

      create(:codespace_prebuild_configuration, repository: @repo, branch: branch)

      client = Codespaces::VscsClient.for_prebuild(location: location, branch: branch, oid: oid)
      result = client.create_prebuild_template(
        location: location,
        environment_options: environment_options,
        name: name,
        repo: @repo,
        prebuild_hash: prebuild_hash,
        moniker: moniker,
        workflow_run_id: workflow_run_id,
        configuration_id: configuration_id,
      )

      request = FakeVSOServer.requests.last
      request_body = GitHub::JSON.parse(request.body)
      actual_storage_type = request_body["storageType"]
      assert_equal storage_type, actual_storage_type
      template_data = request_body["templateInfo"]
      refute_includes template_data.keys, "storageImageVersion"
    end
  end


  context "#update_prebuild_template_status", skip_enterprise: true do
    test "calls the correct endpoint" do
      FakeVSOServer.reset!

      location = "WestUs2"
      template_guid = "gu-id"
      is_success = true
      client = Codespaces::VscsClient.for_prebuild(location: location)

      client.update_prebuild_template_status(location: location, template_guid: template_guid, is_success: is_success)

      expected_path = "/api/v2/prebuilds/templates/#{template_guid}/updatestatus"
      request = FakeVSOServer.requests.last

      assert_equal "POST", request.request_method
      assert_equal expected_path, request.path
    end

    test "raises timeout errors" do
      FakeVSOServer.reset!

      location = "WestUs2"
      template_guid = "gu-id"
      is_success = true

      client = Codespaces::VscsClient.for_prebuild(location: location)

      # Using partial stub to avoid changing vscs_api_hmac_raw implementation
      client.stubs(:vscs_connection).raises(Faraday::TimeoutError.new("Boom!"))

      assert_raises Codespaces::Client::TimeoutError do
        client.update_prebuild_template_status(location: location, template_guid: template_guid, is_success: is_success)
      end
    end

    test "raises connection failed errors" do
      FakeVSOServer.reset!

      location = "WestUs2"
      template_guid = "gu-id"
      is_success = true

      client = Codespaces::VscsClient.for_prebuild(location: location)

      # Using partial stub to avoid changing vscs_api_hmac_raw implementation
      client.stubs(:vscs_connection).raises(Faraday::ConnectionFailed.new("Boom!"))

      assert_raises Codespaces::Client::ConnectionFailed do
        client.update_prebuild_template_status(location: location, template_guid: template_guid, is_success: is_success)
      end
    end
  end

  context "#delete_prebuild_templates!", skip_enterprise: true do
    context "when delete endpoint includes repo & branch & devcontainer_path & config_id" do
      test "calls the correct endpoint for template deletion" do
        FakeVSOServer.reset!

        location = "WestUs2"
        client = Codespaces::VscsClient.for_prebuild(location: location)

        client.delete_prebuild_templates!(location: location, repository_id: @repo.id, branch: "master", devcontainer_path: ".devcontainer/devcontainer.json", configuration_id: "3")
        expected_path = "/api/v2/prebuilds/delete"
        request = FakeVSOServer.requests.last

        assert_equal "POST", request.request_method
        assert_equal expected_path, request.path
        request_body = GitHub::JSON.parse(request.body)
        assert_equal @repo.id, request_body["repoId"]
        assert_equal "master", request_body["branchName"]
        assert_equal ".devcontainer/devcontainer.json", request_body["devContainerPath"]
        assert_equal "3", request_body["configurationId"]
      end

      test "creates request body without config id if its null" do
        FakeVSOServer.reset!

        location = "WestUs2"
        client = Codespaces::VscsClient.for_prebuild(location: location)

        client.delete_prebuild_templates!(location: location, repository_id: @repo.id, branch: "master", devcontainer_path: ".devcontainer/devcontainer.json", configuration_id: nil)
        expected_path = "/api/v2/prebuilds/delete"
        request = FakeVSOServer.requests.last

        assert_equal "POST", request.request_method
        assert_equal expected_path, request.path
        request_body = GitHub::JSON.parse(request.body)
        assert_nil request_body["configurationId"]
      end

      test "raises connection failed errors for template deletion" do
        FakeVSOServer.reset!

        location = "WestUs2"
        client = Codespaces::VscsClient.for_prebuild(location: location)

        # Using partial stub to avoid changing vscs_api_hmac_raw implementation
        client.stubs(:vscs_connection).raises(Faraday::ConnectionFailed.new("Boom!"))

        assert_raises Codespaces::Client::ConnectionFailed do
          client.delete_prebuild_templates!(location: location, repository_id: @repo.id, branch: "master", devcontainer_path: "devcontainer.json", configuration_id: "3")
        end
      end

      test "raises timeout errors for template deletion" do
        FakeVSOServer.reset!

        location = "WestUs2"
        client = Codespaces::VscsClient.for_prebuild(location: location)

        # Using partial stub to avoid changing vscs_api_hmac_raw implementation
        client.stubs(:vscs_connection).raises(Faraday::TimeoutError.new("Boom!"))

        assert_raises Codespaces::Client::TimeoutError do
          client.delete_prebuild_templates!(location: location, repository_id: @repo.id, branch: "master", devcontainer_path: "devcontainer.json", configuration_id: "3")
        end
      end
    end
  end

  context "#update_prebuild_template_versions", skip_enterprise: true do
    test "calls the correct endpoint" do
      FakeVSOServer.reset!

      location = "WestUs2"
      maximum_template_versions = 2
      branch = "master"
      client = Codespaces::VscsClient.for_prebuild(location: location)

      client.update_prebuild_template_versions(location: location, repository: @repo, branch: branch, maximum_template_versions: maximum_template_versions)

      expected_path = "/api/v2/prebuilds/templates/updatemaxversions"
      request = FakeVSOServer.requests.last

      assert_equal "POST", request.request_method
      assert_equal expected_path, request.path
      request_body = GitHub::JSON.parse(request.body)
      assert_equal @repo.id, request_body["repoId"]
      assert_equal branch, request_body["branchName"]
      assert_equal maximum_template_versions, request_body["maxPrebuildTemplateVersions"]
      assert_nil request_body["devContainerPath"]
    end

    test "passes a devContainerPath" do
      FakeVSOServer.reset!

      location = "WestUs2"
      maximum_template_versions = 2
      branch = "master"
      devcontainer_path = ".devcontainer/custom/devcontainer.json"
      client = Codespaces::VscsClient.for_prebuild(location: location)

      client.update_prebuild_template_versions(location: location, repository: @repo, branch: branch, maximum_template_versions: maximum_template_versions, devcontainer_path: devcontainer_path)

      expected_path = "/api/v2/prebuilds/templates/updatemaxversions"
      request = FakeVSOServer.requests.last

      assert_equal "POST", request.request_method
      assert_equal expected_path, request.path
      request_body = GitHub::JSON.parse(request.body)
      assert_equal @repo.id, request_body["repoId"]
      assert_equal branch, request_body["branchName"]
      assert_equal maximum_template_versions, request_body["maxPrebuildTemplateVersions"]
      assert_equal devcontainer_path, request_body["devContainerPath"]
    end

    test "raises timeout errors" do
      FakeVSOServer.reset!

      location = "WestUs2"
      maximum_template_versions = 2
      branch = "master"
      client = Codespaces::VscsClient.for_prebuild(location: location)

      # Using partial stub to avoid changing vscs_api_hmac_raw implementation
      client.stubs(:vscs_connection).raises(Faraday::TimeoutError.new("Boom!"))

      assert_raises Codespaces::Client::TimeoutError do
        client.update_prebuild_template_versions(location: location, repository: @repo, branch: branch, maximum_template_versions: maximum_template_versions)
      end
    end

    test "raises connection failed errors" do
      FakeVSOServer.reset!

      location = "WestUs2"
      maximum_template_versions = 2
      branch = "master"
      client = Codespaces::VscsClient.for_prebuild(location: location)

      # Using partial stub to avoid changing vscs_api_hmac_raw implementation
      client.stubs(:vscs_connection).raises(Faraday::ConnectionFailed.new("Boom!"))

      assert_raises Codespaces::Client::ConnectionFailed do
        client.update_prebuild_template_versions(location: location, repository: @repo, branch: branch, maximum_template_versions: maximum_template_versions)
      end
    end
  end

  context "#export_environment" do
    test "makes the appropriate request" do
      FakeVSOServer.reset!
      codespace = create(:codespace)
      FakeVSOServer.environments = [
        {
          "id" => codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN
        }
      ]

      expected_payload = {
        "type" => "GitPush",
        "branchName" => "MY_BRANCH",
        "repositoryName" => "REPOSITORY_NAME",
        "secrets" => [
          "type" => Codespaces::Secret::TYPE_ENV_VAR,
          "name" => "GIT_PAT",
          "value" => "MY_TOKEN"
        ]
      }

      client = Codespaces::VscsClient.for_codespace(codespace)
      client.export_environment(codespace.guid, branch_name: "MY_BRANCH", repository_name: "REPOSITORY_NAME", token: "MY_TOKEN")

      assert_equal expected_payload, FakeVSOServer.environments_exported.first
    end
  end

  context "gracefully handles too much secret data", skip_enterprise: true do
    test "error is raised on too much secret data" do
      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(
          vscs_target: Codespaces::Vscs.default_target,
          plan: @plan,
          user: @user,
          resource_provider: @plan.resource_provider,
      )

      assert_raises Codespaces::VscsClient::SecretDataTooLarge do


        client.create_environment("WestUs2", @repo, sku_name: @default_sku_name,
                                                    name: "test-codespace",
                                                    moniker: @repo.permalink,
                                                    github_token: "github_token",
                                                    billable_owner: @user,
                                                    create_type: "default",
                                                    secrets: [Codespaces::Secret.new(
                                                        "SUPER_SECRET",
                                                        encrypt_with_owner_next_global_id("$" * Codespaces::VscsClient::PAYLOAD_SIZE_LIMIT, @user),
                                                        @user)])

      end
    end
  end

  context "download codespaces agent" do
    test "can fetch agent download info" do
      FakeVSOServer.reset!
      client = Codespaces::VscsClient.for_prebuild(
          location: "WestUs2",
          vscs_target: Codespaces::Vscs.default_target,
      )

      info = client.fetch_agent_download_info
      assert_equal "https://agent-sas-url", info["assetUri"]
      assert_equal "vsoagentlinux", info["family"]
      assert_equal "VSOAgent_linux_5519558.zip", info["name"]
    end
  end

  context "send codespaces agent telemetry" do
    test "can send telemetry" do
      FakeVSOServer.reset!
      client = Codespaces::VscsClient.for_prebuild(
          location: "WestUs2",
          vscs_target: Codespaces::Vscs.default_target,
      )

      telemetry_data = [
        {
          Level: "info",
          Time: "timestring",
          Message: "info_msg_str",
          OptionalValues: {
              SomeKey: "Value1",
          },
        },
        {
          Level: "error",
          Time: "timestring",
          Message: "error_msg",
          OptionalValues: {
            SomeKey: "Value2",
          },
        }
      ]

      assert_nil client.send_agent_telemetry telemetry_data.to_json
    end
  end

  context "send updated user secrets to vscs" do
    test "it successfully send secrets" do
      FakeVSOServer.reset!

      codespace = create(:codespace, vscs_target: Codespaces::Vscs.default_target, owner: @user)
      client = Codespaces::VscsClient.for_codespace(codespace)

      assert_nil client.update_user_secrets codespace, secrets: []
    end

    test "it fails with an VSCS response code 31 (ACTION_NOT_ALLOWED_IN_THIS_STATE_ERROR_CODE)" do
      FakeVSOServer.reset!

      codespace = create(:codespace, vscs_target: Codespaces::Vscs.default_target, owner: @user)
      client = Codespaces::VscsClient.for_codespace(codespace)
      Codespaces::VscsClient.any_instance.stubs(:vscs_api).raises(Codespaces::VscsClient::BadResponseError.new("BOOM!", nil, 31))

      assert_raises Codespaces::VscsClient::InvalidSecretUpdatingStateError do
        client.update_user_secrets codespace, secrets: []
      end
    end
  end

  context "#notify_environment", skip_enterprise: true do
    test "it successfully makes a request to the notify endpoint" do
      FakeVSOServer.reset!

      codespace = create(:codespace, owner: @user, billable_owner: @user)
      client = Codespaces::VscsClient.for_codespace(codespace)

      client.notify_environment(id: codespace.guid, message: "test", display_mode: "warning", modal: false)
      expected_path = "/api/v1/environments/#{codespace.guid}/notify"
      request = FakeVSOServer.requests.last

      assert_equal "POST", request.request_method
      assert_equal expected_path, request.path
    end

    test "it raises an error if the request fails" do
      FakeVSOServer.reset!

      codespace = create(:codespace, owner: @user, billable_owner: @user)
      client = Codespaces::VscsClient.for_codespace(codespace)

      Codespaces::VscsClient.any_instance.stubs(:vscs_api).raises(Codespaces::VscsClient::BadResponseError.new("BOOM!", nil, 31))

      assert_raises Codespaces::VscsClient::BadResponseError do
        client.notify_environment(id: codespace.guid, message: "test", display_mode: "warning", modal: false)
      end
    end
  end

  context "#vscs_api" do
    test "request with hmac for vscs token endpoint" do
      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(
          vscs_target: Codespaces::Vscs.default_target,
          plan: @plan,
          user: @user,
          resource_provider: @plan.resource_provider,
      )

      client.send(:vscs_api,
        :post,
        "/api/v1/tokens/plans/#{@plan.name}/readAllCodespaces",
        body: {}.to_json,
        caller: "test",
      )

      requests = FakeVSOServer.requests_for("/readAllCodespaces")
      assert requests.length > 0

      requests.each do |request|
        refute_nil request.env["HTTP_REQUEST_HMAC"]
        assert_nil request.env["HTTP_AUTHORIZATION"]
      end
    end

    test "request with hmac for any vscs call" do
      codespace = create(:codespace, owner: @user)

      FakeVSOServer.reset!
      FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN }

      client = Codespaces::VscsClient.new(
          vscs_target: Codespaces::Vscs.default_target,
          plan: @plan,
          user: @user,
          resource_provider: @plan.resource_provider,
      )

      client.delete_environment!(codespace.guid)
      requests = FakeVSOServer.requests.select { |req| req.env["PATH_INFO"].match("/api/v1/environments/#{codespace.guid}") }
      assert requests.length > 0

      requests.each do |request|
        assert_nil request.env["HTTP_AUTHORIZATION"]
        refute_nil request.env["HTTP_REQUEST_HMAC"]
        refute_nil request.env["HTTP_X_SUBSCRIPTION_ID"]
        refute_nil request.env["HTTP_X_USER_ID"]
        refute_nil request.env["HTTP_X_PLAN_ID"]
      end
    end

    test "raises MissingHMACKeyError when hmac key is missing" do
      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(
          vscs_target: nil,
          plan: @plan,
          user: @user,
          resource_provider: @plan.resource_provider,
      )

      assert_raises Codespaces::VscsClient::MissingHMACKeyError do
        client.send(:vscs_api,
          :post,
          "/api/v1/tokens/plans/#{@plan.name}/readAllCodespaces",
          body: {}.to_json,
          caller: "test",
        )
      end
    end

    test "raises BadResponseError when invalid JSON is returned on a successful response" do
      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(
        vscs_target: Codespaces::Vscs.default_target,
        plan: @plan,
        user: @user,
        resource_provider: @plan.resource_provider,
      )

      assert_raises Codespaces::Client::BadResponseError do
        client.send(:vscs_api,
          :post,
          "/api/v1/tokens/plans/#{@plan.name}/readAllCodespacesInvalidJson",
          body: {}.to_json,
          caller: "test",
        )
      end
    end

    context "#vscs_api_hmac_raw" do
      test "start environment uses hmac when making request" do
        FakeVSOServer.reset!
        guid = SecureRandom.uuid
        FakeVSOServer.environments << { "id" => guid, "state" => Codespaces::Vscs::State::SHUTDOWN }
        client = Codespaces::VscsClient.new(
          vscs_target: Codespaces::Vscs.default_target,
          plan: @plan,
          user: @user,
          resource_provider: @plan.resource_provider,
        )

        client.start_environment(guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user)

        request = FakeVSOServer.requests.last
        refute_nil request.env["HTTP_REQUEST_HMAC"]
        refute_nil request.env["HTTP_X_SUBSCRIPTION_ID"]
        refute_nil request.env["HTTP_X_USER_ID"]
      end
    end
  end

  context "#vscs_api_hmac_raw authentication requirements" do
    test "request with token and hmac" do
      codespace = create(:codespace, owner: @user)

      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(
          vscs_target: Codespaces::Vscs.default_target,
          plan: @plan,
          user: @user,
          resource_provider: @plan.resource_provider,
      )

      client.send(:vscs_api_hmac_raw,
        :delete,
        "/api/v1/environments/#{codespace.id}",
        caller: "vscs_api_hmac_raw_test",
        body: {}.to_json,
        tags: ["caller:test"]
      )

      requests = FakeVSOServer.requests_for("/api/v1/environments/#{codespace.id}")
      assert requests.length > 0

      requests.each do |request|
        refute_nil request.env["HTTP_REQUEST_HMAC"]
        refute_nil request.env["HTTP_X_SUBSCRIPTION_ID"]
        refute_nil request.env["HTTP_X_PLAN_ID"]
        refute_nil request.env["HTTP_X_USER_ID"]
      end
    end
  end

  context "vscs tier capacity validation fails" do
    test "create_environment fails with an VSCS response code 37 (TIER_CAPACITY_UNAVAILABLE_ERROR_CODE)" do
      FakeVSOServer.reset!
      client = Codespaces::VscsClient.new(
          vscs_target: Codespaces::Vscs.default_target,
          plan: @plan,
          user: @user,
          resource_provider: @plan.resource_provider,
      )

      Codespaces::VscsClient.any_instance.stubs(:vscs_api).raises(Codespaces::VscsClient::BadResponseError.new("Tier capacity is unavailable!", nil, 37))

      assert_raises Codespaces::VscsClient::TierCapacityUnavailableError do
        client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "", billable_owner: @user, create_type: "default")
      end
    end

    context "start_environment fails with an VSCS response code 37 (TIER_CAPACITY_UNAVAILABLE_ERROR_CODE)" do
      test "with cascade token auth" do
        guid = SecureRandom.uuid
        FakeVSOServer.reset!
        FakeVSOServer.fake_responses = [
          {
            endpoint: "/api/v1/environments/#{guid}/start",
            status: 400,
            body: "37",
          }
        ]
        client = Codespaces::VscsClient.new(
          vscs_target: Codespaces::Vscs.default_target,
          plan: @plan,
          user: @user,
          resource_provider: @plan.resource_provider,
        )

        assert_raises Codespaces::VscsClient::TierCapacityUnavailableError do
          client.start_environment(guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user)
        end
      end

      test "with hmac auth" do
        guid = SecureRandom.uuid
        FakeVSOServer.reset!
        FakeVSOServer.fake_responses = [
          {
            endpoint: "/api/v1/environments/#{guid}/start",
            status: 400,
            body: "37",
          }
        ]
        client = Codespaces::VscsClient.new(
          vscs_target: Codespaces::Vscs.default_target,
          plan: @plan,
          user: @user,
          resource_provider: @plan.resource_provider,
        )

        assert_raises Codespaces::VscsClient::TierCapacityUnavailableError do
          client.start_environment(guid, github_token: "github_token", sku_name: "basicLinux", repository: @repo, billable_owner: @user)
        end
      end
    end
  end

  context "basis auth" do
    context "#fetch_tunnel_access_token_and_visibility" do
      test "returns token" do
        FakeVSOServer.reset!
        codespace = create(:codespace, owner: @user)

        client = Codespaces::VscsClient.for_codespace(codespace)

        port = 80
        result = client.fetch_tunnel_access_token_and_visibility(codespace_id: codespace.id, port: port)

        request = FakeVSOServer.requests.last
        expected_path = "/api/v1/tunnel/#{codespace.id}/portInfo"
        query_string = "portNumber=#{port}"

        assert_equal "GET", request.request_method
        assert_equal expected_path, request.path
        assert_equal query_string, request.query_string
        refute_nil result

        # check result
        token, visibility = result
        refute_nil token
        refute_nil visibility
      end
    end
  end

  context "create codespace with copilot_workspace_id" do
    test "creating copilotWorkspace codespace not allowed without FF " do
      FakeVSOServer.reset!
      GitHub.flipper[:copilot_workspace].disable(@user)
      codespace = create(:codespace, owner: @user, billable_owner: @user)
      client = Codespaces::VscsClient.for_codespace(codespace)
      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "",  billable_owner: @user, create_type: "default", environment_options: { copilot_workspace_id: "1234" })

      environment = FakeVSOServer.environments_created.last
      assert_nil environment["experimentalFeatures"]["copilotWorkspace"]
    end

    test "creating copilotWorkspace codespace allowed under FF " do
      FakeVSOServer.reset!
      GitHub.flipper[:copilot_workspace].enable(@user)
      codespace = create(:codespace, owner: @user, billable_owner: @user)
      client = Codespaces::VscsClient.for_codespace(codespace)
      client.create_environment("WestUs2", @repo, sku_name: @default_sku_name, name: "test-codespace", moniker: @repo.permalink, github_token: "",  billable_owner: @user, create_type: "default", environment_options: { copilot_workspace_id: "1234" })

      environment = FakeVSOServer.environments_created.last
      assert_equal true, environment["experimentalFeatures"]["copilotWorkspace"]
    end
  end

  def default_secrets(user, repository_nwo:, github_token: "github_token", vscs_target_url: "https://vscstest.ngrok.io", vscs_target: :production)
    target_config = Codespaces::Vscs.config_for_target(vscs_target)
    secrets = T.let([
      { "type" => Codespaces::Secret::TYPE_ENV_VAR, "name" => "GITHUB_SERVER_URL", "value" => GitHub.url },
      { "type" => Codespaces::Secret::TYPE_ENV_VAR, "name" => "GITHUB_API_URL", "value" => GitHub.api_url },
      { "type" => Codespaces::Secret::TYPE_ENV_VAR, "name" => "GITHUB_GRAPHQL_URL", "value" => GitHub.graphql_api_url },
      { "type" => Codespaces::Secret::TYPE_ENV_VAR, "name" => "GITHUB_REPOSITORY", "value" => repository_nwo },
      { "type" => Codespaces::Secret::TYPE_ENV_VAR, "name" => "INTERNAL_VSCS_TARGET_URL", "value" => vscs_target_url },
      { "type" => Codespaces::Secret::TYPE_ENV_VAR, "name" => "GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN", "value" => Codespaces::Vscs.dev_tunnels_domain_for_target(vscs_target) },
    ], T::Array[Hash])

    if github_token.present?
      secrets.push({
        "type" => Codespaces::Secret::TYPE_ENV_VAR,
        "name" => "GITHUB_TOKEN",
        "value" => github_token,
      })

      secrets.push({
        "type" => Codespaces::Secret::TYPE_CONTAINER_REGISTRY,
        "name" => "docker.pkg.github.com",
        "value" => github_token,
      })
    end

    if user
      secrets.push({
        "type" => Codespaces::Secret::TYPE_ENV_VAR,
        "name" => "GITHUB_USER",
        "value" => user.login,
      })

      if github_token.present?
        secrets.push({
          "type" => Codespaces::Secret::TYPE_CONTAINER_REGISTRY,
          "name" => "#{user.login}@containers.pkg.github.com",
          "value" => github_token,
        })
      end
    else
      if github_token.present?
        secrets.push({
          "type" => Codespaces::Secret::TYPE_CONTAINER_REGISTRY,
          "name" => "containers.pkg.github.com",
          "value" => "secret secret"
        })
      end
    end

    if !GitHub.flipper[:codespaces_no_default_dockerhub_credentials].enabled?(user)
      secrets.push({
        "type" => Codespaces::Secret::TYPE_CONTAINER_REGISTRY,
        "name" => "#{GitHub.codespaces_dockerhub_registry[:username]}@#{GitHub.codespaces_dockerhub_registry[:url]}",
        "value" => GitHub.codespaces_dockerhub_registry[:password]
      })
    end

    secrets
  end

  def assert_query_parameters(expected_path, query_string, result)
    request = FakeVSOServer.requests.last
    assert_equal "GET", request.request_method
    assert_equal expected_path, request.path
    assert_equal query_string, request.query_string
    assert_includes result.keys, "templateSkus"
    assert_includes result.keys, "poolSkus"
  end
end unless GitHub.enterprise?
