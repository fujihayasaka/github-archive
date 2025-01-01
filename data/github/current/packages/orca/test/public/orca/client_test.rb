# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../../orca_test_helpers"

class OrcaClientTest < GitHub::TestCase
  include OrcaTestHelpers

  fixtures do
    @test_base_url = "http://example.com/twirp"
    @test_hmac_key = "key"

    @organization = create(:organization)
    @repository = create(:private_repository, owner: @organization)
    @admin = @organization.admin
    @pipeline_id = SecureRandom.uuid
    @use_private_telemetry = true
  end

  context ".actor" do
    test "returns an actor" do
      expected = GitHub::Orca::Actor.new(
        id: @admin.id,
        login: @admin.display_login,
        analytics_tracking_id: @admin.analytics_tracking_id
      )

      assert_equal expected, Orca::Client.actor(@admin)
    end
  end

  context ".repository" do
    test "returns a repository" do
      expected = GitHub::Orca::Repository.new(
        id: @repository.id,
        name: @repository.name,
        clone_url: @repository.clone_url
      )

      assert_equal expected, Orca::Client.repository(@repository)
    end
  end

  context ".organization" do
    test "returns an organization" do
      expected = GitHub::Orca::Organization.new(
        id: @organization.id,
        login: @organization.login,
        analytics_tracking_id: @organization.analytics_tracking_id
      )

      assert_equal expected, Orca::Client.organization(@organization)
    end
  end

  context ".client_error?" do
    # Copied from
    # https://github.com/arthurnn/twirp-ruby/blob/main/lib/twirp/error.rb
    # The HTTP status codes are not used in the test, they are just here for
    # understanding the library's intentions for the code.
    [
      [:canceled,            408, false], # Request Timeout
      [:invalid_argument,    400, true],  # Bad Request
      [:malformed,           400, false], # Bad Request
      [:deadline_exceeded,   408, false], # Request Timeout
      [:not_found,           404, true],  # Not Found
      [:bad_route,           404, false], # Not Found
      [:already_exists,      409, false], # Conflict
      [:permission_denied,   403, false], # Forbidden
      [:unauthenticated,     401, false], # Unauthorized
      [:resource_exhausted,  429, false], # Too Many Requests
      [:failed_precondition, 412, false], # Precondition Failed
      [:aborted,             409, false], # Conflict
      [:out_of_range,        400, false], # Bad Request

      [:internal,            500, false], # Internal Server Error
      [:unknown,             500, false], # Internal Server Error
      [:unimplemented,       501, false], # Not Implemented
      [:unavailable,         503, false], # Service Unavailable
      [:data_loss,           500, false], # Internal Server Error
    ].each do |code, _, expected|
      test "returns #{expected} for #{code}" do
        twirp_error = Twirp::Error.new(code, "message")
        assert_equal expected, Orca::Client.client_error?(twirp_error)
      end
    end
  end

  context "#initialize" do
    test "creates a new client with the given HMAC key" do
      client = Orca::Client.new(
        base_url: @test_base_url,
        hmac_key: @test_hmac_key
      )

      assert_equal @test_base_url, client.base_url
    end

    test "raises an error if the base URL is not given" do
      assert_raises(ArgumentError, /base_url cannot be empty/) do
        Orca::Client.new(
          base_url: "",
          hmac_key: @test_hmac_key
        )
      end
    end

    test "raises an error if the HMAC key is not given" do
      assert_raises(ArgumentError, /hmac_key cannot be empty/) do
        Orca::Client.new(
          base_url: @test_base_url,
          hmac_key: ""
        )
      end
    end
  end

  context "#start_customization" do
    test "issues a StartCustomization Twirp RPC request and returns the pipeline ID" do
      pipeline_id = SecureRandom.uuid
      @languages = [Linguist::Language.find_by_name("Ruby")]
      stub_orca_start_customization_request(
          actor: @admin,
          organization: @organization,
          repositories: [@repository],
          languages: @languages,
          use_private_telemetry: @use_private_telemetry,
          response: GitHub::Orca::StartCustomizationResponse.new(
          pipeline_id: pipeline_id,
        ))

      result = Orca.client.start_customization(
        actor: @admin,
        organization: @organization,
        repositories: [@repository],
        languages: @languages,
        use_private_telemetry: @use_private_telemetry
      )

      assert_equal pipeline_id, result
    end

    test "client error" do
      @languages = [Linguist::Language.find_by_name("Ruby")]
      stub_orca_start_customization_request(
          actor: @admin,
          organization: @organization,
          repositories: [@repository],
          languages: @languages,
          use_private_telemetry: @use_private_telemetry,
          response: Twirp::Error.invalid_argument("foo.bar cannot be empty"))

      assert_raises(Orca::Client::ClientError, "error") do
        Orca.client.start_customization(
          actor: @admin,
          organization: @organization,
          repositories: [@repository],
          languages: @languages,
          use_private_telemetry: @use_private_telemetry
        )
      end
    end

    test "server error" do
      @languages = [Linguist::Language.find_by_name("Ruby")]
      stub_orca_start_customization_request(
          actor: @admin,
          organization: @organization,
          repositories: [@repository],
          languages: @languages,
          use_private_telemetry: @use_private_telemetry,
          response: Twirp::Error.internal("server error"))

      assert_raises(Orca::Client::ServerError, "error") do
        Orca.client.start_customization(
          actor: @admin,
          organization: @organization,
          repositories: [@repository],
          languages: @languages,
          use_private_telemetry: @use_private_telemetry
        )
      end
    end
  end

  context "#get_pipeline_details" do
    test "returns pipeline details" do
      stub_orca_request "GetPipelineDetails",
        GitHub::Orca::GetPipelineDetailsRequest.new(
          pipeline_id: @pipeline_id
        ),
        GitHub::Orca::GetPipelineDetailsResponse.new(
          pipeline_details: GitHub::Orca::PipelineDetails.new(
            pipeline: GitHub::Orca::Pipeline.new(
              id: @pipeline_id,
              organization: Orca::Client.organization(@organization),
              completed_at: Time.now.to_s,
            )
          )
        )

      pipeline_details = Orca.client.get_pipeline_details(
        pipeline_id: @pipeline_id
      )
      pipeline = T.must(pipeline_details).pipeline
      assert_equal @pipeline_id, T.must(pipeline).id
    end

    test "pipeline not found" do
      stub_orca_request "GetPipelineDetails",
        GitHub::Orca::GetPipelineDetailsRequest.new(
          pipeline_id: @pipeline_id
        ),
        Twirp::Error.not_found("pipeline not found")

      actual = Orca.client.get_pipeline_details(
        pipeline_id: @pipeline_id
      )
      assert_nil actual
    end

    test "client error" do
      stub_orca_request "GetPipelineDetails",
        GitHub::Orca::GetPipelineDetailsRequest.new(
          pipeline_id: ""
        ),
        Twirp::Error.invalid_argument("pipeline_id cannot be empty")

      assert_raises(Orca::Client::ClientError, "error") do
        Orca.client.get_pipeline_details(
          pipeline_id: ""
        )
      end
    end

    test "server error" do
      stub_orca_request "GetPipelineDetails",
        GitHub::Orca::GetPipelineDetailsRequest.new(
          pipeline_id: @pipeline_id
        ),
        Twirp::Error.internal("internal error")

      assert_raises(Orca::Client::ServerError, "error") do
        Orca.client.get_pipeline_details(
          pipeline_id: @pipeline_id
        )
      end
    end
  end

  context "#get_latest_pipeline_details" do
    test "returns latest pipeline details" do
      stub_orca_request "GetLatestPipelineDetails",
        GitHub::Orca::GetLatestPipelineDetailsRequest.new(
          organization_name: @organization.display_login,
          organization: Orca::Client.organization(@organization),
          status: GitHub::Orca::PipelineStatus::PIPELINE_STATUS_UNSPECIFIED
        ),
        GitHub::Orca::GetLatestPipelineDetailsResponse.new(
          pipeline_details: GitHub::Orca::PipelineDetails.new(
            pipeline: GitHub::Orca::Pipeline.new(
              id: @pipeline_id,
              organization: Orca::Client.organization(@organization),
              completed_at: Time.now.to_s,
            )
          )
        )

      pipeline_details = Orca.client.get_latest_pipeline_details(
        organization: @organization
      )
      pipeline = T.must(pipeline_details).pipeline
      assert_equal @pipeline_id, T.must(pipeline).id
    end

    test "returns latest pipeline details with status" do
      stub_orca_request "GetLatestPipelineDetails",
        GitHub::Orca::GetLatestPipelineDetailsRequest.new(
          organization_name: @organization.display_login,
          organization: Orca::Client.organization(@organization),
          status: GitHub::Orca::PipelineStatus::PIPELINE_STATUS_COMPLETED
        ),
        GitHub::Orca::GetLatestPipelineDetailsResponse.new(
          pipeline_details: GitHub::Orca::PipelineDetails.new(
            pipeline: GitHub::Orca::Pipeline.new(
              id: @pipeline_id,
              organization: Orca::Client.organization(@organization),
              completed_at: Time.now.to_s,
            )
          )
        )

      pipeline_details = Orca.client.get_latest_pipeline_details(
        organization: @organization,
        status: GitHub::Orca::PipelineStatus::PIPELINE_STATUS_COMPLETED,
      )
      pipeline = T.must(pipeline_details).pipeline
      assert_equal @pipeline_id, T.must(pipeline).id
    end

    test "pipeline not found" do
      stub_orca_request "GetLatestPipelineDetails",
        GitHub::Orca::GetLatestPipelineDetailsRequest.new(
          organization: Orca::Client.organization(@organization),
          organization_name: @organization.display_login,
          status: GitHub::Orca::PipelineStatus::PIPELINE_STATUS_UNSPECIFIED
        ),
        Twirp::Error.not_found("pipeline not found")

      actual = Orca.client.get_latest_pipeline_details(
        organization: @organization
      )
      assert_nil actual
    end

    test "client error" do
      stub_orca_request "GetLatestPipelineDetails",
        GitHub::Orca::GetLatestPipelineDetailsRequest.new(
          organization_name: "",
          organization: Orca::Client.organization(Organization.new(login: "")),
          status: GitHub::Orca::PipelineStatus::PIPELINE_STATUS_UNSPECIFIED
        ),
        Twirp::Error.invalid_argument("organization_name cannot be empty")

      assert_raises(Orca::Client::ClientError, "error") do
        Orca.client.get_latest_pipeline_details(
          organization: Organization.new(login: "")
        )
      end
    end

    test "server error" do
      stub_orca_request "GetLatestPipelineDetails",
        GitHub::Orca::GetLatestPipelineDetailsRequest.new(
          organization_name: @organization.display_login,
          organization: Orca::Client.organization(@organization),
          status: GitHub::Orca::PipelineStatus::PIPELINE_STATUS_UNSPECIFIED
        ),
        Twirp::Error.internal("internal error")

      assert_raises(Orca::Client::ServerError, "error") do
        Orca.client.get_latest_pipeline_details(
          organization: @organization
        )
      end
    end
  end

  context "#get_rate_limit" do
    test "returns the rate limit" do
      stub_orca_request "GetLatestPipelineDetails",
        GitHub::Orca::GetLatestPipelineDetailsRequest.new(
          organization_name: @organization.display_login,
          organization: Orca::Client.organization(@organization),
          status: GitHub::Orca::PipelineStatus::PIPELINE_STATUS_UNSPECIFIED
        ),
        GitHub::Orca::GetLatestPipelineDetailsResponse.new(
          pipeline_details: GitHub::Orca::PipelineDetails.new(
            pipeline: GitHub::Orca::Pipeline.new(
              id: @pipeline_id,
              organization: Orca::Client.organization(@organization),
              completed_at: Time.now.to_s,
            )
          ),
          rate_limit: GitHub::Orca::RateLimitDetails.new(
            is_rate_limited: false,
          )
        )
      actual = Orca.client.get_rate_limit(
        organization: @organization
      )
      refute actual.nil?
      refute T.must(actual).is_rate_limited
    end

    test "caches rate limit when get_latest_pipeline_details is called" do
      # Only stub the first request
      stub_orca_request "GetLatestPipelineDetails",
        GitHub::Orca::GetLatestPipelineDetailsRequest.new(
          organization_name: @organization.display_login,
          organization: Orca::Client.organization(@organization),
          status: GitHub::Orca::PipelineStatus::PIPELINE_STATUS_UNSPECIFIED
        ),
        GitHub::Orca::GetLatestPipelineDetailsResponse.new(
          pipeline_details: GitHub::Orca::PipelineDetails.new(
            pipeline: GitHub::Orca::Pipeline.new(
              id: @pipeline_id,
              organization: Orca::Client.organization(@organization),
              completed_at: Time.now.to_s,
            )
          ),
          rate_limit: GitHub::Orca::RateLimitDetails.new(
            is_rate_limited: false,
          )
        )
      # Call get latest pipeline details first
      Orca.client.get_latest_pipeline_details(
        organization: @organization
      )
      # Now call get rate limit, which should not make another request
      actual = Orca.client.get_rate_limit(
        organization: @organization
      )
      refute actual.nil?
      refute T.must(actual).is_rate_limited
    end

    test "cache is org aware" do
      # Only stub the first request
      stub_orca_request "GetLatestPipelineDetails",
        GitHub::Orca::GetLatestPipelineDetailsRequest.new(
          organization_name: @organization.display_login,
          organization: Orca::Client.organization(@organization),
          status: GitHub::Orca::PipelineStatus::PIPELINE_STATUS_UNSPECIFIED
        ),
        GitHub::Orca::GetLatestPipelineDetailsResponse.new(
          pipeline_details: GitHub::Orca::PipelineDetails.new(
            pipeline: GitHub::Orca::Pipeline.new(
              id: @pipeline_id,
              organization: Orca::Client.organization(@organization),
              completed_at: Time.now.to_s,
            )
          ),
          rate_limit: GitHub::Orca::RateLimitDetails.new(
            is_rate_limited: false,
          )
        )
      # Call get latest pipeline details first
      Orca.client.get_latest_pipeline_details(
        organization: @organization
      )
      # A different org should require a seperate call
      org2 = create(:organization)
      stub_orca_request "GetLatestPipelineDetails",
        GitHub::Orca::GetLatestPipelineDetailsRequest.new(
          organization_name: org2.display_login,
          organization: Orca::Client.organization(org2),
          status: GitHub::Orca::PipelineStatus::PIPELINE_STATUS_UNSPECIFIED
        ),
        GitHub::Orca::GetLatestPipelineDetailsResponse.new(
          pipeline_details: GitHub::Orca::PipelineDetails.new(
            pipeline: GitHub::Orca::Pipeline.new(
              id: @pipeline_id,
              organization: Orca::Client.organization(@organization),
              completed_at: Time.now.to_s,
            )
          ),
          rate_limit: GitHub::Orca::RateLimitDetails.new(
            is_rate_limited: true,
          )
        )
      # Now call get rate limit, which should not make another request
      actual = Orca.client.get_rate_limit(
        organization: org2
      )
      refute actual.nil?
      assert T.must(actual).is_rate_limited
    end

    test "caches rate limit when start_customization is called" do
      @languages = [Linguist::Language.find_by_name("Ruby")]
      stub_orca_start_customization_request(
          actor: @admin,
          organization: @organization,
          repositories: [@repository],
          languages: @languages,
          use_private_telemetry: @use_private_telemetry,
          response: GitHub::Orca::StartCustomizationResponse.new(
            pipeline_id: @pipeline_id,
            rate_limit: GitHub::Orca::RateLimitDetails.new(
              is_rate_limited: false,
            )
        ))

      Orca.client.start_customization(
        actor: @admin,
        organization: @organization,
        repositories: [@repository],
        languages: @languages,
        use_private_telemetry: @use_private_telemetry
      )
      # Now call get rate limit, which should not make another request
      actual = Orca.client.get_rate_limit(
        organization: @organization
      )
      refute actual.nil?
      refute T.must(actual).is_rate_limited
    end
  end


  test "get pipelines" do
    stub_orca_request "GetPipelines",
      GitHub::Orca::GetPipelinesRequest.new(
        organization: Orca::Client.organization(@organization),
      ),
      GitHub::Orca::GetPipelinesResponse.new(
          pipelines: [GitHub::Orca::Pipeline.new(
            id: @pipeline_id,
            organization: Orca::Client.organization(@organization),
            completed_at: Time.now.to_s,
          )]
      )
    pipelines = Orca.client.get_pipelines(
      organization: @organization
    )
    refute_nil pipelines
    assert_equal T.must(pipelines).pipelines.count, 1
  end
end
