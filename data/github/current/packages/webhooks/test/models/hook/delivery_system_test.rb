# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/aqueduct_test_client"
require "timecop"

class Hook
  class Event
    class DeliverySystemTestEvent < Hook::Event
      extend T::Helpers

      supports_targets Repository, Organization, Integration, Marketplace::Listing
      feature_flag :delivery_system_test_event_hook

      event_attr :action, :hooks, :actor, :feature_flag_actor, :target_organization, :target_repository, :include_per_hook_headers

      def subscribed_hooks
        Array.wrap(T.unsafe(self).hooks)
      end

      def headers_for(hook)
        if T.unsafe(self).include_per_hook_headers
          super + [{ "X-Example" => "Hook:#{hook.id}" }]
        else
          super
        end
      end
    end
  end

  class Payload
    class DeliverySystemTestPayload < Hook::Payload
      def to_payload_hash
        {
          action: hook_event.action,
        }
      end
    end
  end
end

class HookDeliverySystemTest < GitHub::TestCase
  include HydroTestHelpers
  include DogstatsTestHelpers

  fixtures do
    @org = create(:organization, plan: "business_plus")
    @repo = create :repository, owner: @org, from_example: :post_receive_job_test
    @repo2 = create :repository, owner: @org

    @integration = Integration::Events.stub_const(:SUPPORTED_EVENTS, %w(delivery_system_test)) do
      Integration::Events.stub_const(:RESOURCE_TO_EVENTS, { "metadata" => %w(delivery_system_test) }) do
        integration = create(:integration,
          :with_active_hook,
          default_permissions: { "metadata" => :read },
          default_events: %w(delivery_system_test),
        )
        @installation = make_integration_installation(integration: integration, target: @org)
        @other_installation = make_integration_installation(integration: integration, target: create(:organization))
        integration
      end
    end

    enable_feature_flag(:public_key_webhook_signing, @integration)

    @org_hook = create :hook, :org, installation_target: @org, config: { url: "http://example.com/endpoint" }
    @repo_hook = create :hook, :web, installation_target: @repo, config: { url: "http://example.com/endpoint" }
    @repo_hook2 = create :hook, :web, installation_target: @repo, config: { url: "http://example.com/anotherendpoint" }
    @repo_with_content_type_hook = create :hook, :web, installation_target: @repo2, config: { url: "http://example.com/endpoint2", content_type: "application/vnd.github-hooks.hawkeye-preview+json" }
    @integration_hook = @integration.hook
    @integration_hook.update(config: { url: "http://example.com/endpoint" })

    make_trusted_oauth_apps_owner
    @actions_app = GitHub.launch_github_app || create(:launch_integration, :with_active_hook, default_permissions: Apps::Privileged::Actions::PERMISSIONS, default_events: %w(status workflow_run push issues))
    @actions_lab_app = create(:launch_lab_integration, :with_active_hook, default_permissions: Apps::Privileged::Actions::PERMISSIONS, default_events: %w(status))
    @chatops_app = GitHub.slack_github_app || create(:slack_integration)

    @actions_repo = create :repository, owner: @org, from_example: :post_receive_job_test
    example_repo_snapshot

    GitHub.stubs(:actions_enabled?).returns(true)

    workflow = create(:workflow, repository: @actions_repo)
    check_suite = create(:check_suite_for_actions_app,
      status: :in_progress,
      conclusion: nil,
      head_sha: @actions_repo.default_branch_ref.target_oid,
      repository: @actions_repo,
      head_repository: @actions_repo,
      event: "push",
      workflow_file_path: ".github/workflows/main.yml",
      completed_log_url: "https://logs.github.com/something",
      rerequestable: true,
      created_at: 3.weeks.ago)
    @workflow_run = check_suite.workflow_run

    disable_feature_flag(:write_to_hookshot_resharded_db)
    disable_feature_flag(:hookshot_go_async_hook_delivery_metadata)
    disable_feature_flag(:hookshot_go_async_hook_delivery_payloads)
    disable_feature_flag(:webhooks_validate_payload_schema)
  end

  setup do
    example_repo_restore
    GitHub.stubs(:actions_enabled?).returns(true)

    @triggered_at = 10.minutes.ago
    @event = Hook::Event::DeliverySystemTestEvent.new action: "created",
      hooks: [@org_hook, @repo_hook, @repo_hook2, @repo_with_content_type_hook, @integration_hook],
      feature_flag_actor: @org,
      triggered_at: @triggered_at
    @delivery_system = Hook::DeliverySystem.new @event

    reset_aqueduct_clients!
    @hookshot_client = stub "Hookshot::Client", deliver: [200, "OK"]
    Hookshot::Client.stubs(:for_parent).returns @hookshot_client

    @client = AqueductTestClient.new(app: "hookshot-test")
    GitHub.stubs(:build_aqueduct_client).returns(@client)

    uuid = SimpleUUID::UUID.new(Time.now)
    @guid = uuid.to_guid
    @guid_time = uuid.to_time
    SimpleUUID::UUID.any_instance.stubs(:to_guid).returns(@guid)

    @avatar_query_params = { v: 2, b: 1 }
    @avatar_query_params[:jwt] = private_avatar_jwt if TestEnv.test_all_features?

    @org_payload = {
      parent: "organization-#{@org.id}",
      guid: @guid,
      event: "delivery_system_test",
      payload: {
        action: "created",
      },
      pricing_plan: nil,
      events_v2_validation_enabled: false,
      delivery_rate_limit_key: nil,
      hooks: [
        {
          id: @org_hook.id,
          service: "web",
          configuration: { needs_public_key_signature: false },
          headers: [],
          data: { "url" => "http://example.com/endpoint", "insecure_ssl" => "0" },
          callback_url: "#{GitHub.api_url}/hooks/#{@guid}/#{@org_hook.id}",
          metadata: {
            repo_id: nil,
            installation_id: nil,
          },
        },
      ],
    }

    @integration_payload = {
      parent: "integration-#{@integration.id}",
      guid: @guid,
      event: "delivery_system_test",
      payload: {
        action: "created",
      },
      pricing_plan: nil,
      events_v2_validation_enabled: false,
      delivery_rate_limit_key: nil,
      hooks: [
        {
          id: @integration_hook.id,
          service: "web",
          configuration: { needs_public_key_signature: true },
          headers: [],
          data: { "url" => "http://example.com/endpoint", "insecure_ssl" => "0" },
          callback_url: "#{GitHub.api_url}/hooks/#{@guid}/#{@integration_hook.id}",
          metadata: {
            repo_id: nil,
            installation_id: nil,
          },
        },
      ],
    }

    @org_with_org_payload = {
      parent: "organization-#{@org.id}",
      guid: @guid,
      event: "delivery_system_test",
      payload: {
        action: "created",
        organization: {
          login: @org.login,
          id: @org.id,
          node_id: @org.global_relay_id,
          url: "#{GitHub.api_url}/orgs/#{@org}",
          repos_url: "#{GitHub.api_url}/orgs/#{@org}/repos",
          events_url: "#{GitHub.api_url}/orgs/#{@org}/events",
          hooks_url: "#{GitHub.api_url}/orgs/#{@org}/hooks",
          issues_url: "#{GitHub.api_url}/orgs/#{@org}/issues",
          members_url: "#{GitHub.api_url}/orgs/#{@org}/members{/member}",
          public_members_url: "#{GitHub.api_url}/orgs/#{@org}/public_members{/member}",
          avatar_url: "#{GitHub.alambic_avatar_url}/u/#{@org.id}?#{@avatar_query_params.to_query}",
          description: nil,
        },
      },
      pricing_plan: @org.plan.name,
      events_v2_validation_enabled: false,
      delivery_rate_limit_key: "Organization:#{@org.id}",
      hooks: [
        {
          id: @org_hook.id,
          service: "web",
          configuration: { needs_public_key_signature: false },
          headers: [],
          data: { "url" => "http://example.com/endpoint", "insecure_ssl" => "0" },
          callback_url: "#{GitHub.api_url}/hooks/#{@guid}/#{@org_hook.id}",
          metadata: {
            repo_id: nil,
            installation_id: nil,
          },
        },
      ],
    }

    @integration_with_installation_payload = @integration_payload.merge(
      payload: {
        action: "created",
        organization: {
          login: @org.login,
          id: @org.id,
          node_id: @org.global_relay_id,
          url: "#{GitHub.api_url}/orgs/#{@org}",
          repos_url: "#{GitHub.api_url}/orgs/#{@org}/repos",
          events_url: "#{GitHub.api_url}/orgs/#{@org}/events",
          hooks_url: "#{GitHub.api_url}/orgs/#{@org}/hooks",
          issues_url: "#{GitHub.api_url}/orgs/#{@org}/issues",
          members_url: "#{GitHub.api_url}/orgs/#{@org}/members{/member}",
          public_members_url: "#{GitHub.api_url}/orgs/#{@org}/public_members{/member}",
          avatar_url: "#{GitHub.alambic_avatar_url}/u/#{@org.id}?#{@avatar_query_params.to_query}",
          description: nil,
        },
        installation: {
          id: @installation.id,
          node_id: @installation.global_relay_id,
        },
      },
      pricing_plan: @org.plan.name,
      events_v2_validation_enabled: false,
      delivery_rate_limit_key: "Organization:#{@org.id}",
      hooks: [
        {
          id: @integration_hook.id,
          service: "web",
          configuration: { needs_public_key_signature: true },
          headers: [],
          data: { "url" => "http://example.com/endpoint", "insecure_ssl" => "0" },
          callback_url: "#{GitHub.api_url}/hooks/#{@guid}/#{@integration_hook.id}",
          metadata: {
            repo_id: nil,
            installation_id: @installation.id,
          },
        },
      ],
    )

    @integration_with_installation_and_custom_headers_payload = @integration_with_installation_payload.merge(
      hooks: [
        {
          id: @integration_hook.id,
          service: "web",
          configuration: { needs_public_key_signature: true },
          headers: [
            { "X-Example" => "Hook:#{@integration_hook.id}" },
          ],
          data: { "url" => "http://example.com/endpoint", "insecure_ssl" => "0" },
          callback_url: "#{GitHub.api_url}/hooks/#{@guid}/#{@integration_hook.id}",
          metadata: {
            repo_id: nil,
            installation_id: @installation.id,
          },
        },
      ],
    )

    @repo_with_repo_payload = {
      parent: "repository-#{@repo.id}",
      guid: @guid,
      event: "delivery_system_test",
      payload: {
        action: "created",
        repository: Api::Serializer.serialize(:repository_with_custom_properties_hash, @repo),
      },
      pricing_plan: @repo.owner.plan.name,
      events_v2_validation_enabled: false,
      delivery_rate_limit_key: "User:#{@repo.owner.id}",
      hooks: [
        {
          id: @repo_hook.id,
          service: "web",
          configuration: { needs_public_key_signature: false },
          headers: [],
          data: { "url" => "http://example.com/endpoint", "insecure_ssl" => "0" },
          callback_url: "#{GitHub.api_url}/hooks/#{@guid}/#{@repo_hook.id}",
          metadata: {
            repo_id: @repo.id,
            installation_id: nil,
          },
        },
      ],
    }

    @v3_repo_payload = {
      parent: "repository-#{@repo.id}",
      guid: @guid,
      event: "delivery_system_test",
      payload: {
        action: "created",
      },
      pricing_plan: nil,
      events_v2_validation_enabled: false,
      delivery_rate_limit_key: nil,
      hooks: [
        {
          id: @repo_hook.id,
          service: "web",
          configuration: { needs_public_key_signature: false },
          headers: [],
          data: { "url" => "http://example.com/endpoint", "insecure_ssl" => "0" },
          callback_url: "#{GitHub.api_url}/hooks/#{@guid}/#{@repo_hook.id}",
          metadata: {
            repo_id: nil,
            installation_id: nil,
          },
        },
        {
          id: @repo_hook2.id,
          service: "web",
          configuration: { needs_public_key_signature: false },
          headers: [],
          data: { "url" => "http://example.com/anotherendpoint", "insecure_ssl" => "0" },
          callback_url: "#{GitHub.api_url}/hooks/#{@guid}/#{@repo_hook2.id}",
          metadata: {
            repo_id: nil,
            installation_id: nil,
          },
        },
      ],
    }

    @repo_with_content_type_payload = {
      parent: "repository-#{@repo2.id}",
      guid: @guid,
      event: "delivery_system_test",
      payload: {
        action: "created",
      },
      pricing_plan: nil,
      events_v2_validation_enabled: false,
      delivery_rate_limit_key: nil,
      hooks: [
        {
          id: @repo_with_content_type_hook.id,
          service: "web",
          configuration: { needs_public_key_signature: false },
          headers: [],
          data: {
            "url" => "http://example.com/endpoint2",
            "content_type" => "application/vnd.github-hooks.hawkeye-preview+json",
            "insecure_ssl" => "0",
          },
          callback_url: "#{GitHub.api_url}/hooks/#{@guid}/#{@repo_with_content_type_hook.id}",
          metadata: {
            repo_id: nil,
            installation_id: nil,
          },
        },
      ],
    }

    Hook.stubs(:delivers_in_test?).returns(true)
    enable_feature_flag(:delivery_system_test_event_hook)

    @actions_repo.importing_stopped!

    # Fixes issue where @actions_lab_app fixture being reloaded by test framework causes test to fail every other run.
    GitHub.stubs(:launch_lab_github_app).returns(@actions_lab_app)
  end

  context ".feature_flags_for_payload" do
    test "returns empty array when parent is nil" do
      parent = "repo-1234"
      enable_feature_flag(:write_to_hookshot_resharded_db, Hook::ParentAsActor.new(parent))
      assert_equal [], Hook::DeliverySystem.feature_flags_for_payload(nil)
    end

    test "returns array of feature flags" do
      parent = "repo-1234"
      enable_feature_flag(:write_to_hookshot_resharded_db, Hook::ParentAsActor.new(parent))
      assert_equal [:write_to_hookshot_resharded_db], Hook::DeliverySystem.feature_flags_for_payload(parent)
    end

    test "only sets feature flags defined in feature_flags_for_payload" do
      parent = "repo-1234"
      enable_feature_flag(:write_to_hookshot_resharded_db, Hook::ParentAsActor.new(parent))
      enable_feature_flag(:public_key_webhook_signing, Hook::ParentAsActor.new(parent))
      enable_feature_flag(:hookshot_go_async_hook_delivery_metadata, Hook::ParentAsActor.new(parent))
      enable_feature_flag(:hookshot_go_async_hook_delivery_payloads, Hook::ParentAsActor.new(parent))
      enable_feature_flag(:webhooks_validate_payload_schema, Hook::ParentAsActor.new(parent))
      assert_equal [:write_to_hookshot_resharded_db,
        :hookshot_go_async_hook_delivery_metadata,
        :hookshot_go_async_hook_delivery_payloads,
        :webhooks_validate_payload_schema], Hook::DeliverySystem.feature_flags_for_payload(parent)
    end
  end

  context ".deliver" do
    test "builds a new delivery instance and triggers deliver on it" do
      event = Hook::Event::DeliverySystemTestEvent.new action: "created"
      Hook::DeliverySystem.any_instance.expects(:deliver)

      Hook::DeliverySystem.deliver event
    end
  end

  context ".redeliver" do
    test "enqueues a redelivery to the hookshot-$ENV Aqueduct app" do
      @org_hook.content_type = "json"
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      GitHub.context.push(request_id: "test-request-id")
      aq_client = AqueductTestClient.new(app: "hookshot-test")
      GitHub.stubs(:aqueduct_gateway_circuit_breaker).returns(nil)
      GitHub.expects(:build_aqueduct_client)
        .with(app: "hookshot-test", url: GitHub.aqueduct_hookshot_url, circuit_breaker: nil,  api_key: nil, api_key_version: nil)
        .returns(aq_client)

      Hook::DeliverySystem.redeliver @guid, @org_hook

      enqueued = aq_client.enqueued_for(app: "hookshot-test", queue: "hookshot-redeliveries")
      assert_equal 1, enqueued.count
      payload = JSON.parse(enqueued.first[:payload])
      assert_equal @guid, payload["guid"]
      assert_equal @org_hook.id, payload["hook_id"]
      assert_equal @org_hook.hookshot_parent_id, payload["parent"]
      assert_equal @org_hook.config_with_tenant_scoped_url, payload["hook_data"]
      configuration = { "needs_public_key_signature" => Hook::DeliverySystem.needs_public_key_signature?(@org_hook) }
      assert_equal configuration, payload["hook_configuration"]
      refute_nil payload["enqueued_at"]
      refute_nil payload["github_request_id"]
    end

    test "records time spent" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      Hook::DeliverySystem.redeliver @guid, @org_hook

      assert_equal 1, @client.enqueued_for(app: "hookshot-test", queue: "hookshot-redeliveries").size

      assert_equal 1, GitHub.dogstats.distributions("hooks.send_redelivery_to_aqueduct.time").count
    end

    test "records error raised" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      GitHub.aqueduct_primary.stubs(:send_job).raises(Aqueduct::Client::ClientError.new(RuntimeError.new))

      Hookshot::Client.stub_const(:PARENTS_USING_STAGING, {}) do
        assert_raises Aqueduct::Client::ClientError do
          Hook::DeliverySystem.redeliver @guid, @org_hook
        end
      end

      assert_equal 1, GitHub.dogstats.increments("hooks.send_redelivery_to_aqueduct.error").count
    end

    test "sets interpolated tenant-scoped hook url in payload with FF enabled" do
      app = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: true }, options: { owner: @org })
      hook = create :hook, installation_target: app
      hook.url = "https://{hostname}/callback"

      expected_payload = {
        hook_id: hook.id,
        guid: @guid,
        parent: hook.hookshot_parent_id,
        hook_data: hook.config_with_tenant_scoped_url,
        hook_configuration: {
          needs_public_key_signature: false
        }
      }

      enable_feature_flag(:tenant_scoped_config_url)
      Hook::DeliverySystem.expects(:post_redelivery_to_aqueduct).with(expected_payload)

      Hook::DeliverySystem.redeliver @guid, hook
    end

    test "does not set interpolated tenant-scoped hook url in payload with FF disabled" do
      app = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: true }, options: { owner: @org })
      hook = create :hook, installation_target: app
      hook.url = "https://{hostname}/callback"

      expected_payload = {
        hook_id: hook.id,
        guid: @guid,
        parent: hook.hookshot_parent_id,
        hook_data: hook.config, # no tenant-scoped url
        hook_configuration: {
          needs_public_key_signature: false
        }
      }

      disable_feature_flag(:tenant_scoped_config_url)

      Hook::DeliverySystem.redeliver @guid, hook
    end
  end

  context ".post_payload_to_hookshot" do
    test "posts a payload to Hookshot" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      @hookshot_client.expects(:deliver).with(@org_payload).returns([200, ""])

      Hook::DeliverySystem.post_payload_to_hookshot(@org_payload)

      expected_tags = [
        "status:200",
        "event:hook/delivery_system_test_created",
        "event_type:hook/delivery_system_test",
      ]
      assert_equal 1, GitHub.dogstats.distributions("hooks.send_to_hookshot.time", tags: expected_tags).count
    end

    test "finds parent from string or symbol key" do
      Hookshot::Client.expects(:for_parent).with("parent-123").twice.returns(@hookshot_client)

      Hook::DeliverySystem.post_payload_to_hookshot({ parent: "parent-123", hooks: [] })
      Hook::DeliverySystem.post_payload_to_hookshot({ "parent" => "parent-123", "hooks" => [] })
    end

    test "raises a HookShot::BadResponseError if the response is not OK" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      @hookshot_client.expects(:deliver).with(@org_payload).returns([500, ""])

      assert_raises Hookshot::BadResponseError do
        Hook::DeliverySystem.post_payload_to_hookshot(@org_payload)
      end

      expected_tags = [
        "status:500",
        "event:hook/delivery_system_test_created",
        "event_type:hook/delivery_system_test",
      ]
      assert_equal 1, GitHub.dogstats.distributions("hooks.send_to_hookshot.time", tags: expected_tags).count
    end

    test "raises a Hookshot::PayloadTooLarge error if the status was 413" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      @hookshot_client.expects(:deliver).with(@org_payload).returns([413, ""])

      assert_raises Hookshot::PayloadTooLarge do
        Hook::DeliverySystem.post_payload_to_hookshot(@org_payload)
      end

      expected_tags = [
        "status:413",
        "event:hook/delivery_system_test_created",
        "event_type:hook/delivery_system_test",
      ]
      assert_equal 1, GitHub.dogstats.distributions("hooks.send_to_hookshot.time", tags: expected_tags).count
    end

    test "increments a counter when delivery raises and continues to bubble up the error" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      @hookshot_client.expects(:deliver).with(@org_payload).raises(StandardError.new("HALP"))

      assert_raises StandardError do
        Hook::DeliverySystem.post_payload_to_hookshot(@org_payload)
      end

      assert_equal 0, GitHub.dogstats.distributions("hooks.send_to_hookshot.time").count
      expected_tags = [
        "exception:standard_error",
        "event:hook/delivery_system_test_created",
        "event_type:hook/delivery_system_test",
      ]
      assert_equal 1, GitHub.dogstats.increments("hooks.delivery_error.count", tags: expected_tags).count
    end
  end

  context ".enqueue_payload_to_hookshot" do
    test "includes flipper feature metadata in each payload" do
      parent = "repo-1234"
      payload = {
        parent: parent,
        hook: {
          data: {
            url: "http://foo.com/bar",
            content_type: "json",
          },
          configuration: {
            needs_public_key_signature: false,
          },
        },
      }
      enable_feature_flag(:write_to_hookshot_resharded_db, Hook::ParentAsActor.new(parent))
      enable_feature_flag(:hookshot_go_async_hook_delivery_metadata, Hook::ParentAsActor.new(parent))
      enable_feature_flag(:hookshot_go_async_hook_delivery_payloads, Hook::ParentAsActor.new(parent))
      enable_feature_flag(:webhooks_validate_payload_schema, Hook::ParentAsActor.new(parent))

      mock_client = mock("GitHub::Aqueduct::Client")
      Hook::DeliverySystem.expects(:aqueduct_client_for).once.with(parent).returns(mock_client)
      GitHub.stubs(:context_propagation_map).returns({})

      Timecop.freeze(time) do
        enqueued_at = (Time.now.to_f * 1_000).round
        mock_client.expects(:send_job).with(has_entries({
          queue: "hookshot",
          payload: payload.merge({
            github_request_id: nil,
            enqueued_at: enqueued_at,
            features: %w[write_to_hookshot_resharded_db hookshot_go_async_hook_delivery_metadata hookshot_go_async_hook_delivery_payloads webhooks_validate_payload_schema]
          }).to_json,
          headers: {}
        }))
        Hook::DeliverySystem.enqueue_payload_to_hookshot(payload)
      end
    end

    test "uses correct options for generating an aqueduct client" do
      disable_feature_flag(:write_to_hookshot_resharded_db)
      disable_feature_flag(:hookshot_go_async_hook_delivery_metadata)
      disable_feature_flag(:hookshot_go_async_hodok_delivery_payloads)
      GitHub.stubs(:context_propagation_map).returns({})

      parent = "repo-1234"
      payload = {
        parent: parent,
        hook: {
          data: {
            url: "http://foo.com/bar",
            content_type: "json",
          },
          configuration: {
            needs_public_key_signature: false,
          },
        },
      }
      now = Time.now
      enqueued_at = (now.to_f * 1_000).round
      job_args = {
        queue: "hookshot",
        payload: payload.merge({
          github_request_id: nil,
          enqueued_at: enqueued_at,
          features: [],
          }).to_json,
        headers: {}
      }

      mock_client = mock
      mock_client.expects(:send_job).with(has_entries(job_args))
      Hook::DeliverySystem.expects(:aqueduct_client_for).once.with(parent).returns(mock_client)

      Timecop.freeze(now) do
        Hook::DeliverySystem.enqueue_payload_to_hookshot(payload)
      end
    end

    test "delivers to actions queue" do
      GitHub.stubs(:actions_enabled?).returns(true)
      parent = "integration-#{@actions_app&.id}"
      payload = @repo_with_repo_payload.merge({
        parent: parent,
      })
      Hook::DeliverySystem.expects(:aqueduct_client_for).with(parent).never
      Hook::DeliverySystem.expects(:actions_aqueduct_client).returns(mock(send_job: true))

      Hook::DeliverySystem.enqueue_payload_to_hookshot(payload)
    end

    test "delivers to actions webhooks queue for production app" do
      GitHub.stubs(:actions_enabled?).returns(true)
      parent = "integration-#{@actions_app&.id}"
      payload = @repo_with_repo_payload.merge({
        parent: parent,
      })
      Hook::DeliverySystem.expects(:aqueduct_client_for).with(parent).never
      mock_actions_client = mock
      mock_actions_client.expects(:send_job).with(has_entries(queue: "webhooks"))
      Hook::DeliverySystem.expects(:actions_aqueduct_client).returns(mock_actions_client)

      Hook::DeliverySystem.enqueue_payload_to_hookshot(payload)
    end

    test "delivers to actions webhooks-lab queue for lab app" do
      GitHub.stubs(:actions_enabled?).returns(true)
      parent = "integration-#{@actions_lab_app&.id}"
      payload = @repo_with_repo_payload.merge({
        parent: parent,
      })
      Hook::DeliverySystem.expects(:aqueduct_client_for).with(parent).never
      mock_actions_client = mock
      mock_actions_client.expects(:send_job).with(has_entries(queue: "webhooks-lab"))
      Hook::DeliverySystem.expects(:actions_aqueduct_client).returns(mock_actions_client)

      Hook::DeliverySystem.enqueue_payload_to_hookshot(payload)
    end

    test "delivers actions webhook only to actions queue" do
      GitHub.stubs(:actions_enabled?).returns(true)
      parent = "integration-#{@actions_app&.id}"
      payload = @repo_with_repo_payload.merge({
        parent: parent,
      })
      Hook::DeliverySystem.expects(:aqueduct_client_for).never
      Hook::DeliverySystem.expects(:actions_aqueduct_client).returns(mock(send_job: true))
      Hook::DeliverySystem.enqueue_payload_to_hookshot(payload)
    end

    test "sends actions webhook to Aqueduct with ttl specified", skip_enterprise: true do
      GitHub.stubs(:actions_enabled?).returns(true)
      parent = "integration-#{@actions_app&.id}"
      payload = @repo_with_repo_payload.merge({
        parent: parent,
      })

      mock_actions_client = mock
      mock_actions_client.expects(:send_job).with(has_entries(ttl: 60))
      Hook::DeliverySystem.expects(:actions_aqueduct_client).returns(mock_actions_client)

      Timecop.freeze(@guid_time + 29.minutes) do
        Hook::DeliverySystem.enqueue_payload_to_hookshot(payload)
      end
    end

    # This is testing that we correctly handle Time.now - hook_age_seconds resulting in a negative value
    # This is not expected, but could happen as a result of clock skew
    test "sends actions webhook to Aqueduct with ttl specified where event time is in the future", skip_enterprise: true do
      GitHub.stubs(:actions_enabled?).returns(true)
      parent = "integration-#{@actions_app&.id}"
      payload = @repo_with_repo_payload.merge({
        parent: parent,
      })

      mock_actions_client = mock
      mock_actions_client.expects(:send_job).with(has_entries(ttl: 1800)) # 30 minutes
      Hook::DeliverySystem.expects(:actions_aqueduct_client).returns(mock_actions_client)

      Timecop.freeze(@guid_time - 1.minute) do
        Hook::DeliverySystem.enqueue_payload_to_hookshot(payload)
      end
    end

    test "sends actions webhook to Aqueduct with ttl of 0 when age exceeds max ttl", skip_enterprise: true do
      GitHub.stubs(:actions_enabled?).returns(true)
      parent = "integration-#{@actions_app&.id}"
      payload = @repo_with_repo_payload.merge({
        parent: parent,
      })

      logs = []
      msgs = []
      GitHub::logger.expects(:info).with { |msg, log| logs << log; msgs << msg }.at_least_once
      mock_actions_client = mock
      mock_actions_client.expects(:send_job).with(has_entries(ttl: 0))
      Hook::DeliverySystem.expects(:actions_aqueduct_client).returns(mock_actions_client)

      Timecop.freeze(@guid_time + 31.minutes) do
        Hook::DeliverySystem.enqueue_payload_to_hookshot(payload)
      end

      expected_msg = "Actions hook age exceeds time to live"
      expected_log = {
        "gh.request_id" => nil,
        "code.namespace" => "Hook::DeliverySystem",
        "code.function" => "enqueue_payload_to_hookshot",
        "gh.catalog_service" => "github/actions_experience",
        "gh.webhook.queue" => "webhooks",
        "gh.webhook.delivery_guid" => @guid,
        "gh.webhook.event_type" => "delivery_system_test",
        "gh.webhook.triggered_at" => @guid_time,
        "gh.webhook.age_seconds" => 1860,
        "gh.webhook.ttl_limit_seconds" => 1800,
        "gh.webhook.expired" => true,
        "gh.repo.id" => @repo.id,
      }

      assert_equal expected_msg, msgs.last
      assert_equal expected_log, logs.last
    end

    test "sends actions webhook to Aqueduct with a ttl of 0 when age exactly equals max ttl", skip_enterprise: true do
      GitHub.stubs(:actions_enabled?).returns(true)
      parent = "integration-#{@actions_app&.id}"
      payload = @repo_with_repo_payload.merge({
        parent: parent,
      })


      logs = []
      msgs = []
      GitHub::logger.expects(:info).with { |msg, log| logs << log; msgs << msg }.at_least_once
      mock_actions_client = mock
      mock_actions_client.expects(:send_job).with(has_entries(ttl: 0))
      Hook::DeliverySystem.expects(:actions_aqueduct_client).returns(mock_actions_client)

      Timecop.freeze(@guid_time + 30.minutes) do
        Hook::DeliverySystem.enqueue_payload_to_hookshot(payload)
      end

      expected_msg = "Actions hook age exceeds time to live"
      expected_log = {
        "gh.request_id" => nil,
        "code.namespace" => "Hook::DeliverySystem",
        "code.function" => "enqueue_payload_to_hookshot",
        "gh.catalog_service" => "github/actions_experience",
        "gh.webhook.queue" => "webhooks",
        "gh.webhook.delivery_guid" => @guid,
        "gh.webhook.event_type" => "delivery_system_test",
        "gh.webhook.triggered_at" => @guid_time,
        "gh.webhook.age_seconds" => 1800,
        "gh.webhook.ttl_limit_seconds" => 1800,
        "gh.webhook.expired" => true,
        "gh.repo.id" => @repo.id,
      }

      assert_equal expected_msg, msgs.last
      assert_equal expected_log, logs.last
    end

    test "sends actions webhook to Aqueduct without ttl specified in enterprise", enterprise_only: true do
      GitHub.stubs(:actions_enabled?).returns(true)
      parent = "integration-#{@actions_app&.id}"
      payload = @repo_with_repo_payload.merge({
        parent: parent,
      })

      mock_actions_client = mock
      mock_actions_client.expects(:send_job).with(Not(has_key(:ttl)))
      Hook::DeliverySystem.expects(:actions_aqueduct_client).returns(mock_actions_client)

      Timecop.freeze(@guid_time + 30.seconds) do
        Hook::DeliverySystem.enqueue_payload_to_hookshot(payload)
      end
    end

    test "sends actions webhook to Aqueduct without ttl specified where age exceeds max ttl in enterprise", enterprise_only: true do
      GitHub.stubs(:actions_enabled?).returns(true)
      parent = "integration-#{@actions_app&.id}"
      payload = @repo_with_repo_payload.merge({
        parent: parent,
      })

      mock_actions_client = mock
      mock_actions_client.expects(:send_job).with(Not(has_key(:ttl)))
      Hook::DeliverySystem.expects(:actions_aqueduct_client).returns(mock_actions_client)

      Timecop.freeze(@guid_time + 31.minutes) do
        Hook::DeliverySystem.enqueue_payload_to_hookshot(payload)
      end
    end

    test "sends actions webhook to Aqueduct without ttl specified where age exactly equals max ttl in enterprise", enterprise_only: true do
      GitHub.stubs(:actions_enabled?).returns(true)
      parent = "integration-#{@actions_app&.id}"
      payload = @repo_with_repo_payload.merge({
        parent: parent,
      })

      mock_actions_client = mock
      mock_actions_client.expects(:send_job).with(Not(has_key(:ttl)))
      Hook::DeliverySystem.expects(:actions_aqueduct_client).returns(mock_actions_client)

      Timecop.freeze(@guid_time + 30.minutes) do
        Hook::DeliverySystem.enqueue_payload_to_hookshot(payload)
      end
    end

    test "moves actions_meta outside payload[:payload] when it is an actions_delivery" do
      GitHub.stubs(:actions_enabled?).returns(true)
      parent = "integration-#{@actions_app&.id}"
      @repo_with_repo_payload[:payload] = @repo_with_repo_payload[:payload].merge({
        actions_meta: {
          rerun_info: {
            key: "value"
          }
        }
      })

      payload = @repo_with_repo_payload.merge({
        parent: parent,
      })

      Hook::DeliverySystem.expects(:aqueduct_client_for).with(parent).never
      mock_client = mock("GitHub::Aqueduct::Client")
      Hook::DeliverySystem.expects(:actions_aqueduct_client).returns(mock_client)

      mock_client.expects(:send_job).with do |job_args|
        payload_hash = JSON.parse(job_args[:payload])
        payload_hash.has_key?("actions_meta") && !payload_hash["payload"].has_key?("actions_meta")
      end

      Hook::DeliverySystem.enqueue_payload_to_hookshot(payload)
    end

    test "removes actions_meta from payload when it is not an actions_delivery" do
      GitHub.stubs(:actions_enabled?).returns(true)
      parent = "repo-1234"
      @repo_with_repo_payload[:payload] = @repo_with_repo_payload[:payload].merge({
        actions_meta: {
          rerun_info: {
            key: "value"
          }
        }
      })

      payload = @repo_with_repo_payload.merge({
        parent: parent,
      })

      mock_client = mock("GitHub::Aqueduct::Client")
      Hook::DeliverySystem.expects(:aqueduct_client_for).once.with(parent).returns(mock_client)
      Hook::DeliverySystem.expects(:actions_aqueduct_client).never

      mock_client.expects(:send_job).with do |job_args|
        payload_hash = JSON.parse(job_args[:payload])
        !payload_hash.has_key?("actions_meta") && !payload_hash["payload"].has_key?("actions_meta")
      end

      Hook::DeliverySystem.enqueue_payload_to_hookshot(payload)
    end
  end

  context ".hookshot_go_default_aqueduct_client" do
    test "uses the aqueduct_hookshot_url config" do
      GitHub.stubs(:aqueduct_hookshot_url).returns("http://hookshot.aqueduct")
      GitHub.stubs(:aqueduct_gateway_circuit_breaker).returns(nil)
      GitHub.expects(:build_aqueduct_client).with(app: "hookshot-test", url: "http://hookshot.aqueduct", circuit_breaker: nil, api_key: nil, api_key_version: nil)
      Hook::DeliverySystem.hookshot_go_default_aqueduct_client
    end
  end

  context ".hookshot_go_staging_aqueduct_client" do
    test "uses the aqueduct_hookshot_url config" do
      GitHub.stubs(:aqueduct_hookshot_staging_url).returns("http://hookshot.aqueduct")
      GitHub.stubs(:aqueduct_gateway_circuit_breaker).returns(nil)
      GitHub.expects(:build_aqueduct_client).with(app: "hookshot-staging", url: "http://hookshot.aqueduct", circuit_breaker: nil, api_key: nil, api_key_version: nil)
      Hook::DeliverySystem.hookshot_go_staging_aqueduct_client
    end
  end

  context ".aqueduct_client_for" do
    context "and it is not a redelivery" do
      context "when the parent is enabled for staging" do
        test "returns the staging client" do
          parent = "repository-7550011" # staging repo

          staging_go_client = mock("staging_go_client")
          Hook::DeliverySystem.expects(:hookshot_go_staging_aqueduct_client)
            .returns(staging_go_client)

          client = Hook::DeliverySystem.aqueduct_client_for(parent)
          assert_equal staging_go_client, client
        end
      end

      context "when running in a dynamic lab environment" do
        test "returns the staging client" do
          GitHub.stubs(:dynamic_lab?).returns(true)
          staging_go_client = mock("staging_go_client")
          Hook::DeliverySystem.expects(:hookshot_go_staging_aqueduct_client)
            .returns(staging_go_client)

          client = Hook::DeliverySystem.aqueduct_client_for("repo-123")
          assert_equal staging_go_client, client
        end
      end

      context "when the parent is enabled for prod" do
        test "returns the default client" do
          parent = "repository-1" # prod repo

          production_go_client = mock("production_go_client")
          Hook::DeliverySystem.expects(:hookshot_go_default_aqueduct_client)
            .returns(production_go_client)

          client = Hook::DeliverySystem.aqueduct_client_for(parent)
          assert_equal production_go_client, client
        end
      end
    end

    context "and it is a redelivery" do
      context "when the parent is enabled for staging" do
        test "returns the staging GO client" do
          parent = "repository-7550011" # staging repo

          staging_go_client = mock("staging_go_client")
          Hook::DeliverySystem.expects(:hookshot_go_staging_aqueduct_client)
            .returns(staging_go_client)

          client = Hook::DeliverySystem.aqueduct_client_for(parent)
          assert_equal staging_go_client, client
        end
      end

      context "when the parent is enabled for prod" do
        test "returns the default GO client" do
          parent = "repository-1" # prod repo

          production_go_client = mock("production_go_client")
          Hook::DeliverySystem.expects(:hookshot_go_default_aqueduct_client)
            .returns(production_go_client)

          client = Hook::DeliverySystem.aqueduct_client_for(parent)
          assert_equal production_go_client, client
        end
      end
    end
  end

  context "#deliver" do
    context "when no subscribed hooks" do
      test "instruments metadata for dropped event" do
        event = Hook::Event::DeliverySystemTestEvent.new action: "created",
        hooks: [],
        triggered_at: @triggered_at,
        target_organization: @org
        request_id = SecureRandom.uuid
        GitHub.context.push(request_id: request_id)

        delivery_system = Hook::DeliverySystem.new event
        delivery_system.deliver

        assert_hydro_published(
          {
            event_type: event.event_type,
            event_action: event.attributes[:action],
            filtered_reason: "no_deliveries",
            guid: event.guid,
            target_repository_id: nil,
            target_organization_id: @org.id,
            triggered_at:  event.attributes[:triggered_at],
            request_id: GitHub.context[:request_id]
          }, schema:  "github.webhooks.v0.DroppedEventMetadata"
        )
      end
    end

    context "when payload is large" do
      test "triggers .post_payload_to_hookshot for each payload" do
        GitHub::Aqueduct.stubs(:is_payload_size_large?).returns(true)
        Hook::DeliverySystem.expects(:post_payload_to_hookshot).with(@org_payload)
        Hook::DeliverySystem.expects(:post_payload_to_hookshot).with(@v3_repo_payload)
        Hook::DeliverySystem.expects(:post_payload_to_hookshot).with(@repo_with_content_type_payload)
        Hook::DeliverySystem.expects(:post_payload_to_hookshot).with(@integration_payload)

        @delivery_system.deliver
      end

      test "does not POST to Hookshot if all the hooks are muted" do
        GitHub::Aqueduct.stubs(:is_payload_size_large?).returns(true)
        rejected_policy = stub("RejectedOAP", satisfied?: false)
        OauthApplicationPolicy::Hook.stubs(:new).returns(rejected_policy)

        hookshot_client = stub "Hookshot::Client"
        Hookshot::Client.stubs(:for_parent).returns hookshot_client
        hookshot_client.expects(:deliver).never

        @delivery_system.deliver
      end

      test "records success in DD on a per trigger basis" do
        GitHub::Aqueduct.stubs(:is_payload_size_large?).returns(true)
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        Hook::DeliverySystem.expects(:post_payload_to_hookshot).with(@org_payload)
        Hook::DeliverySystem.expects(:post_payload_to_hookshot).with(@v3_repo_payload)
        Hook::DeliverySystem.expects(:post_payload_to_hookshot).with(@repo_with_content_type_payload)
        Hook::DeliverySystem.expects(:post_payload_to_hookshot).with(@integration_payload)

        @delivery_system.deliver

        expected_tags = [
          "event:hook/delivery_system_test_created",
          "event_type:hook/delivery_system_test",
          "status:success",
        ]

        assert_equal 1, GitHub.dogstats.increments("hooks.delivered_to_hookshot.per_trigger.count", tags: expected_tags).count
      end

      test "records errors in DD on a per trigger basis and lets them continue to bubble up" do
        GitHub::Aqueduct.stubs(:is_payload_size_large?).returns(true)
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        Hook::DeliverySystem.expects(:post_payload_to_hookshot).with(@org_payload).raises(Hookshot::PayloadTooLarge.new(nil, nil))

        assert_raises(Hookshot::PayloadTooLarge) do
          @delivery_system.deliver
        end

        expected_tags = [
          "event:hook/delivery_system_test_created",
          "event_type:hook/delivery_system_test",
          "status:failure",
          "exception_class:hookshot/payload_too_large",
        ]

        assert_equal 1, GitHub.dogstats.increments("hooks.delivered_to_hookshot.per_trigger.count", tags: expected_tags).count
      end

      test "records metrics in DD for hooks successfully posted to hookshot" do
        GitHub::Aqueduct.stubs(:is_payload_size_large?).returns(true)
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        mock_payload = {
          parent: "repository-#{@repo.id}",
          guid: @guid,
          event: "delivery_system_test",
          payload: {
            action: "created",
          },
          hooks: [
            {
              id: @repo_hook.id,
              service: "web",
              configuration: { needs_public_key_signature: false },
              headers: [],
              data: { "url" => "http://example.com/endpoint", "insecure_ssl" => "0" },
              callback_url: "#{GitHub.api_url}/hooks/#{@guid}/#{@repo_hook.id}",
              metadata: {
                repo_id: nil,
                installation_id: nil,
              },
            },
            {
              id: @repo_hook2.id,
              service: "web",
              configuration: { needs_public_key_signature: false },
              headers: [],
              data: { "url" => "http://example.com/anotherendpoint", "insecure_ssl" => "0" },
              callback_url: "#{GitHub.api_url}/hooks/#{@guid}/#{@repo_hook2.id}",
              metadata: {
                repo_id: nil,
                installation_id: nil,
              },
            },
          ],
        }
        Hook::DeliverySystem.post_payload_to_hookshot(mock_payload)

        expected_tags = [
          "event:hook/delivery_system_test_created",
          "event_type:hook/delivery_system_test",
          "queue:none"
        ]
        metrics = GitHub.dogstats.counts("hooks.delivered_to_queue.per_hook.count", tags: expected_tags)
        assert_equal 1, metrics.count
        assert_equal 2, metrics[0].value
      end

      test "records metrics on payloads that are too large" do
        GitHub::Aqueduct.stubs(:is_payload_size_large?).returns(true)
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
        GitHub.stubs(:hookshot_payload_size_limit).returns(1)

        @delivery_system.deliver

        # there should be a metric for each hook that was rejected not just each delivery
        assert_equal 5, GitHub.dogstats.distributions("hooks.hookshot_payload.payload_too_large").count
      end

      test "records metrics for payload size" do
        GitHub::Aqueduct.stubs(:is_payload_size_large?).returns(true)
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        @delivery_system.deliver

        assert_equal 4, GitHub.dogstats.distributions("hooks.hookshot_payload.payload_size").count
      end

      test "logs large payload metadata to splunk" do
        enable_feature_flag(:webhooks_log_large_payloads)
        logs = []
        msgs = []
        GitHub::Aqueduct.stubs(:is_payload_size_large?).returns(true)
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
        GitHub::logger.expects(:warn).with { |msg, log| logs << log; msgs << msg }.at_least_once

        @delivery_system.deliver
      end

      test "does not log large payload metadata to splunk" do
        disable_feature_flag(:webhooks_log_large_payloads)
        GitHub::Aqueduct.stubs(:is_payload_size_large?).returns(true)
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
        GitHub::logger.expects(:warn).never
        @delivery_system.deliver
      end
    end

    context "when payload is not too large" do
      test "triggers .enqueue_payload_to_hookshot for each payload and hook combination" do
        GitHub::Aqueduct.stubs(:is_payload_size_large?).returns(false)
        Hook::DeliverySystem.expects(:enqueue_payload_to_hookshot).times(5)
        @delivery_system.deliver
      end

      test "does not deliver hooks if all the hooks are muted" do
        rejected_policy = stub("RejectedOAP", satisfied?: false)
        OauthApplicationPolicy::Hook.stubs(:new).returns(rejected_policy)

        Hook::DeliverySystem.expects(:enqueue_payload_to_hookshot).never
        @delivery_system.deliver
      end

      test "records success in DD on a per trigger basis when delivered via queue" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        Hook::DeliverySystem.expects(:enqueue_payload_to_hookshot).times(5)

        @delivery_system.deliver

        expected_tags = [
          "event:hook/delivery_system_test_created",
          "event_type:hook/delivery_system_test",
          "status:success",
        ]

        assert_equal 1, GitHub.dogstats.increments("hooks.delivered_to_aqueduct.per_trigger.count", tags: expected_tags).count
      end

      test "records metrics in DD for hooks delivered to queue" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        @delivery_system.deliver

        expected_tags = [
          "event:hook/delivery_system_test_created",
          "event_type:hook/delivery_system_test",
          "queue:#{Hook::DeliverySystem::DELIVERY_QUEUE}",
          "aqueduct_app:hookshot-test"
        ]
        assert_equal 5, GitHub.dogstats.increments("hooks.delivered_to_queue.per_queue.count", tags: expected_tags).count
      end

      test "records hook metadata and event payload size" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        @delivery_system.deliver

        expected_tags = [
          "event:hook/delivery_system_test_created",
          "event_type:hook/delivery_system_test",
          "type:jit_hydrated",
          "site:DEFAULT_SITE",
        ]
        assert_equal 1, GitHub.dogstats.distributions("hooks.hook_metadata_size", tags: expected_tags).count
        assert_equal 1, GitHub.dogstats.distributions("hooks.event_payload_size", tags: expected_tags).count
      end

      test "records tenant context metrics in DD in multi-tenant mode when tenant set" do
        enable_feature_flag(:tenant_context_telemetry_webhooks_dd)

        business = create(:business)
        on_multi_tenant_enterprise(tenant: business) do
          GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

          @delivery_system.deliver

          expected_tags = [
            "event:hook/delivery_system_test_created",
            "event_type:hook/delivery_system_test",
            "aqueduct_app:hookshot-test",
            "queue:hookshot",
            "service:hookshot",
            "tenant_set:true",
            "query_scoping:enabled",
            "tenant_headers_present:true"
          ]
          assert_equal 5, GitHub.dogstats.increments("tenant_context.webhooks", tags: expected_tags).count
        end
      end

      test "records tenant context metrics in DD in multi-tenant mode when tenant not set" do
        enable_feature_flag(:tenant_context_telemetry_webhooks_dd)

        on_multi_tenant_enterprise do
          GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

          @delivery_system.deliver

          expected_tags = [
            "event:hook/delivery_system_test_created",
            "event_type:hook/delivery_system_test",
            "aqueduct_app:hookshot-test",
            "queue:hookshot",
            "service:hookshot",
            "tenant_set:false",
            "query_scoping:enabled",
            "tenant_headers_present:false"
          ]
          assert_equal 5, GitHub.dogstats.increments("tenant_context.webhooks", tags: expected_tags).count
        end
      end

      test "records metrics in DD for hooks delivered to queue using aqueduct_app hookshot-staging" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
        GitHub.expects(:dynamic_lab?).at_least_once.returns(true)

        @delivery_system.deliver

        expected_tags = [
          "event:hook/delivery_system_test_created",
          "event_type:hook/delivery_system_test",
          "queue:#{Hook::DeliverySystem::DELIVERY_QUEUE}",
          "aqueduct_app:hookshot-staging"
        ]
        assert_equal 5, GitHub.dogstats.increments("hooks.delivered_to_queue.per_queue.count", tags: expected_tags).count
      end

      test "skip recording latency metric in DD for hooks with invalid guid" do
        @payload_with_invalid_guid = {
            guid: "abc-123",
            event: "issues",
            parent: "organization-#{@org.id}",
            action: "created",
        }

        Failbot.expects(:report).with(instance_of(TypeError), app: "github-event-dispatch")

        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
        Hook::DeliverySystem.enqueue_payload_to_hookshot(@payload_with_invalid_guid)

        tags = [
          "event:hook/delivery_system_test_created",
          "event_type:hook/delivery_system_test",
          "service:#{Hook::DeliverySystem::HOOKSHOT_SERVICE}",
          "aqueduct_app:hookshot-test"
        ]
        assert_equal 0, GitHub.dogstats.distributions("hooks.webhook_latency", tags: tags).count
      end

      test "records latency metric in DD for hooks delivered to queue" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        @delivery_system.deliver

        expected_tags = [
          "event:hook/delivery_system_test_created",
          "event_type:hook/delivery_system_test",
          "service:#{Hook::DeliverySystem::HOOKSHOT_SERVICE}",
          "aqueduct_app:hookshot-test"
        ]

        assert_equal 5, GitHub.dogstats.distributions("hooks.webhook_latency", tags: expected_tags).count
      end

      test "records errors in DD on a per trigger basis and lets them continue to bubble up" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        Hook::DeliverySystem.expects(:enqueue_payload_to_hookshot).raises(Hookshot::PayloadTooLarge.new(nil, nil))

        assert_raises(Hookshot::PayloadTooLarge) do
          @delivery_system.deliver
        end

        expected_tags = [
          "event:hook/delivery_system_test_created",
          "event_type:hook/delivery_system_test",
          "status:failure",
          "exception_class:hookshot/payload_too_large",
        ]

        assert_equal 1, GitHub.dogstats.increments("hooks.delivered_to_aqueduct.per_trigger.count", tags: expected_tags).count
      end

      test "records metrics on payloads that are too large" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
        GitHub.stubs(:hookshot_payload_size_limit).returns(1)

        @delivery_system.deliver

        # there should be a metric for each hook that was rejected not just each delivery
        assert_equal 5, GitHub.dogstats.distributions("hooks.hookshot_payload.payload_too_large").count
      end

      test "records metrics for payload size" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
        @delivery_system.deliver

        assert_equal 4, GitHub.dogstats.distributions("hooks.hookshot_payload.payload_size").count
      end
    end

    context "instrumentation when in enterprise" do
      test "does not publish to hydro" do
        GitHub::Aqueduct.stubs(:is_payload_size_large?).returns(true)
        @delivery_system.deliver

        assert_hydro_messages(
          count: 0,
          schema: "github.webhooks.v0.DeliveryMetadata",
        )
      end
    end if GitHub.enterprise?

    context "instrumentation when not in enterprise", skip_enterprise: true do
      test "publishes a hydro event" do
        request_id = "test-request-id"
        GitHub.context.push(request_id: request_id)

        oauth_app = build :oauth_application, user: @org
        @org_hook.oauth_application = oauth_app
        @event.target_organization = @org

        @delivery_system.deliver

        assert_hydro_published({
          delivery_guid: @guid,
          delivery_type: :HOOKSHOT,
          hook_id: @org_hook.id,
          hook_url: @org_hook.config["url"],
          hook_event: "delivery_system_test",
          hook_action: "created",
          hook_actor: Hydro::EntitySerializer.user(@event.actor),
          hook_installation_target_type: :USER,
          hook_installation_target_id: @org.id,
          hook_creator: Hydro::EntitySerializer.user(@org_hook.creator),
          hook_oauth_application: Hydro::EntitySerializer.app(oauth_app),
          hook_payload_bytes: @org_with_org_payload.to_json.bytesize,
          hook_target_repository: nil,
          hook_target_organization: Hydro::EntitySerializer.organization(@org),
          hook_integration_installation_id: nil,
          github_request_id: request_id
        }, schema: "github.webhooks.v0.DeliveryMetadata")
      end

      test "publishes a hydro event with integration installation id" do
        event = Hook::Event::DeliverySystemTestEvent.new action: "created",
          hooks: [@integration_hook],
          triggered_at: @triggered_at,
          target_organization: @org
        delivery_system = Hook::DeliverySystem.new event
        delivery_system.deliver

        assert_hydro_published({
          delivery_guid: @guid,
          delivery_type: :HOOKSHOT,
          hook_id: @integration_hook.id,
          hook_url: @integration_hook.config["url"],
          hook_event: "delivery_system_test",
          hook_action: "created",
          hook_actor: Hydro::EntitySerializer.user(@event.actor),
          hook_installation_target_type: :INTEGRATION,
          hook_installation_target_id: @integration.id,
          hook_creator: Hydro::EntitySerializer.user(@integration_hook.creator),
          hook_oauth_application: nil,
          hook_payload_bytes: @integration_with_installation_payload.to_json.bytesize,
          hook_target_repository: nil,
          hook_target_organization: Hydro::EntitySerializer.organization(@org),
          hook_integration_installation_id: @installation.id,
        }, schema: "github.webhooks.v0.DeliveryMetadata")
      end

      test "publishes a hydro event for each hook" do
        @delivery_system.deliver

        assert_hydro_messages(
          count: @event.hooks.count,
          schema: "github.webhooks.v0.DeliveryMetadata",
        )
      end

      test "publishes a hydro event with HOOKSHOT delivery_type and target repository and records counter metric" do
        event = Hook::Event::DeliverySystemTestEvent.new action: "created",
          hooks: [@repo_hook],
          triggered_at: @triggered_at,
          target_repository: @repo
        delivery_system = Hook::DeliverySystem.new event

        delivery_system.deliver

        assert_hydro_published({
          delivery_guid: @guid,
          delivery_type: :HOOKSHOT,
          hook_id: @repo_hook.id,
          hook_url: @repo_hook.config["url"],
          hook_event: "delivery_system_test",
          hook_action: "created",
          hook_actor: Hydro::EntitySerializer.user(event.actor),
          hook_installation_target_type: :REPOSITORY,
          hook_installation_target_id: @repo.id,
          hook_creator: Hydro::EntitySerializer.user(@repo_hook.creator),
          hook_oauth_application: nil,
          hook_payload_bytes: @repo_with_repo_payload.to_json.bytesize,
          hook_target_repository: Hydro::EntitySerializer.repository(@repo),
          hook_target_organization: nil,
          hook_integration_installation_id: nil,
        }, schema: "github.webhooks.v0.DeliveryMetadata")

        assert_equal 1, GitHub.dogstats.increments("hooks.on_hookworker_entry.count", tags: ["queue:hookshot", "service:hookshot"]).count
        assert_equal 0, GitHub.dogstats.increments("hooks.on_hookworker_entry.count", tags: ["queue:webhooks"]).count
        assert_equal 0, GitHub.dogstats.increments("hooks.on_hookworker_entry.count", tags: ["queue:webhook-slack"]).count
      end

      test "publishes event with ACTIONS delivery_type and records counter metric for Actions Integration" do
        PrivilegedAppHelper.reconfigure_privileged_app(app_alias: :actions, app: @integration)

        GitHub.stubs(:launch_github_app).returns(@integration)
        event = Hook::Event::DeliverySystemTestEvent.new action: "created",
          hooks: [@integration_hook],
          triggered_at: @triggered_at,
          target_organization: @org
        delivery_system = Hook::DeliverySystem.new event

        delivery_system.deliver

        assert_hydro_published({
          delivery_guid: @guid,
          delivery_type: :ACTIONS,
          hook_id: @integration.hook.id,
          hook_url: @integration_hook.config["url"],
          hook_event: "delivery_system_test",
          hook_action: "created",
          hook_actor: Hydro::EntitySerializer.user(@event.actor),
          hook_installation_target_type: :INTEGRATION,
          hook_installation_target_id: @integration.id,
          hook_creator: Hydro::EntitySerializer.user(@integration_hook.creator),
          hook_oauth_application: nil,
          hook_payload_bytes: @integration_with_installation_payload.to_json.bytesize,
          hook_target_repository: nil,
          hook_target_organization: Hydro::EntitySerializer.organization(@org),
          hook_integration_installation_id: @installation.id,
        }, schema: "github.webhooks.v0.DeliveryMetadata")

        assert_equal 1, GitHub.dogstats.increments("hooks.on_hookworker_entry.count", tags: ["queue:webhooks", "service:actions"]).count
        assert_equal 0, GitHub.dogstats.increments("hooks.on_hookworker_entry.count", tags: ["queue:webhook-slack"]).count
        assert_equal 0, GitHub.dogstats.increments("hooks.on_hookworker_entry.count", tags: ["queue:hookshot"]).count
      end

      test "publishes event with CHATOPS delivery_type and records counter metric for ChatOps Integrations" do
        PrivilegedAppHelper.reconfigure_privileged_app(app_alias: :slack, app: @integration)

        GitHub.stubs(:slack_github_app).returns(@integration)
        event = Hook::Event::DeliverySystemTestEvent.new action: "created",
          hooks: [@integration_hook],
          triggered_at: @triggered_at,
          target_organization: @org
        delivery_system = Hook::DeliverySystem.new event

        delivery_system.deliver

        assert_hydro_published({
          delivery_guid: @guid,
          delivery_type: :CHATOPS,
          hook_id: @integration.hook.id,
          hook_url: @integration_hook.config["url"],
          hook_event: "delivery_system_test",
          hook_action: "created",
          hook_actor: Hydro::EntitySerializer.user(@event.actor),
          hook_installation_target_type: :INTEGRATION,
          hook_installation_target_id: @integration.id,
          hook_creator: Hydro::EntitySerializer.user(@integration_hook.creator),
          hook_oauth_application: nil,
          hook_payload_bytes: @integration_with_installation_payload.to_json.bytesize,
          hook_target_repository: nil,
          hook_target_organization: Hydro::EntitySerializer.organization(@org),
          hook_integration_installation_id: @installation.id,
        }, schema: "github.webhooks.v0.DeliveryMetadata")

        assert_equal 1, GitHub.dogstats.increments("hooks.on_hookworker_entry.count", tags: ["queue:webhook-slack", "service:chatops"]).count
        assert_equal 0, GitHub.dogstats.increments("hooks.on_hookworker_entry.count", tags: ["queue:webhooks"]).count
        assert_equal 0, GitHub.dogstats.increments("hooks.on_hookworker_entry.count", tags: ["queue:hookshot"]).count
      end

      test "strips sensitive data from hook url in hydro" do
        sensitive_url = "https://username:password@www.sensitive.com/path?token=secret"
        safe_url = "https://www.sensitive.com/path"
        @org_hook.config["url"] = sensitive_url
        @org_payload[:hooks].first[:data]["url"] = sensitive_url

        @delivery_system.deliver

        assert_hydro_published({
          delivery_guid: @guid,
          delivery_type: :HOOKSHOT,
          hook_id: @org_hook.id,
          hook_url: safe_url,
          hook_event: "delivery_system_test",
          hook_action: "created",
          hook_actor: Hydro::EntitySerializer.user(@event.actor),
          hook_installation_target_type: :USER,
          hook_installation_target_id: @org.id,
          hook_creator: Hydro::EntitySerializer.user(@org_hook.creator),
          hook_oauth_application: nil,
          hook_payload_bytes: @org_payload.to_json.bytesize,
        }, schema: "github.webhooks.v0.DeliveryMetadata")
      end

      test "falls back to empty url in hydro when hook url is invalid" do
        invalid_url = '\invalid.com'
        @org_hook.config["url"] = invalid_url
        @org_payload[:hooks].first[:data]["url"] = invalid_url

        @delivery_system.deliver

        assert_hydro_published({
          delivery_guid: @guid,
          delivery_type: :HOOKSHOT,
          hook_id: @org_hook.id,
          hook_url: "",
          hook_event: "delivery_system_test",
          hook_action: "created",
          hook_actor: Hydro::EntitySerializer.user(@event.actor),
          hook_installation_target_type: :USER,
          hook_installation_target_id: @org.id,
          hook_creator: Hydro::EntitySerializer.user(@org_hook.creator),
          hook_oauth_application: nil,
          hook_payload_bytes: @org_payload.to_json.bytesize,
        }, schema: "github.webhooks.v0.DeliveryMetadata")
      end
    end
  end

  context "#generate_hookshot_payloads" do
    test "generates each delivery's payload" do
      @delivery_system.generate_hookshot_payloads
      payloads = @delivery_system.payloads

      assert_equal 4, payloads.size

      assert_includes payloads, @org_payload
      assert_includes payloads, @v3_repo_payload
      assert_includes payloads, @repo_with_content_type_payload
      assert_includes payloads, @integration_payload
    end

    test "handles payload too large exception when payload exceeds max size limit" do
      exception = Hook::DeliverySystem::PayloadTooLarge
      @delivery_system.stubs(:hookshot_payload).raises(exception)
      logs = []
      GitHub::logger.expects(:error).with { |e| logs << e }.at_least_once
      @delivery_system.generate_hookshot_payloads
      logs.each do |x|
        assert x[:exception].is_a?(Hook::DeliverySystem::PayloadTooLarge)
      end

    end

    test "inserts installation hash for deliveries to a hook with a single subscribed installation" do
      event = Hook::Event::DeliverySystemTestEvent.new action: "created",
        hooks: [@org_hook, @integration_hook],
        triggered_at: @triggered_at,
        target_organization: @org
      @delivery_system = Hook::DeliverySystem.new event

      @delivery_system.generate_hookshot_payloads
      payloads = @delivery_system.payloads

      assert_equal 2, payloads.size

      assert_includes payloads, @org_with_org_payload
      assert_includes payloads, @integration_with_installation_payload
    end

    test "inserts installation hash for deliveries to a hook with a single subscribed installation with enterprise_managed_org", skip_enterprise: true do
      @admin = create(:emu, :owner)
      @enterprise = @admin.enterprise_managed_business
      @enterprised_managed_org = create(:organization, :enterprise_managed_organization, business: @enterprise)
      enterprised_managed_org_hook = create :hook, :org, installation_target: @enterprised_managed_org, config: { url: "http://example.com/endpoint" }

      enterprise_with_enterprise_payload = {
        parent: "organization-#{@enterprised_managed_org.id}",
        guid: @guid,
        event: "delivery_system_test",
        payload: {
          action: "created",
          organization: {
            login: @enterprised_managed_org.login,
            id: @enterprised_managed_org.id,
            node_id: @enterprised_managed_org.global_relay_id,
            url: "#{GitHub.api_url}/orgs/#{@enterprised_managed_org}",
            repos_url: "#{GitHub.api_url}/orgs/#{@enterprised_managed_org}/repos",
            events_url: "#{GitHub.api_url}/orgs/#{@enterprised_managed_org}/events",
            hooks_url: "#{GitHub.api_url}/orgs/#{@enterprised_managed_org}/hooks",
            issues_url: "#{GitHub.api_url}/orgs/#{@enterprised_managed_org}/issues",
            members_url: "#{GitHub.api_url}/orgs/#{@enterprised_managed_org}/members{/member}",
            public_members_url: "#{GitHub.api_url}/orgs/#{@enterprised_managed_org}/public_members{/member}",
            avatar_url: "#{GitHub.alambic_avatar_url}/u/#{@enterprised_managed_org.id}?#{@avatar_query_params.to_query}",
            description: nil,
          },
          enterprise: {
              id: @enterprised_managed_org.business.id,
              slug: @enterprise.slug,
              name: @enterprised_managed_org.business.name,
              node_id: @enterprise.global_relay_id,
              avatar_url: "#{GitHub.alambic_avatar_url}/b/#{@enterprised_managed_org.business.id}?#{@avatar_query_params.to_query}",
              description: nil,
              website_url: nil,
              html_url: "#{GitHub.url}/enterprises/#{@enterprised_managed_org.business}",
              created_at: @enterprised_managed_org.business.created_at.to_fs(:iso8601),
              updated_at: @enterprised_managed_org.business.updated_at.to_fs(:iso8601),
          },
        },
        pricing_plan: @enterprise.plan.name,
        events_v2_validation_enabled: false,
        delivery_rate_limit_key: "Enterprise:#{@enterprised_managed_org.business.id}",
        hooks: [
          {
            id: enterprised_managed_org_hook.id,
            service: "web",
            configuration: { needs_public_key_signature: false },
            headers: [],
            data: { "url" => "http://example.com/endpoint", "insecure_ssl" => "0" },
            callback_url: "#{GitHub.api_url}/hooks/#{@guid}/#{enterprised_managed_org_hook.id}",
            metadata: {
              repo_id: nil,
              installation_id: nil,
            },
          },
        ],
      }
      event = Hook::Event::DeliverySystemTestEvent.new action: "created",
        hooks: [enterprised_managed_org_hook],
        triggered_at: @triggered_at,
        target_organization: @enterprised_managed_org
      @delivery_system = Hook::DeliverySystem.new event

      @delivery_system.generate_hookshot_payloads
      payloads = @delivery_system.payloads

      assert_equal 1, payloads.size

      assert_includes payloads, enterprise_with_enterprise_payload
    end

    test "only one read per role is performed when reading installations" do
      enable_feature_flag(:installation_specifics_for_fallback)

      # This is the case when reading from both: replica/primary fails
      IntegrationInstallation.destroy_all

      event = Hook::Event::DeliverySystemTestEvent.new action: "created",
        hooks: [@org_hook, @integration_hook],
        triggered_at: @triggered_at,
        target_organization: @org

      @delivery_system = Hook::DeliverySystem.new event

      @delivery_system.generate_hookshot_payloads
      payloads = @delivery_system.payloads

      assert_equal 2, payloads.size
      assert_includes payloads, @org_with_org_payload
      integration_without_installation_payload = @integration_with_installation_payload.dup
      # remove installation expected fields because there are no installations!
      integration_without_installation_payload[:payload].delete(:installation)
      integration_without_installation_payload[:hooks].first[:metadata][:installation_id] = nil
      assert_includes payloads, integration_without_installation_payload

      expected_tags = ["installations:none", "role:writing"]
      assert_dogstats_increment(1, "hooks.subscribed_installations", tags: expected_tags)
    end

    test "falls back to primary to read installations" do
      enable_feature_flag(:installation_specifics_for_fallback)

      # This is the case when reading from replica fails but reading
      # from primary returns the installation. aka false/negative
      event = Hook::Event::DeliverySystemTestEvent.new action: "created",
        hooks: [@org_hook, @integration_hook],
        triggered_at: @triggered_at,
        target_organization: @org
      @delivery_system = Hook::DeliverySystem.new event

      @delivery_system.expects(:read_subscribed_installation).
        with(:reading, @installation.integration_id.to_s, event).
        returns(nil)

      @delivery_system.expects(:read_subscribed_installation).
        with(:writing, @installation.integration_id.to_s, event).
        returns(@installation)

      @delivery_system.generate_hookshot_payloads
      payloads = @delivery_system.payloads

      assert_equal 2, payloads.size
      assert_includes payloads, @org_with_org_payload
      assert_includes payloads, @integration_with_installation_payload
      expected_tags = ["installations:present", "role:writing"]
      not_expected_tags = ["role:reading"]
      assert_dogstats_increment(1, "hooks.subscribed_installations", tags: expected_tags)
      assert_dogstats_increment(0, "hooks.subscribed_installations", tags: not_expected_tags)
    end

    test "reads installations from replicas by default" do
      enable_feature_flag(:installation_specifics_for_fallback)

      # The happy case. Most installations will be just readable from a replica.
      event = Hook::Event::DeliverySystemTestEvent.new action: "created",
        hooks: [@org_hook, @integration_hook],
        triggered_at: @triggered_at,
        target_organization: @org
      @delivery_system = Hook::DeliverySystem.new event

      @delivery_system.generate_hookshot_payloads
      payloads = @delivery_system.payloads

      assert_equal 2, payloads.size
      assert_includes payloads, @org_with_org_payload
      assert_includes payloads, @integration_with_installation_payload
      expected_tags = ["installations:present", "role:reading"]
      assert_dogstats_increment(1, "hooks.subscribed_installations", tags: expected_tags)
    end

    test "it doesn't fall back to primary to read installations when the flipper is disabled" do
      disable_feature_flag(:installation_specifics_for_fallback)
      IntegrationInstallation.destroy_all

      event = Hook::Event::DeliverySystemTestEvent.new action: "created",
        hooks: [@org_hook, @integration_hook],
        triggered_at: @triggered_at,
        target_organization: @org
      @delivery_system = Hook::DeliverySystem.new event

      @delivery_system.generate_hookshot_payloads
      payloads = @delivery_system.payloads

      assert_equal 2, payloads.size
      assert_includes payloads, @org_with_org_payload
      integration_without_installation_payload = @integration_with_installation_payload.dup
      # remove installation expected fields because there are no installations!
      integration_without_installation_payload[:payload].delete(:installation)
      integration_without_installation_payload[:hooks].first[:metadata][:installation_id] = nil
      assert_includes payloads, integration_without_installation_payload

      expected_tags = ["installations:none", "role:reading"]
      assert_dogstats_increment(1, "hooks.subscribed_installations", tags: expected_tags)
    end

    test "inserts custom headers if the event has some" do
      event = Hook::Event::DeliverySystemTestEvent.new action: "created",
        hooks: [@integration_hook],
        include_per_hook_headers: true,
        triggered_at: @triggered_at,
        target_organization: @org
      @delivery_system = Hook::DeliverySystem.new event

      @delivery_system.generate_hookshot_payloads
      payloads = @delivery_system.payloads

      assert_equal 1, payloads.size

      assert_includes payloads, @integration_with_installation_and_custom_headers_payload
      payloads.each do |payload|
        payload[:hooks].each do |hook|
          assert_equal 1, hook[:headers].count
          assert_includes hook[:headers].first.keys, "X-Example"
          refute_includes hook[:headers].first.keys, "X-GitHub-Tenant"
          refute_includes hook[:headers].first.keys, "X-GitHub-Tenant-ID"
        end
      end
    end

    test "inserts X-GitHub-Tenant headers when enabled" do
      business = create(:business)
      on_multi_tenant_enterprise(tenant: business) do
        event = Hook::Event::DeliverySystemTestEvent.new action: "created",
          hooks: [@integration_hook],
          include_per_hook_headers: true,
          triggered_at: @triggered_at,
          target_organization: @org
        @delivery_system = Hook::DeliverySystem.new event
        @delivery_system.generate_hookshot_payloads
        payloads = @delivery_system.payloads

        refute payloads.empty?
        payloads.each do |payload|
          payload[:hooks].each do |hook|
            assert_includes hook[:headers], { "X-GitHub-Tenant" => "#{business.slug}" }
            assert_includes hook[:headers], { "X-GitHub-Tenant-ID" => "#{business.id}" }
          end
        end
      end
    end

    test "sets interpolated hook url to payload when FF enabled" do
      app = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: true }, options: { owner: @org })
      hook = create :hook, installation_target: app
      hook.url = "https://{hostname}/callback"

      expected_payload = {
        parent: "integration-#{app.id}",
        guid: @guid,
        event: "delivery_system_test",
        payload: {
          action: "created",
          organization: {
            login: @org.login,
            id: @org.id,
            node_id: @org.global_relay_id,
            url: "#{GitHub.api_url}/orgs/#{@org}",
            repos_url: "#{GitHub.api_url}/orgs/#{@org}/repos",
            events_url: "#{GitHub.api_url}/orgs/#{@org}/events",
            hooks_url: "#{GitHub.api_url}/orgs/#{@org}/hooks",
            issues_url: "#{GitHub.api_url}/orgs/#{@org}/issues",
            members_url: "#{GitHub.api_url}/orgs/#{@org}/members{/member}",
            public_members_url: "#{GitHub.api_url}/orgs/#{@org}/public_members{/member}",
            avatar_url: "#{GitHub.alambic_avatar_url}/u/#{@org.id}?#{@avatar_query_params.to_query}",
            description: nil,
          }
        },
        pricing_plan: @org.plan.name,
        events_v2_validation_enabled: false,
        delivery_rate_limit_key: "Organization:#{@org.id}",
          hooks: [
          {
            id: hook.id,
            service: "web",
            configuration: { needs_public_key_signature: false },
            headers: [],
            data: { "url" => "#{GitHub.url}/callback", "content_type" => "json", "insecure_ssl" => "0" },
            callback_url: "#{GitHub.api_url}/hooks/#{@guid}/#{hook.id}",
            metadata: {
              repo_id: nil,
              installation_id: nil,
            },
          },
        ],
      }
      event = Hook::Event::DeliverySystemTestEvent.new action: "created",
        hooks: [hook],
        triggered_at: @triggered_at,
        target_organization: @org
      @delivery_system = Hook::DeliverySystem.new event

      enable_feature_flag(:tenant_scoped_config_url)
      @delivery_system.generate_hookshot_payloads
      payloads = @delivery_system.payloads

      assert_equal 1, payloads.size
      assert_includes payloads, expected_payload

      expected_tags = [
        "events_v2_validation_enabled:false"
      ]

      assert_equal 1, GitHub.dogstats.distributions("hooks.time", tags: expected_tags).count
    end

    test "sets events_v2_validation_enabled to true" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      app = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: true }, options: { owner: @org })
      hook = create :hook, installation_target: app
      hook.url = "https://{hostname}/callback"

      expected_payload = {
        parent: "integration-#{app.id}",
        guid: @guid,
        event: "delivery_system_test",
        payload: {
          action: "created",
          organization: {
            login: @org.login,
            id: @org.id,
            node_id: @org.global_relay_id,
            url: "#{GitHub.api_url}/orgs/#{@org}",
            repos_url: "#{GitHub.api_url}/orgs/#{@org}/repos",
            events_url: "#{GitHub.api_url}/orgs/#{@org}/events",
            hooks_url: "#{GitHub.api_url}/orgs/#{@org}/hooks",
            issues_url: "#{GitHub.api_url}/orgs/#{@org}/issues",
            members_url: "#{GitHub.api_url}/orgs/#{@org}/members{/member}",
            public_members_url: "#{GitHub.api_url}/orgs/#{@org}/public_members{/member}",
            avatar_url: "#{GitHub.alambic_avatar_url}/u/#{@org.id}?#{@avatar_query_params.to_query}",
            description: nil,
          }
        },
        pricing_plan: @org.plan.name,
        events_v2_validation_enabled: true,
        delivery_rate_limit_key: "Organization:#{@org.id}",
          hooks: [
          {
            id: hook.id,
            service: "web",
            configuration: { needs_public_key_signature: false },
            headers: [],
            data: { "url" => "#{GitHub.url}/callback", "content_type" => "json", "insecure_ssl" => "0" },
            callback_url: "#{GitHub.api_url}/hooks/#{@guid}/#{hook.id}",
            metadata: {
              repo_id: nil,
              installation_id: nil,
            },
          },
        ],
      }
      event = Hook::Event::DeliverySystemTestEvent.new action: "created",
        hooks: [hook],
        triggered_at: @triggered_at,
        target_organization: @org,
        flags: { events_v2_validation_enabled: true }
      @delivery_system = Hook::DeliverySystem.new event

      enable_feature_flag(:tenant_scoped_config_url)
      @delivery_system.generate_hookshot_payloads
      payloads = @delivery_system.payloads

      assert_equal 1, payloads.size
      assert_includes payloads, expected_payload

      expected_tags = [
        "events_v2_validation_enabled:true"
      ]

      assert_equal 1, GitHub.dogstats.distributions("hooks.time", tags: expected_tags).count
    end

    test "filters out hookshot deliveries with hookshot_deliveries_enabled set to false when events_v2_run_monolith_hookshot_filter_logic and events_v2_discard_hookshot_deliveries are enabled" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      @actions_repo.enable_actions_app(entry_point: :test_case)

      @actions_repo.default_branch_ref.append_commit({ committer: @actions_repo.owner, message: "Updating test workflow" }, @actions_repo.owner) do |files|
        files.add(".github/workflows/test.yml", "name: Test\non: [push,status,workflow_dispatch]") # includes status trigger
      end

      @chatops_installation = make_integration_installation(
        integration: @chatops_app,
        target: @org,
        permissions: { "metadata" => :read, "contents" => :read },
      )

      event = Hook::Event::StatusEvent.new status: create(:status, repository: @actions_repo), flags: { events_v2_validation_enabled: false, hookshot_deliveries_enabled: false }
      hook = create :hook, installation_target: @actions_repo, events: ["status"], url: "http://example.com"

      actor = Events::ParentAsActor.new(hook.hookshot_parent_id)
      enable_feature_flag(:events_v2_run_monolith_hookshot_filter_logic)
      enable_feature_flag(:events_v2_discard_hookshot_deliveries, actor)

      @delivery_system = Hook::DeliverySystem.new event

      @delivery_system.generate_hookshot_payloads
      payloads = @delivery_system.payloads

      # Actions and Chatops deliveries should still exist.
      assert_equal 2, payloads.size
      assert_equal "integration-#{@actions_app.id}", payloads[0][:parent]
      assert_equal "integration-#{@chatops_app.id}", payloads[1][:parent]

      expected_tags = [
        "event_type:status",
        "event_action:",
        "discarded:true"
      ]
      assert_equal 1, GitHub.dogstats.increments("hooks.discarded_events_v2_hooks", tags: expected_tags).count

      assert_hydro_published_partial({
        guid: event.guid,
        delivery_type: :HOOKSHOT,
        event_type: "status",
        event_action: "",
        dropped_reason: :EVENTS_V2_DELIVERY,
        hook_id: hook.id,
        target_repository_id: @actions_repo.id,
        target_organization_id: @actions_repo.owner.id,
        request_id: GitHub.context[:request_id],
        triggered_at: event.triggered_at,
        parent: hook.hookshot_parent_id
      }, schema: "github.webhooks.v0.DroppedDeliveryMetadata")
    end

    test "does not filter out hookshot deliveries with hookshot_deliveries_enabled set to true when events_v2_run_monolith_hookshot_filter_logic and events_v2_discard_hookshot_deliveries are enabled" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      @actions_repo.enable_actions_app(entry_point: :test_case)

      @actions_repo.default_branch_ref.append_commit({ committer: @actions_repo.owner, message: "Updating test workflow" }, @actions_repo.owner) do |files|
        files.add(".github/workflows/test.yml", "name: Test\non: [push,status,workflow_dispatch]") # includes status trigger
      end

      @chatops_installation = make_integration_installation(
        integration: @chatops_app,
        target: @org,
        permissions: { "metadata" => :read, "contents" => :read },
      )

      event = Hook::Event::StatusEvent.new status: create(:status, repository: @actions_repo), flags: { events_v2_validation_enabled: false, hookshot_deliveries_enabled: true }
      hook = create :hook, installation_target: @actions_repo, events: ["status"], url: "http://example.com"

      actor = Events::ParentAsActor.new(hook.hookshot_parent_id)
      enable_feature_flag(:events_v2_run_monolith_hookshot_filter_logic)
      enable_feature_flag(:events_v2_discard_hookshot_deliveries, actor)

      @delivery_system = Hook::DeliverySystem.new event

      @delivery_system.generate_hookshot_payloads
      payloads = @delivery_system.payloads

      # Hookshot, Actions, and Chatops deliveries should all still exist.
      assert_equal 3, payloads.size
      assert_equal "repository-#{@actions_repo.id}", payloads[0][:parent]
      assert_equal "integration-#{@actions_app.id}", payloads[1][:parent]
      assert_equal "integration-#{@chatops_app.id}", payloads[2][:parent]

      assert_hydro_messages(
        count: 0,
        schema: "github.webhooks.v0.DroppedDeliveryMetadata",
      )
    end

    test "does not filter out hookshot deliveries with hookshot_deliveries_enabled set to false when events_v2_run_monolith_hookshot_filter_logic is enabled but events_v2_discard_hookshot_deliveries is disabled" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      @actions_repo.enable_actions_app(entry_point: :test_case)

      @actions_repo.default_branch_ref.append_commit({ committer: @actions_repo.owner, message: "Updating test workflow" }, @actions_repo.owner) do |files|
        files.add(".github/workflows/test.yml", "name: Test\non: [push,status,workflow_dispatch]") # includes status trigger
      end

      @chatops_installation = make_integration_installation(
        integration: @chatops_app,
        target: @org,
        permissions: { "metadata" => :read, "contents" => :read },
      )

      event = Hook::Event::StatusEvent.new status: create(:status, repository: @actions_repo), flags: { events_v2_validation_enabled: false, hookshot_deliveries_enabled: false }
      hook = create :hook, installation_target: @actions_repo, events: ["status"], url: "http://example.com"

      actor = Events::ParentAsActor.new(hook.hookshot_parent_id)
      enable_feature_flag(:events_v2_run_monolith_hookshot_filter_logic)
      disable_feature_flag(:events_v2_discard_hookshot_deliveries, actor)

      @delivery_system = Hook::DeliverySystem.new event

      @delivery_system.generate_hookshot_payloads
      payloads = @delivery_system.payloads

      # Hookshot, Actions, and Chatops deliveries should all still exist.
      assert_equal 3, payloads.size
      assert_equal "repository-#{@actions_repo.id}", payloads[0][:parent]
      assert_equal "integration-#{@actions_app.id}", payloads[1][:parent]
      assert_equal "integration-#{@chatops_app.id}", payloads[2][:parent]

      expected_tags = [
        "event_type:status",
        "event_action:",
        "discarded:false"
      ]
      assert_equal 1, GitHub.dogstats.increments("hooks.discarded_events_v2_hooks", tags: expected_tags).count

      assert_hydro_messages(
        count: 0,
        schema: "github.webhooks.v0.DroppedDeliveryMetadata",
      )
    end

    test "does not filter out hookshot deliveries with hookshot_deliveries_enabled set to false when events_v2_run_monolith_hookshot_filter_logic and events_v2_discard_hookshot_deliveries are disabled" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      @actions_repo.enable_actions_app(entry_point: :test_case)

      @actions_repo.default_branch_ref.append_commit({ committer: @actions_repo.owner, message: "Updating test workflow" }, @actions_repo.owner) do |files|
        files.add(".github/workflows/test.yml", "name: Test\non: [push,status,workflow_dispatch]") # includes status trigger
      end

      @chatops_installation = make_integration_installation(
        integration: @chatops_app,
        target: @org,
        permissions: { "metadata" => :read, "contents" => :read },
      )

      event = Hook::Event::StatusEvent.new status: create(:status, repository: @actions_repo), flags: { events_v2_validation_enabled: false, hookshot_deliveries_enabled: false }
      hook = create :hook, installation_target: @actions_repo, events: ["status"], url: "http://example.com"

      actor = Events::ParentAsActor.new(hook.hookshot_parent_id)
      disable_feature_flag(:events_v2_run_monolith_hookshot_filter_logic)
      disable_feature_flag(:events_v2_discard_hookshot_deliveries, actor)

      @delivery_system = Hook::DeliverySystem.new event

      @delivery_system.generate_hookshot_payloads
      payloads = @delivery_system.payloads

      # Hookshot, Actions, and Chatops deliveries should all still exist.
      assert_equal 3, payloads.size
      assert_equal "repository-#{@actions_repo.id}", payloads[0][:parent]
      assert_equal "integration-#{@actions_app.id}", payloads[1][:parent]
      assert_equal "integration-#{@chatops_app.id}", payloads[2][:parent]

      expected_tags = [
        "event_type:status",
        "event_action:"
      ]
      assert_equal 0, GitHub.dogstats.increments("hooks.discarded_events_v2_hooks", tags: expected_tags).count

      assert_hydro_messages(
        count: 0,
        schema: "github.webhooks.v0.DroppedDeliveryMetadata",
      )
    end

    test "does not set interpolated hook url to payload when FF enabled" do
      app = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: true }, options: { owner: @org })
      hook = create :hook, installation_target: app
      hook.url = "https://{hostname}/callback"

      expected_payload = {
        parent: "integration-#{app.id}",
        guid: @guid,
        event: "delivery_system_test",
        payload: {
          action: "created",
          organization: {
            login: @org.login,
            id: @org.id,
            node_id: @org.global_relay_id,
            url: "#{GitHub.api_url}/orgs/#{@org}",
            repos_url: "#{GitHub.api_url}/orgs/#{@org}/repos",
            events_url: "#{GitHub.api_url}/orgs/#{@org}/events",
            hooks_url: "#{GitHub.api_url}/orgs/#{@org}/hooks",
            issues_url: "#{GitHub.api_url}/orgs/#{@org}/issues",
            members_url: "#{GitHub.api_url}/orgs/#{@org}/members{/member}",
            public_members_url: "#{GitHub.api_url}/orgs/#{@org}/public_members{/member}",
            avatar_url: "#{GitHub.alambic_avatar_url}/u/#{@org.id}?#{@avatar_query_params.to_query}",
            description: nil,
          }
        },
        pricing_plan: @org.plan.name,
        delivery_rate_limit_key: "Organization:#{@org.id}",
          hooks: [
          {
            id: hook.id,
            service: "web",
            configuration: { needs_public_key_signature: false },
            headers: [],
            data: {
              "url" => "https://{hostname}/callback", # non-interpolated url
              "content_type" => "json",
              "insecure_ssl" => "0"
            },
            callback_url: "#{GitHub.api_url}/hooks/#{@guid}/#{hook.id}",
            metadata: {
              repo_id: nil,
              installation_id: nil,
            },
          },
        ],
      }
      event = Hook::Event::DeliverySystemTestEvent.new action: "created",
        hooks: [hook],
        triggered_at: @triggered_at,
        target_organization: @org
      @delivery_system = Hook::DeliverySystem.new event

      disable_feature_flag(:tenant_scoped_config_url)
    end
  end

  context "#enqueue_payload_to_hookshot - Internal App filtering" do
    test "uses the generic handler for internal apps with no aqueduct property" do
      integration = create(:integration)
      Apps::Privileged::Registry.reset_configuration!
      Apps::Privileged::Registry.configure(
        app: integration,
        app_alias: :some_integration,
        id: ->() { integration.id },
        properties: {}
      )

      parent = "integration-#{integration.id}"
      payload = @repo_with_repo_payload.merge({
        parent: parent,
      })

      mock_client = mock("GitHub::Aqueduct::Client")
      Hook::DeliverySystem.stubs(:aqueduct_client_for).returns(mock_client)
      mock_client.expects(:send_job).with(has_entries(queue: "hookshot"))
      Hook::DeliverySystem.enqueue_payload_to_hookshot(payload)
    end

    test "uses the generic handler for non-internal apps" do
      integration = create(:integration)
      parent = "integration-#{integration.id}"
      payload = @repo_with_repo_payload.merge({
        parent: parent,
      })

      mock_client = mock("GitHub::Aqueduct::Client")
      Hook::DeliverySystem.stubs(:aqueduct_client_for).returns(mock_client)
      mock_client.expects(:send_job).with(has_entries(queue: "hookshot"))
      Hook::DeliverySystem.enqueue_payload_to_hookshot(payload)
    end
  end

  context "#generate_hookshot_payloads - GitHub Actions filtering" do
    test "generates a status payload if the repo has a status trigger" do
      @actions_repo.enable_actions_app(entry_point: :test_case)

      @actions_repo.default_branch_ref.append_commit({ committer: @actions_repo.owner, message: "Updating test workflow" }, @actions_repo.owner) do |files|
        files.add(".github/workflows/test.yml", "name: Test\non: [push,status,workflow_dispatch]") # includes status trigger
      end

      event = Hook::Event::StatusEvent.new status: create(:status, repository: @actions_repo)
      delivery_system = Hook::DeliverySystem.new event

      delivery_system.generate_hookshot_payloads

      assert_equal 1, delivery_system.payloads.size # We only expect the payload for the @actions_app subscription
      payload = delivery_system.payloads.first

      assert_equal "integration-#{@actions_app.id}", payload[:parent]
      assert_equal @guid, payload[:guid]
      assert_equal "status", payload[:event]
      assert_equal 1, payload[:hooks].size
    end

    test "generates a status payload for lab if the repo has a status trigger" do
      make_integration_installation(integration: @actions_lab_app, repository: @actions_repo)

      @actions_repo.default_branch_ref.append_commit({ committer: @actions_repo.owner, message: "Updating test workflow" }, @actions_repo.owner) do |files|
        files.add(".github/workflows-lab/test.yml", "name: Test\non: [push,status,workflow_dispatch]") # includes status trigger
      end

      event = Hook::Event::StatusEvent.new status: create(:status, repository: @actions_repo)
      delivery_system = Hook::DeliverySystem.new event

      delivery_system.generate_hookshot_payloads

      assert_equal 1, delivery_system.payloads.size # We only expect the payload for the @actions_lab_app subscription
      payload = delivery_system.payloads.first

      assert_equal "integration-#{@actions_lab_app.id}", payload[:parent]
      assert_equal @guid, payload[:guid]
      assert_equal "status", payload[:event]
      assert_equal 1, payload[:hooks].size
    end

    test "generates a workflow_run payload if the repo has a workflow_run trigger" do
      @actions_repo.enable_actions_app(entry_point: :test_case)

      @actions_repo.default_branch_ref.append_commit({ committer: @actions_repo.owner, message: "Updating test workflow" }, @actions_repo.owner) do |files|
        files.add(".github/workflows/test.yml", "name: Test\non: [push,workflow_run]") # includes workflow_run trigger
      end

      event = Hook::Event::WorkflowRunEvent.new(run_id: @workflow_run.id, action: "completed")
      delivery_system = Hook::DeliverySystem.new event

      delivery_system.generate_hookshot_payloads

      assert_equal 1, delivery_system.payloads.size # We only expect the payload for the @actions_app subscription
      payload = delivery_system.payloads.first

      assert_equal "integration-#{@actions_app.id}", payload[:parent]
      assert_equal @guid, payload[:guid]
      assert_equal "workflow_run", payload[:event]
      assert_equal 1, payload[:hooks].size
    end

    test "drops the status payload if the repo doesn't have a status trigger" do
      @actions_repo.enable_actions_app(entry_point: :test_case)

      @actions_repo.default_branch_ref.append_commit({ committer: @actions_repo.owner, message: "Updating test workflow" }, @actions_repo.owner) do |files|
        files.add(".github/workflows/test.yml", "name: Test\non: [push]") # No status trigger
      end

      event = Hook::Event::StatusEvent.new status: create(:status, repository: @actions_repo)
      delivery_system = Hook::DeliverySystem.new event

      delivery_system.generate_hookshot_payloads

      assert delivery_system.payloads.none? # The @actions_app subscription should be filtered out, based on the event and the repo contents
    end

    test "drops the payload if the repo is locked for migration" do
      @actions_repo.enable_actions_app(entry_point: :test_case)
      @actions_repo.lock_for_migration

      @actions_repo.default_branch_ref.append_commit({ committer: @actions_repo.owner, message: "Updating test workflow" }, @actions_repo.owner) do |files|
        files.add(".github/workflows/test.yml", "name: Test\non: [push,workflow_run]") # includes workflow_run trigger
      end

      event = Hook::Event::WorkflowRunEvent.new(run_id: @workflow_run.id, action: "completed")
      delivery_system = Hook::DeliverySystem.new event

      delivery_system.generate_hookshot_payloads

      assert delivery_system.payloads.none? # The event payload is empty as this is filtered out as an importing repo.
    end

    test "drops the payload if the repo is importing" do
      @actions_repo.enable_actions_app(entry_point: :test_case)
      @actions_repo.importing_started!

      @actions_repo.default_branch_ref.append_commit({ committer: @actions_repo.owner, message: "Updating test workflow" }, @actions_repo.owner) do |files|
        files.add(".github/workflows/test.yml", "name: Test\non: [push,workflow_run]") # includes workflow_run trigger
      end

      event = Hook::Event::WorkflowRunEvent.new(run_id: @workflow_run.id, action: "completed")
      delivery_system = Hook::DeliverySystem.new event

      delivery_system.generate_hookshot_payloads

      assert delivery_system.payloads.none? # The event payload is empty as this is filtered out as an importing repo.
    end

    test "drops the issues payload a matching workflow trigger exists" do
      @actions_repo.enable_actions_app(entry_point: :test_case)

      @actions_repo.default_branch_ref.append_commit({ committer: @actions_repo.owner, message: "Updating test workflow" }, @actions_repo.owner) do |files|
        files.add(".github/workflows/test.yml", "name: Test\non: [issues]") # Issues trigger
      end

      issue = create(:issue, repository: @actions_repo, user: @actions_repo.owner)

      # lock after issue creation as this is disabled during migrations.
      @actions_repo.lock_for_migration
      event = Hook::Event::IssuesEvent.new(action: :created, issue_id: issue.id, actor_id: @actions_repo.owner.id)

      delivery_system = Hook::DeliverySystem.new event

      delivery_system.generate_hookshot_payloads

      assert delivery_system.payloads.none? # The event payload is empty as this is filtered out as an importing repo.
    end

    test "drops the lab status payload if the repo doesn't have a status trigger and both feature flags are set" do
      make_integration_installation(integration: @actions_lab_app, repository: @actions_repo)

      @actions_repo.default_branch_ref.append_commit({ committer: @actions_repo.owner, message: "Updating test workflow" }, @actions_repo.owner) do |files|
        files.add(".github/workflows-lab/test.yml", "name: Test\non: [push]") # No status trigger
      end

      event = Hook::Event::StatusEvent.new status: create(:status, repository: @actions_repo)
      delivery_system = Hook::DeliverySystem.new event

      delivery_system.generate_hookshot_payloads

      assert delivery_system.payloads.none? # The @actions_lab_app subscription should be filtered out, based on the event and the repo contents
    end

    test "drops the workflow_run payload if the repo doesn't have a workflow_run trigger" do
      @actions_repo.enable_actions_app(entry_point: :test_case)

      @actions_repo.default_branch_ref.append_commit({ committer: @actions_repo.owner, message: "Updating test workflow" }, @actions_repo.owner) do |files|
        files.add(".github/workflows/test.yml", "name: Test\non: [push]") # No workflow_run trigger
      end

      event = Hook::Event::WorkflowRunEvent.new(run_id: @workflow_run.id, action: "completed")
      delivery_system = Hook::DeliverySystem.new event

      delivery_system.generate_hookshot_payloads

      assert delivery_system.payloads.none? # The @actions_app subscription should be filtered out, based on the event and the repo contents
    end

    test "drops the status payload only for actions if there are other subscribers" do
      @actions_repo.enable_actions_app(entry_point: :test_case)

      @actions_repo.default_branch_ref.append_commit({ committer: @actions_repo.owner, message: "Updating test workflow" }, @actions_repo.owner) do |files|
        files.add(".github/workflows/test.yml", "name: Test\non: [push]") # No status trigger
      end

      another_integration = create :github_owned_integration, :with_active_hook, name: "Another Integration", default_permissions: { "statuses" => :write }, default_events: %w(status)
      another_integration.install_on(@org, repositories: [@actions_repo], installer: @org.admins.first, entry_point: :test_case)

      event = Hook::Event::StatusEvent.new status: create(:status, repository: @actions_repo)
      delivery_system = Hook::DeliverySystem.new event

      delivery_system.generate_hookshot_payloads

      assert_equal 1, delivery_system.payloads.size # We only expect the payload for the other integration
      payload = delivery_system.payloads.first

      assert_equal "integration-#{another_integration.id}", payload[:parent]
      assert_equal @guid, payload[:guid]
      assert_equal "status", payload[:event]
      assert_equal 1, payload[:hooks].size
    end

    test "drops the lab status payload only for actions if there are other subscribers" do
      make_integration_installation(integration: @actions_lab_app, repository: @actions_repo)

      @actions_repo.default_branch_ref.append_commit({ committer: @actions_repo.owner, message: "Updating test workflow" }, @actions_repo.owner) do |files|
        files.add(".github/workflows-lab/test.yml", "name: Test\non: [push]") # No status trigger
      end

      another_integration = create :github_owned_integration, :with_active_hook, name: "Another Integration", default_permissions: { "statuses" => :write }, default_events: %w(status)
      another_integration.install_on(@org, repositories: [@actions_repo], installer: @org.admins.first, entry_point: :test_case)

      event = Hook::Event::StatusEvent.new status: create(:status, repository: @actions_repo)
      delivery_system = Hook::DeliverySystem.new event

      delivery_system.generate_hookshot_payloads

      assert_equal 1, delivery_system.payloads.size # We only expect the payload for the other integration
      payload = delivery_system.payloads.first

      assert_equal "integration-#{another_integration.id}", payload[:parent]
      assert_equal @guid, payload[:guid]
      assert_equal "status", payload[:event]
      assert_equal 1, payload[:hooks].size
    end

    test "drops the workflow_run payload only for actions if there are other subscribers" do
      @actions_repo.enable_actions_app(entry_point: :test_case)

      @actions_repo.default_branch_ref.append_commit({ committer: @actions_repo.owner, message: "Updating test workflow" }, @actions_repo.owner) do |files|
        files.add(".github/workflows/test.yml", "name: Test\non: [push]") # No workflow_run trigger
      end

      another_integration = create :github_owned_integration, :with_active_hook, name: "Another Integration", default_permissions: { "actions" => :write }, default_events: %w(workflow_run)
      another_integration.install_on(@org, repositories: [@actions_repo], installer: @org.admins.first, entry_point: :test_case)

      event = Hook::Event::WorkflowRunEvent.new(run_id: @workflow_run.id, action: "completed")
      delivery_system = Hook::DeliverySystem.new event

      delivery_system.generate_hookshot_payloads

      assert_equal 1, delivery_system.payloads.size # We only expect the payload for the other integration
      payload = delivery_system.payloads.first

      assert_equal "integration-#{another_integration.id}", payload[:parent]
      assert_equal @guid, payload[:guid]
      assert_equal "workflow_run", payload[:event]
      assert_equal 1, payload[:hooks].size
    end

    test "generates a status payloads for lab only if the repo has a lab status trigger" do
      # Only the Lab Actions app is installed
      make_integration_installation(integration: @actions_lab_app, repository: @actions_repo)

      @actions_repo.default_branch_ref.append_commit({ committer: @actions_repo.owner, message: "Updating test workflow" }, @actions_repo.owner) do |files|
        files.add(".github/workflows-lab/test.yml", "name: Test\non: [push,status,workflow_dispatch]") # lab workflow includes status trigger
      end

      event = Hook::Event::StatusEvent.new status: create(:status, repository: @actions_repo)
      delivery_system = Hook::DeliverySystem.new event

      delivery_system.generate_hookshot_payloads

      assert_equal 1, delivery_system.payloads.size # We only expect the payload for the @actions_lab_app subscription
      prod_payload = delivery_system.payloads.find { |payload| payload[:parent] == "integration-#{@actions_app.id}" }
      lab_payload = delivery_system.payloads.find { |payload| payload[:parent] == "integration-#{@actions_lab_app.id}" }

      assert_nil prod_payload

      refute_nil lab_payload
      assert_equal @guid, lab_payload[:guid]
      assert_equal "status", lab_payload[:event]
      assert_equal 1, lab_payload[:hooks].size
    end

    test "generates a status payload for lab and prod if the repo has a status trigger" do
      @actions_repo.enable_actions_app(entry_point: :test_case)

      make_integration_installation(integration: @actions_lab_app, repository: @actions_repo)

      @actions_repo.default_branch_ref.append_commit({ committer: @actions_repo.owner, message: "Updating test workflow" }, @actions_repo.owner) do |files|
        files.add(".github/workflows/test.yml", "name: Test\non: [push,workflow_dispatch]") # prod workflow without status trigger
        files.add(".github/workflows-lab/test.yml", "name: Test\non: [push,status,workflow_dispatch]") # lab workflow includes status trigger
      end

      event = Hook::Event::StatusEvent.new status: create(:status, repository: @actions_repo)
      delivery_system = Hook::DeliverySystem.new event

      delivery_system.generate_hookshot_payloads

      assert_equal 2, delivery_system.payloads.size # We only expect the payload for the @actions_app and @actions_lab_app subscriptions
      prod_payload = delivery_system.payloads.find { |payload| payload[:parent] == "integration-#{@actions_app.id}" }
      lab_payload = delivery_system.payloads.find { |payload| payload[:parent] == "integration-#{@actions_lab_app.id}" }

      refute_nil prod_payload
      assert_equal @guid, prod_payload[:guid]
      assert_equal "status", prod_payload[:event]
      assert_equal 1, prod_payload[:hooks].size

      refute_nil lab_payload
      assert_equal @guid, lab_payload[:guid]
      assert_equal "status", lab_payload[:event]
      assert_equal 1, lab_payload[:hooks].size
    end

    test "generates a non-default branch event payload regardless of workflow triggers" do
      @actions_repo.enable_actions_app(entry_point: :test_case)

      @actions_repo.default_branch_ref.append_commit({ committer: @actions_repo.owner, message: "Updating test workflow" }, @actions_repo.owner) do |files|
        files.add(".github/workflows/test.yml", "name: Test\non: [gollum]") # No push event trigger
      end

      event = Hook::Event::PushEvent.new({
        repo: @actions_repo,
        before: "c1800491d95c42b4e96fb83f31fe8d9230c62907",
        after: "63611721afd41f58f801d66e543d8288b4c5eb44",
        ref: "refs/heads/master",
        pusher: create(:user),
      })
      delivery_system = Hook::DeliverySystem.new event

      delivery_system.generate_hookshot_payloads

      assert_equal 2, delivery_system.payloads.size # We expect payloads for the @actions_app subscription and the organization
      actions_payload = delivery_system.payloads.find { |payload| payload[:parent] == "integration-#{@actions_app.id}" }
      org_payload = delivery_system.payloads.find { |payload| payload[:parent] == "organization-#{@actions_repo.owner.id}" }

      assert_equal "integration-#{@actions_app.id}", actions_payload[:parent]
      assert_equal @guid, actions_payload[:guid]
      assert_equal "push", actions_payload[:event]
      assert_equal 1, actions_payload[:hooks].size

      refute_nil org_payload
    end

    test "generates an issues payload a matching workflow trigger exists" do
      @actions_repo.enable_actions_app(entry_point: :test_case)

      @actions_repo.default_branch_ref.append_commit({ committer: @actions_repo.owner, message: "Updating test workflow" }, @actions_repo.owner) do |files|
        files.add(".github/workflows/test.yml", "name: Test\non: [issues]") # Issues trigger
      end

      issue = create(:issue, repository: @actions_repo, user: @actions_repo.owner)
      event = Hook::Event::IssuesEvent.new(action: :created, issue_id: issue.id, actor_id: @actions_repo.owner.id)

      delivery_system = Hook::DeliverySystem.new event

      delivery_system.generate_hookshot_payloads

      assert_equal 1, delivery_system.payloads.size # We only expect the payload for the @actions_app subscription
      payload = delivery_system.payloads.first

      assert_equal "integration-#{@actions_app.id}", payload[:parent]
      assert_equal @guid, payload[:guid]
      assert_equal "issues", payload[:event]
      assert_equal 1, payload[:hooks].size
    end

    test "drops the issues payload when the repo doesn't have an issues workflow trigger" do
      @actions_repo.enable_actions_app(entry_point: :test_case)

      @actions_repo.default_branch_ref.append_commit({ committer: @actions_repo.owner, message: "Updating test workflow" }, @actions_repo.owner) do |files|
        files.add(".github/workflows/test.yml", "name: Test\non: [push]") # No issues trigger
      end

      issue = create(:issue, repository: @actions_repo, user: @actions_repo.owner)
      event = Hook::Event::IssuesEvent.new(action: :created, issue_id: issue.id, actor_id: @actions_repo.owner.id)

      delivery_system = Hook::DeliverySystem.new event

      delivery_system.generate_hookshot_payloads

      assert delivery_system.payloads.none? # The @actions_app subscription should be filtered out, based on the event and the repo contents
    end

    test "Generates a workflow_run payload if the event was created by Actions and the FF is enabled" do
      enable_feature_flag(:workflow_run_is_not_filtered)
      @actions_repo.enable_actions_app(entry_point: :test_case)

      @actions_repo.default_branch_ref.append_commit({ committer: @actions_repo.owner, message: "Updating test workflow" }, @actions_repo.owner) do |files|
        files.add(".github/workflows/test.yml", "name: Test\non: [push,workflow_run]") # includes workflow_run trigger
      end

      actions_check_suite = create(:check_suite_for_actions_app,
        creator: GitHub.launch_github_app.bot,
        repository: @actions_repo)

      actions_created_workflow_run = actions_check_suite.workflow_run

      event = Hook::Event::WorkflowRunEvent.new(run_id: actions_created_workflow_run.id, action: "completed")
      delivery_system = Hook::DeliverySystem.new event

      delivery_system.generate_hookshot_payloads

      assert_equal 1, delivery_system.payloads.size # We only expect the payload for the @actions_app subscription
      payload = delivery_system.payloads.first

      assert_equal "integration-#{@actions_app.id}", payload[:parent]
      assert_equal @guid, payload[:guid]
      assert_equal "workflow_run", payload[:event]
      assert_equal 1, payload[:hooks].size
    end

    test "drops a workflow_run payload if the event was created by Actions when the FF is disabled" do
      disable_feature_flag(:workflow_run_is_not_filtered)
      @actions_repo.enable_actions_app(entry_point: :test_case)

      @actions_repo.default_branch_ref.append_commit({ committer: @actions_repo.owner, message: "Updating test workflow" }, @actions_repo.owner) do |files|
        files.add(".github/workflows/test.yml", "name: Test\non: [push,workflow_run]") # includes workflow_run trigger
      end

      actions_check_suite = create(:check_suite_for_actions_app,
        creator: GitHub.launch_github_app.bot,
        repository: @actions_repo)

      actions_created_workflow_run = actions_check_suite.workflow_run

      event = Hook::Event::WorkflowRunEvent.new(run_id: actions_created_workflow_run.id, action: "completed")
      delivery_system = Hook::DeliverySystem.new event

      delivery_system.generate_hookshot_payloads

      assert delivery_system.payloads.none?
    end
  end

  context "#generate_push_event_hookshot_payloads" do
    test "does not include git data in the payload" do
      event = Hook::Event::PushEvent.new({
        repo: @repo,
        before: "c1800491d95c42b4e96fb83f31fe8d9230c62907",
        after: "63611721afd41f58f801d66e543d8288b4c5eb44",
        ref: "refs/heads/master",
        pusher: create(:user),
      })

      delivery_system = Hook::DeliverySystem.new event
      delivery_system.generate_push_event_hookshot_payloads

      delivery_system.payloads.each do |payload|
        refute payload[:payload].has_key?(:created)
        refute payload[:payload].has_key?(:deleted)
        refute payload[:payload].has_key?(:forced)
        refute payload[:payload].has_key?(:base_ref)
        refute payload[:payload].has_key?(:compare)
        refute payload[:payload].has_key?(:commits)
        refute payload[:payload].has_key?(:head_commit)
      end
    end

    test "does include mysql data in the payload" do
      event = Hook::Event::PushEvent.new({
        repo: @repo,
        before: "c1800491d95c42b4e96fb83f31fe8d9230c62907",
        after: "63611721afd41f58f801d66e543d8288b4c5eb44",
        ref: "refs/heads/master",
        pusher: create(:user),
      })

      delivery_system = Hook::DeliverySystem.new event
      delivery_system.generate_push_event_hookshot_payloads

      delivery_system.payloads.each do |payload|
        assert payload[:payload].has_key?(:repository)
        assert payload[:payload].has_key?(:pusher)
        assert payload[:payload].has_key?(:sender)
      end
    end

    test "raises when called for a non push event" do
      assert_raises(StandardError) do
        @delivery_system.generate_push_event_hookshot_payloads
      end
    end
  end

  context "#install_actions_app_and_queue_event" do
    test "queues job to install actions app when needed" do
      enable_feature_flag(:actions_required_workflows_on_demand_app_installation)

      user = create(:user)
      example_repo :rebase_pull_request, @repo
      issue = create(:issue, user: user, repository: @repo)
      pull = create(:pull_request,
        repository: @repo,
        base_repository: @repo,
        base_user: @repo.owner,
        base_ref: "master",
        head_repository: @repo,
        head_user: @repo.owner,
        head_ref: "contrib",
        issue: issue,
      )

      ruleset_workflow_path = ".github/workflows/required.yml"
      ruleset_workflow_ref = "refs/heads/main"

      @repo2.heads.find_or_build(ruleset_workflow_ref).append_commit({ message: "add workflow", committer: user }, @repo2.owner) do |files|
        files.add(ruleset_workflow_path, "some content")
      end

      ruleset = create :repository_ruleset, :targets_default_branch, :targets_all_repos, source: @org, enforcement: :enabled
      create(:repository_rule_configuration, rule_type: "workflows", repository_ruleset: ruleset, parameters: {
        workflows: [{
          repository_id: @repo2.id,
          path: ruleset_workflow_path,
          ref: ruleset_workflow_ref
        }]
      })

      event = Hook::Event::PullRequestEvent.new(
        action: :created,
        pull_request_id: pull.id,
        actor_id: @org.id,
      )

      assert_enqueued_jobs 1, only: Actions::EnableActionsOnRepositoryJob do
        Hook::DeliverySystem.deliver event
      end
    end

    test "queues job to install actions app when needed on enterprise" do
      user = create(:user)
      example_repo :rebase_pull_request, @repo
      issue = create(:issue, user: user, repository: @repo)
      pull = create(:pull_request,
        repository: @repo,
        base_repository: @repo,
        base_user: @repo.owner,
        base_ref: "master",
        head_repository: @repo,
        head_user: @repo.owner,
        head_ref: "contrib",
        issue: issue,
      )

      ruleset_workflow_path = ".github/workflows/required.yml"
      ruleset_workflow_ref = "refs/heads/main"

      @repo2.heads.find_or_build(ruleset_workflow_ref).append_commit({ message: "add workflow", committer: user }, @repo2.owner) do |files|
        files.add(ruleset_workflow_path, "some content")
      end

      ruleset = create :repository_ruleset, :targets_default_branch, :targets_all_repos, source: @org, enforcement: :enabled
      create(:repository_rule_configuration, rule_type: "workflows", repository_ruleset: ruleset, parameters: {
        workflows: [{
          repository_id: @repo2.id,
          path: ruleset_workflow_path,
          ref: ruleset_workflow_ref
        }]
      })

      event = Hook::Event::PullRequestEvent.new(
        action: :created,
        pull_request_id: pull.id,
        actor_id: @org.id,
      )

      if GitHub.enterprise?
        assert_enqueued_jobs 1, only: Actions::EnableActionsOnRepositoryJob do
          Hook::DeliverySystem.deliver event
        end
      end
    end

    test "do not queue job to install actions app when actions_required_workflows_on_demand_app_installation is disabled", skip_enterprise: true do
      disable_feature_flag(:actions_required_workflows_on_demand_app_installation)

      user = create(:user)
      example_repo :rebase_pull_request, @repo
      issue = create(:issue, user: user, repository: @repo)
      pull = create(:pull_request,
        repository: @repo,
        base_repository: @repo,
        base_user: @repo.owner,
        base_ref: "master",
        head_repository: @repo,
        head_user: @repo.owner,
        head_ref: "contrib",
        issue: issue,
      )

      ruleset_workflow_path = ".github/workflows/required.yml"
      ruleset_workflow_ref = "refs/heads/main"

      @repo2.heads.find_or_build(ruleset_workflow_ref).append_commit({ message: "add workflow", committer: user }, @repo2.owner) do |files|
        files.add(ruleset_workflow_path, "some content")
      end

      ruleset = create :repository_ruleset, :targets_default_branch, :targets_all_repos, source: @org, enforcement: :enabled
      create(:repository_rule_configuration, rule_type: "workflows", repository_ruleset: ruleset, parameters: {
        workflows: [{
          repository_id: @repo2.id,
          path: ruleset_workflow_path,
          ref: ruleset_workflow_ref
        }]
      })

      event = Hook::Event::PullRequestEvent.new(
        action: :created,
        pull_request_id: pull.id,
        actor_id: @org.id,
      )

      assert_enqueued_jobs 0, only: Actions::EnableActionsOnRepositoryJob do
        Hook::DeliverySystem.deliver event
      end
    end

    test "do not queue job to install actions app for non PR events" do
      enable_feature_flag(:actions_required_workflows_on_demand_app_installation)

      user = create(:user)
      event = Hook::Event::PushEvent.new({
        repo: @repo,
        before: "c1800491d95c42b4e96fb83f31fe8d9230c62907",
        after: "63611721afd41f58f801d66e543d8288b4c5eb44",
        ref: "refs/heads/master",
        pusher: user,
      })

      ruleset_workflow_path = ".github/workflows/required.yml"
      ruleset_workflow_ref = "refs/heads/main"

      @repo2.heads.find_or_build(ruleset_workflow_ref).append_commit({ message: "add workflow", committer: user }, @repo2.owner) do |files|
        files.add(ruleset_workflow_path, "some content")
      end

      ruleset = create :repository_ruleset, :targets_default_branch, :targets_all_repos, source: @org, enforcement: :enabled
      create(:repository_rule_configuration, rule_type: "workflows", repository_ruleset: ruleset, parameters: {
        workflows: [{
          repository_id: @repo2.id,
          path: ruleset_workflow_path,
          ref: ruleset_workflow_ref
        }]
      })

      assert_enqueued_jobs 0, only: Actions::EnableActionsOnRepositoryJob do
        Hook::DeliverySystem.deliver event
      end
    end
  end

  context "#deliver_later" do
    test "raises a PayloadsNotGenerated error if generate_hookshot_payloads was not called first" do
      assert_raises(Hook::DeliverySystem::PayloadsNotGenerated) do
        @delivery_system.deliver_later
      end
    end

    test "does not log deliveries to hydro if in enterprise mode" do
      @delivery_system.generate_hookshot_payloads
      @delivery_system.deliver_later

      assert_hydro_messages(
        count: 0,
        schema: "github.webhooks.v0.DeliveryMetadata",
      )
    end if GitHub.enterprise?

    test "logs all deliveries to hydro if not in enterprise mode", skip_enterprise: true do
      @delivery_system.generate_hookshot_payloads
      @delivery_system.deliver_later

      assert_hydro_messages(
        count: @event.hooks.count,
        schema: "github.webhooks.v0.DeliveryMetadata",
      )
    end

    test "does not make any deliveries when the event feature flag is disabled" do
      disable_feature_flag(:delivery_system_test_event_hook)

      @delivery_system.generate_hookshot_payloads

      Hook::DeliverySystem.expects(:post_payload_to_hookshot).never
      assert_performed_jobs(0) { @delivery_system.deliver_later }
    end

    context "when payload size is too large" do
      test "triggers .post_payload_to_hookshot for each payload" do
        GitHub::Aqueduct.stubs(:is_payload_size_large?).returns(true)
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        Hook::DeliverySystem.expects(:post_payload_to_hookshot).with(@org_payload)
        Hook::DeliverySystem.expects(:post_payload_to_hookshot).with(@v3_repo_payload)
        Hook::DeliverySystem.expects(:post_payload_to_hookshot).with(@repo_with_content_type_payload)
        Hook::DeliverySystem.expects(:post_payload_to_hookshot).with(@integration_payload)

        @delivery_system.generate_hookshot_payloads
        @delivery_system.deliver_later

        expected_tags = [
          "event:hook/delivery_system_test_created",
          "event_type:hook/delivery_system_test",
        ]

        assert_equal 4, GitHub.dogstats.increments("hooks.delivered_to_hookshot.per_trigger.count", tags: expected_tags).count
      end

      test "emits tier1 event size metric" do
        GitHub::Aqueduct.stubs(:is_payload_size_large?).returns(true)
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        @delivery_system.generate_hookshot_payloads
        @delivery_system.deliver_later

        expected_tags = [
          "event:hook/delivery_system_test_created",
          "event_type:hook/delivery_system_test",
          "prehydrated:true"
        ]

        assert_equal 4, GitHub.dogstats.distributions("hooks.tier1_event_size", tags: expected_tags).count
      end
    end

    context "when payload size is not too large" do
      test "queues EnqueueToHookshot jobs for each hook in each generated payload" do
        GitHub::Aqueduct.stubs(:is_payload_size_large?).returns(false)
        event = Hook::Event::DeliverySystemTestEvent.new action: "created",
          hooks: [@org_hook, @repo_hook],
          feature_flag_actor: @org,
          triggered_at: @triggered_at
        delivery_system = Hook::DeliverySystem.new event
        delivery_system.generate_hookshot_payloads

        assert_performed_jobs(2, only: [EnqueueToHookshotJob]) do
          delivery_system.deliver_later
        end
      end

      test "records to datadog signals for each hook in each generated payload when use_aqueduct is enabled and payload can fit to aqueduct" do
        GitHub::Aqueduct.stubs(:is_payload_size_large?).returns(false)
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
        event = Hook::Event::DeliverySystemTestEvent.new action: "created",
          hooks: [@org_hook, @repo_hook],
          feature_flag_actor: @org,
          triggered_at: @triggered_at
        delivery_system = Hook::DeliverySystem.new event
        delivery_system.generate_hookshot_payloads

        assert_performed_jobs(2) do
          delivery_system.deliver_later
        end

        expected_tags = [
          "event:hook/delivery_system_test_created",
          "event_type:hook/delivery_system_test",
          "job:enqueue-to-hookshot"
        ]

        stats = GitHub.dogstats.increments("hooks.enqueued_per_hook.count", tags: expected_tags)
        assert_equal 2, stats.size
      end

      test "emits tier1 event size metric" do
        GitHub::Aqueduct.stubs(:is_payload_size_large?).returns(false)
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
        event = Hook::Event::DeliverySystemTestEvent.new action: "created",
          hooks: [@org_hook, @repo_hook],
          feature_flag_actor: @org,
          triggered_at: @triggered_at
        delivery_system = Hook::DeliverySystem.new event
        delivery_system.generate_hookshot_payloads
        delivery_system.deliver_later

        expected_tags = [
          "event:hook/delivery_system_test_created",
          "event_type:hook/delivery_system_test",
          "prehydrated:true"
        ]
        assert_equal 2, GitHub.dogstats.distributions("hooks.tier1_event_size", tags: expected_tags).count
      end

      context "when not in enterprise mode", skip_enterprise: true do
        test "publishes a hydro event with delivery_type = actions for actions events" do

          hook = create(:hook, installation_target: @actions_app)

          event = Hook::Event::PingEvent.new(hook_id: hook.id)
          delivery_system = Hook::DeliverySystem.new event
          delivery_system.generate_hookshot_payloads
          delivery_system.deliver_later

          assert_hydro_published_partial({
            delivery_guid: @guid,
            delivery_type: :ACTIONS,
            hook_event: "ping",
          }, schema: "github.webhooks.v0.DeliveryMetadata")
        end

        test "publishes a hydro event with delivery_type = hookshot hookshot events" do
          hook = if @repo.repo_hook_associations_ff?
            Hook.hooks_for_target(@repo).first
          else
            @repo.hooks.first
          end

          event = Hook::Event::PingEvent.new(hook_id: hook.id)
          delivery_system = Hook::DeliverySystem.new event
          delivery_system.generate_hookshot_payloads
          delivery_system.deliver_later

          assert_hydro_published_partial({
            delivery_guid: @guid,
            delivery_type: :HOOKSHOT,
            hook_event: "ping",
          }, schema: "github.webhooks.v0.DeliveryMetadata")
        end
      end
    end
  end

  context "#deliver_push_event_later" do
    test "queues a single PostPushEventToHookshot job for all payloads" do
      event = Hook::Event::PushEvent.new({
        repo: @repo,
        before: "c1800491d95c42b4e96fb83f31fe8d9230c62907",
        after: "63611721afd41f58f801d66e543d8288b4c5eb44",
        ref: "refs/heads/master",
        pusher: create(:user),
      })

      delivery_system = Hook::DeliverySystem.new event
      delivery_system.generate_push_event_hookshot_payloads
      delivery_system.deliver_push_event_later

      check_args = proc do |event, _|
        payloads = delivery_system.payloads
        assert_equal event, payloads
      end

      assert_enqueued_jobs(1, only: PostPushEventToHookshotJob)
      assert_enqueued_with(job: PostPushEventToHookshotJob, args: check_args)
    end

    context "instruments delivery when not in enterprise mode", skip_enterprise: true do
      test "publishes a hydro event for actions events" do
        hook = create(:hook, installation_target: @actions_app)

        event = Hook::Event::PushEvent.new({
          repo: @repo,
          before: "c1800491d95c42b4e96fb83f31fe8d9230c62907",
          after: "63611721afd41f58f801d66e543d8288b4c5eb44",
          ref: "refs/heads/master",
          pusher: create(:user),
        })

        event.stubs(:subscribed_hooks).returns([hook])

        delivery_system = Hook::DeliverySystem.new event
        delivery_system.generate_push_event_hookshot_payloads
        delivery_system.deliver_push_event_later

        assert_hydro_published_partial({
          delivery_guid: @guid,
          delivery_type: :ACTIONS,
          hook_event: "push",
        }, schema: "github.webhooks.v0.DeliveryMetadata")
      end

      test "publishes a hydro event for hookshot events" do
        hook = if @repo.repo_hook_associations_ff?
          Hook.hooks_for_target(@repo).first
        else
          @repo.hooks.first
        end

        event = Hook::Event::PushEvent.new({
          repo: @repo,
          before: "c1800491d95c42b4e96fb83f31fe8d9230c62907",
          after: "63611721afd41f58f801d66e543d8288b4c5eb44",
          ref: "refs/heads/master",
          pusher: create(:user),
        })

        event.stubs(:subscribed_hooks).returns([hook])

        delivery_system = Hook::DeliverySystem.new event
        delivery_system.generate_push_event_hookshot_payloads
        delivery_system.deliver_push_event_later

        assert_hydro_published_partial({
          delivery_guid: @guid,
          delivery_type: :HOOKSHOT,
          hook_event: "push",
        }, schema: "github.webhooks.v0.DeliveryMetadata")
      end

      test "records a metric for tier1 event size" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
        hook = if @repo.repo_hook_associations_ff?
          Hook.hooks_for_target(@repo).first
        else
          @repo.hooks.first
        end

        event = Hook::Event::PushEvent.new({
          repo: @repo,
          before: "c1800491d95c42b4e96fb83f31fe8d9230c62907",
          after: "63611721afd41f58f801d66e543d8288b4c5eb44",
          ref: "refs/heads/master",
          pusher: create(:user),
        })

        event.stubs(:subscribed_hooks).returns([hook])

        delivery_system = Hook::DeliverySystem.new event
        delivery_system.generate_push_event_hookshot_payloads
        delivery_system.deliver_push_event_later

        expected_tags = [
          "event:hook/push",
          "event_type:hook/push",
          "site:#{GitHub.site}",
          "prehydrated:true"
        ]
        assert_equal 1, GitHub.dogstats.distributions("hooks.tier1_event_size", tags: expected_tags).count
      end

      test "records stats about enqueued job when not using Kubernetes" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        event = Hook::Event::PushEvent.new({
          repo: @repo,
          before: "c1800491d95c42b4e96fb83f31fe8d9230c62907",
          after: "63611721afd41f58f801d66e543d8288b4c5eb44",
          ref: "refs/heads/master",
          pusher: create(:user),
        })

        delivery_system = Hook::DeliverySystem.new event
        delivery_system.generate_push_event_hookshot_payloads
        delivery_system.deliver_push_event_later

        check_args = proc do |event, _|
          payloads = delivery_system.payloads
          assert_equal event, payloads
        end

        assert_enqueued_jobs(1, only: PostPushEventToHookshotJob)
        assert_enqueued_with(job: PostPushEventToHookshotJob, args: check_args)

        expected_tags = ["event:hook/push", "event_type:hook/push", "job:post-push-event-to-hookshot"]
        assert_equal 1, GitHub.dogstats.counts("hooks.enqueued_per_hook.count", tags: expected_tags).count
        assert_equal 1, GitHub.dogstats.increments("hooks.job_enqueued.count", tags: expected_tags).count
      end
    end
  end

  context "#grouped_hooks" do
    test "returns a hash keyed by an array of parent and payload version" do
      result = @delivery_system.send(:grouped_hooks)
      expected_result = {
        @org_hook.hookshot_parent_id => [@org_hook],
        @repo_hook.hookshot_parent_id => [@repo_hook, @repo_hook2],
        @repo_with_content_type_hook.hookshot_parent_id => [@repo_with_content_type_hook],
        @integration_hook.hookshot_parent_id => [@integration_hook],
      }

      assert_equal expected_result, result
    end

    test "doesn't return service hooks" do
      @repo_hook2.name = "irc"

      result = @delivery_system.send(:grouped_hooks)

      key = @repo_hook.hookshot_parent_id
      refute_includes result[key], @repo_hook2
    end

    test "doesn't return email service hooks" do
      @repo_hook2.name = "email"

      result = @delivery_system.send(:grouped_hooks)

      key = @repo_hook.hookshot_parent_id
      refute_includes result[key], @repo_hook2
    end

    test "filters out hooks on denylist" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      enable_feature_flag(:webhooks_denylist, @integration)
      result = @delivery_system.send(:grouped_hooks)
      key = @integration_hook.hookshot_parent_id
      refute result.key?(key)
      expected_tags = ["site:DEFAULT_SITE", "queue:hookshot", "service:hookshot"]
      assert_equal 1, GitHub.dogstats.increments("hooks.blocked_from_denylist.count", tags: expected_tags).count
    end

    test "does not filter out hooks if not on denylist" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      disable_feature_flag(:webhooks_denylist, @integration)
      result = @delivery_system.send(:grouped_hooks)
      key = @integration_hook.hookshot_parent_id
      assert result.key?(key)
      expected_tags = ["site:DEFAULT_SITE", "queue:hookshot", "service:hookshot"]
      assert_equal 0, GitHub.dogstats.increments("hooks.blocked_from_denylist.count", tags: expected_tags).count
    end
  end

  context "#chatops_hooks" do

    test "does not deliver to chatops queue when hook is not for chatops" do
      @chatops_installation = make_integration_installation(
        integration: @chatops_app,
        target: @org,
        permissions: { "metadata" => :read, "contents" => :read },
      )

      parent = "integration-#{GitHub.slack_github_app&.id + 10}"
      payload = @repo_with_repo_payload.merge({
        parent: parent,
      })
      payload[:payload] = payload[:payload].merge({
        installation: {
          id: @chatops_installation[:id]
        }
      })
      Hook::DeliverySystem.expects(:aqueduct_client_for).with(parent).returns(mock(send_job: true))
      Hook::DeliverySystem.expects(:chatops_aqueduct_client).never

      Hook::DeliverySystem.enqueue_payload_to_hookshot(payload)
    end

    test "delivers to chatops queue when hook is for chatops" do
      @chatops_installation = make_integration_installation(
        integration: @chatops_app,
        target: @org,
        permissions: { "metadata" => :read, "contents" => :read },
      )

      parent = "integration-#{GitHub.slack_github_app&.id}"
      payload = @repo_with_repo_payload.merge({
        parent: parent,
      })
      payload[:payload] = payload[:payload].merge({
        installation: {
          id: @chatops_installation[:id]
        }
      })
      Hook::DeliverySystem.expects(:aqueduct_client_for).never
      Hook::DeliverySystem.expects(:chatops_aqueduct_client).returns(mock(send_job: true))

      Hook::DeliverySystem.enqueue_payload_to_hookshot(payload)
    end

    test "delivers chatops workflow_job webhook to *-workflows queue when hook is for chatops" do
      @chatops_installation = make_integration_installation(
        integration: @chatops_app,
        target: @org,
        permissions: { "metadata" => :read, "contents" => :read },
      )

      parent = "integration-#{GitHub.slack_github_app&.id}"
      payload = @repo_with_repo_payload.merge({
        parent: parent,
      })
      payload[:payload] = payload[:payload].merge({
        installation: {
          id: @chatops_installation[:id]
        }
      })
      payload[:event] = "workflow_job"
      Hook::DeliverySystem.expects(:aqueduct_client_for).with(parent).never
      mock_chatops_client = mock
      mock_chatops_client.expects(:send_job).with(has_entries(queue: "webhook-slack-workflows"))
      mock_chatops_client.expects(:send_job).with(has_entries(queue: "webhook-slack")).never
      Hook::DeliverySystem.expects(:chatops_aqueduct_client).returns(mock_chatops_client)

      Hook::DeliverySystem.enqueue_payload_to_hookshot(payload)
    end

    test "delivers chatops webhook to webhook-slack queue when hook is for chatops" do
      @chatops_installation = make_integration_installation(
        integration: @chatops_app,
        target: @org,
        permissions: { "metadata" => :read, "contents" => :read },
      )

      parent = "integration-#{GitHub.slack_github_app&.id}"
      payload = @repo_with_repo_payload.merge({
        parent: parent,
      })
      payload[:payload] = payload[:payload].merge({
        installation: {
          id: @chatops_installation[:id]
        }
      })
      Hook::DeliverySystem.expects(:aqueduct_client_for).with(parent).never
      mock_chatops_client = mock
      mock_chatops_client.expects(:send_job).with(has_entries(queue: "webhook-slack"))
      mock_chatops_client.expects(:send_job).with(has_entries(queue: "webhook-slack-workflows")).never
      Hook::DeliverySystem.expects(:chatops_aqueduct_client).returns(mock_chatops_client)

      Hook::DeliverySystem.enqueue_payload_to_hookshot(payload)
    end

  end

  context ".build_aqueduct_job", skip_enterprise: true do
    tenant_header = "X-GitHub-Tenant"
    tenant_id_header = "X-GitHub-Tenant-ID"

    test "headers include tenant and tenant_id when GitHub::CurrentTenant is set" do
      emu = create(:emu)

      on_multi_tenant_enterprise(tenant: emu.enterprise_managed_business) do
        job = Hook::DeliverySystem.build_aqueduct_job("{}", "queue")
        assert_includes job[:headers], tenant_header
        assert_includes job[:headers], tenant_id_header

        tenant = GitHub::CurrentTenant.get
        assert_equal job[:headers][tenant_id_header], tenant.id.to_s
        assert_equal job[:headers][tenant_header], tenant.slug
      end
    end

    test "headers do not include tenant and tenant_id when GitHub::CurrentTenant is not set" do
      job = Hook::DeliverySystem.build_aqueduct_job("{}", "queue")
      assert !job[:headers].include?(tenant_header)
      assert !job[:headers].include?(tenant_id_header)
    end
  end

  def reset_aqueduct_clients!
    Hook::DeliverySystem.instance_variable_set("@hookshot_ruby_staging_aqueduct_client", nil)
    Hook::DeliverySystem.instance_variable_set("@hookshot_ruby_default_aqueduct_client", nil)
    Hook::DeliverySystem.instance_variable_set("@hookshot_go_staging_aqueduct_client", nil)
    Hook::DeliverySystem.instance_variable_set("@hookshot_go_default_aqueduct_client", nil)
    Hook::DeliverySystem.instance_variable_set("@actions_aqueduct_client", nil)
    Hook::DeliverySystem.instance_variable_set("@chatops_aqueduct_client", nil)
  end
end
