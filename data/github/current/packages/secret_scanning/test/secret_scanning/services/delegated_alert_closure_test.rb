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
    test "raises ServiceError if request already exists" do
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
      resource_id = "5"
      comment = "Help!"
      reason = "false_positive"
      frozen_time = Time.utc(2020, 1, 1, 1, 1, 1, 100).freeze
      called_closure_exemption_request_id = T.let(nil, T.nilable(Integer))

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
          expected_metadata = { "reason" => reason }
          assert_equal expected_metadata, request.metadata
          assert_equal comment, request.requester_comment

          assert_equal request.id, called_closure_exemption_request_id
        end
      end
    end
  end

  context "existing_alert_closure_requests" do
    test "returns nil if there are no existing requests" do
      assert_nil @service.existing_alert_closure_request(@repo, "resource_identifier")
    end

    test "returns an array of requests if there are existing requests" do
      # Ideally there will only be 1 closure request per repo and resource ID, but the DB technically allows more.
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
      # We should get the first (original) request
      assert_equal request1, @service.existing_alert_closure_request(@repo, "resource_identifier")

    end
  end

end
