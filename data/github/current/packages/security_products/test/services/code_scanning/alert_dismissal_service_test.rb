# typed: true
# frozen_string_literal: true

require "test_helper"

module CodeScanning
  class AlertDismissalServiceTest < GitHub::TestCase

    fixtures do
      GitHub::Enterprise.ensure_business!

      @owner = create(:user)
      @org = create(:organization, admin: @owner)

      @security_managers_team = create :public_team, organization: @org, name: "Security Managers"
      ::SecurityProduct::SecurityManagerRole.grant_to_team!(@security_managers_team)

      @user = create(:user)

      @security_manager = create(:user)
      @org.add_member(@security_manager)
      @security_managers_team.add_member(@security_manager)

      @repo = create(:private_repository, owner: @org, from_example: :simple)

      @alert_number = 2
    end

    setup do
      ::Repository.any_instance.stubs(:code_scanning_usable?).returns(true)
    end

    context ".request_dismissal" do
      test "raises when the requester is not valid" do
        assert_raises ActiveRecord::RecordInvalid do
          CodeScanning::AlertDismissalService.request_dismissal(
            repository: @repo,
            requester: @user,
            alert_number: @alert_number,
            resolution: Turboscan::Proto::ResultResolution::WONT_FIX,
            resolution_note: nil,
          )
        end
      end

      test "returns false when there is a pending request" do
        request = create_request

        assert_not CodeScanning::AlertDismissalService.request_dismissal(
          repository: @repo,
          requester: @owner,
          alert_number: @alert_number,
          resolution: Turboscan::Proto::ResultResolution::WONT_FIX,
          resolution_note: nil,
        )
      end

      test "returns true when there are previous non pending requests" do
        request = create_request
        CodeScanning::AlertDismissalService.reject_request(repository: @repo, reviewer: @security_manager, request_id: T.must(request.id))

        assert CodeScanning::AlertDismissalService.request_dismissal(
          repository: @repo,
          requester: @owner,
          alert_number: @alert_number,
          resolution: Turboscan::Proto::ResultResolution::WONT_FIX,
          resolution_note: nil,
        )

        existing_requests = Exemptions::ExemptionRequest.where(
          request_type: CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE,
          repository: @repo,
          resource_identifier: CodeScanning::AlertDismissalService.resource_identifier(repository: @repo, alert_number: @alert_number),
        ).all
        assert_equal 2, existing_requests.length
      end
    end

    context "reject_request" do
      test "works" do
        request = create_request
        assert CodeScanning::AlertDismissalService.reject_request(repository: @repo, reviewer: @security_manager, request_id: T.must(request.id))

        request.reload
        assert_equal Exemptions::ExemptionEvaluator::EvaluationResult::Rejected, request.compute_status
      end

      test "returns false when there is no request" do
        assert_not CodeScanning::AlertDismissalService.reject_request(repository: @repo, reviewer: @security_manager, request_id: 1)
      end

      test "returns false when the request is not pending" do
        # setup
        request = create_request
        Exemptions::ExemptionResponse.approve!(request, @security_manager)
        request.reload
        assert_equal Exemptions::ExemptionEvaluator::EvaluationResult::Approved, request.compute_status

        # test
        assert_not  CodeScanning::AlertDismissalService.reject_request(repository: @repo, reviewer: @security_manager, request_id: T.must(request.id))
        request.reload
        assert_equal Exemptions::ExemptionEvaluator::EvaluationResult::Approved, request.compute_status
      end

      test "raises when the reviewer is not valid" do
        request = create_request

        assert_raises ActiveRecord::RecordInvalid do
          CodeScanning::AlertDismissalService.reject_request(repository: @repo, reviewer: @user, request_id: T.must(request.id))
        end
        request.reload
        assert_equal Exemptions::ExemptionEvaluator::EvaluationResult::Pending, request.compute_status
      end
    end

    context "approve_request" do
      test "returns false when there is no request" do
        assert_not CodeScanning::AlertDismissalService.approve_request(repository: @repo, reviewer: @security_manager, request_id: 1)
      end

      test "returns false when the request is not pending" do
        # setup
        request = create_request
        Exemptions::ExemptionResponse.reject!(request, @security_manager)
        request.reload
        assert_equal Exemptions::ExemptionEvaluator::EvaluationResult::Rejected, request.compute_status

        # test
        assert_not  CodeScanning::AlertDismissalService.approve_request(repository: @repo, reviewer: @security_manager, request_id: T.must(request.id))
        request.reload
        assert_equal Exemptions::ExemptionEvaluator::EvaluationResult::Rejected, request.compute_status
      end

      test "raises when the reviewer is not valid" do
        request = create_request

        assert_raises ActiveRecord::RecordInvalid do
          CodeScanning::AlertDismissalService.approve_request(repository: @repo, reviewer: @user, request_id: T.must(request.id))
        end
        request.reload
        assert_equal Exemptions::ExemptionEvaluator::EvaluationResult::Pending, request.compute_status
      end

      test "works" do
        request = create_request

        Turbocassette.use("code-scanning/set-status-close-1") do
          assert CodeScanning::AlertDismissalService.approve_request(repository: @repo, reviewer: @security_manager, request_id: T.must(request.id))
        end

        request.reload
        assert_equal Exemptions::ExemptionEvaluator::EvaluationResult::Approved, request.compute_status
      end
    end

    def create_request
      Exemptions::ExemptionRequest.create!(
        resource_owner: @repo,
        requester: @owner,
        repository: @repo,
        resource_identifier: CodeScanning::AlertDismissalService::resource_identifier(repository: @repo, alert_number: @alert_number),
        request_type: CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE,
        expires_at: 1.week.from_now.floor(0),
        metadata: {
          "resolution": "#{Turboscan::Proto::ResultResolution::WONT_FIX}",
          "alert_number": "#{@alert_number}",
        },
      )
    end
  end
end
