# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventExemptionRequestEventTest < GitHub::TestCase
  include HookEventTestHelper
  include RulesEngine::RefUpdateTestHelper
  include FineGrainedPermissionsTestHelper

  fixtures do
    enable_feature_flag(:push_ruleset_exemption_request)
    enable_feature_flag(:secret_scanning_exemption_request)

    @org_admin = create(:user)
    @org = create(:business_plus_organization, name: "org", admin: @org_admin)
    @org_repo = create(:private_repository, owner: @org)
    @org_member = create(:user)
    @org.add_member(@org_member)
    @org_repo.add_member(@org_member, action: :write)
    grant_custom_role(user: @org_member, target: @org_repo, fgps: [:view_secret_scanning_alerts, :resolve_secret_scanning_alerts])
    grant_custom_role(user: @org_member, target: @org_repo, fgps: [:read_code_scanning, :write_code_scanning])

    push_ruleset = create(:repository_ruleset, :org_admin_bypass_any, target: "push", source: @org_repo)
    config = create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 10
    })
    ref_update = create_branch_update(@org_repo, name: "main")
    run = RuleEngine::RuleRun.failure(rule_config: config, ref_update: ref_update, message: "failed")
    @suite = RuleEngine::RuleSuite.for_ref_update(ref_update: ref_update, rule_runs: [run], actor: @org_member)
    @suite.save!
  end

  setup do
    # Make Code Scanning available
    ::Repository.any_instance.stubs(:code_scanning_usable?).returns(true)
  end

  # Iterate through integration tests for each request type
  # While the instrumentation is the same and is called from the ExemptionRequest class
  # we have independent hook events for each request type
  [
    "push_ruleset_bypass",
    SecretScanning::Constants::EXEMPTION_REQUEST_TYPE,
    SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE,
    CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE,
  ].each do |request_type|
    test "#{request_type} required attributes" do
      event = if request_type == "push_ruleset_bypass"
        Hook::Event::ExemptionRequestPushRulesetEvent
      elsif request_type == SecretScanning::Constants::EXEMPTION_REQUEST_TYPE
        Hook::Event::ExemptionRequestSecretScanningEvent
      elsif request_type == SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE
        Hook::Event::DismissalRequestSecretScanningEvent
      elsif request_type == CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE
        Hook::Event::DismissalRequestCodeScanningEvent
      end
      assert_event_required_attributes event, :action, :exemption_request_id
    end

    context "#{request_type} #actor" do
      test "#{request_type} is present for exemption request event" do
        assert_equal build_exemption_request_event(request_type:).actor, @exemption_request.requester
      end

      test "#{request_type} is present for exemption request response event" do
        assert_equal build_exemption_request_response_event(request_type:).actor, @exemption_response.reviewer
      end
    end

    context "#{request_type} #target_repository" do
      test "#{request_type} is present for exemption request event" do
        assert_equal build_exemption_request_event(request_type:).target_repository, @exemption_request.repository
      end

      test "#{request_type} is present for exemption request response event" do
        assert_equal build_exemption_request_response_event(request_type:).target_repository, @exemption_request.repository
      end
    end

    context "#{request_type} #target_organization" do
      test "#{request_type} is present for exemption request event for repo owned by org" do
        assert_equal build_exemption_request_event(request_type:).target_organization, @exemption_request.repository.organization
      end

      test "#{request_type} is present for exemption response event for repo owned by org" do
        assert_equal build_exemption_request_response_event(request_type:).target_organization, @exemption_request.repository.organization
      end
    end

    context "#{request_type} #exemption_request" do
      test "#{request_type} is present for exemption request event" do
        assert_equal build_exemption_request_event(request_type:).exemption_request, @exemption_request
      end

      test "#{request_type} is present for exemption response event" do
        assert_equal build_exemption_request_response_event(request_type:).exemption_request, @exemption_request
      end
    end

    context "#{request_type} #exemption_response" do
      test "#{request_type} is not present for exemption request event" do
        assert_nil build_exemption_request_event(request_type:).exemption_response
      end

      test "#{request_type} is present for exemption response event" do
        assert_equal build_exemption_request_response_event(request_type:).exemption_response, @exemption_response
      end
    end
  end

  test "app with invalid permissions cannot subscribe to exemption_request_push_ruleset hook" do
    app = build(:integration, :with_active_hook, default_permissions: { "contents" => :read }, default_events: %w(exemption_request_push_ruleset))
    refute app.valid?
    assert_includes app.errors.full_messages, "Default events are not supported by permissions: exemption_request_push_ruleset"
  end

  test "app with valid permissions can subscribe to exemption_request_push_ruleset hook" do
    app = build(:integration, :with_active_hook, default_permissions: { "administration" => :read }, default_events: %w(exemption_request_push_ruleset))
    assert app.valid?
  end

  test "app with invalid permissions cannot subscribe to exemption_request_secret_scanning hook" do
    app = build(:integration, :with_active_hook, default_permissions: { "contents" => :read }, default_events: %w(exemption_request_secret_scanning))
    refute app.valid?
    assert_includes app.errors.full_messages, "Default events are not supported by permissions: exemption_request_secret_scanning"
  end

  test "app with valid permissions can subscribe to exemption_request_secret_scanning hook" do
    app = build(:integration, :with_active_hook, default_permissions: { "secret_scanning_alerts" => :read }, default_events: %w(exemption_request_secret_scanning))
    assert app.valid?
  end

  test "app with invalid permissions cannot subscribe to dismissal_request_secret_scanning hook" do
    app = build(:integration, :with_active_hook, default_permissions: { "contents" => :read }, default_events: %w(dismissal_request_secret_scanning))
    refute app.valid?
    assert_includes app.errors.full_messages, "Default events are not supported by permissions: dismissal_request_secret_scanning"
  end

  test "app with valid permissions can subscribe to dismissal_request_secret_scanning hook" do
    app = build(:integration, :with_active_hook, default_permissions: { "secret_scanning_alerts" => :read }, default_events: %w(dismissal_request_secret_scanning))
    assert app.valid?
  end

  test "app with invalid permissions cannot subscribe to dismissal_request_code_scanning hook" do
    app = build(:integration, :with_active_hook, default_permissions: { "contents" => :read }, default_events: %w(dismissal_request_code_scanning))
    refute app.valid?
    assert_includes app.errors.full_messages, "Default events are not supported by permissions: dismissal_request_code_scanning"
  end

  test "app with valid permissions can subscribe to dismissal_request_code_scanning hook" do
    app = build(:integration, :with_active_hook, default_permissions: { "security_events" => :read }, default_events: %w(dismissal_request_code_scanning))
    assert app.valid?
  end

  def exemption_request(request_type:)
    if request_type == CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE
      metadata = {
        "alert_number": "7",
        "resolution": "2"
      }
    end

    @exemption_request ||= Exemptions::ExemptionRequest.create!(
      resource_owner: @suite,
      requester: @org_member,
      resource_identifier: @suite.after_oid,
      repository: @suite.repository,
      request_type:,
      metadata:,
    )
  end

  def exemption_response(request_type:)
    @exemption_response ||= Exemptions::ExemptionResponse.create!(
      exemption_request: exemption_request(request_type:),
      reviewer: @org_admin,
      status: :approved
    )
  end

  def build_exemption_request_event(request_type:)
    event = if request_type == "push_ruleset_bypass"
      Hook::Event::ExemptionRequestPushRulesetEvent
    elsif request_type == SecretScanning::Constants::EXEMPTION_REQUEST_TYPE
      Hook::Event::ExemptionRequestSecretScanningEvent
    elsif request_type == SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE
      Hook::Event::DismissalRequestSecretScanningEvent
    elsif request_type == CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE
      Hook::Event::DismissalRequestCodeScanningEvent
    end
    return nil if event.nil?
    event.new(actor_id: exemption_request(request_type:).requester_id, action: :created, exemption_request_id: exemption_request(request_type:).id)
  end

  def build_exemption_request_response_event(request_type:)
    event = if request_type == "push_ruleset_bypass"
      Hook::Event::ExemptionRequestPushRulesetEvent
    elsif request_type == SecretScanning::Constants::EXEMPTION_REQUEST_TYPE
      SecretScanning::Services::DelegatedBypassService.expects(:can_review_bypass_request?).with(@org_repo, @org_admin).returns([true, ""])
      Hook::Event::ExemptionRequestSecretScanningEvent
    elsif request_type == SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE
      Hook::Event::DismissalRequestSecretScanningEvent
    elsif request_type == CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE
      Hook::Event::DismissalRequestCodeScanningEvent
    end
    return nil if event.nil?
    event.new(actor_id: exemption_response(request_type:).reviewer_id, action: :response_submitted, exemption_request_id: exemption_request(request_type:).id, exemption_response_id: exemption_response(request_type:).id)
  end
end
