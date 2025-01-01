# typed: true
# frozen_string_literal: true

require "test_helper"

class AlertsServiceTest < GitHub::TestCase
  include SecretScanning::Errors

  ResponseMock = Struct.new(:data, :error)
  ResponseErrorMock = Struct.new(:msg)

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:user, login: "repoadmin", email: "repoadmin@github.com")
    @org = create(:business_plus_organization, name: "org", admin: @user)
    @repo = create(:private_repository, owner: @org)

    @alerts_service = SecretScanning::Services::AlertsService.new
  end

  context "#get_alert" do
    test "invokes get token rpc call" do
      GitHub.flipper[SecretScanning::Features::FeatureFlagHelper::FeatureFlags::GENERIC_SECRETS_BLOCK].disable
      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token).with(equals(get_token_request)).once

      @alerts_service.get_alert(@repo, @user, 1, 1)
    end

    test "invokes wrap token rpc call if token is valid" do
      GitHub.flipper[SecretScanning::Features::FeatureFlagHelper::FeatureFlags::GENERIC_SECRETS_BLOCK].disable
      token = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.now.utc,
        updated_at: Time.now.utc,
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(path: "foo.txt"),
        id: 1,
        label: "token_api",
        number: 1,
        repository_id: @repo.id,
        slug: "token_api",
        token_type: "TOKEN_API"
      )

      data = GitHub::Proto::SecretScanning::Api::V2::GetTokenResponse.new(token: token)
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:get_token).with(equals(get_token_request)).returns(
        ResponseMock.new(
          data: data
        )
      )

      expected_wrapped_token = GitHub::TokenScanning::Service::Token.new(token, @repo, data)

      GitHub::TokenScanning::Service::Client.expects(:wrap_token).with(token, @repo, data).once.returns(expected_wrapped_token)

      @alerts_service.get_alert(@repo, @user, 1, 1)
    end
  end

  context "#resolve_token" do
    test "resolves alert with valid resolution and no dismissal comment" do
      GitHub::TokenScanning::Service::Client.expects(:to_resolution).with("revoked").returns(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REVOKED).once

      GitHub::TokenScanning::Service::Client.any_instance.expects(:resolve_tokens).with(equals(resolve_token_request(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REVOKED))).returns(ResponseMock.new(error: nil)).once

      @alerts_service.resolve_alert(repository: @repo, user: @user, numbers: [1], resolution: "revoked", numbers_to_slugs: { 1 => "test_slug" })
    end

    test "resolves alert with valid resolution and a dismissal comment" do
      GitHub::TokenScanning::Service::Client.expects(:to_resolution).with("false_positive").returns(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::FALSE_POSITIVE).once

      dismissal_comment = "This alert isn't true"

      GitHub::TokenScanning::Service::Client.any_instance.expects(:resolve_tokens).with(equals(resolve_token_request(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::FALSE_POSITIVE, dismissal_comment))).returns(ResponseMock.new(error: nil)).once

      @alerts_service.resolve_alert(repository: @repo, user: @user, numbers: [1], resolution: "false_positive", dismissal_comment: dismissal_comment, numbers_to_slugs: { 1 => "test_slug" })
    end

    test "dismissal comment with non UTF-8 characters is normalized before resolution" do
      GitHub::TokenScanning::Service::Client.expects(:to_resolution).with("false_positive").returns(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::FALSE_POSITIVE).once

      dismissal_comment = "κόσμε"

      GitHub::TokenScanning::Service::Client.any_instance.expects(:resolve_tokens).with(equals(resolve_token_request(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::FALSE_POSITIVE, dismissal_comment))).returns(ResponseMock.new(error: nil)).once

      @alerts_service.resolve_alert(repository: @repo, user: @user, numbers: [1], resolution: "false_positive", dismissal_comment: dismissal_comment, numbers_to_slugs: { 1 => "test_slug" })
    end

    test "dismissal comment is nil if alert is reopened" do
      GitHub::TokenScanning::Service::Client.expects(:to_resolution).with("reopened").returns(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REOPENED).once

      GitHub::TokenScanning::Service::Client.any_instance.expects(:resolve_tokens).with(equals(resolve_token_request(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REOPENED))).returns(ResponseMock.new(error: nil)).once

      @alerts_service.resolve_alert(repository: @repo, user: @user, numbers: [1], resolution: "reopened", dismissal_comment: "this comment should be nil", numbers_to_slugs: { 1 => "test_slug" })
    end

    test "returns unprocessable entity if resolution is invalid" do
      GitHub::TokenScanning::Service::Client.expects(:to_resolution).with("invalid").returns(nil).once
      GitHub::TokenScanning::Service::Client.any_instance.expects(:resolve_tokens).never

      response = @alerts_service.resolve_alert(repository: @repo, user: @user, numbers: [1], resolution: "invalid", numbers_to_slugs: { 1 => "test_slug" })

      assert_equal  UnprocessableEntity, response.class
    end

    test "returns timeout error when response is nil" do
      GitHub::TokenScanning::Service::Client.expects(:to_resolution).with("revoked").returns(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REVOKED).once

      GitHub::TokenScanning::Service::Client.any_instance.stubs(:resolve_tokens).with(equals(resolve_token_request(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REVOKED))).returns(nil)

      response = @alerts_service.resolve_alert(repository: @repo, user: @user, numbers: [1], resolution: "revoked", numbers_to_slugs: { 1 => "test_slug" })

      assert_equal SecretScanning::Errors::ServiceError, response.class
      assert_equal "timeout when resolving token", response.message
    end

    test "returns error with message when present" do
      GitHub::TokenScanning::Service::Client.expects(:to_resolution).with("revoked").returns(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REVOKED).once

      GitHub::TokenScanning::Service::Client.any_instance.stubs(:resolve_tokens).with(equals(resolve_token_request(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REVOKED))).returns(ResponseMock.new(error: ResponseErrorMock.new(msg: "something went wrong")))

      response = @alerts_service.resolve_alert(repository: @repo, user: @user, numbers: [1], resolution: "revoked", numbers_to_slugs: { 1 => "test_slug" })

      assert_equal SecretScanning::Errors::ServiceError, response.class
      assert_equal "something went wrong", response.message
    end

    test "audit entry is logged for resolution" do
      GitHub::TokenScanning::Service::Client.expects(:to_resolution).with("revoked").returns(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REVOKED).once
      GitHub::TokenScanning::Service::Client.any_instance.expects(:resolve_tokens).with(equals(resolve_token_request(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REVOKED))).returns(ResponseMock.new(error: nil))

      GitHub.expects(:instrument).with(
        "secret_scanning_alert.resolve",
        {
          user: @user,
          repo: @repo,
          number: 1,
          org: @org,
          resolution: :revoked,
          secret_type: "test_slug",
        }
      ).once

      @alerts_service.resolve_alert(repository: @repo, user: @user, numbers: [1], resolution: "revoked", numbers_to_slugs: { 1 => "test_slug" })
    end

    test "audit entry is logged for reopening" do
      GitHub::TokenScanning::Service::Client.expects(:to_resolution).with("reopened").returns(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REOPENED).once
      GitHub::TokenScanning::Service::Client.any_instance.expects(:resolve_tokens).with(equals(resolve_token_request(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REOPENED))).returns(ResponseMock.new(error: nil))

      GitHub.expects(:instrument).with(
        "secret_scanning_alert.reopen",
        {
          user: @user,
          repo: @repo,
          number: 1,
          org: @org,
          secret_type: "test_slug",
        }
      ).once

      @alerts_service.resolve_alert(repository: @repo, user: @user, numbers: [1], resolution: "reopened", numbers_to_slugs: { 1 => "test_slug" })
    end
  end

  context "#report" do
    test "reports alert" do
      data = GitHub::Proto::SecretScanning::Api::V2::ReportTokenResponse.new
      GitHub::TokenScanning::Service::Client.any_instance.expects(:report_token).with(equals(report_token_request)).returns(ResponseMock.new(error: nil, data: data)).once

      error = @alerts_service.report_alert(repository: @repo, user: @user, number: 1)
      assert_nil error
    end

    test "returns generic error when response is nil" do
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:report_token).with(equals(report_token_request)).returns(nil)

      response = @alerts_service.report_alert(repository: @repo, user: @user, number: 1)

      assert_equal SecretScanning::Errors::ServiceError, response.class
      assert_equal "An error has occurred while reporting the alert", response.message
    end

    test "returns error with message when present" do
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:resolve_tokens).with(equals(resolve_token_request(GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REVOKED))).returns(ResponseMock.new(error: ResponseErrorMock.new(msg: "something went wrong"), data: nil)).once

      response = @alerts_service.resolve_alert(repository: @repo, user: @user, numbers: [1], resolution: "revoked", numbers_to_slugs: { 1 => "test_slug" })

      assert_equal SecretScanning::Errors::ServiceError, response.class
      assert_equal "something went wrong", response.message
    end
  end

  context "#alert_timeline" do
    test "returns timeline data" do
      data = GitHub::Proto::SecretScanning::Api::V2::GetTimelineResponse.new(
        total_number_of_events: 0,
        latest_ascending: GitHub::Proto::SecretScanning::Api::V2::TimelineSegment.new(
          events: [],
          cursor: nil
        ),
        earliest_ascending: GitHub::Proto::SecretScanning::Api::V2::TimelineSegment.new(
          events: [],
          cursor: nil
        ),
      )

      GitHub::TokenScanning::Service::Client.any_instance.expects(:get_timeline).with({
        repository_id: @repo.id,
        token_alert_number: 1
      }).returns(ResponseMock.new(data: data)).once

      response = @alerts_service.get_alert_timeline(@repo, @user, get_token_for_timeline)

      assert_equal data, response
    end

    test "returns error if response is nil" do
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:get_timeline).with({
        repository_id: @repo.id,
        token_alert_number: 1
      }).returns(nil).once

      Failbot.expects(:report).once

      response = @alerts_service.get_alert_timeline(@repo, @user, get_token_for_timeline)

      assert_nil response
    end

    test "returns error if response contains it" do
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:get_timeline).with({
        repository_id: @repo.id,
        token_alert_number: 1
      }).returns(ResponseMock.new(error: ResponseErrorMock.new(msg: "something went wrong"))).once

      Failbot.expects(:report).once

      response = @alerts_service.get_alert_timeline(@repo, @user, get_token_for_timeline)

      assert_nil response
    end

    test "returns error if data is nil" do
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:get_timeline).with({
        repository_id: @repo.id,
        token_alert_number: 1
      }).returns(ResponseMock.new(data: nil)).once

      Failbot.expects(:report).once

      response = @alerts_service.get_alert_timeline(@repo, @user, get_token_for_timeline)

      assert_nil response
    end
  end

  context "#on_demand_check" do
    test "returns on demand check" do
      last_checked = Time.now
      data = GitHub::Proto::SecretScanning::Api::V2::GetTokenValidationStatusResponse.new(
          validity: :TOKEN_VALIDITY_ACTIVE,
          validation_details: {
            validity_last_checked: last_checked
          }
      )
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:get_token_validation_status).with(equals({
        repository_id: @repo.id,
        token_number: 1,
        requested_by_user_id: @user.id
      })).returns(ResponseMock.new(data: data)).once

      response = @alerts_service.validate_token_on_demand(@repo, @user, 1)

      assert_equal :TOKEN_VALIDITY_ACTIVE, response.validity
      assert_equal last_checked, response.validity_last_checked
      assert_empty response.token_groups
    end
    test "returns error if response is nil" do
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:get_token_validation_status).with(equals({
        repository_id: @repo.id,
        token_number: 1,
        requested_by_user_id: @user.id
      })).returns(ResponseMock.new(data: nil)).once

      Failbot.expects(:report).once

      response = @alerts_service.validate_token_on_demand(@repo, @user, 1)

      assert_nil response
    end
  end

  def get_token_request
    {
      repository_id: @repo.id,
      token_id: 1,
      include_commit_oids: true,
      include_included_locations: true,
      limit: SecretScanning::Services::AlertsService::LOCATIONS_PER_PAGE,
      page: 1,
      feature_flags: ["stop_using_has_valid_locations"],
      include_location_count: true,
      include_config_filters: true
    }
  end

  def resolve_token_request(resolution, dismissal_comment = nil)
    {
      repository_id: @repo.id,
      token_numbers: [1],
      resolver_id: @user.id,
      resolution: resolution,
      default_branch_name: @repo.default_branch,
      feature_flags: [],
      resolution_comment: dismissal_comment
    }
  end

  def report_token_request
    {
      repository_id: @repo.id,
      number: 1,
      reporting_user_id: @user.id
    }
  end

  def get_token_for_timeline
    token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
      created_at: Time.parse("2023-03-10"),
      first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
      id: 1,
      label: "GitHub Personal Access Token",
      token_type: "GITHUB",
      repository_id: @repo.id,
      number: 1,
    )

    GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
  end
end
