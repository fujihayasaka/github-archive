# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventSecretScanningAlertEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @user = create(:user)
    @org = create(:organization, admin: @user)
    @repo = create(:private_repository, owner: @org)

    found_token = GitHub::TokenScanning::FoundToken.new(
      type: "some_type",
      token: SecureRandom.hex(32),
      url: "",
      report_url: "",
      path: "foo.txt",
      commit: SecureRandom.hex(20),
      blob: SecureRandom.hex(20),
      start_line: 1,
      end_line: 2,
      start_column: 3,
      end_column: 4,
      content_type: 1
    )
    @secret_result = TokenScanResult.create_from_found_token!(@repo, "some_type", found_token.token)
  end

  setup do
    Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
    SecurityProduct::AdvancedSecurity.any_instance.stubs(:enabled?).returns(true)
    GitHub::Turboscan::ManagedAnalyses.expects(:get_managed_analysis_info).at_least(0).returns(nil)

    SecretScanning::Features::Repo::TokenScanning.new(@repo).enable(actor: @user)
  end

  context "#repository_id" do
    test "is required" do
      assert_event_required_attributes Hook::Event::SecretScanningAlertEvent, :repository_id
    end
  end

  context "#action" do
    test "is required" do
      assert_event_required_attributes Hook::Event::SecretScanningAlertEvent, :action
    end

    test "returns the specified action" do
      assert_equal :created, event.action

      event = Hook::Event::SecretScanningAlertEvent.new(action: :resolved,
        repository_id: @repo.id, alert_number: @secret_result.number)
      assert_equal :resolved, event.action

      event = Hook::Event::SecretScanningAlertEvent.new(action: :reopened,
        repository_id: @repo.id, alert_number: @secret_result.number)
      assert_equal :reopened, event.action

      event = Hook::Event::SecretScanningAlertEvent.new(action: :revoked,
        repository_id: @repo.id, alert_number: @secret_result.number)
      assert_equal :revoked, event.action

      event = Hook::Event::SecretScanningAlertEvent.new(action: :publicly_leaked,
        repository_id: @repo.id, alert_number: @secret_result.number)
      assert_equal :publicly_leaked, event.action
    end
  end

  context "#alert_number" do
    test "is required" do
      assert_event_required_attributes Hook::Event::SecretScanningAlertEvent, :alert_number
    end
  end

  context "#target_repository" do
    test "returns the specified target_repository" do
      assert_equal @repo, event.target_repository
    end
  end

  context "#deliverable?" do
    test "returns true if the alert exists." do
      VCR.use_cassette "secret-scanning/webhook-event-deliverable" do
        assert event.deliverable?
      end
    end

    test "returns false if the secret result is not found for the alert id." do
      VCR.use_cassette "secret-scanning/webhook-alert-not-found" do
        SecretScanning::Features::Repo::TokenScanning.new(@repo).disable(actor: @user)
        event = Hook::Event::SecretScanningAlertEvent.new(action: :created,
          repository_id: @repo.id, alert_number: 159)
        refute event.deliverable?
      end
    end

    test "returns false if secret scanning is disabled." do
      SecretScanning::Features::Repo::TokenScanning.new(@repo).disable(actor: @user)
      refute event.deliverable?
    end

    test "returns false if secret scanning is unsupported by config" do
      GitHub.stubs(:configuration_secret_scanning_enabled?).returns(false)
      refute event.deliverable?
    end
  end

  def event
    @event ||= Hook::Event::SecretScanningAlertEvent.new(action: :created,
      repository_id: @repo.id, alert_number: @secret_result.number)
  end
end
