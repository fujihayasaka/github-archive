# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/conditional_access/filter_test_helper"
require "test_helpers/fake_kredz"

class Codespaces::StartTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper
  include DogstatsTestHelpers
  include HydroTestHelpers

  fixtures do
    make_trusted_oauth_apps_owner

    @user = create(:user, login: "user")
    GitHub.flipper[:codespaces_disable_starts].disable
    @user_session = create(:user_session, user: @user)

    existing_plan = create(:codespace_plan, resource_provider: "Microsoft.Codespaces")
    @codespace = create(:codespace, owner: @user, plan: existing_plan)

    @integration = create(:codespaces_integration)

    @user.disable_feature(:codespaces_cwtp_no_limits)
  end

  setup_once do
    enable_cache_storage
  end

  setup do
    reset_cache
    reset_monolith_redis_rate_limiter
    FakeVSOServer.reset!
    FakeVSOServer.environments = [
      {
        "id" => @codespace.guid,
        "state" => "Starting",
        "skuName" => "standardLinux32gb",
        "connection" => "connection data",
        "skuDisplayName" => "Standard (Linux): 4 cores, 8 GB RAM, 32 GB storage",
        "accessToken" => "supersecret"
      }
    ]
  end

  teardown_once do
    disable_cache_storage
  end

  context "codespace permissions" do
    test "it allows the owner to start a codespace if it is accessible" do
      @codespace.stubs(:accessible?).returns(true)
      assert_nothing_raised do
        Codespaces::Start.call(@codespace, user: @user, session: @user_session)
      end
    end

    test "it prevents starts if the codespace is not accessible" do
      @codespace.stubs(:accessible?).returns(false)
      assert_raises(Codespaces::Start::InaccessibleError) do
        Codespaces::Start.call(@codespace, user: @user, session: @user_session)
      end
    end
  end
  context "disabling start" do
    test "checks the codespaces_disable_starts feature flag" do
      GitHub.flipper[:codespaces_disable_starts].enable
      assert_raises_with_message ActiveModel::ValidationError, /Starting codespaces is temporarily unavailable./ do
        Codespaces::Start.call(@codespace, user: @user, session: @user_session)
      end
    end
  end

  context "using user_session", skip_enterprise: true do
    test "Returns a github token" do
      FakeKredz.with_no_secrets do
        result = Codespaces::Start.call(@codespace, user: @user, session: @user_session)
        refute_nil result.github_token
      end
    end

    test "Returns a codespace (gpg) token" do
      FakeKredz.with_no_secrets do
        result = Codespaces::Start.call(@codespace, user: @user, session: @user_session)
        refute_nil result.codespace_token
      end
    end

    test "Returns a the raw response from vscs" do
      FakeKredz.with_no_secrets do
        result = Codespaces::Start.call(@codespace, user: @user, session: @user_session)
        assert_kind_of Faraday::Response, result.response
      end
    end

    test "Returns the cascade token" do
      FakeKredz.with_no_secrets do
        result = Codespaces::Start.call(@codespace, user: @user, session: @user_session)
        assert_equal "supersecret", result.cascade_token
      end
    end

    test "Returns the connection data" do
      FakeKredz.with_no_secrets do
        result = Codespaces::Start.call(@codespace, user: @user, session: @user_session)
        assert_equal "connection data", result.connection
      end
    end

    test "accepts request_cascade_token option" do
      start = Codespaces::Start.new(@codespace, user: @user, session: @user_session, request_cascade_token: true)
      assert_equal true, start.request_cascade_token
    end

    test "when response is unsuccessful, set cascade_token to nil" do
      FakeKredz.with_no_secrets do
        other_codespace = create(:codespace, owner: @user)
        FakeVSOServer.fake_responses = [
          {
            endpoint: "/api/v1/environments/#{other_codespace.guid}/start",
            status: 400,
            body: "7",
          }
        ]
        begin
          result = Codespaces::Start.call(other_codespace, user: @user, session: @user_session, request_cascade_token: true)
          assert_nil result.cascade_token
        rescue Codespaces::VscsClient::BadResponseError
        end
      end
    end

    test "when response is a bad response,raise bad response error" do
      FakeKredz.with_no_secrets do
        other_codespace = create(:codespace, owner: @user)
        FakeVSOServer.fake_responses = [
          {
            endpoint: "/api/v1/environments/#{other_codespace.guid}/start",
            status: 400,
            body: "BadRequest(Something bad happened)",
          }
        ]
        assert_raises Codespaces::VscsClient::BadResponseError do
          Codespaces::Start.call(other_codespace, user: @user, session: @user_session, request_cascade_token: true)
        end
      end
    end

    test "uses github token if parameter is passed in" do
      token = "foobar"
      start = Codespaces::Start.new(@codespace, user: @user, session: @user_session, github_token: token)
      assert_equal token, start.github_token
    end

    test "clears the last known stop notice cache" do
      Codespaces::LastKnownStopNoticeCache.expects(:clear).with(billable_owner_id: @codespace.billable_owner_id)

      Codespaces::Start.call(@codespace, user: @user, session: @user_session)
    end
  end

  context "using cap_filter", skip_enterprise: true do
    test "Returns the cascade token" do
      vscode_app = create(:vscode_oauth_app)
      saml_org = create(:business_plus_org, admin: @user)
      access = make_oauth(@user, ["repo"], vscode_app)

      Organization::CredentialAuthorization.grant(organization: saml_org, credential: access, actor: @user)
      @user.oauth_access = access

      @user.oauth_access = Codespaces::Tokens.grant_repository_access(@user, @codespace)

      FakeKredz.with_no_secrets do
        result = Codespaces::Start.call(@codespace, user: @user, cap_filter: cap_authorizing_filter)
        assert_equal "supersecret", result.cascade_token
      end
    end
  end

  context "concurrency limits", skip_enterprise: true do
    test "it allows starts if the concurrency policy allows it" do
      @codespace.merge_environment_data!({ state: Codespaces::Vscs::State::SHUTDOWN })

      FakeKredz.with_no_secrets do
        Codespaces::Start.call(@codespace, user: @user, session: @user_session, concurrency_policy: FakeConcurrencyPolicy.new(allow_count: Float::INFINITY))
      end
    end

    test "it blocks starts if the concurrency policy rejects it" do
      @codespace.merge_environment_data!({ state: Codespaces::Vscs::State::SHUTDOWN })

      assert_raises Codespaces::ConcurrencyLimitError do
        FakeKredz.with_no_secrets do
          Codespaces::Start.call(@codespace, user: @user, session: @user_session, concurrency_policy: FakeConcurrencyPolicy.new(allow_count: 0))
        end
      end
    end

    test "it blocks starts if the copilot workspace concurrency policy rejects it" do
      @user.enable_feature(:copilot_workspace)
      cw_codespace = create(:codespace, copilot_workspace_id: SecureRandom.hex(18), owner: @user)
      cw_codespace.merge_environment_data!({ state: Codespaces::Vscs::State::SHUTDOWN })

      assert_raises Codespaces::CopilotWorkspaceConcurrencyLimitError do
        FakeKredz.with_no_secrets do
          Codespaces::Start.call(cw_codespace, user: @user, session: @user_session, concurrency_policy: FakeConcurrencyPolicy.new(allow_count: 0))
        end
      end
    end

    test "it allows starting cwtp codespaces if user has the opt-out flag" do
      @user.enable_feature(:copilot_workspace)
      @user.enable_feature(:codespaces_cwtp_no_limits)
      cw_codespace = create(:codespace, copilot_workspace_id: SecureRandom.hex(18), owner: @user)
      cw_codespace.merge_environment_data!({ state: Codespaces::Vscs::State::SHUTDOWN })

      FakeVSOServer.reset!
      FakeVSOServer.environments = [
        {
          "id" => cw_codespace.guid,
          "state" => "Shutdown",
        }
      ]

      assert_nothing_raised do
        FakeKredz.with_no_secrets do
          Codespaces::Start.call(cw_codespace, user: @user, session: @user_session, concurrency_policy: FakeConcurrencyPolicy.new(allow_count: 0))
        end
      end
    end

    test "it allows starting codespaces that are already starting" do
      FakeVSOServer.reset!
      FakeVSOServer.environments = [
        {
          "id" => @codespace.guid,
          "state" => Codespaces::Vscs::State::STARTING,
        }
      ]
      @codespace.merge_environment_data!({ state: Codespaces::Vscs::State::STARTING })

      concurrency_policy = FakeConcurrencyPolicy.new(allow_count: 1)
      FakeKredz.with_no_secrets do
        Codespaces::Start.call(@codespace, user: @user, session: @user_session, concurrency_policy: concurrency_policy)
        Codespaces::Start.call(@codespace, user: @user, session: @user_session, concurrency_policy: concurrency_policy)
      end
    end

    test "it doesn't leak state manipulation when an error occurs" do
      FakeVSOServer.reset!
      FakeVSOServer.environments = [
        {
          "id" => @codespace.guid,
          "state" => Codespaces::Vscs::State::SHUTDOWN,
        }
      ]
      FakeVSOServer.fake_responses = [
        {
          endpoint: "/api/v1/environments/#{@codespace.guid}/start",
          status: 400,
          body: "BadRequest(Something bad happened)",
        }
      ]
      @codespace.merge_environment_data!({ state: Codespaces::Vscs::State::SHUTDOWN })
      FakeKredz.with_no_secrets do
        assert_raises Codespaces::VscsClient::BadResponseError do
          Codespaces::Start.call(@codespace, user: @user, session: @user_session, concurrency_policy: FakeConcurrencyPolicy.new(allow_count: Float::INFINITY))
        end
        assert_equal Codespaces::Vscs::State::SHUTDOWN, @codespace.reload.environment_data["state"]
      end
    end

    test "it doesn't leak state manipulation when an error occurs with no environment_data" do
      FakeVSOServer.reset!
      FakeVSOServer.environments = [
        {
          "id" => @codespace.guid,
          "state" => Codespaces::Vscs::State::SHUTDOWN,
        }
      ]
      FakeVSOServer.fake_responses = [
        {
          endpoint: "/api/v1/environments/#{@codespace.guid}/start",
          status: 400,
          body: "BadRequest(Something bad happened)",
        }
      ]
      @codespace.update(environment_data: nil)
      FakeKredz.with_no_secrets do
        assert_raises Codespaces::VscsClient::BadResponseError do
          Codespaces::Start.call(@codespace, user: @user, session: @user_session, concurrency_policy: FakeConcurrencyPolicy.new(allow_count: Float::INFINITY))
        end
        assert_nil @codespace.reload.environment_data["state"]
      end
    end
  end

  context "token caching", skip_enterprise: true do
    test "reenqueues async if connection isn't required and token is cached" do
      Timecop.freeze do
        @codespace.merge_environment_data!({ state: Codespaces::Vscs::State::SHUTDOWN })
        Codespaces::TokenCache.write_codespace_cascade_token(
          owner_id: @user.id,
          guid: @codespace.guid,
          token: "token",
          expiration: Time.now + 1.hour,
        )
        Codespaces::VscsClient.any_instance.expects(:start_environment).never
        Codespaces::Start::Job.expects(:perform_later)
        FakeKredz.with_no_secrets do
          Codespaces::Start.call(@codespace, user: @user, session: @user_session, require_connection: false)
        end
      end
    end

    test "when we reenqueues async we instruments connect once" do
      Timecop.freeze do
        events = subscribe "codespaces.connect"

        perform_enqueued_jobs(only: Codespaces::Start::Job) do
          @codespace.merge_environment_data!({ state: Codespaces::Vscs::State::SHUTDOWN })
          Codespaces::TokenCache.write_codespace_cascade_token(
            owner_id: @user.id,
            guid: @codespace.guid,
            token: "token",
            expiration: Time.now + 1.hour,
          )

          FakeKredz.with_no_secrets do
            Codespaces::Start.call(@codespace, user: @user, session: @user_session, require_connection: false)
          end
        end

        assert_equal events.length, 1
      end
    end

    test "when we jump to a background job we don't raise an exception for 422 errors" do
      Timecop.freeze do
        FakeVSOServer.reset!
        FakeVSOServer.environments = [
          {
            "id" => @codespace.guid,
            "state" => "Available",
          }
        ]
        FakeVSOServer.fake_responses = [
          {
            endpoint: "/api/v1/environments/#{@codespace.guid}/start",
            status: 422,
            body: "7",
          }
        ]
        operation = create(:codespaces_async_operation, codespace: @codespace, operation: :start_codespace)
        perform_enqueued_jobs(only: Codespaces::Start::Job) do
          @codespace.merge_environment_data!({ state: Codespaces::Vscs::State::SHUTDOWN })
          Codespaces::TokenCache.write_codespace_cascade_token(
            owner_id: @user.id,
            guid: @codespace.guid,
            token: "token",
            expiration: Time.now + 1.hour,
          )

          FakeKredz.with_no_secrets do
            assert_nothing_raised do
              Codespaces::Start.call(@codespace, user: @user, session: @user_session, require_connection: false, operation: operation)
            end
          end
        end
        assert operation.reload.op_ended_at
      end
    end

    test "when we jump to a background job we raise an exception for 5xx errors" do
      Timecop.freeze do
        FakeVSOServer.reset!
        FakeVSOServer.environments = [
          {
            "id" => @codespace.guid,
            "state" => "Available",
          }
        ]
        FakeVSOServer.fake_responses = [
          {
            endpoint: "/api/v1/environments/#{@codespace.guid}/start",
            status: 500,
          }
        ]
        operation = create(:codespaces_async_operation, codespace: @codespace, operation: :start_codespace)
        perform_enqueued_jobs(only: Codespaces::Start::Job) do
          @codespace.merge_environment_data!({ state: Codespaces::Vscs::State::SHUTDOWN })
          Codespaces::TokenCache.write_codespace_cascade_token(
            owner_id: @user.id,
            guid: @codespace.guid,
            token: "token",
            expiration: Time.now + 1.hour,
          )

          FakeKredz.with_no_secrets do
            assert_raises Codespaces::VscsClient::BadResponseError do
              Codespaces::Start.call(@codespace, user: @user, session: @user_session, require_connection: false, operation: operation)
            end
          end
        end
        assert operation.reload.op_ended_at
      end
    end

    test "when we jump to a background job we immediately end operations when an unexpected error occurs" do
      Timecop.freeze do
        FakeVSOServer.reset!
        operation = create(:codespaces_async_operation, codespace: @codespace, operation: :start_codespace)
        Codespaces::VscsClient.any_instance.expects(:start_environment).raises(StandardError)
        perform_enqueued_jobs(only: Codespaces::Start::Job) do
          @codespace.merge_environment_data!({ state: Codespaces::Vscs::State::SHUTDOWN })
          Codespaces::TokenCache.write_codespace_cascade_token(
            owner_id: @user.id,
            guid: @codespace.guid,
            token: "token",
            expiration: Time.now + 1.hour,
          )

          FakeKredz.with_no_secrets do
            assert_raises StandardError do
              Codespaces::Start.call(@codespace, user: @user, session: @user_session, require_connection: false, operation: operation)
            end
          end
        end
        assert operation.reload.op_ended_at
        assert_dogstats_increment(1, "codespaces.async_operations.ended", tags: ["operation:start_codespace", "state:failed"])
      end
    end

    test "returns early if codespace is starting and token is cached" do
      Timecop.freeze do
        @codespace.merge_environment_data!({ state: Codespaces::Vscs::State::STARTING })
        Codespaces::TokenCache.write_codespace_cascade_token(
          owner_id: @user.id,
          guid: @codespace.guid,
          token: "token",
          expiration: Time.now + 1.hour,
        )
        Codespaces::VscsClient.any_instance.expects(:start_environment).never
        Codespaces::Start::Job.expects(:perform_later).never
        FakeKredz.with_no_secrets do
          Codespaces::Start.call(@codespace, user: @user, session: @user_session, require_connection: false)
        end
      end
    end

    test "doesn't reenqueue async if token isn't cached" do
      Timecop.freeze do
        @codespace.merge_environment_data!({ state: Codespaces::Vscs::State::SHUTDOWN })
        Codespaces::Start::Job.expects(:perform_later).never
        FakeKredz.with_no_secrets do
          Codespaces::Start.call(@codespace, user: @user, session: @user_session, require_connection: false)
        end
      end
    end
  end

  context "rate limits", skip_enterprise: true do
    test "raises exception if at rate limit and logs to datadog" do
      GitHub.flipper[:codespaces_automated_testing].disable
      GitHub.flipper[:codespaces_bypass_rate_limiting].disable


      GitHub.stub(:codespaces_per_minute_rate_limit, 0) do
        assert_raise Codespaces::RateLimitError do # rubocop:todo Style/Minitest
          FakeKredz.with_no_secrets do
            Codespaces::Start.call(@codespace, user: @user, session: @user_session)
          end
        end
        assert_dogstats_increment(1, "codespaces.rate_limited")
      end
    end

    test "allows creation if below rate limit" do
      GitHub.stub(:codespaces_per_minute_rate_limit, 1) do
        FakeKredz.with_no_secrets do
          Codespaces::Start.call(@codespace, user: @user, session: @user_session)
        end
      end
    end

    test "increments rate limit after successful start" do
      GitHub.flipper[:codespaces_automated_testing].disable
      GitHub.flipper[:codespaces_bypass_rate_limiting].disable

      GitHub.stub(:codespaces_per_minute_rate_limit, 1) do
        refute Codespaces::PerUserRateLimiter.at_limit?(@user)
        FakeKredz.with_no_secrets do
          Codespaces::Start.call(@codespace, user: @user, session: @user_session)
          assert Codespaces::PerUserRateLimiter.at_limit?(@user)
          assert Codespaces::PerUserStartTracker.new(@user).codespace_most_recently_started?(@codespace)
        end
      end
    end

    test "doesn't increment rate limit if already started" do
      GitHub.flipper[:codespaces_automated_testing].disable
      GitHub.flipper[:codespaces_bypass_rate_limiting].disable

      Codespaces::PerUserStartTracker.new(@user).track_start(@codespace)
      GitHub.stub(:codespaces_per_minute_rate_limit, 1) do
        refute Codespaces::PerUserRateLimiter.at_limit?(@user)
        FakeKredz.with_no_secrets do
          Codespaces::Start.call(@codespace, user: @user, session: @user_session)
          refute Codespaces::PerUserRateLimiter.at_limit?(@user)
        end
      end
    end
  end

  context "Copilot Workspace" do
    test "checks copilot workspace usage limits when starting one" do
      @user.enable_feature(:copilot_workspace)
      cw = create(:copilot_workspace, owner: @user)
      create(:codespace_usage_record, :for_copilot_workspace, owner: @user, usage_seconds: Codespaces::Dials::CopilotWorkspaceUsageLimitSeconds.new(force_cache_miss: true).value)
      assert_raises_with_message ActiveModel::ValidationError, "Validation failed: You've reached your Copilot Workspace usage limit." do
        FakeKredz.with_no_secrets do
          Codespaces::Start.call(cw, user: @user, session: @user_session, require_connection: false)
        end
      end
    end
  end

  context "setting failover_details", skip_enterprise: true do
    test "is passed to vscs" do
      org = create(:organization)
      org_repo = create(:private_repository, owner: org)
      org_codespace = create(:codespace, repository: org_repo, owner: @user)
      org_codespace.location = "westus2"
      org_codespace.vscs_target = :latestdev

      failover_details = { failoverEnabled: true, failoverRegion: "westeurope" }

      Codespaces::GetFailoverDetails
        .expects(:call)
        .with(region: org_codespace.location, user: @user, vscs_target: org_codespace.vscs_target, is_copilot_workspace: org_codespace.copilot_workspace?)
        .returns(failover_details)

      Codespaces::VscsClient
        .any_instance.expects(:start_environment)
        .with(org_codespace.guid, has_entries(failover_details: failover_details))
        .returns([Faraday::Response.new(body: "{}"), nil])

      FakeKredz.with_no_secrets do
        Codespaces::Start.call(org_codespace, user: @user, session: @user_session)
      end
    end
  end

  context "sends uses storage v2", skip_enterprise: true do
    test "does not pass use storage v2 if not in environment data" do
      org = create(:organization)
      org_repo = create(:private_repository, owner: org)
      org_codespace = create(:codespace, repository: org_repo, owner: @user)

      Codespaces::VscsClient
      .any_instance.expects(:start_environment)
      .with(org_codespace.guid, has_entries(uses_storage_v2: false))
      .returns([Faraday::Response.new(body: "{}"), nil])

      FakeKredz.with_no_secrets do
        Codespaces::Start.call(org_codespace, user: @user, session: @user_session)
      end
    end

    test "passes use storage v2 if its in environment data" do
      org = create(:organization)
      org_repo = create(:private_repository, owner: org)

      GitHub.flipper[:codespaces_developer].enable(@user)
      org_codespace = create(:codespace, repository: org_repo, owner: @user)

      environment_data = org_codespace.environment_data.merge({ features: { useStorageV2: "true" } })
      org_codespace.stubs(:environment_data).returns(Codespaces::Environment.new(environment_data))

      Codespaces::VscsClient
      .any_instance.expects(:start_environment)
      .with(org_codespace.guid, has_entries(uses_storage_v2: true))
      .returns([Faraday::Response.new(body: "{}"), nil])

      FakeKredz.with_no_secrets do
        Codespaces::Start.call(org_codespace, user: @user, session: @user_session)
      end
    end
  end

  context "setting auto_shutdown_delay_minutes", skip_enterprise: true do
    test "is passed to vscs" do
      org = create(:organization)
      org_repo = create(:private_repository, owner: org)
      org_codespace = create(:codespace, repository: org_repo, owner: @user)

      Codespaces::VscsClient
        .any_instance.expects(:start_environment)
        .with(org_codespace.guid, has_entries(auto_shutdown_delay_minutes: 30))
        .returns([Faraday::Response.new(body: "{}"), nil])

      FakeKredz.with_no_secrets do
        Codespaces::Start.call(org_codespace, user: @user, session: @user_session)
      end
    end

    test "sets has_max_idle_timeout_policy_override" do
      org = create(:codespaces_organization, plan: GitHub::Plan.business)
      org_repo = create(:private_repository, owner: org)
      org_codespace = create(:codespace, repository: org_repo, owner: @user)

      policy_group_org = create(:policy_group, owner: org, name: "all repos")
      create(:policy_group_membership, policy_group: policy_group_org, target: org)
      create(:policy_constraint, policy_group: policy_group_org, maximum_value: 10, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_IDLE_TIMEOUT)

      Codespaces::VscsClient
        .any_instance.expects(:start_environment)
        .with(org_codespace.guid, has_entries(auto_shutdown_delay_minutes: 10))
        .returns([Faraday::Response.new(body: "{}"), nil])

      FakeKredz.with_no_secrets do
        Codespaces::Start.call(org_codespace, user: @user, session: @user_session)
        assert Codespaces::MaximumIdleTimeoutPolicy.has_override?(org_codespace.id)
      end
    end

    test "does not set has_max_idle_timeout_policy_override" do
      GitHub.flipper[:codespaces_billing_free].enable
      org = create(:codespaces_organization, plan: GitHub::Plan.free)
      org_repo = create(:private_repository, owner: org)
      org_codespace = create(:codespace, repository: org_repo, owner: @user, environment_data: { auto_shutdown_delay_minutes: 10 })

      policy_group_org = create(:policy_group, owner: org, name: "all repos")
      create(:policy_group_membership, policy_group: policy_group_org, target: org)
      create(:policy_constraint, policy_group: policy_group_org, maximum_value: 240, allowed_values: nil, name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_IDLE_TIMEOUT)

      Codespaces::VscsClient
        .any_instance.expects(:start_environment)
        .with(org_codespace.guid, has_entries(auto_shutdown_delay_minutes: 10))
        .returns([Faraday::Response.new(body: "{}"), nil])

      FakeKredz.with_no_secrets do
        Codespaces::Start.call(org_codespace, user: @user, session: @user_session)
        refute Codespaces::MaximumIdleTimeoutPolicy.has_override?(org_codespace.id)
      end
    end
  end

  test "instruments hydro event", skip_enterprise: true do
    FakeKredz.with_no_secrets do
      Codespaces::Start.call(@codespace, user: @user, session: @user_session)

      message = {
        codespace: Hydro::EntitySerializer.codespace(@codespace),
        actor: Hydro::EntitySerializer.user(@codespace.owner)
      }

      assert_hydro_published(message, schema: "github.codespaces.v0.CodespaceStart")
    end
  end

  context "handling invalid SKU transitions", skip_enterprise: true do
    test "doesn't blow up if we get valid JSON back from the VSCS API on a 4xx" do
      FakeKredz.with_no_secrets do
        codespace = create(:codespace, owner: @user)
        FakeVSOServer.reset!
        FakeVSOServer.environments = [
          {
            "id" => codespace.guid,
          }
        ]
        FakeVSOServer.fake_responses = [
          {
            endpoint: "/api/v1/environments/#{codespace.guid}/start",
            status: 400,
            body: { huh: "weird" }.to_json,
          }
        ]
        assert_raises Codespaces::VscsClient::BadResponseError do
          Codespaces::Start.call(codespace, user: @user, session: @user_session, request_cascade_token: true)
        end
      end
    end

    test "doesn't blow up if we get an integer from the VSCS API on a 4xx" do
      FakeKredz.with_no_secrets do
        codespace = create(:codespace, owner: @user)
        FakeVSOServer.reset!
        FakeVSOServer.environments = [
          {
            "id" => codespace.guid,
          }
        ]
        FakeVSOServer.fake_responses = [
          {
            endpoint: "/api/v1/environments/#{codespace.guid}/start",
            status: 400,
            body: "7",
          }
        ]
        assert_raises Codespaces::VscsClient::BadResponseError do
          Codespaces::Start.call(codespace, user: @user, session: @user_session, request_cascade_token: true)
        end
      end
    end

    test "retries the start API call if we receive an invalid SKU transition under certain circumstances" do
      FakeKredz.with_no_secrets do
        codespace = create(:codespace, :stopped_in_vscs)
        codespace.async_operations.update_storage.create(op_started_at: 5.minutes.ago, op_ended_at: 1.minute.ago)
        FakeVSOServer.reset!
        FakeVSOServer.environments = [
          {
            "id" => codespace.guid,
            "state" => Codespaces::Vscs::State::STARTING,
            "skuName" => "largePremiumLinux", # Different SKU than we have on the codespace on our side.
            "connection" => "connection data",
            "skuDisplayName" => "Premium (Linux): 16 cores, 32 GB RAM, 128 GB storage",
            "accessToken" => "supersecret"
          }
        ]
        FakeVSOServer.fake_responses = [
          {
            endpoint: "/api/v1/environments/#{codespace.guid}/start",
            status: 400,
            body: "Cannot transition to SKU #{codespace.sku_name}",
          },
          {
            endpoint: "/api/v1/environments/#{codespace.guid}/start",
            status: 200,
            body: {
              id: codespace.guid,
              state: Codespaces::Vscs::State::STARTING,
              skuName: "largePremiumLinux",
            }.to_json
          }
        ]
        assert_nothing_raised do
          Codespaces::Start.call(codespace, user: codespace.owner, session: create(:user_session, user: codespace.owner), request_cascade_token: true)
        end
        assert_equal "largePremiumLinux", codespace.reload.sku_name
        # Ensure that we're reserving the right capacity and not what we originally reserved for the initial SKU.
        concurrency_policy = Codespaces::ConcurrencyPolicy.new(codespace.owner, billable_owner: codespace.billable_owner)
        report = concurrency_policy.send(:concurrency_report)
        assert_equal 1, report[:instances]
        assert_equal 16, report[:cores]
      end
    end

    test "doesn't retry if there wasn't as SKU mismatch" do
      FakeKredz.with_no_secrets do
        other_codespace = create(:codespace, owner: @user)
        other_codespace.async_operations.update_storage.create(op_started_at: 5.minutes.ago, op_ended_at: 1.minute.ago)
        FakeVSOServer.reset!
        FakeVSOServer.environments = [
          {
            "id" => other_codespace.guid,
            "state" => "Shutdown",
            "skuName" => other_codespace.sku_name,
            "connection" => "connection data",
            "skuDisplayName" => "Premium (Linux): 16 cores, 32 GB RAM, 128 GB storage",
            "accessToken" => "supersecret"
          }
        ]
        FakeVSOServer.fake_responses = [
          {
            endpoint: "/api/v1/environments/#{other_codespace.guid}/start",
            status: 400,
            body: "Cannot transition to SKU #{other_codespace.sku_name}",
          }
        ]
        assert_raises Codespaces::VscsClient::BadResponseError do
          Codespaces::Start.call(other_codespace, user: @user, session: @user_session, request_cascade_token: true)
        end
      end
    end

    test "doesn't retry if we haven't done a storage resize (even if there's a SKU mismatch)" do
      FakeKredz.with_no_secrets do
        other_codespace = create(:codespace, owner: @user)
        FakeVSOServer.reset!
        FakeVSOServer.environments = [
          {
            "id" => other_codespace.guid,
            "state" => "Shutdown",
            "skuName" => "premiumLinux", # Different SKU than we have on the codespace on our side.
            "connection" => "connection data",
            "skuDisplayName" => "Premium (Linux): 16 cores, 32 GB RAM, 128 GB storage",
            "accessToken" => "supersecret"
          }
        ]
        FakeVSOServer.fake_responses = [
          {
            endpoint: "/api/v1/environments/#{other_codespace.guid}/start",
            status: 400,
            body: "Cannot transition to SKU #{other_codespace.sku_name}",
          }
        ]
        assert_raises Codespaces::VscsClient::BadResponseError do
          Codespaces::Start.call(other_codespace, user: @user, session: @user_session, request_cascade_token: true)
        end
      end
    end
  end

  context "async operation" do
    test "attempting to start codespace with pending async operation raises exception for blocking pending operations", skip_enterprise: true do
      create(:codespaces_async_operation, codespace: @codespace, operation: :update_storage)
      assert_raise Codespaces::AsyncOperation::PendingError do # rubocop:todo Style/Minitest
        FakeKredz.with_no_secrets do
          Codespaces::Start.call(@codespace, user: @user, session: @user_session)
        end
      end
    end

    test "is an accepted parameter" do
      FakeKredz.with_no_secrets do
        Codespaces::Start.call(@codespace, user: @user, session: @user_session, operation: create(:codespaces_async_operation, codespace: @codespace, operation: :start_codespace))
      end
    end

    test "is marked started by successful client call" do
      operation = create(:codespaces_async_operation, codespace: @codespace, operation: :start_codespace)
      operation.expects(:mark_as_started).once
      operation.expects(:mark_as_ended).never
      FakeKredz.with_no_secrets do
        Codespaces::Start.call(@codespace, user: @user, session: @user_session, operation: operation)
      end
    end

    test "is marked ended by concurrency limit hit" do
      operation = create(:codespaces_async_operation, codespace: @codespace, operation: :start_codespace)
      operation.expects(:mark_as_ended).once
      @codespace.expects(:consuming_compute?).returns(false)
      Codespaces::ConcurrencyPolicy.any_instance.expects(:reserve_capacity).yields(false)
      assert_raises Codespaces::ConcurrencyLimitError do
        FakeKredz.with_no_secrets do
          Codespaces::Start.call(@codespace, user: @user, session: @user_session, operation: operation)
        end
      end
    end

    test "is marked ended by inaccessible error" do
      operation = create(:codespaces_async_operation, codespace: @codespace, operation: :start_codespace)
      operation.expects(:mark_as_ended).once
      @codespace.expects(:accessible?).returns(false)
      assert_raises Codespaces::Start::InaccessibleError do
        FakeKredz.with_no_secrets do
          Codespaces::Start.call(@codespace, user: @user, session: @user_session, operation: operation)
        end
      end
    end

    test "is marked ended when we exit early because the codespace is already running and we skipped the API call" do
      operation = create(:codespaces_async_operation, codespace: @codespace, operation: :start_codespace)
      @codespace.stubs(consuming_compute?: true)
      Codespaces::TokenCache.expects(:read_codespace_cascade_token).returns("foobar")

      FakeKredz.with_no_secrets do
        Codespaces::Start.call(@codespace, user: @user, session: @user_session, operation: operation, require_connection: false)
      end
      assert operation.reload.op_ended_at
      assert_dogstats_increment(1, "codespaces.async_operations.ended", tags: ["operation:start_codespace", "state:ended"])
    end

    test "is marked succeeded when the environment is already available but an API call was made" do
      GitHub.flipper[:codespaces_start_already_started].enable
      operation = create(:codespaces_async_operation, codespace: @codespace, operation: :start_codespace)
      FakeKredz.with_no_secrets do
        FakeVSOServer.environments = [
          {
            "id" => @codespace.guid,
            "state" => "Available",
          }
        ]
        Codespaces::Start.call(@codespace, user: @user, session: @user_session, operation: operation, require_connection: false)
      end
      assert operation.reload.op_ended_at
      assert_dogstats_increment(1, "codespaces.async_operations.ended", tags: ["operation:start_codespace", "state:succeeded"])
    end
  end

  context "instrumentation" do
    test "instrumentation is sent when performed_in_background is false", skip_enterprise: true do
      events = subscribe "codespaces.connect"

      FakeKredz.with_no_secrets do
        Codespaces::Start.call(@codespace, user: @user, session: @user_session)
      end

      assert_equal events.length, 1
    end

    test "instrumentation is not sent when performed_in_background is true", skip_enterprise: true do
      events = subscribe "codespaces.connect"

      FakeKredz.with_no_secrets do
        Codespaces::Start.call(@codespace, user: @user, session: @user_session, performed_in_background: true)
      end

      assert_equal events.length, 0
    end

    test "start_environment instrumentation is sent when performed_in_background is false and not already started", skip_enterprise: true do
      @codespace.update(environment_data: { state: Codespaces::Vscs::State::SHUTDOWN })
      events = subscribe "codespaces.start_environment"

      FakeKredz.with_no_secrets do
        Codespaces::Start.call(@codespace, user: @user, session: @user_session)
      end

      assert_equal events.length, 1
    end

    test "start_environment instrumentation is not sent when performed_in_background is true and not already started", skip_enterprise: true do
      events = subscribe "codespaces.start_environment"

      FakeKredz.with_no_secrets do
        Codespaces::Start.call(@codespace, user: @user, session: @user_session, performed_in_background: true)
      end

      assert_equal events.length, 0
    end

    test "start_environment instrumentation is not sent when performed_in_background is false and codespace is already started", skip_enterprise: true do
      @codespace.update(environment_data: { state: Codespaces::Vscs::State::CONSUMING_COMPUTE_STATES.first })
      events = subscribe "codespaces.start_environment"

      FakeKredz.with_no_secrets do
        Codespaces::Start.call(@codespace, user: @user, session: @user_session)
      end

      assert_equal events.length, 0
    end
  end

  context "copilot workspace" do
    context "copilot_workspace_allowed validation" do
      test "raises error if copilot workspace is not allowed" do
        GitHub.flipper[:copilot_workspace].disable(@user)
        cw_codespace = create(:copilot_workspace, owner: @user)

        assert_raises Codespaces::CopilotWorkspaceFeatureDisabledError do
          FakeKredz.with_no_secrets do
            Codespaces::Start.call(cw_codespace, user: @user, session: @user_session)
          end
        end
      end

      test "does not raise error if user has :copilot_workspace feature flag" do
        cw_codespace = create(:copilot_workspace, owner: @user)
        GitHub.flipper[:copilot_workspace].enable(@user)
        FakeVSOServer.reset!
        FakeVSOServer.environments = [
          {
            "id" => cw_codespace.guid,
            "state" => "Shutdown",
          }
        ]
        assert_nothing_raised do
          FakeKredz.with_no_secrets do
            Codespaces::Start.call(cw_codespace, user: @user, session: @user_session)
          end
        end
      end
    end
  end

  class FakeConcurrencyPolicy
    def initialize(allow_count:)
      @count = 0
      @allow_count = allow_count
    end

    def reserve_capacity(...)
      @count += 1
      yield(@count <= @allow_count)
    end
  end
end unless GitHub.enterprise?
