# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Jobs
  class HydroCustomPatternDryRunNotificationJobTest < GitHub::TestCase
    include HydroMessageJobTestHelpers
    include GitHub::LoggerHelper

    setup do
      @user = create(:user, login: "repoadmin", email: "repoadmin@github.com")
      @org = create(:enterprise_linked_organization)
      @repo = create(:private_repository, owner: @org)
    end

    setup do
      SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
      Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
    end

    test "sends email notifications to custom pattern author on completion of dry run" do
      custom_pattern = test_custom_pattern

      message = {
        repository_id: @repo.id,
        custom_pattern: custom_pattern,
        dry_run_status: :COMPLETED,
        match_count: 5,
      }

      SecretScanningMailer.expects(:custom_pattern_dry_run_scan_summary)
      .with(@repo, :repository_scope, custom_pattern, @user, 5).once.returns(stub(deliver_later: nil))

      perform_hydro_message_job(message, schema: "token_scanning_service.v0.CustomPatternDryRunNotify", queue: "hydro_custom_pattern_dry_run_notification")
    end

    test "sends email notifications on proxima to custom pattern author on completion of dry run" do
      on_multi_tenant_enterprise do
        GitHub::CurrentTenant.remove

        custom_pattern = test_custom_pattern

        message = {
          repository_id: @repo.id,
          custom_pattern: custom_pattern,
          dry_run_status: :COMPLETED,
          match_count: 5,
        }

        SecretScanningMailer.expects(:custom_pattern_dry_run_scan_summary)
        .with(@repo, :repository_scope, custom_pattern, @user, 5).once.returns(stub(deliver_later: nil))

        perform_hydro_message_job(message, schema: "token_scanning_service.v0.CustomPatternDryRunNotify", queue: "hydro_custom_pattern_dry_run_notification")
      end
    end

    test "logs email notifications delivery" do
      custom_pattern = test_custom_pattern

      message = {
        repository_id: @repo.id,
        custom_pattern: custom_pattern,
        dry_run_status: :COMPLETED,
        match_count: 5,
      }

      SecretScanningMailer.expects(:custom_pattern_dry_run_scan_summary)
      .with(@repo, :repository_scope, custom_pattern, @user, 5).once.returns(stub(deliver_later: nil))

      expected_log = {
        "SeverityText" => "INFO",
        "Body" => "CustomPatternDryRunNotify message processed",
        "code.namespace" => "HydroCustomPatternDryRunNotificationJob",
        "code.function" => "perform",
        "gh.notifications.pattern_id" => custom_pattern[:id],
        "gh.notifications.owner.id" => @repo.id.to_s,
        "gh.notifications.scope" => :repository_scope,
        "gh.notifications.dry_run_status" => :COMPLETED
      }
      assert_logged(**expected_log) do
        perform_hydro_message_job(message, schema: "token_scanning_service.v0.CustomPatternDryRunNotify", queue: "hydro_custom_pattern_dry_run_notification")
      end
    end

    test "logs notified socket channel" do
      custom_pattern = test_custom_pattern

      message = {
        repository_id: @repo.id,
        custom_pattern: custom_pattern,
        dry_run_status: :COMPLETED,
        match_count: 5,
      }

      SecretScanningMailer.expects(:custom_pattern_dry_run_scan_summary)
      .with(@repo, :repository_scope, custom_pattern, @user, 5).once.returns(stub(deliver_later: nil))

      expected_log = {
        "SeverityText" => "INFO",
        "Body" => "Notified socket channel successfully",
        "code.namespace" => "HydroCustomPatternDryRunNotificationJob",
        "code.function" => "notify_socket_channel",
        "gh.notifications.pattern_id" => custom_pattern[:id],
        "gh.notifications.owner.id" => @repo.id.to_s,
        "gh.notifications.scope" => :repository_scope,
        "gh.notifications.dry_run_status" => :COMPLETED
      }
      assert_logged(**expected_log) do
        perform_hydro_message_job(message, schema: "token_scanning_service.v0.CustomPatternDryRunNotify", queue: "hydro_custom_pattern_dry_run_notification")
      end
    end

    test "sends email notifications to custom pattern author on failure of dry run" do
      custom_pattern = test_custom_pattern

      message = {
        repository_id: @repo.id,
        custom_pattern: custom_pattern,
        dry_run_status: :FAILED,
        match_count: 5,
      }

      SecretScanningMailer.expects(:custom_pattern_dry_run_scan_failed)
      .with(@repo, :repository_scope, custom_pattern, @user).once.returns(stub(deliver_later: nil))

      perform_hydro_message_job(message, schema: "token_scanning_service.v0.CustomPatternDryRunNotify", queue: "hydro_custom_pattern_dry_run_notification")
    end

    test "publishes notification to web socket when message is processed" do
      custom_pattern = test_custom_pattern

      message = {
        repository_id: @repo.id,
        custom_pattern: custom_pattern,
        dry_run_status: :COMPLETED,
        match_count: 5,
      }

      data = {
        status: :COMPLETED,
        gid: custom_pattern[:id].to_s
      }
      channel = GitHub::WebSocket::Channels.custom_pattern_dry_run_status(@repo)
      GitHub::WebSocket.expects(:notify_custom_pattern_dry_run_channel).with(@repo, channel, data).once

      perform_hydro_message_job(message, schema: "token_scanning_service.v0.CustomPatternDryRunNotify", queue: "hydro_custom_pattern_dry_run_notification")
    end

    test "does not publish any notification when secret scanning is disabled for repo" do
      SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(false)
      custom_pattern = test_custom_pattern

      message = {
        repository_id: @repo.id,
        custom_pattern: custom_pattern,
        dry_run_status: :COMPLETED,
        match_count: 5,
      }

      GitHub::WebSocket.expects(:notify_custom_pattern_dry_run_channel).never

      perform_hydro_message_job(message, schema: "token_scanning_service.v0.CustomPatternDryRunNotify", queue: "hydro_custom_pattern_dry_run_notification")
    end

    test "does not publish any notification when custom patterns disabled for org" do
      SecretScanning::Features::Org::CustomPatterns.any_instance.stubs(:feature_available?).returns(false)
      custom_pattern = test_custom_pattern(:ORGANIZATION_SCOPE)

      message = {
        repository_id: @repo.id,
        custom_pattern: custom_pattern,
        dry_run_status: :COMPLETED,
        match_count: 5,
      }

      GitHub::WebSocket.expects(:notify_custom_pattern_dry_run_channel).never

      perform_hydro_message_job(message, schema: "token_scanning_service.v0.CustomPatternDryRunNotify", queue: "hydro_custom_pattern_dry_run_notification")
    end

    test "does not publish any notification when custom patterns disabled for business" do
      SecretScanning::Features::Business::CustomPatterns.any_instance.stubs(:feature_available?).returns(false)
      custom_pattern = test_custom_pattern(:BUSINESS_SCOPE)

      message = {
        repository_id: @repo.id,
        custom_pattern: custom_pattern,
        dry_run_status: :COMPLETED,
        match_count: 5,
      }

      GitHub::WebSocket.expects(:notify_custom_pattern_dry_run_channel).never

      perform_hydro_message_job(message, schema: "token_scanning_service.v0.CustomPatternDryRunNotify", queue: "hydro_custom_pattern_dry_run_notification")
    end

    def test_custom_pattern(scope = :REPOSITORY_SCOPE)
      {
        id: 3,
        owner_scope_id: 0,
        name: "Test Custom Pattern",
        scope: scope,
        created_by_id: @user.id,
      }
    end
  end
end
