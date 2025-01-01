# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Jobs
  class HydroSecretScanningJobGroupEventProcessorJobTest < GitHub::TestCase
    include HydroMessageJobTestHelpers
    include SecretScanning::Features::FeatureFlagHelper

    CustomPatternMock = Struct.new(:data, :error)
    CustomPatternDataMock = Struct.new(:custom_pattern, :custom_pattern_id, :total_result_count)
    OrgPatternMock = Struct.new(:id, :owner_scope_id, :display_name, :scope, :created_by_id)

    setup do
      @user = create(:user, login: "repoadmin", email: "repoadmin@github.com")
      @org = create(:enterprise_linked_organization, admin: @user)
      @repo = create(:repository, owner: @org)
      if !GitHub.enterprise?
        @business = create(:business)
      else
        @business = Business.first
      end
      @expected_admin_recipients_for_owner = {
        @business => @business.admins.to_a,
        @org => @org.admins.to_a
      }
      # Add a business admin who has emails disabled. We're deliberately excluding them from @expected_admin_recipients_for_owner[@business] because of their email setting.
      business_owner_emails_disabled = create(:user, login: "business-disabled")
      @business.add_owner(business_owner_emails_disabled, actor: business_owner_emails_disabled)
      GitHub.newsies.get_and_update_settings(business_owner_emails_disabled) do |settings|
        settings.subscribed_settings.delete(Newsies::HANDLER_EMAIL)
      end
    end

    setup do
      Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
      SecurityProduct::AdvancedSecurity.any_instance.stubs(:enabled?).returns(true)
      SecretScanning::Features::Repo::TokenScanning.new(@repo).enable(actor: @user)
      GitHub.stubs(:secret_scanning_service_enabled?).returns(true)

      GitHub::TokenScanning::Service::Client.any_instance.stubs(:dry_run_metadata_for_pattern).returns(test_metadata)
    end

    test "sends email notifications to org custom pattern author on completion of dry run" do
      custom_pattern = test_org_custom_pattern
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:get_custom_pattern).returns(CustomPatternMock.new(data: CustomPatternDataMock.new(custom_pattern: custom_pattern)))
      message = {
        scope: :ORGANIZATION_SCOPE,
        owner_id: @org.id,
        group_id: 10,
        group_type: :GROUP_TYPE_DRY_RUN,
        event_type: :EVENT_TYPE_DONE,
        group_status: :GROUP_STATUS_COMPLETED,
      }
      SecretScanningMailer.expects(:custom_pattern_dry_run_scan_summary)
      .with(@org, :organization_scope, { id: custom_pattern.id, name: custom_pattern.display_name }, @user, 2).once.returns(stub(deliver_later: nil))

      perform_hydro_message_job(message, schema: "token_scanning_service.v0.JobGroupEvent", queue: "hydro_secret_scanning_job_group_event_processor")
    end

    test "does not send email notification if dry run is deleted before completion" do
      custom_pattern = test_org_custom_pattern
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:get_custom_pattern).returns(CustomPatternMock.new(data: CustomPatternDataMock.new(custom_pattern: custom_pattern)))
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:dry_run_metadata_for_pattern).returns(CustomPatternMock.new(data: nil, error: Twirp::Error.new(:not_found, nil)))
      message = {
        scope: :ORGANIZATION_SCOPE,
        owner_id: @org.id,
        group_id: 10,
        group_type: :GROUP_TYPE_DRY_RUN,
        event_type: :EVENT_TYPE_DONE,
        group_status: :GROUP_STATUS_COMPLETED,
      }
      SecretScanningMailer.expects(:custom_pattern_dry_run_scan_summary)
      .with(@org, :organization_scope, { id: custom_pattern.id, name: custom_pattern.display_name }, @user, 2).never

      perform_hydro_message_job(message, schema: "token_scanning_service.v0.JobGroupEvent", queue: "hydro_secret_scanning_job_group_event_processor")
    end

    context "after initial backfill scan completes" do
      test "sends 'secrets found' to org admin if secrets are found" do
        run_and_verify_secrets_email(@org, :ORGANIZATION_SCOPE, 10)
      end

      test "sends 'secrets found' to enterprise admin if secrets are found" do
        run_and_verify_secrets_email(@business, :BUSINESS_SCOPE, 10)
      end
    end

    def test_org_custom_pattern
      OrgPatternMock.new(
        id: 3,
        owner_scope_id: @org.id,
        display_name: "Test Custom Pattern",
        scope: :ORGANIZATION_SCOPE,
        created_by_id: @user.id,
      )
    end

    def test_metadata
      CustomPatternMock.new(
        data: CustomPatternDataMock.new(
          custom_pattern_id: 1,
          total_result_count: 2,
        ),
      )
    end

    def run_and_verify_secrets_email(owner, scope, total_token_count)
      security_config = SecurityConfiguration.create_configuration(
        model_hash: {
          "name" => "config name",
          "description" => "config description",
          "enable_ghas" => true,
          "private_vulnerability_reporting" => "disabled",
          "dependency_graph" => "disabled",
          "dependency_graph_autosubmit_action" => "disabled",
          "dependency_graph_autosubmit_action_options" => {},
          "dependabot_alerts" => "disabled",
          "dependabot_security_updates" => "disabled",
          "code_scanning" => "disabled",
          "secret_scanning" => "disabled",
          "secret_scanning_push_protection" => "disabled",
          "secret_scanning_delegated_bypass" => "disabled",
          "secret_scanning_validity_checks" => "disabled",
          "secret_scanning_non_provider_patterns" => "disabled",
          "secret_scanning_generic_secrets" => "disabled",
          "target" => @org
        },
        default_for_new_public_repos: false,
        default_for_new_private_repos: false,
        enforcement: :not_enforced,
        actor: @user,
      )
      security_config.save!
      message = {
        scope: scope,
        owner_id: owner.id,
        group_id: 10,
        group_type: :GROUP_TYPE_BACKFILL,
        event_type: :EVENT_TYPE_DONE,
        group_status: :GROUP_STATUS_COMPLETED,
        security_configuration_id: security_config.id,
      }
      end_time = DateTime.now
      start_time = end_time - 1.hour
      repos_scanned_count = 3
      # Stub the job groups API
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:get_job_group_summary).returns(CustomPatternMock.new(
        data: GitHub::Proto::SecretScanning::Api::V1::JobGroupSummaryResponse.new(
          total_token_count: total_token_count,
          repos_scanned_count: repos_scanned_count,
          job_group: GitHub::Proto::SecretScanning::Types::V1::JobGroup.new(
            job_group_id: message[:group_id],
            status: GitHub::Proto::SecretScanning::Types::V1::JobGroupStatus::JOB_GROUP_COMPLETED,
            started_at: Google::Protobuf::Timestamp.new(seconds: start_time.to_i),
            completed_at: Google::Protobuf::Timestamp.new(seconds: end_time.to_i),
            owner_id: owner.id,
            owner_scope: GitHub::Proto::SecretScanning::Types::V1::OwnerScope::ORGANIZATION_SCOPE,
          )
        )
      ))
      recipients = @expected_admin_recipients_for_owner[owner]

      # Setup a security manager team, if the owner is an org
      if owner.organization?
        security_manager_user = create(:user)
        security_manager_user_emails_disabled = create(:user)

        GitHub.newsies.get_and_update_settings(security_manager_user_emails_disabled) do |settings|
          settings.subscribed_settings.delete(Newsies::HANDLER_EMAIL)
        end
        create :team, organization: @org
        @security_manager_team = create(:security_manager_team, organization: @org, privacy: :closed)
        @security_manager_team.add_member(security_manager_user)
        @security_manager_team.add_member(security_manager_user_emails_disabled)
        # Because `security_manager_user_emails_disabled` has emails disabled, they should not be included in the recipients list
        recipients += [security_manager_user]
      end

      SecretScanningMailer.expects(:secrets_found_for_initial_org_or_enterprise_backfill).with(recipients, owner, message[:group_id], repos_scanned_count, total_token_count, security_config.name).once.returns(stub(deliver_later: nil))

      perform_hydro_message_job(message, schema: "token_scanning_service.v0.JobGroupEvent", queue: "hydro_secret_scanning_job_group_event_processor")
    end
  end
end
