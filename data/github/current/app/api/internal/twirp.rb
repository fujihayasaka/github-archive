# typed: true
# frozen_string_literal: true

class Api::Internal::Twirp < ::Api::Internal
  PATH_REGEX = %r{\A(?:/api)?(?:/v3)?/internal/twirp/(.*)}.freeze

  before do
    log_data.merge!({
      "peer.service": self.class.client_name_from_header(request),
    })
  end

  # Public: Mount a service for a Twirp handler.
  #
  # handler_class - The Api::Internal::Twirp::Handler subclass.
  #
  # Returns nothing.
  def self.mount(handler_class)
    post "/internal/twirp/#{handler_class.service_class.service_full_name}/*", operation_id: :internal do
      @route_owner = "@github/api-platform-reviewers"
      handler = handler_class.new
      # Pass `env:` explicitly here because `handler` hasn't received it yet.
      # (It will get it during `.call(...)` below, but we should initialize our context _first_).
      handler.push_service_mapping_context(env: env)
      Failbot.push("rpc.service": handler_class.name)
      # Add an exception handler to report the error
      handler.service.exception_raised do |err, service_env|
        Failbot.report(err, {
          "rpc.method": service_env[:rpc_method],
        })
      end

      # TODO: Delete this section and config/initializers/twirp_monkeypatch.rb when twirp.non-strict-json metrics reach 0
      req = Rack::Request.new(env)
      content_type = req.get_header("CONTENT_TYPE")
      if content_type == ::Twirp::Encoding::JSON
        catalog_service = env[GitHub::TaggingHelper::PROCESS_SERVICE_KEY]
        tags = ["route:#{route_pattern}", "catalog_service:#{catalog_service}"]
        GitHub.dogstats.increment("twirp.non-strict-json", tags: tags)
      end

      handler.service.call(env)
    end
  end

  UNKNOWN_CLIENT_NAME = "unknown"

  def self.client_name_from_header(request)
    received_hmac = request.env[Api::App::HmacDependency::REQUEST_HMAC_HEADER]

    if received_hmac.present?
      hmac_status, client_key = Api::Internal::Twirp.verify_request_hmac(received_hmac)
      if hmac_status == :success
        GitHub.api_internal_twirp_hmac_settings.fetch(client_key, UNKNOWN_CLIENT_NAME)
      end
    end
  end

  def self.acceptable_media_types
    ["application/protobuf"]
  end

  mount ::Api::Internal::Twirp::Repositories::V1::RepositoriesAPIHandler
  mount ::Api::Internal::Twirp::Secretscanning::V1::LoginPasswordAPIHandler
  mount ::Api::Internal::Twirp::Secretscanning::V1::PublicKeyAPIHandler
  mount ::Api::Internal::Twirp::Secretscanning::V1::RepositoriesAPIHandler
  mount ::Api::Internal::Twirp::Secretscanning::V1::IssuesAPIHandler
  mount ::Api::Internal::Twirp::Secretscanning::V1::TenantAPIHandler
  mount ::Api::Internal::Twirp::Secretscanning::V1::DiscussionsAPIHandler
  mount ::Api::Internal::Twirp::Secretscanning::V1::PullRequestsAPIHandler
  mount ::Api::Internal::Twirp::Secretscanning::V1::OrgAPIHandler
  mount ::Api::Internal::Twirp::Secretscanning::V1::OauthAccessAPIHandler
  mount ::Api::Internal::Twirp::Secretscanning::V1::BlobsAPIHandler
  mount ::Api::Internal::Twirp::Secretscanning::V1::UsersAPIHandler
  mount ::Api::Internal::Twirp::Secretscanning::V1::ExemptionsAPIHandler
  mount ::Api::Internal::Twirp::ActionsRunService::Environments::V1::EnvironmentsAPIHandler
  mount ::Api::Internal::Twirp::ActionsBrokerService::BillingOwner::V1::BillingOwnerApiHandler

  # Monolith Twirp tooling
  mount ::Api::Internal::Twirp::Examples::Octocat::V1::OctocatAPIHandler
  mount ::Api::Internal::Twirp::Modelsgateway::Telemetry::V1::ModelsLogAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::EditPullRequestReviewCommentAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::EditPullRequestReviewThreadAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::EditPullRequestReviewAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::EditPullRequestAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::EditIssueAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::EditIssueCommentAPIHandler
  mount ::Api::Internal::Twirp::Modelsgateway::Access::V1::AccessAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V2::ImportIssueCommentsAPIHandler
  mount ::Api::Internal::Twirp::Copilotapi::KnowledgeBases::V1::KnowledgeBasesAPIHandler
  mount ::Api::Internal::Twirp::Licensing::Customers::V1::EnterpriseInstallationsApiHandler
  mount ::Api::Internal::Twirp::Licensing::Customers::V1::UsersAPIHandler
  mount ::Api::Internal::Twirp::Licensing::EnterpriseInstallations::V1::UsersAPIHandler
  mount ::Api::Internal::Twirp::Licensing::Repositories::V1::RepositoriesAPIHandler
  mount ::Api::Internal::Twirp::Actions::Core::V1::WorkflowRunExecutionsAPIHandler
  mount ::Api::Internal::Twirp::Classroom::Organizations::V1::OrganizationsAPIHandler
  mount ::Api::Internal::Twirp::AdvisoryDB::Advisories::V1::ListAdvisoriesAPIHandler
  mount ::Api::Internal::Twirp::GitSrcMigrator::Monolith::V1::SourceImportsAPIHandler
  mount ::Api::Internal::Twirp::Webhooksubscriptions::Subscriptions::V1::SubscriptionsAPIHandler
  mount ::Api::Internal::Twirp::Classroom::Assignments::V1::AssignmentsAPIHandler
  mount ::Api::Internal::Twirp::Features::Groups::V1::GroupsAPIHandler
  mount ::Api::Internal::Twirp::Copilot::Organizations::V1::CopilotOrganizationDetailAPIHandler
  mount ::Api::Internal::Twirp::CodeScanning::SuggestedFixes::V1::SuggestedFixesAPIHandler
  mount ::Api::Internal::Twirp::Copilotapi::Agents::V1::AgentsAPIHandler
  mount ::Api::Internal::Twirp::Copilotapi::Chat::V1::AttachmentsAPIHandler
  mount ::Api::Internal::Twirp::Copilotapi::Chat::V1::SkillsAPIHandler
  mount ::Api::Internal::Twirp::Copilotapi::CustomCopilots::V1::CustomCopilotsAPIHandler
  mount ::Api::Internal::Twirp::Copilotapi::CustomInstructions::V1::CustomInstructionsAPIHandler
  mount ::Api::Internal::Twirp::Copilotapi::Core::V1::AuthorizationAPIHandler
  mount ::Api::Internal::Twirp::Copilot::Users::V1::CopilotUserDetailAPIHandler
  mount ::Api::Internal::Twirp::DependencyGraph::Users::V1::UsersAPIHandler
  mount ::Api::Internal::Twirp::DependencyGraphPlatform::Actions::V1::ActionsAPIHandler
  mount ::Api::Internal::Twirp::DependencyGraphPlatform::Advisories::V1::AdvisoriesAPIHandler
  mount ::Api::Internal::Twirp::DependencyGraphPlatform::Integrations::V1::IntegrationsAPIHandler
  mount ::Api::Internal::Twirp::DependencyGraphPlatform::Repositories::V1::RepositoriesAPIHandler
  mount ::Api::Internal::Twirp::Features::Actors::V1::ActorsAPIHandler
  mount ::Api::Internal::Twirp::Features::FeatureSync::V1::FeatureSyncAPIHandler
  mount ::Api::Internal::Twirp::Features::CustomGates::V1::CustomGatesAPIHandler
  mount ::Api::Internal::Twirp::CodeScanning::Turboghas::V1::TurboghasAPIHandler
  mount ::Api::Internal::Twirp::CodeScanning::Enterprise::V1::StorageAPIHandler
  mount ::Api::Internal::Twirp::CodeScanning::Repositories::V1::RepositoriesAPIHandler
  mount ::Api::Internal::Twirp::Classroom::AccessCheck::V1::AccessCheckAPIHandler
  mount ::Api::Internal::Twirp::Kredz::Core::V1::OwnerAPIHandler
  mount ::Api::Internal::Twirp::ActionsResults::Core::V1::ArtifactsApiHandler
  mount ::Api::Internal::Twirp::ActionsResults::Core::V1::ChecksApiHandler
  mount ::Api::Internal::Twirp::Kredz::Core::V1::ActorsAPIHandler
  mount ::Api::Internal::Twirp::Billing::Products::V1::ZuoraProductAPIHandler
  mount ::Api::Internal::Twirp::CodeScanning::ManagedAnalyses::V1::ManagedAnalysesAPIHandler
  mount ::Api::Internal::Twirp::Dependabot::Settings::V1::AutofixAPIHandler
  mount ::Api::Internal::Twirp::Dependabot::Settings::V1::RepositoryAPIHandler
  mount ::Api::Internal::Twirp::Dependabot::PullRequests::V1::PullRequestApiHandler
  mount ::Api::Internal::Twirp::Proxima::EnterpriseManagement::V1::EnterpriseManagementAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::ValidateIpAllowlistAPIHandler
  mount ::Api::Internal::Twirp::Webhooks::Core::V1::WebhooksAPIHandler
  mount ::Api::Internal::Twirp::Actions::Core::V1::AccountDetailsAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::ArchiveExportAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::ValidateSourceCredentialsAPIHandler
  mount ::Api::Internal::Twirp::Spokesd::Core::V1::UsersAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::ImportMigrationLogAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::ImportPermissionsAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::ImportReleaseAPIHandler
  mount ::Api::Internal::Twirp::Classroom::ClassroomCodespaces::V1::ClassroomCodespacesAPIHandler
  mount ::Api::Internal::Twirp::Registrymetadata::Core::V1::LaunchAPIHandler
  mount ::Api::Internal::Twirp::Actions::Core::V1::GlobalIdAPIHandler
  mount ::Api::Internal::Twirp::Actions::Core::V1::IntegrationsAPIHandler
  mount ::Api::Internal::Twirp::Actions::Core::V1::ActorsAPIHandler
  mount ::Api::Internal::Twirp::Auditlog::Streaming::V1::StreamingAPIHandler
  mount ::Api::Internal::Twirp::Notifications::Notifyd::V1::NotifydAPIHandler
  mount ::Api::Internal::Twirp::Classroom::ClassroomRepositories::V1::ClassroomRepositoriesAPIHandler
  mount ::Api::Internal::Twirp::MailReplies::Replies::V1::RepliesAPIHandler
  mount ::Api::Internal::Twirp::Billing::Accounts::V1::BillableOwnerAPIHandler
  mount ::Api::Internal::Twirp::Actions::Core::V1::ChecksApiHandler
  mount ::Api::Internal::Twirp::Actions::Core::V1::WorkflowDetailsAPIHandler
  mount ::Api::Internal::Twirp::Actions::Core::V1::UsersAPIHandler
  mount ::Api::Internal::Twirp::Actions::Core::V1::RepositoriesAPIHandler
  mount ::Api::Internal::Twirp::Actions::Core::V1::ResolveActionsAPIHandler
  mount ::Api::Internal::Twirp::Classroom::Repositories::V1::RepositoriesAPIHandler
  mount ::Api::Internal::Twirp::Actions::Core::V1::EnvironmentsAPIHandler
  mount ::Api::Internal::Twirp::Actions::Core::V1::PoliciesAPIHandler
  mount ::Api::Internal::Twirp::Classroom::Integration::V1::IntegrationAPIHandler
  mount ::Api::Internal::Twirp::Classroom::Users::V1::UsersAPIHandler
  mount ::Api::Internal::Twirp::Classroom::AssignmentReuse::V1::AssignmentReuseAPIHandler
  mount ::Api::Internal::Twirp::Classroom::SyncClassroom::V1::SyncClassroomAPIHandler
  mount ::Api::Internal::Twirp::EducationWeb::Users::V1::UsersAPIHandler
  mount ::Api::Internal::Twirp::EducationWeb::Repos::V1::ReposAPIHandler
  mount ::Api::Internal::Twirp::EducationWeb::Repos::V1::ClassroomReposAPIHandler
  mount ::Api::Internal::Twirp::EducationWeb::Orgs::V1::OrgsApiHandler
  mount ::Api::Internal::Twirp::Features::Core::V1::FeaturesAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::CreateImportAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::DeployKeyAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::IdentityAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::ImportAssetAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::ImportCloseIssueReferencesAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::ImportCommitCommentAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::ImportIssueAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::ImportIssueCommentAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::ImportLabelsAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::ImportMilestonesAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::ImportOrganizationAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::ImportOrganizationSettingsAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::ImportProjectAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::ImportProtectedBranchAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::ImportPullRequestAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::ImportPullRequestReviewAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::ImportReactionsAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::ImportRepositoryAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::ImportTeamAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::LockRepositoryAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::MannequinAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::OrganizationAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::TimelineEventsAPIHandler
  mount ::Api::Internal::Twirp::Registrymetadata::Core::V1::LoginAPIHandler
  mount ::Api::Internal::Twirp::Registrymetadata::Core::V1::CollabAuthAPIHandler
  mount ::Api::Internal::Twirp::Registrymetadata::Core::V1::RepoAPIHandler
  mount ::Api::Internal::Twirp::Registrymetadata::Core::V1::OrgAPIHandler
  mount ::Api::Internal::Twirp::Registrymetadata::Core::V1::OwnerAPIHandler
  mount ::Api::Internal::Twirp::Registrymetadata::Core::V1::BillingAPIHandler
  mount ::Api::Internal::Twirp::Registrymetadata::Core::V1::MigrationAPIHandler
  mount ::Api::Internal::Twirp::Support::HelpHub::V1::AbuseReportsApiHandler
  mount ::Api::Internal::Twirp::Support::HelpHub::V1::BusinessesAPIHandler
  mount ::Api::Internal::Twirp::Support::HelpHub::V1::DiscussionsAPIHandler
  mount ::Api::Internal::Twirp::Support::HelpHub::V1::UsersAPIHandler
  mount ::Api::Internal::Twirp::Support::HelpHub::V1::RepositoriesSupportAPIHandler
  mount ::Api::Internal::Twirp::Support::HelpHub::V1::LfsSupportAPIHandler
  mount ::Api::Internal::Twirp::Packageregistry::AuditLog::V1::AuditLogHandler
  mount ::Api::Internal::Twirp::Actions::Core::V1::RefsAPIHandler
  mount ::Api::Internal::Twirp::TrustTiers::TrustTier::V1::TrustTierAPIHandler
  mount ::Api::Internal::Twirp::PipelineMonitor::Monitoring::V1::MonitoringAPIHandler
  mount ::Api::Internal::Twirp::Pages::Dfs::V1::PagesDfsHandler
  mount ::Api::Internal::Twirp::Pages::Pagesdeployerapi::V1::ArtifactsApiHandler
  mount ::Api::Internal::Twirp::Pages::Pagesdeployerapi::V1::AccessTokenApiHandler
  mount ::Api::Internal::Twirp::Billing::Repositories::V1::RepositoryAPIHandler
  mount ::Api::Internal::Twirp::GitSrcMigrator::Monolith::V1::GitSrcMigratorWorkflowAPIHandler
  mount ::Api::Internal::Twirp::Octoshift::Imports::V1::ArchiveStorageAPIHandler
  mount ::Api::Internal::Twirp::Odometer::Core::V1::BusinessesAPIHandler

  # Webhook payload hydration handlers
  mount ::Api::Internal::Twirp::IssueComments::WebhookPayloadHydration::IssueCommentApiHandler
  mount ::Api::Internal::Twirp::PullRequests::WebhookPayloadHydration::PullRequestReviewApiHandler
  mount ::Api::Internal::Twirp::Issues::WebhookPayloadHydration::IssuesEventApiHandler
  ##
  # ::Api::Internal access control checks

  def externally_accessible?
    # We need to be able to access this endpoint from the outside world for now. Eventually once the service is up and running, the requests will be coming from the internal network
    return true if url.include?("proxima.enterprisemanagement.v1.EnterpriseManagementAPI")

    false
  end

  def require_request_hmac?
    true
  end

  def authenticated_for_private_mode?
    true
  end
end
