# typed: true
# frozen_string_literal: true

require "test_helper"

class DelegatedAlertClosuresServiceTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  fixtures do
    @business = create(:business)
    @admin = create(:user, login: "bizadmin")
    @org = create(:business_plus_org, admin: @admin, business: @business)
    @repo = create(:repository, owner: @org)
    @user = create(:user)
    @repo.add_member(@user)
  end

  setup do
    @service = SecretScanning::Services::DelegatedAlertClosuresService.new
    grant_custom_role(user: @user, target: @repo, fgps: [:view_secret_scanning_alerts, :resolve_secret_scanning_alerts])
  end

  context "create_alert_closure_request" do
    test "raises ServiceError if an open request already exists" do
      request = Exemptions::ExemptionRequest.create!(
        requester: @user,
        resource_owner: @repo,
        resource_identifier: "3",
        repository: @repo,
        request_type: SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE,
        expires_at: 1.week.from_now.floor(0),
        metadata: {
          "reason": "wont_fix"
        },
        requester_comment: "Help me"
      )
      error = assert_raises SecretScanning::Errors::ServiceError do
        @service.create_alert_closure_request(@repo, @user, request.resource_identifier, request.metadata["reason"], request.requester_comment)
      end
      assert_equal "A request to close this alert has already been made.", error.message
    end

    test "raises ServiceError if resource_id isn't an int" do
      error = assert_raises SecretScanning::Errors::ServiceError do
        @service.create_alert_closure_request(@repo, @user, "not an int", "tests", "comment")
      end
      assert_equal "resource ID must be an integer", error.message
    end

    test "raises ServiceError if TSS returns an error" do
      SecretScanning::Services::AlertsService.any_instance.expects(:update_token_with_closure_request_id).returns(SecretScanning::Errors::Error.new("TSS is down"))
      error = assert_raises SecretScanning::Errors::ServiceError do
        @service.create_alert_closure_request(@repo, @user, "4", "tests", "comment")
      end
      assert_equal "Unable to update closure request ID in TSS: TSS is down", error.message
    end

    test "creates a new request and updates TSS" do
      create_alert_closure_request_helper("5")
    end

    test "creates a new request even if there is an existing, cancelled request" do
      resource_id = "5"
      Exemptions::ExemptionRequest.create!(
        requester: @user,
        resource_owner: @repo,
        resource_identifier: resource_id,
        repository: @repo,
        request_type: SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE,
        expires_at: 1.week.from_now.floor(0),
        metadata: {
          "reason": "wont_fix"
        },
        requester_comment: "Help me",
        status: "cancelled"
      )
      create_alert_closure_request_helper(resource_id)
    end

    test "creates a new request even if there is an existing denied request" do
      resource_id = "5"
      request = Exemptions::ExemptionRequest.create!(
        requester: @user,
        resource_owner: @repo,
        resource_identifier: resource_id,
        repository: @repo,
        request_type: SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE,
        expires_at: 1.week.from_now.floor(0),
        metadata: {
          "reason": "wont_fix"
        },
        requester_comment: "Help me",
      )
      Exemptions::ExemptionResponse.reject!(request, @admin)
      create_alert_closure_request_helper(resource_id)
    end

    test "emits audit log entry" do
      resource_id = "6"
      comment = "Help!"
      reason = "false_positive"
      frozen_time = Time.utc(2020, 1, 1, 1, 1, 1, 100).freeze
      called_closure_exemption_request_id = T.let(nil, T.nilable(Integer))

      Exemptions::Evaluators::SecretScanningClosureRequestBypass.any_instance.expects(:is_valid_requester?).returns([true, nil])
      SecretScanning::Services::AlertsService.any_instance.expects(:update_token_with_closure_request_id).with do |repo, user, token_number, closure_request_id|
        assert_equal @repo, repo
        assert_equal @user, user
        assert_equal resource_id.to_i, token_number
        # Capture the closure request ID so we can assert it later
        called_closure_exemption_request_id = closure_request_id
      end.returns(nil)

      GitHub.stubs(:instrument).with("cache_get.spokes_adapter", any_parameters)
      GitHub.stubs(:instrument).with("sequence.next", any_parameters)
      GitHub.expects(:instrument).with(
        "secret_scanning_closure_request.create",
        {
          actor: @user,
          repo: @repo,
          org: @org,
          number: called_closure_exemption_request_id,
          alert_number: resource_id,
          reason:,
          comment:,
        }
      )

      request = @service.create_alert_closure_request(@repo, @user, resource_id, reason, comment)
    end
  end

  context "existing_alert_closure_requests" do
    test "returns nil if there are no existing requests" do
      assert_nil @service.existing_alert_closure_request(@repo, "resource_identifier")
    end

    test "returns the latest request if there are existing requests" do
      request1 = Exemptions::ExemptionRequest.create!(
        requester: @user,
        resource_owner: @repo,
        resource_identifier: "resource_identifier",
        repository: @repo,
        request_type: SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE,
        expires_at: 1.week.from_now.floor(0),
        metadata: {
          "reason": "wont_fix"
        },
        requester_comment: "Help me"
      )
      request2 = Exemptions::ExemptionRequest.create!(
        requester: @user,
        resource_owner: @repo,
        resource_identifier: "resource_identifier",
        repository: @repo,
        request_type: SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE,
        expires_at: 1.week.from_now.floor(0),
        metadata: {
          "reason": "wont_fix"
        },
        requester_comment: "Help me"
      )
      # We should get the latest request
      assert_equal request2, @service.existing_alert_closure_request(@repo, "resource_identifier")

    end
  end

  def create_alert_closure_request_helper(resource_id)
    comment = "Help!"
    reason = "false_positive"
    token_label = "Token API"
    frozen_time = Time.utc(2020, 1, 1, 1, 1, 1, 100).freeze
    called_closure_exemption_request_id = T.let(nil, T.nilable(Integer))


    SecretScanning::Services::AlertsService.any_instance.expects(:get_alert)
      .with(@repo, @user, resource_id.to_i, nil, include_related_alerts: false)
      .returns([GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: frozen_time,
        updated_at: frozen_time,
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(path: "foo.txt"),
        id: 1,
        label: token_label,
        number: 1,
        repository_id: @repo.id,
        slug: "token_api",
        token_type: "TOKEN_API"
      )])

    SecretScanning::Services::AlertsService.any_instance.expects(:update_token_with_closure_request_id).with do |repo, user, token_number, closure_request_id|
      assert_equal @repo, repo
      assert_equal @user, user
      assert_equal resource_id.to_i, token_number
      # Capture the closure request ID so we can assert it later
      called_closure_exemption_request_id = closure_request_id
    end.returns(nil)

    Timecop.freeze frozen_time do
      freeze_time do
        request = @service.create_alert_closure_request(@repo, @user, resource_id, reason, comment)

        assert_equal @user, request.requester
        assert_equal @repo, request.resource_owner
        assert_equal resource_id, request.resource_identifier
        assert_equal SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE, request.request_type
        assert_equal 1.week.from_now.floor(0), request.expires_at
        expected_metadata = { "reason" => reason, "alert_title" => token_label }
        assert_equal expected_metadata, request.metadata
        assert_equal comment, request.requester_comment

        assert_equal request.id, called_closure_exemption_request_id
      end
    end
  end


end
