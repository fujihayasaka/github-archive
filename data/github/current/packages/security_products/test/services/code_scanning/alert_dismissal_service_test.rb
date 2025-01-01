# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../../helpers/advanced_security_skus_base_test"

module CodeScanning
  class AlertDismissalServiceTest < AdvancedSecuritySKUsBaseTest
    include AuditLog::IntegrationTestHelpers

    fixtures do
      GitHub::Enterprise.ensure_business!

      @owner = create(:user)
      @org = create(:business_plus_org, admin: @owner)

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
      do_purchase(entity: @org, actor: @user)
      enable_service(@repo, actor: @user)
      ::Repository.any_instance.stubs(:code_scanning_usable?).returns(true)
      # SecurityProduct::ServiceManager.new(@repo).toggle_services(@user, services_to_enable: [[:advanced_security, { force?: true }]])

      GitHub.stubs(:code_scanning_enabled?).returns(true)
      GitHub.stubs(:actions_enabled?).returns(true)
    end

    context "enable/disable" do
      skus_test "can_enable? returns true if all conditions are met" do
        can_enable = CodeScanning::AlertDismissalService.new(@repo).can_enable?(actor: @user, options: {})

        assert_equal true, can_enable.value
      end

      test "can_enable? returns false if advanced security is disabled" do
        owner = create(:user)
        org = create(:business_plus_org, admin: owner)
        repo = create(:private_repository, owner: org, from_example: :simple)
        assert repo.advanced_security_products_bundled?

        can_enable = CodeScanning::AlertDismissalService.new(repo).can_enable?(actor: @user, options: {})
        assert_equal false, can_enable.value
        assert_equal :advanced_security_disabled, can_enable.error
      end

      skus_test "can_enable? returns false if code security is disabled" do
        ::Repository.any_instance.stubs(:advanced_security_products_bundled?).returns(false)

        owner = create(:user)
        org = create(:business_plus_org, admin: owner)
        repo = create(:private_repository, owner: org, from_example: :simple)

        refute repo.advanced_security_products_bundled?

        can_enable = CodeScanning::AlertDismissalService.new(repo).can_enable?(actor: @user, options: {})
        assert_equal false, can_enable.value
        assert_equal :code_security_disabled, can_enable.error
      end

      test "enabled? returns true if delegated alert dismissal is enabled" do
        alert_dismissal_service = CodeScanning::AlertDismissalService.new(@repo)
        CodeScanningRepositoryConfig.new(@repo).enable_code_scanning_delegated_alert_dismissal_settings(actor: @user)

        assert_equal true, alert_dismissal_service.enabled?
      end

      test "enabled? returns false if delegated alert dismissal is not enabled" do
        alert_dismissal_service = CodeScanning::AlertDismissalService.new(@repo)

        assert_equal false, alert_dismissal_service.enabled?
      end

      test "enabled? returns false if repo owner is not org" do
        user_repo = create(:private_repository, owner: @user, from_example: :simple)

        alert_dismissal_service = CodeScanning::AlertDismissalService.new(user_repo)

        assert_equal false, alert_dismissal_service.enabled?
      end

      test "on_enable has no error if all conditions are met" do
        alert_dismissal_service = CodeScanning::AlertDismissalService.new(@repo)

        result = alert_dismissal_service.on_enable(actor: @user, options: {})

        assert_nil result.error
      end

      test "on_disable returns no error" do
        alert_dismissal_service = CodeScanning::AlertDismissalService.new(@repo)

        result = alert_dismissal_service.on_disable(actor: @user, options: {})

        assert_nil result.error
      end

      test "on_enable fails if there is an enforced security configuration" do
        alert_dismissal_service = CodeScanning::AlertDismissalService.new(@repo)
        security_configuration = create(
          :security_configuration,
          :enforced,
          target: @org,
          enable_ghas: true,
          code_scanning_delegated_alert_dismissal: "disabled",
          dependabot_alerts: "disabled",
          dependency_graph: "disabled",
          dependabot_security_updates: "disabled",
        )
        repository_security_configuration = create(
          :repository_security_configuration,
          security_configuration:,
          repository: @repo,
          state: "enforced"
        )

        result = alert_dismissal_service.enable(actor: @user, options: {})
        assert_equal result.error, :security_configuration_enforced
        result = alert_dismissal_service.disable(actor: @user, options: {})
        assert_nil result.error
      end

      test "on_disable fails if there is an enforced security configuration" do
        alert_dismissal_service = CodeScanning::AlertDismissalService.new(@repo)
        security_configuration = create(
          :security_configuration,
          :enforced,
          target: @org,
          enable_ghas: true,
          code_scanning_delegated_alert_dismissal: "enabled",
          dependabot_alerts: "disabled",
          dependency_graph: "disabled",
          dependabot_security_updates: "disabled",
        )
        repository_security_configuration = create(
          :repository_security_configuration,
          security_configuration:,
          repository: @repo,
          state: "enforced"
        )


        result = alert_dismissal_service.disable(actor: @user, options: {})
        assert_equal result.error, :security_configuration_enforced
        result = alert_dismissal_service.enable(actor: @user, options: {})
        assert_nil result.error
      end
    end

    context ".request_dismissal" do
      test "raises when the requester is not valid" do
        assert_raises CodeScanning::AlertDismissalService::AlertDismissalError do
          CodeScanning::AlertDismissalService.request_dismissal(
            repository: @repo,
            requester: @user,
            alert_number: @alert_number,
            resolution: Turboscan::Proto::ResultResolution::WONT_FIX,
            resolution_note: nil,
            pr_review_thread_id: nil,
            campaign_id: nil,
          )
        end
      end

      test "raises when there is a pending request" do
        create_request
        assert_raises CodeScanning::AlertDismissalService::AlertDismissalError do
          CodeScanning::AlertDismissalService.request_dismissal(
            repository: @repo,
            requester: @owner,
            alert_number: @alert_number,
            resolution: Turboscan::Proto::ResultResolution::WONT_FIX,
            resolution_note: nil,
            pr_review_thread_id: nil,
            campaign_id: nil,
          )
        end
      end

      test "creates a new request when there are previous non pending requests" do
        request = create_request
        CodeScanning::AlertDismissalService.reject_request(repository: @repo, reviewer: @security_manager, request_id: T.must(request.id))

        GitHub::Turboscan.stubs(:alert).returns(Twirp::ClientResp.new(
          data: Turboscan::Proto::AlertResponse.new(
            result: Turboscan::Proto::Result.new(
              message_text: "XSS Vulnerability",
              rule: Turboscan::Proto::Rule.new(
                short_description: "XSS Vulnerability",)
            ))
        ))

        events = assert_performed_audit_entries(count: 1, only: "code_scanning.alert_closure_requested") do
          assert CodeScanning::AlertDismissalService.request_dismissal(
            repository: @repo,
            requester: @owner,
            alert_number: @alert_number,
            resolution: Turboscan::Proto::ResultResolution::WONT_FIX,
            resolution_note: nil,
            pr_review_thread_id: nil,
            campaign_id: nil,
          )
        end

        existing_requests = Exemptions::ExemptionRequest.where(
          request_type: CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE,
          repository: @repo,
          resource_identifier: CodeScanning::AlertDismissalService.resource_identifier(repository: @repo, alert_number: @alert_number),
        ).order(created_at: :desc).all
        assert_equal 2, existing_requests.length

        req = existing_requests[0]
        assert_equal "XSS Vulnerability", req.metadata["alert_title"]

        assert_subset_hash(
          {
            repo_id: @repo.id,
            action: "code_scanning.alert_closure_requested",
            actor: @owner.display_login,
            dismissal_request_id: req.id,
            alert_number: @alert_number,
          },
          events.first
        )
      end
    end

    context "reject_request" do
      test "works" do
        request = create_request

        events = assert_performed_audit_entries(count: 1, only: "code_scanning.alert_closure_denied") do
          assert CodeScanning::AlertDismissalService.reject_request(repository: @repo, reviewer: @security_manager, request_id: T.must(request.id))
        end

        request.reload
        assert_equal Exemptions::ExemptionEvaluator::EvaluationResult::Rejected, request.compute_status
        assert_equal "rejected", request.status

        assert_subset_hash(
          {
            repo_id: @repo.id,
            action: "code_scanning.alert_closure_denied",
            actor: @security_manager.display_login,
            dismissal_request_id: request.id,
            alert_number: @alert_number
          },
          events.first
        )
      end

      test "raises when there is no request" do
        assert_raises CodeScanning::AlertDismissalService::AlertDismissalError do
          CodeScanning::AlertDismissalService.reject_request(repository: @repo, reviewer: @security_manager, request_id: 1)
        end
      end

      test "raises when the request is not pending" do
        # setup
        request = create_request
        Turbocassette.use("code-scanning/set-status-close-with-approver") do
          assert CodeScanning::AlertDismissalService.approve_request(repository: @repo, reviewer: @security_manager, request_id: T.must(request.id))
        end
        request.reload
        assert_equal Exemptions::ExemptionEvaluator::EvaluationResult::Approved, request.compute_status

        # test
        assert_raises CodeScanning::AlertDismissalService::AlertDismissalError do
          CodeScanning::AlertDismissalService.reject_request(repository: @repo, reviewer: @security_manager, request_id: T.must(request.id))
        end
        request.reload
        assert_equal Exemptions::ExemptionEvaluator::EvaluationResult::Approved, request.compute_status
      end

      test "raises when the reviewer is not valid" do
        request = create_request

        assert_raises CodeScanning::AlertDismissalService::AlertDismissalError do
          CodeScanning::AlertDismissalService.reject_request(repository: @repo, reviewer: @user, request_id: T.must(request.id))
        end
        request.reload
        assert_equal Exemptions::ExemptionEvaluator::EvaluationResult::Pending, request.compute_status
      end
    end

    context "approve_request" do
      test "raises when there is no request" do
        assert_raises CodeScanning::AlertDismissalService::AlertDismissalError do
          CodeScanning::AlertDismissalService.approve_request(repository: @repo, reviewer: @security_manager, request_id: 1)
        end
      end

      test "raises when the request is not pending" do
        # setup
        request = create_request
        Exemptions::ExemptionResponse.reject!(request, @security_manager)
        request.reload
        assert_equal Exemptions::ExemptionEvaluator::EvaluationResult::Rejected, request.compute_status

        # test
        assert_raises CodeScanning::AlertDismissalService::AlertDismissalError do
          CodeScanning::AlertDismissalService.approve_request(repository: @repo, reviewer: @security_manager, request_id: T.must(request.id))
        end
        request.reload
        assert_equal Exemptions::ExemptionEvaluator::EvaluationResult::Rejected, request.compute_status
      end

      test "raises when the reviewer is not valid" do
        request = create_request

        assert_raises CodeScanning::AlertDismissalService::AlertDismissalError do
          CodeScanning::AlertDismissalService.approve_request(repository: @repo, reviewer: @user, request_id: T.must(request.id))
        end
        request.reload
        assert_equal Exemptions::ExemptionEvaluator::EvaluationResult::Pending, request.compute_status
      end

      test "works" do
        request = create_request

        events = assert_performed_audit_entries(count: 1, only: "code_scanning.alert_closure_approved") do
          Turbocassette.use("code-scanning/set-status-close-with-approver") do
            assert CodeScanning::AlertDismissalService.approve_request(repository: @repo, reviewer: @security_manager, request_id: T.must(request.id))
          end
        end

        request.reload
        assert_equal Exemptions::ExemptionEvaluator::EvaluationResult::Approved, request.compute_status
        assert_equal "approved", request.status

        assert_subset_hash(
          {
            repo_id: @repo.id,
            action: "code_scanning.alert_closure_approved",
            actor: @security_manager.display_login,
            dismissal_request_id: request.id,
            alert_number: @alert_number
          },
          events.first
        )
      end

      test "reads the pr_review_thread_id correctly" do
        request = create_request

        CodeScanning::AlertDismissalService.expects(:close_alert)
        .with(
          repository: @repo,
          alert_number: @alert_number,
          resolution: Turboscan::Proto::ResultResolution::WONT_FIX,
          resolver: @owner,
          resolution_note: nil,
          pr_review_thread_id: nil,
          campaign_id: nil,
          reviewer: @security_manager,
        )
        CodeScanning::AlertDismissalService.approve_request(repository: @repo, reviewer: @security_manager, request_id: T.must(request.id))

        request = create_request
        request.metadata["pr_review_thread_id"] = "1"
        request.save!
        CodeScanning::AlertDismissalService.expects(:close_alert)
        .with(
          repository: @repo,
          alert_number: @alert_number,
          resolution: Turboscan::Proto::ResultResolution::WONT_FIX,
          resolver: @owner,
          resolution_note: nil,
          pr_review_thread_id: 1,
          campaign_id: nil,
          reviewer: @security_manager,
        )
        CodeScanning::AlertDismissalService.approve_request(repository: @repo, reviewer: @security_manager, request_id: T.must(request.id))
      end
    end

    context "has_pending_request?" do
      test "returns false if no requests" do
        CodeScanning::AlertDismissalService.new(@repo).on_enable(actor: @user, options: {})

        assert_not CodeScanning::AlertDismissalService.has_pending_request?(repository: @repo, alert_number: @alert_number)
      end

      test "returns true if there is a pending request" do
        CodeScanning::AlertDismissalService.new(@repo).on_enable(actor: @user, options: {})

        create_request
        assert CodeScanning::AlertDismissalService.has_pending_request?(repository: @repo, alert_number: @alert_number)
      end

      test "returns false if delegated dismissal is disabled" do
        create_request
        assert_not CodeScanning::AlertDismissalService.has_pending_request?(repository: @repo, alert_number: @alert_number)
      end

      test "returns false if there is a non pending request" do
        CodeScanning::AlertDismissalService.new(@repo).on_enable(actor: @user, options: {})

        request = create_request
        Exemptions::ExemptionResponse.reject!(request, @security_manager)

        assert_not CodeScanning::AlertDismissalService.has_pending_request?(repository: @repo, alert_number: @alert_number)
      end

      test "returns true if there is a pending and a non pending request" do
        CodeScanning::AlertDismissalService.new(@repo).on_enable(actor: @user, options: {})

        request = create_request
        Exemptions::ExemptionResponse.reject!(request, @security_manager)

        request = create_request

        assert CodeScanning::AlertDismissalService.has_pending_request?(repository: @repo, alert_number: @alert_number)
      end
    end

    context "get_org_reviewer_ids" do
      test "works" do
        direct_sec_man = create(:user)
        @org.add_member(direct_sec_man)
        @org.grant_org_role(assignee: direct_sec_man, role: Role.security_manager_role)

        reviewers = CodeScanning::AlertDismissalService.get_org_reviewer_ids(@org)
        assert_equal 3, reviewers.length
        assert_same_elements [@owner.id, @security_manager.id, direct_sec_man.id], reviewers
      end
    end

    context "has_rejected_request?" do
      test "returns false if no requests" do
        assert_not CodeScanning::AlertDismissalService.has_rejected_request?(repository: @repo, alert_number: @alert_number)
      end

      test "returns true if there is a rejected request" do
        request = create_request
        Exemptions::ExemptionResponse.reject!(request, @security_manager)

        assert CodeScanning::AlertDismissalService.has_rejected_request?(repository: @repo, alert_number: @alert_number)
      end

      test "returns true if there is a pending request and rejected request (rejected request is the last request)" do
        create_request

        travel 1.minute
        request = create_request
        Exemptions::ExemptionResponse.reject!(request, @security_manager)

        assert CodeScanning::AlertDismissalService.has_rejected_request?(repository: @repo, alert_number: @alert_number)
      end

      test "returns false if there is a rejected request and pending request (pending request is the last request)" do
        request = create_request
        Exemptions::ExemptionResponse.reject!(request, @security_manager)

        travel 1.minute
        request = create_request

        assert_not CodeScanning::AlertDismissalService.has_rejected_request?(repository: @repo, alert_number: @alert_number)
      end
    end

    def create_request
      Exemptions::ExemptionRequest.create!(
        resource_owner: @repo,
        requester: @owner,
        repository: @repo,
        resource_identifier: CodeScanning::AlertDismissalService::resource_identifier(repository: @repo, alert_number: @alert_number),
        request_type: CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE,
        expires_at: 1.week.from_now,
        metadata: {
          "resolution": Turboscan::Proto::ResultResolution::WONT_FIX.to_s,
          "alert_number": @alert_number.to_s,
        },
      )
    end
  end
end
