# typed: true
# frozen_string_literal: true

require "uri"
require "mustermann"

# Rack app responsible for sending API requests to the appropriate Sinatra
# app.  This lives in the GitHub module so that Rails reloading leaves it
# alone.
module GitHub::Routers
  class Api
    INTERNAL_AVATARS_REGEX = Regexp.union(
      %r{^internal/user/\d+/avatars(/|$)},
      %r{^internal/organizations/\d+/avatars(/|$)},
      %r{^internal/oauth-applications/\d+/avatars(/|$)},
      %r{^internal/integrations/\d+/avatars(/|$)},
      %r{^internal/teams/\d+/avatars(/|$)},
      %r{^internal/businesses/\d+/avatars(/|$)},
      %r{^internal/user/avatars(/|$)}
    )

    INTERNAL_REPOSITORIES_REGEX = Regexp.union(
      %r{^internal/repositories/\d+/git/(pushes|password_auth)(/|$)},
      %r{^internal/repositories/\d+/wiki/git/pushes(/|$)},
      %r{^internal/repositories/\d+/?$},
      %r{^internal/repositories/audits(/|$)},
      %r{^internal/networks/\d+/?$},
      %r{^internal/networks/audits(/|$)}
    )

    INTERNAL_STORAGE_USER_FILES_REGEX = Regexp.union(
      %r{^internal/storage/user/\d+/files(/|$)},
      %r{^internal/storage/user/\d+/repository/\d+/files(/|$)},
      %r{^internal/storage/github-enterprise-assets/}
    )
    INTERNAL_CODESPACES_PREBUILD_REGEX = Regexp.union(
      %r{^internal/vscs/codespaces/prebuild/instances$},
      %r{^internal/vscs/codespaces/repository/\d+/prebuild/templates$},
      %r{^internal/vscs/codespaces/prebuild/templates(/|$)}
    )
    INTERNAL_MULTIPART_POLICIES_REGEX = Regexp.union(
      %r{^internal/repositories/\d+/package_versions/\d+/registry/.*/policies$},
      %r{^internal/repositories/\d+/registry/.*/policies$},
      %r{^internal/migrations/\d+/archive/.*/policies$}
    )
    ENTERPRISE_SECRET_SCANNING_REGEX = Regexp.union(
      %r{^enterprises/[^/]+/secret-scanning},
      %r{^enterprises/[^/]+/code_security_and_analysis},
      %r{^enterprises/[^/]+/[^/]+/(enable_all|disable_all)}
    )
    CODESPACES_ORGANIZATION_REGEX = Regexp.union(
      %r{^organizations/\d+/codespaces},
      %r{^organizations/\d+/codespaces/access},
      %r{^organizations/\d+/members/\d+/codespaces(/\w+)?}
    )
    ORGANIZATION_OUTSIDE_COLLABORATORS_REGEX = Regexp.union(
      %r{^organizations/\d+/personal-access-token-requests(/[^/]+|$)},
      %r{^organizations/\d+/personal-access-token-requests/\d+(/[^/]+|$)},
      %r{^organizations/\d+/personal-access-token-requests/\d+/repositories(/[^/]+|$)}
    )
    ORGANIZATION_PROGRAMMATIC_ACCESS_GRANTS_REGEX = Regexp.union(
      %r{^organizations/\d+/personal-access-tokens(/[^/]+|$)},
      %r{^organizations/\d+/personal-access-token-requests/\d+(/[^/]+|$)},
      %r{^organizations/\d+/personal-access-tokens/\d+/repositories(/[^/]+|$)}

    )
    ORGANIZATION_TEAM_SYNC_REGEX = Regexp.union(
      %r{^organizations/\d+/team-sync/groups},
      %r{^organizations/\d+/team/\d+/team-sync/group-mappings},
      %r{^organizations/\d+/team/\d+/team-sync/group-mappings-state}
    )
    ORGANIZATION_EXTERNAL_GROUPS_REGEX = Regexp.union(
      %r{^organizations/\d+/external-groups},
      %r{^organizations/\d+/external-group/\d+},
      %r{^organizations/\d+/team/\d+/external-groups}

    )
    ORGANIZATION_TEAMS_REGEX = Regexp.union(
      %r{^organizations/\d+/team},
      %r{^organizations/\d+/team/\d+/permissions$},
      %r{^organizations/\d+/team/\d+$},
      %r{^organizations/\d+/team/\d+/invitations},
      %r{^organizations/\d+/team/\d+/members},
      %r{^organizations/\d+/team/\d+/members/},
      %r{^organizations/\d+/team/\d+/memberships/},
      %r{^organizations/\d+/team/\d+/teams}
    )
    ORGANIZATION_ROLE_ASSIGNMENT_REGEX = Regexp.union(
      %r{^organizations/\d+/organization-roles/users},
      %r{^organizations/\d+/organization-roles/team},
      %r{^organizations/\d+/organization-roles/\d+/users},
      %r{^organizations/\d+/organization-roles/\d+/teams}
    )
    REPOSITORY_CONTENTS_REGEX = Regexp.union(
      %r{^repositories/\d+/contents},
      %r{^repositories/\d+/readme},
      %r{^repositories/\d+/license},
      %r{^repositories/\d+/(tar|zip)ball}
    )
    CHECK_RUNS_REGEX = Regexp.union(
      %r{^repositories/\d+/commits/.+/check-runs(/$|$)},
      %r{^repositories/\d+/check-runs(/|$)},
      %r{^repositories/\d+/check-suites/\d+/check-runs(/|$)}
    )
    CHECK_SUITES_REGEX = Regexp.union(
      %r{^repositories/\d+/commits/.+/check-suites(/|$)},
      %r{^repositories/\d+/check-suites(/|$)},
      %r{^repositories/\d+/check-suite-requests(/|$)}
    )
    JOBS_REGEX = Regexp.union(
      %r{^repositories/\d+/actions/runs/\d+/jobs},
      %r{^repositories/\d+/actions/runs/\d+/attempts/\d+/jobs},
      %r{^repositories/\d+/actions/jobs(/|$)}
    )
    WORKFLOW_RUNS_REGEX = Regexp.union(
      %r{^repositories/\d+/actions/workflows/[^/]+/runs(/|$)},
      %r{^repositories/\d+/actions/required_workflows/[^/]+/runs(/|$)},
      %r{^repositories/\d+/actions/runs$},
      %r{^repositories/\d+/actions/runs/\d+(/|$)}
    )
    REPOSITORY_BRANCHES_REGEX = Regexp.union(
      %r{^repositories/\d+/branches},
      %r{^repositories/\d+/merges},
      %r{^repositories/\d+/merge-upstream}
    )
    NETWORK_LOGS_REGEX = Regexp.union(
      %r{^repositories/\d+/actions/runs/\d+/network_logs$},
      %r{^repositories/\d+/actions/workflows/[^/]+/network_logs$},
      %r{^repositories/\d+/actions/jobs/\d+/network_logs$}
    )

    REPOSITORY_POLICIES_REGEX = Regexp.union(
      %r{^repositories/\d+/releases/\d+/assets/policies$},
      %r{^repositories/\d+/package_versions/\d+/registry/.*/policies$},
      %r{^repositories/\d+/tasks/[^/]+/runs/\d+/log/policies$},
      %r{^repositories/\d+/code-scanning/codeql/databases/[^/]+/policies$}
    )
    REPOSITORY_CODEQL_VARIANT_ANALYSIS_REPO_TASKS_UPDATE_REGEX = Regexp.union(
      %r{^repositories/\d+/code-scanning/codeql/variant-analyses/\d+/repositories$},
      %r{^repositories/\d+/code-scanning/codeql/variant-analyses/\d+/repositories/\d+/status$},
      %r{^repositories/\d+/code-scanning/codeql/variant-analyses/\d+/repositories/\d+/artifact}
    )
    POLICIES_REGEX = Regexp.union(
      %r{^migrations/\d+/archive/policies$},
      %r{^runs/\d+/log/policies$},
      %r{^businesses/[^/]+/user-accounts-uploads/policies$}
    )
    PROJECTS_REGEX = Regexp.union(
      %r{^user/\d+/projects},
      %r{^user/projects(/|$)},
      %r{^projects/\d+},
      %r{^projects/columns/\d+},
      %r{^projects/columns/cards/\d+}
    )
    EVENTS_REGEX = Regexp.union(
      %r{^events(/|$)},
      %r{^networks/[^/]+/[^/]+/events},
      %r{^user/\d+/(received_)?events}
    )
    GITHUB_CHATOPS_REGEX = Regexp.union(
      %r{^personal_schedule_reminders/\w+},
      %r{^personal_schedule_reminders$},
      %r{^schedule_reminders/\d+/workspace(/\w+|s$)},
      %r{^schedule_reminders/reminders$},
      %r{^schedule_reminders/\d+/reminder(/\d+|s)$},
      %r{^schedule_reminders/organizations/\d+/teams/search}
    )
    ORGANIZATIONS_REGEX = Regexp.union(
      %r{^user/orgs(/|$)},
      %r{^user/\d+/orgs(/|$)},
      %r{^org(s)?/},
      %r{^user/memberships/org(s|anizations)}
    )
    INTEGRATION_INSTALLATIONS_REGEX = Regexp.union(
      %r{^installation/token},
      %r{^installation/repositories(/|$)},
      %r{^installations/\d+/repositories(/|$)},
      %r{^user/installations/\d+/repositories(/|$)}
    )
    INTEGRATIONS_REGEX = Regexp.union(
      %r{^(app|integration)/installations(/|$)},
      %r{^(app|integration)/installation/access_tokens},
      %r{^(app|integration)/global/access_tokens},
      %r{^(app|integration)/global/\d+/access_tokens},
      %r{^app/installation-requests},
      %r{^user/\d+/installation(/|$)}
    )
    USER_EMAILS_REGEX = Regexp.union(
      %r{^user/emails(/|$)},
      %r{^user/email(/|$)},
      %r{^user/public_emails(/|$)}
    )
    USER_FOLLOWERS_REGEX = Regexp.union(
      %r{^user/followers(/|$)},
      %r{^user/following(/|$)},
      %r{^user/\d+/followers(/|$)},
      %r{^user/\d+/following(/|$)}
    )
    MOBILE_UPLOADS_REGEX = Regexp.union(
      %r{^mobile/upload/policy},
      %r{^mobile/upload/assets/\d+},
      %r{^mobile/upload/repository-files/\d+}
    )
    COPILOT_REGEX = Regexp.union(
      %r{^copilot_internal/v2/token$},
      %r{^copilot_internal/notification},
      %r{^copilot_internal/repository_check$},
      %r{^copilot_internal/user$},
      %r{^copilot_internal/content_exclusion$},
      %r{^copilot_internal/content_restrictions$},
      %r{^copilot_internal/check_indexing_status$},
      %r{^copilot_internal/workspace$}
    )

    COPILOT_ORG_SEATS_REGEX = Regexp.union(
      %r{^organizations/\d+/members/\d+/copilot(/|$)},
      %r{^organizations/\d+/copilot/seats(/|$)},
      %r{^organizations/\d+/copilot/billing(/|$)},
      %r{^organizations/\d+/copilot/billing/selected_\d+(/|$)}
    )

    COPILOT_ENTERPRISE_SEATS_REGEX = Regexp.union(
      %r{^enterprises/\d+/copilot/billing/seats(/|$)}
    )

    COPILOT_ORG_USAGE_REGEX = %r{^organizations/\d+/copilot/usage(/|$)}

    COPILOT_ENTERPRISE_USAGE_REGEX = %r{^enterprises/\d+/copilot/usage(/|$)}

    COPILOT_ENTERPRISE_TEAM_USAGE_REGEX = %r{^enterprises/\d+/team/\d+/copilot/usage(/|$)}

    COPILOT_TEAM_USAGE_REGEX = %r{^organizations/\d+/team/\d+/copilot/usage(/|$)}

    ENTERPRISE_TEAMS_REGEX = Regexp.union(
      %r{^enterprises/\d+/teams},
    )
    ENTERPRISE_TEAM_MEMBERSHIPS_REGEX = Regexp.union(
      %r{^enterprises/\d+/teams/\d+/memberships},
    )

    API_PATH = "github.api_path".freeze
    DEPRECATED_ROUTE = "deprecated_route".freeze
    QUERY_STRING = "QUERY_STRING".freeze
    PATH_INFO = "PATH_INFO".freeze
    ORIGINAL_PATH_INFO = "ORIGINAL_PATH_INFO".freeze
    SERVER_NAME = "SERVER_NAME".freeze
    ThisAppKey = "github.this_app_slug".freeze
    ThisUserKey = "github.this_user".freeze
    ThisTeamKey = "github.this_team".freeze
    ThisRepositoryKey = "github.this_repository".freeze
    ThisRepositoryNameWithOwnerKey = "github.this_repository_nwo".freeze
    ProcessCategoryKey = "process.request_category".freeze
    ProcessCategoryDataDogKey = "process.request_category_datadog".freeze
    ProcessCategory = "api".freeze
    Accept = "HTTP_ACCEPT".freeze
    UnconvertedPathKey = "unconverted_path".freeze

    TailingStatusRegex = %r{/repositories/(?<repo_id>\d+)/commits/(?<ref>.*)/(?<status>status(es)?)$}
    RepositoryIDRegex = %r{/repositories/(?<repo_id>\d+)(/|$)}
    # Extend this to other resources by changing the (?<resource>(check-suites|check-runs)) bit like so:
    # (?<resource>(check-suites|check-runs|my-other-resource)).
    AmbiguousCommitsAPIRefRegex = %r{/repositories/(?<repo_id>\d+)/commits/(?<ref>.*)/(?<resource>(check-suites|check-runs))(/$|$)}
    VariantAnalysisRegex = %r{^(?<prefix>/repositories/\d+/code-scanning/codeql/variant-analyses/\d+)/repos/(?<owner>[^/]+)/(?<name>[^/]+)(?<resource>/.*|$)}

    # Regexp to match against SERVER_NAME. If the pattern does # not match,
    # the request is forwarded to the next middleware in the chain.
    # This matches dotcom API requests (i.e. "api.github.com").
    HOST_PATTERN = /(^|\.)api\./

    # Matched against SERVER_NAME for internal API requests.
    INTERNAL_API_PATTERN = /^(internal-api\.service\.|unicorn-internal-api\.)/

    # For some environments, we use a path prefix to determine API calls instead
    # of a host name. This Regexp will be matched against PATH_INFO to extract
    # the actual api path versus the prefix.
    PATH_PREFIX = %r{^(/api/v3)(.*)$}

    # Match GraphQL at the toplevel so it's not nested under v3
    GRAPHQL_PATH_PREFIX = %r{^(/api)(/graphql.*)$}

    def self.internal_api_host?(host)
      host =~ INTERNAL_API_PATTERN
    end

    def initialize(app)
      @app = app
    end

    # This is where the Rack magic happens.
    #
    # env - The Hash environment of the current Rack request..
    #
    # Returns an Array Rack response.
    def call(env)
      app = app_for(env)
      app.call(env)
    end

    # Internal: Route to the correct Rack app.
    #
    # Returns a Rack middlware
    def app_for(env)
      if (GitHub.multi_tenant_enterprise? || use_path_prefix?) && (env[PATH_INFO] =~ GRAPHQL_PATH_PREFIX || env[PATH_INFO] =~ PATH_PREFIX)
        env[API_PATH]  = $1
        env[PATH_INFO] = $2
        select_app(env)
      elsif env[SERVER_NAME] =~ HOST_PATTERN || self.class.internal_api_host?(env[SERVER_NAME])
        select_app(env)
      elsif Rails.env.development? && env[PATH_INFO].start_with?("/lfs")
        select_app(env)
      elsif Rails.env.test? && env[PATH_INFO] =~ %r{/git/pushes\z|pre-receive-hooks|password_auth}
        select_app(env)
      else
        @app
      end
    end

    # Internal: Should we use an API path prefix in determining what router to call?
    #
    # Returns Boolean
    def use_path_prefix?
      GitHub.use_api_path_prefix?
    end

    # Determines which Rack app to pass the request to.  API requests get a
    # Sinatra app.  Other requests are passed down the chain (to Rails).  In the
    # future we may want to look at the Accept header or ?v param to do better
    # content negotiation for API v4.
    #
    # env - The Hash environment of the current Rack request..
    #
    # Returns a Rack object.
    def select_app(env)
      select_app_without_instrumentation(env)
    end

    def select_internal_app(route_path)
      case route_path
      when INTERNAL_AVATARS_REGEX
        ::Api::Internal::Avatars

      when %r{^internal/repositories/\d+/media/blobs(/|$)},
           %r{^internal/media(/|$)}
        ::Api::Internal::MediaApp

      when INTERNAL_REPOSITORIES_REGEX
        ::Api::Internal::Repositories

      when %r{^internal/gists/\d+/git/pushes(/|$)},
           %r{^internal/gists/\d+/?$},
           %r{^internal/gists/audits(/|$)}
        ::Api::Internal::Gists

      when %r{^internal/aleph/}
        ::Api::Internal::Aleph

      when %r{^internal/blackbird/}
        ::Api::Internal::Blackbird

      when %r{^internal/actions/hosted-runners/images}
        ::Api::Internal::ActionsImageDeployment

      when %r{^internal/actions/}
        ::Api::Internal::Actions

      when %r{^internal/assets/user/auth(/|$)}
        ::Api::Internal::AssetsAuth

      when %r{^internal/assets/user(/|$)}
        ::Api::Internal::AssetsAvatars

      when %r{^internal/assets/avatars/quarantine(/|$)}
        ::Api::Internal::Quarantine

      when %r{^internal/assets/avatars(/|$)}
        ::Api::Internal::AssetsAvatars

      when %r{^internal/assets/media(/|$)}
        ::Api::Internal::AssetsMedia

      when %r{^internal/assets/archives(/|$)}
        ::Api::Internal::Assets

      when %r{^internal/assets/quarantined_user_asset(/|$)}
        ::Api::Internal::Quarantine

      when INTERNAL_STORAGE_USER_FILES_REGEX
        ::Api::Internal::StorageUserFiles

      when %r{^internal/pages/auth},
           %r{^internal/pages/build}
        ::Api::Internal::Pages

      when %r{^internal/storage/avatars(/|$)}
        ::Api::Internal::StorageAvatars

      when %r{^internal/storage/github-enterprise-releases/},
           %r{^internal/storage/releases/\d+/files(/|$)}
        ::Api::Internal::StorageReleaseFiles

      when %r{^internal/storage/raw_lfs/}
        ::Api::Internal::StorageRawLfs

      when %r{^internal/storage/lfs/}
        ::Api::Internal::StorageLfs

      when %r{^internal/spokes/entities/([^/]+)/(\d+)(\.wiki)?/replicas(/|$)}
        ::Api::Internal::Replicas

      when %r{^internal/storage/repositories(/|$)}
        ::Api::Internal::StorageRepositoryFiles

      when %r{^internal/storage/upload-manifest-files(/|$)}
        ::Api::Internal::StorageUploadManifestFiles

      when %r{^internal/storage/marketplace-listing-screenshots(/|$)}
        ::Api::Internal::StorageMarketplaceListingScreenshots

      when %r{^internal/storage/marketplace-listing-images(/|$)}
        ::Api::Internal::StorageMarketplaceListingImages

      when %r{^internal/storage/repository/\d+/images(/|$)}
        ::Api::Internal::StorageRepositoryImages

      when %r{^internal/storage/migrations(/|$)}
        ::Api::Internal::StorageMigrationArchives

      when %r{^internal/storage/oauth_logos(/|$)}
        ::Api::Internal::StorageOauthApplicationLogos

      when %r{^internal/storage/businesses(/|$)}
        ::Api::Internal::StorageEnterpriseInstallationUserAccountsUploads

      when %r{^internal/registry/.*/@.+/.+(/|$)}
        ::Api::Internal::PackageRegistry

      when %r{^internal/porter/}
        ::Api::Internal::PorterCallbacks

      when %r{^internal/lfs/}
        ::Api::Internal::Lfs

      when %r{^internal/email_bounce(/|$)}
        ::Api::Internal::EmailBounce

      when %r{^internal/marketplace/traffic_analytics_ready(/|$)}
        ::Api::Internal::MarketplaceAnalytics

      when %r{^internal/twirp/}
        if GitHub.twirp_enabled?
          ::Api::Internal::Twirp
        else
          ::Api::Root
        end

      when %r{^internal/vscs/environment_heartbeat},
           %r{^internal/vscs/environment_webhook}
        ::Api::Internal::Codespaces::Webhook

      when %r{^internal/codespaces/.*/failover},
           %r{^internal/codespaces/failover}
        ::Api::Internal::Codespaces::Failover

      when %r{^internal/codespaces/}
        ::Api::Internal::Codespaces::PortForwarding

      when INTERNAL_CODESPACES_PREBUILD_REGEX
        ::Api::Internal::Codespaces::Prebuilds

      when %r{^internal/global_flags(/|$)}
        ::Api::Internal::GlobalFlags

      when INTERNAL_MULTIPART_POLICIES_REGEX
        ::Api::Internal::MultiPartPolicies

      when %r{^internal/pre-receive-hooks/\d+/errors}
        ::Api::Internal::PreReceiveHooks

      when %r{^internal/raw/}
        ::Api::Internal::Raw

      when %r{^internal/archive}
        ::Api::Internal::Archive

      when %r{^internal/apps/}
        ::Api::Internal::Apps

      when %r{^internal/neutron/}
        ::Api::Internal::Neutron

      when %r{^internal/code-scanning/}
        ::Api::Internal::CodeScanning

      end
    end

    def select_enterprise_app(route_path)
      case route_path
      when %r{^enterprises/\d+/(license-sync-status)(/|$)}
        ::Api::EnterpriseLicenseSync

      when %r{^enterprises/\d+/(consumed-licenses)(/|$)}
        ::Api::EnterpriseLicensing

      when %r{^enterprises/\d+/actions/runners(/|$)}
        ::Api::EnterpriseRunners

      when %r{^enterprises/\d+/actions/hosted-runners(/|$)}
        ::Api::EnterpriseHostedRunners

      when %r{^enterprises/\d+/actions/github-hosted-runners/images/custom/\d+/versions(/|$)},
           %r{^enterprises/\d+/actions/github-hosted-runners/\d+(/|$)}
        ::Api::EnterpriseLargerGitHubRunners

      when %r{^enterprises/\d+/actions/cache(/|$)}
        ::Api::EnterpriseActionsCache

      when %r{^enterprises/[^/]+/actions/oidc/customization/issuer}
        ::Api::EnterpriseActionsOIDCCustomIssuerApi

      when %r{^enterprises/\d+/actions/permissions(/|$)}
        ::Api::EnterpriseActionsPermissions

      when %r{^enterprises/\d+/advanced-security(/|$)}
        ::Api::EnterpriseAdvancedSecurity

      when %r{^enterprises/\d+/actions/runner-groups(/|$)}
        ::Api::EnterpriseRunnerGroups

      when %r{^enterprises/\d+/announcement}
        ::Api::AnnouncementBanners

      when %r{^enterprises/\d+/apps(/|$)},
           %r{^enterprises/\d+/apps/installable_organizations/\d+/accessible_repositories(/|$)}
        ::Api::EnterpriseApps

      when %r{^enterprises/[^/]+/audit-log/stream-key(/|$)},
           %r{^enterprises/[^/]+/audit-log/streams(/|$)},
           %r{^enterprises/[^/]+/audit-log/streams/\d+(/|$)}
        ::Api::AuditLog::Streams

      when %r{^enterprises/[^/]+/audit-log(/|$)}
        ::Api::AuditLog::Enterprise

      when ENTERPRISE_SECRET_SCANNING_REGEX
        ::Api::EnterpriseSecretScanning

      when %r{^enterprises/\d+/settings/billing/}
        ::Api::Billing

      when %r{^enterprise-installation/usage-metrics/actions-job-executions}
        ::Api::EnterpriseInstallationActionsJobExecutions
      when %r{^enterprise-installation}
        ::Api::EnterpriseInstallation

      when %r{^enterprise/announcement}
        if GitHub.enterprise?
          ::Api::Enterprise::Announcement
        else
          ::Api::Root
        end
      when %r{^enterprise/contractors}
        if GitHub.enterprise?
          ::Api::Enterprise::Contractors
        else
          ::Api::Root
        end
      when %r{^enterprise/stats/security-products}
        if GitHub.enterprise?
          ::Api::Enterprise::Stats::SecurityProducts
        else
          ::Api::Root
        end
      when %r{^enterprise/stats}
        if GitHub.enterprise?
          ::Api::Enterprise::Stats
        else
          ::Api::Root
        end
      when %r{^enterprise/avatars}
        if GitHub.enterprise?
          ::Api::Enterprise::Avatars
        else
          ::Api::Root
        end
      when %r{^enterprise/(github|settings)}
        if GitHub.enterprise?
          ::Api::Enterprise::Settings
        else
          ::Api::Root
        end

      when %r{^enterprise/actions-token}
        if GitHub.enterprise?
          ::Api::Enterprise::Actions
        else
          ::Api::Root
        end

      when %r{^enterprise/tokens}
        if GitHub.enterprise?
          ::Api::Enterprise::Tokens
        else
          ::Api::Root
        end

      when %r{^enterprises/\d+/code-scanning}
        ::Api::EnterpriseCodeScanning

      when %r{^enterprises/\d+/properties/schema(/|$)}
        ::Api::EnterpriseCustomPropertiesSchema

      when %r{^enterprises/\d+/dependabot/alerts}
        ::Api::EnterpriseDependabotAlerts

      when COPILOT_ENTERPRISE_SEATS_REGEX
        ::Api::CopilotForBusiness::Seats

      when COPILOT_ENTERPRISE_USAGE_REGEX
        ::Api::CopilotForBusiness::Usage

      when COPILOT_ENTERPRISE_TEAM_USAGE_REGEX
        ::Api::CopilotForBusiness::Usage

      when ENTERPRISE_TEAM_MEMBERSHIPS_REGEX
        ::Api::EnterpriseTeamMemberships

      when ENTERPRISE_TEAMS_REGEX
        ::Api::EnterpriseTeams
      end

    end

    def select_organization_app(route_path)
      case route_path
      when %r{^organizations/\d+/codespaces/secrets(/|$)},
           %r{^organizations/\d+/codespaces/secrets/\w+/repositories}
        ::Api::Codespaces::Secrets::Organization

      when CODESPACES_ORGANIZATION_REGEX
        ::Api::Codespaces::Organization

      when COPILOT_ORG_SEATS_REGEX
        ::Api::CopilotForBusiness::Seats

      when COPILOT_ORG_USAGE_REGEX
        ::Api::CopilotForBusiness::Usage

      when COPILOT_TEAM_USAGE_REGEX
        ::Api::CopilotForBusiness::Usage

      when %r{^organizations/\d+/migrations(/|$)}
        ::Api::Migrations

      when %r{^organizations/\d+/announcement}
        ::Api::AnnouncementBanners

      when %r{^organizations/\d+/hooks}
        ::Api::OrganizationHooks

      when %r{^organizations/\d+/pre-receive-hooks}
        ::Api::OrganizationPreReceiveHooks

      when %r{^organizations/\d+/actions/required_workflows(/|$)}
        ::Api::RequiredWorkflows

      when %r{^organizations/\d+/actions/runners(/|$)}
        ::Api::OrganizationRunners

      when %r{^organizations/\d+/actions/hosted-runners(/|$)}
        ::Api::OrganizationHostedRunners

      when %r{^organizations/\d+/settings/network-configurations(/|$)}
        ::Api::OrganizationNetworkConfigurations

      when %r{^organizations/\d+/credential-authorizations(/|$)}
        ::Api::OrganizationsCredentialAuthorizations

      when %r{^organizations/[^/]+/audit-log(/|$)}
        ::Api::AuditLog::Organization

      when %r{^organizations/\d+/secret-scanning}
        ::Api::OrganizationSecretScanning

      when %r{^organizations/\d+/code-scanning}
        ::Api::OrganizationCodeScanning

      when %r{^organizations/\d+/dependabot/alerts}
        ::Api::OrganizationDependabotAlerts

      when %r{^organizations/\d+/code-security/configurations}
        ::Api::OrganizationCodeSecurityConfigurations

      when %r{^organizations/\d+/security-advisories}
        ::Api::OrganizationRepositoryAdvisories

      when %r{^organizations/\d+/actions/github-hosted-runners/images/custom/\d+/versions(/|$)},
           %r{^organizations/\d+/actions/github-hosted-runners/\d+(/|$)}
        ::Api::OrganizationLargerGitHubRunners

      when %r{^organizations/\d+/actions/cache(/|$)}
        ::Api::OrganizationActionsCache

      when %r{^organizations/\d+/actions/oidc/customization/sub(/|$)}
        ::Api::OrganizationOIDCCustomSubClaimTemplateApi

      when %r{^organizations/\d+/repos(/|$)}
        ::Api::Repositories

      when %r{^organizations/\d+/settings/billing/}
        ::Api::Billing

      when %r{^organizations/\d+/actions/runner-groups(/|$)}
        ::Api::OrganizationRunnerGroups

      when %r{^organizations/\d+/actions/permissions(/|$)}
        ::Api::OrganizationActionsPermissions

      when %r{^organizations/\d+/actions/secrets(/|$)}
        ::Api::OrganizationActionsSecrets

      when %r{^organizations/\d+/actions/variables(/|$)}
        ::Api::OrganizationActionsVariables

      when %r{^organizations/\d+/dependabot/secrets(/|$)}
        ::Api::OrganizationDependabotSecrets

      when %r{^organizations/\d+/properties/schema(/|$)},
           %r{^organizations/\d+/properties/schema/\d+}
        ::Api::OrganizationCustomPropertiesSchema

      when %r{^organizations/\d+/properties/values}
        ::Api::OrganizationCustomPropertiesValues

      when %r{^organizations/\d+/(public_)?members(/[^/]+|$)},
           %r{^organizations/\d+/memberships(/[^/]+|$)}
        ::Api::OrganizationMembers

      when %r{^organizations/\d+/interaction-limits}
        ::Api::InteractionLimits

      when %r{^organizations/\d+/(failed_)?invitations}
        ::Api::OrganizationInvitations

      when %r{^organizations/\d+/outside_collaborators(/[^/]+|$)}
        ::Api::OrganizationOutsideCollaborators

      when ORGANIZATION_OUTSIDE_COLLABORATORS_REGEX
        ::Api::OrganizationProgrammaticAccessGrantRequests

      when ORGANIZATION_PROGRAMMATIC_ACCESS_GRANTS_REGEX
        ::Api::OrganizationProgrammaticAccessGrants

      when %r{^organizations/\d+/team/\d+/discussions/\d+/reactions},
           %r{^organizations/\d+/team/\d+/discussions/\d+/comments/\d+/reactions}
        ::Api::Reactions

      when %r{^organizations/\d+/team/\d+/discussions}
        ::Api::TeamDiscussions

      when %r{^organizations/\d+/team/\d+/projects(/|$)}
        ::Api::OrganizationTeamProjects

      when %r{^organizations/\d+/team/\d+/repos},
           %r{^organizations/\d+/team/\d+/repositories/}
        ::Api::OrganizationTeamRepositories

      when ORGANIZATION_TEAM_SYNC_REGEX
        ::Api::OrganizationTeamSync

      when ORGANIZATION_EXTERNAL_GROUPS_REGEX
        ::Api::OrganizationExternalGroups

      when %r{^organizations/\d+/projects}
        ::Api::Projects

      when %r{^organizations/\d+/packages},
           %r{^organizations/\d+/docker/conflicts}
        ::Api::Packages

      when %r{^organizations/\d+/events}
        ::Api::Events

      when %r{^organizations/\d+/blocks}
        ::Api::UserBlocking

      when %r{^organizations/\d+/issues}
        ::Api::Issues

      when %r{^organizations/\d+/rulesets}
        ::Api::RepositoryRules

      when ORGANIZATION_TEAMS_REGEX
        ::Api::OrganizationTeams

      when %r{^organizations/\d+/custom_roles},
           %r{^organizations/\d+/custom-repository-roles}
        ::Api::OrganizationCustomRoles

      when ORGANIZATION_ROLE_ASSIGNMENT_REGEX
        ::Api::OrganizationRoleAssignment

      when %r{^organizations/\d+/organization-roles}
        ::Api::OrganizationCustomOrgRoles

      when %r{^organizations/\d+/fine_grained_permissions},
           %r{^organizations/\d+/repository-fine-grained-permissions}
        ::Api::OrganizationFineGrainedPermissions

      when %r{^organizations/\d+/organization-fine-grained-permissions}
        ::Api::OrganizationFineGrainedOrgPermissions

      when %r{^organizations/\d+/installation(/|$)}
        ::Api::Integrations

      when %r{^organizations/\d+/security-managers}
        ::Api::OrganizationSecurityManagers

      when %r{^organizations/\d+/attestations.*$}
        ::Api::Attestations

      when %r{^organizations/\d+/knowledge-bases(/[^/]+|$)}
        ::Api::KnowledgeBases

      when %r{^organizations}
        ::Api::Organizations
      end
    end

    def select_repository_app(route_path)
      case route_path
      when %r{^repositories/\d+/collaborators}
        ::Api::RepositoryCollaborators

      when %r{^repositories/\d+/keys}
        ::Api::RepositoryKeys

      when %r{^repositories/\d+/autolinks(/|$)},
           %r{^repositories/\d+/autolinks/\d+}
        ::Api::RepositoryAutolinks

      when %r{^repositories/\d+/lfs(/|$)}
        ::Api::RepositoryLfs

      when %r{^repositories/\d+/dispatches}
        ::Api::RepositoryEventDispatches

      when %r{^repositories/\d+/import/issues}
        ::Api::ImportIssues

      when %r{^repositories/\d+/import}
        ::Api::Porter

      when %r{^repositories/\d+/pre-receive-hooks}
        ::Api::RepositoryPreReceiveHooks

      when REPOSITORY_CONTENTS_REGEX
        ::Api::RepositoryContents

      when CHECK_RUNS_REGEX
        ::Api::CheckRuns

      when CHECK_SUITES_REGEX
        ::Api::CheckSuites

      when %r{^repositories/\d+/comments/\d+/reactions}
        ::Api::RepositoryCommitCommentReactions

      when %r{^repositories/\d+/comments(/|$)},
           %r{^repositories/\d+/commits/.+/comments(/|$)}
        ::Api::RepositoryCommitComments

      when %r{^repositories/\d+/commits(/|$)}
        ::Api::RepositoryCommits

      when %r{^repositories/\d+/activity(/|$)}
        ::Api::RepositoryActivities

      when %r{^repositories/\d+/actions/oidc/customization/sub(/|$)}
        ::Api::RepositoryOIDCCustomSubClaimTemplate

      when %r{^repositories/\d+/actions/resolve/(?<ref>.*)$}
        ::Api::ActionsResolve

      when JOBS_REGEX
        ::Api::Jobs

      when %r{^repositories/\d+/actions/artifacts(/|$)},
           %r{^repositories/\d+/actions/runs/\d+/artifacts}
        ::Api::Artifacts

      when %r{^repositories/\d+/actions/cache(s)?(/|$)}
        ::Api::ActionsCache

      when %r{^repositories/\d+/attestations.*$}
        ::Api::Attestations

      when %r{^repositories/\d+/actions/runs/\d+/pending_deployments$},
           %r{^repositories/\d+/actions/runs/\d+/deployment_protection_rule$}
        ::Api::DeploymentRequests

      when WORKFLOW_RUNS_REGEX
        ::Api::WorkflowRuns

      when %r{^repositories/\d+/actions/workflows(/|$)},
           %r{^repositories/\d+/actions/workflows/[^/]+/dispatches$}
        ::Api::Workflows

      when %r{^repositories/\d+/actions/dynamic$},
           %r{^repositories/\d+/actions/dynamic/[^/]+(/|$)}
        ::Api::ActionsDynamicWorkflows

      when %r{^repositories/\d+/actions/runners(/|$)}
        ::Api::RepositoryRunners

      when %r{^repositories/\d+/codeowners/errors$}
        ::Api::Codeowners

      when %r{^repositories/\d+/actions/required_workflows(/|$)}
        ::Api::RequiredWorkflows

      when %r{^repositories/\d+/actions/permissions(/|$)}
        ::Api::RepositoryActionsPermissions

      when %r{^repositories/\d+/codespaces/secrets(/|$)}
        ::Api::Codespaces::Secrets::Repository

      when %r{^repositories/\d+/codespaces},
           %r{^repositories/\d+/pulls/[^/]+/codespaces}
        ::Api::Codespaces::Public

      when %r{^repositories/\d+/actions/secrets(/|$)},
           %r{^repositories/\d+/actions/organization-secrets(/|$)}
        ::Api::ActionsSecrets

      when %r{^repositories/\d+/dependabot/secrets(/|$)}
        ::Api::DependabotSecrets

      when %r{^repositories/\d+/environments/[^/]+/secrets(/|$)}
        ::Api::EnvironmentSecrets

      when %r{^repositories/\d+/environments/[^/]+/variables(/|$)}
        ::Api::EnvironmentActionsVariables

      when %r{^repositories/\d+/environments/[^/]+/deployment_protection_rules(/|$)}
        ::Api::DeploymentProtectionRules

      when %r{^repositories/\d+/actions/variables(/|$)},
           %r{^repositories/\d+/actions/organization-variables(/|$)}
        ::Api::ActionsVariables

      when %r{^repositories/\d+/environments/[^/]+/deployment-branch-policies(/|$)}
        ::Api::DeploymentBranchPolicies

      when %r{^repositories/\d+/environments(/|$)}
        ::Api::Environments

      when %r{^repositories/\d+/deployments/\d+/statuses}
        ::Api::DeploymentStatuses

      when %r{^repositories/\d+/pulls/comments/\d+/reactions}
        ::Api::PullCommentReactions

      when %r{^repositories/\d+/pulls/comments},
           %r{^repositories/\d+/pulls/[^/]+/comments}
        ::Api::PullComments

      when %r{^repositories/\d+/pulls/[^/]+/reviews/\d+/(events|dismissals)}
        ::Api::PullRequestReviewEvents

      when %r{^repositories/\d+/pulls/[^/]+/reviews}
        ::Api::PullRequestReviews

      when %r{^repositories/\d+/pulls/[^/]+/requested_reviewers}
        ::Api::PullRequestReviewRequests

      when %r{^repositories/\d+/pulls}
        ::Api::Pulls

      when %r{^repositories/\d+/deployments}
        ::Api::Deployments

      when %r{^repositories/\d+/pages}
        ::Api::RepositoryPages

      when %r{^repositories/\d+/private-vulnerability-reporting}
        ::Api::RepositoryAdvisories

      when %r{^repositories/\d+/vulnerability-alerts}
        ::Api::RepositoryVulnerabilityAlerts

      when %r{^repositories/\d+/automated-security-fixes}
        ::Api::RepositoryAutomatedSecurityFixes

      when %r{^repositories/\d+/properties/values}
        ::Api::RepositoryCustomProperties

      when %r{^repositories/\d+/releases/\d+/reactions}
        ::Api::RepositoryReleaseReactions

      when %r{^repositories/\d+/stats(/|$)}
        ::Api::RepositoryStats

      when %r{^repositories/\d+/tags/protection}
        ::Api::RepositoryTagProtectionStates

      when %r{^repositories/\d+/dependency-graph/compare/.+\.\.\..+$}
        ::Api::RepositoryDependencyGraphDiff

      when %r{^repositories/\d+/dependency-graph/sbom$}
        ::Api::RepositoryDependencyGraphSBOM

      when %r{^repositories/\d+/dependency-graph}
        ::Api::RepositoryDependencyGraph

      # This API node will be deprecated soon
      when %r{^repositories/\d+/snapshots}
        ::Api::RepositoryDependencyGraph

      when %r{^repositories/\d+/security-advisories(/|$)}
        ::Api::RepositoryAdvisories

      when %r{^repositories/\d+/actions-runners}
        ::Api::RepositoryActionsRunners

      when %r{^repositories/\d+/announcement}
        ::Api::AnnouncementBanners

      when REPOSITORY_BRANCHES_REGEX
        ::Api::RepositoryBranches

      when %r{^repositories/\d+/community/([^/]+)}
        ::Api::RepositoryCommunity

      when %r{^repositories/\d+/interaction-limits}
        ::Api::InteractionLimits

      when %r{^repositories/\d+/issues/comments/\d+/reactions},
           %r{^repositories/\d+/issues/\d+/reactions}
        ::Api::Reactions

      when REPOSITORY_POLICIES_REGEX
        ::Api::Policies

      when %r{^repositories/\d+/hooks}
        ::Api::RepositoryHooks

      when %r{^repositories/\d+/projects}
        ::Api::Projects

      when %r{^repositories/\d+/events}
        ::Api::Events

      when %r{^repositories/\d+/releases}
        ::Api::RepositoryReleases

      when %r{^repositories/\d+/codespaces/machines}
        ::Api::Codespaces::Public

      when %r{^repositories/\d+/issues/([^/]+/)?comments}
        ::Api::IssueComments

      when %r{^repositories/\d+/issues/([^/]+/)?assignees}
        ::Api::IssueAssignees

      when %r{^repositories/\d+/issues/([^/]+/)?events}
        ::Api::IssueEvents

      when %r{^repositories/\d+/issues/([^/]+/)?timeline}
        ::Api::IssueTimeline

      when %r{^repositories/\d+/issues/[^/]+/labels}
        ::Api::Labels

      when %r{^repositories/\d+/labels(/|$)}
        ::Api::Labels

      when %r{^repositories/\d+/milestones/[^/]+/labels$}
        ::Api::Labels
      when %r{^repositories/\d+/milestones(/|$)}
        ::Api::Milestones

      when %r{^repositories/\d+/traffic(/|$)}
        ::Api::Traffic

      when %r{^repositories/\d+/(notifications|subscription)}
        ::Api::Notifications

      when %r{^repositories/\d+/hooks}
        ::Api::RepositoryHooks

      when %r{^repositories/\d+/rules}
        ::Api::RepositoryRules

      when %r{^repositories/\d+/issues(/|$)}
        ::Api::Issues

      when %r{^repositories/\d+/assignees(/|$)}
        ::Api::Issues

      when %r{^repositories/\d+/git/commits(/|$)}
        ::Api::GitCommits
      when %r{^repositories/\d+/git/(trees|tree-file-list)(/|$)}
        ::Api::GitTrees
      when %r{^repositories/\d+/git/blobs(/|$)}
        ::Api::GitBlobs
      when %r{^repositories/\d+/git/tags(/|$)}
        ::Api::GitTags
      when %r{^repositories/\d+/git/refs(/|$)}
        ::Api::GitRefs
      when %r{^repositories/\d+/git/(ref|matching-refs|extract-ref)/}
        ::Api::GitRefs
      when %r{^repositories/\d+/git}
        ::Api::Git
      when %r{^repositories/\d+/status(es)?(/|$)}
        ::Api::Statuses

      when %r{^repositories/\d+/(watchers|stargazers)(/|$)}
        ::Api::RepositoryActivityStars

      when %r{^repositories/\d+/subscribers(/|$)}
        ::Api::RepositoryActivitySubscriptions

      when %r{^repositories/\d+/invitations}
        ::Api::RepositoryInvitations

      when %r{^repositories/\d+/topics(/|$)}
        ::Api::Topics

      when %r{^repositories/\d+/installation}
        ::Api::Integrations

      when %r{^repositories/\d+/code_scanning/(analysis|sarifs)$},
           %r{^repositories/\d+/code-scanning/(analysis|sarifs)$}
        ::Api::RepositoryCodeScanningUpload

      when %r{^repositories/\d+/code-scanning/codeql-action}
        ::Api::RepositoryCodeScanningCodeqlAction

      when %r{^repositories/\d+/code-scanning/codeql/databases}
        ::Api::RepositoryCodeScanningDatabases

      when %r{^repositories/\d+/code-scanning/codeql/status}
        ::Api::RepositoryCodeScanningCodeql

      when %r{^repositories/\d+/code-scanning/codeql/auto-model}
        ::Api::RepositoryCodeqlAutoModel

      when %r{^repositories/\d+/code-scanning/codeql/variant-analyses$},
           %r{^repositories/\d+/code-scanning/codeql/variant-analyses/\d+$}
        ::Api::RepositoryCodeqlVariantAnalyses

      when %r{^repositories/\d+/code-scanning/codeql/variant-analyses/\d+/repositories/\d+$}
        ::Api::RepositoryCodeqlVariantAnalysisRepoTasks

      when REPOSITORY_CODEQL_VARIANT_ANALYSIS_REPO_TASKS_UPDATE_REGEX
        ::Api::RepositoryCodeqlVariantAnalysisRepoTasksUpdate

      when %r{^repositories/\d+/code-scanning/default-setup}
        ::Api::RepositoryCodeScanningDefaultSetup

      when %r{^repositories/\d+/code-scanning/alerts/\d+/fixes}
        ::Api::RepositoryCodeScanningAutofix

      when %r{^repositories/\d+/code_scanning},
           %r{^repositories/\d+/code-scanning}
        ::Api::RepositoryCodeScanning

      when %r{^repositories/\d+/secret-scanning}
        ::Api::RepositorySecretScanning

      when %r{^repositories/\d+/dependabot/alerts}
        ::Api::RepositoryDependabotAlerts

      when %r{^repositories/\d+/reachability}
        ::Api::Reachability

      when %r{^repositories/\d+/discussions(/|$)}
        ::Api::Discussions

      when %r{^repositories/\d+/code-security-configuration}
        ::Api::RepositoryCodeSecurityConfigurations
      end
    end

    def select_other_app(route_path, env)
      case route_path
      when %r{^third-party/mailchimp/webhook(/|$)}
        ::Api::ThirdParty::Mailchimp

      when %r{^user/codespaces/secrets/\w+/repositories(/|$)}
        ::Api::Codespaces::Secrets::UserRepositories

      when %r{^user/codespaces/secrets(/|$)}
        ::Api::Codespaces::Secrets::User

      when %r{^user/codespaces(/|$)}
        ::Api::Codespaces::Public

      when %r{^lfs/}
        ::Api::Lfs

      when %r{^gists/[^/]+/comments$},
           %r{^gists/([^/]+/)?comments/[^/]+(/|$)}
        ::Api::GistComments

      when %r{^user/\d+/attestations.*$}
        ::Api::Attestations

      when %r{^user/\d+/gists(/|$)},
           %r{^gists(/|$)}
        ::Api::Gists

      when %r{^notifications(/|$)}
        ::Api::Notifications

      when POLICIES_REGEX
        ::Api::Policies

      when %r{^businesses/[^/]+/user-accounts-uploads(/|$)}
        ::Api::BusinessEnterpriseInstallationUserAccountsUploads

      when %r{^user/\d+/repos(/|$)},
           %r{^user/repos(/|$)}
        ::Api::Repositories

      when %r{^repositories/\d+/immutable-actions},
           %r{^repos/\d+/immutable-actions}
        ::Api::RepositoryActionsReleasesMigration

      when %r{^user/(watched|starred)(/|$)},
           %r{^user/\d+/(watched|starred)(/|$)}
        ::Api::RepositoryActivityStars

      when %r{^user/subscriptions(/|$)},
           %r{^user/\d+/subscriptions(/|$)}
        ::Api::RepositoryActivitySubscriptions

      when %r{^hooks(/|$)}
        ::Api::RepositoryHooks

      when %r{^user/migrations(/|$)}
        ::Api::Migrations

      when %r{^user/teams},
           %r{^user/memberships/teams}
        ::Api::OrganizationTeams


      when %r{^reactions/\d+}
        ::Api::Reactions

      when %r{^marketplace/actions/verified_owners$}
        ::Api::ActionsVerifiedOwners

      when %r{^projects/\d+/collaborators}
        ::Api::ProjectCollaborators

      when PROJECTS_REGEX
        ::Api::Projects

      when %r{^user/packages},
           %r{^user/\d+/packages},
           %r{^user/docker/conflicts},
           %r{^user/\d+/docker/conflicts},
           %r{^packages/container-registry-url}
        ::Api::Packages

      when EVENTS_REGEX
        ::Api::Events

      when %r{^user/blocks}
        ::Api::UserBlocking

      when %r{^user/interaction-limits(/|$)}
        ::Api::InteractionLimits

      when %r{^user/issues}
        ::Api::Issues

      when %r{^actions/runner-registration}
        ::Api::ActionsRunnerRegistration

      when %r{^actions/runners/register}
        ::Api::ActionsRunnerRegistration

      when %r{^org(s)?/\d+/credential-authorizations(/|$)}
        ::Api::OrganizationsCredentialAuthorizations

      when %r{^user/\d+/settings/billing/}
        ::Api::Billing

      when %r{^org(s)?/[^/]+/audit-log(/|$)}
        ::Api::AuditLog::Organization

      when GITHUB_CHATOPS_REGEX
        ::Api::GitHubChatops

      when %r{^org(s)?/\d+/secret-scanning}
        ::Api::OrganizationSecretScanning

      when %r{^org(s)?/\d+/code-scanning}
        ::Api::OrganizationCodeScanning

      when %r{^org(s)?/\d+/dependabot/alerts}
        ::Api::OrganizationDependabotAlerts

      when %r{^org(s)?/\d+/code-security/configurations}
        ::Api::OrganizationCodeSecurityConfigurations

      when ORGANIZATIONS_REGEX
        ::Api::Organizations

      when %r{^scim/v2/organizations/\d+(/|$)}
        ::Api::OrganizationsScim

      when %r{^scim/v2/enterprises/[^/]+/Users(/|$)}
        ::Api::EnterpriseUsersScim

      when %r{^scim/v2/enterprises/[^/]+/Groups(/|$)}
        ::Api::EnterpriseGroupsScim

      when %r{^user/repository_invitations(/|$)}
        ::Api::RepositoryInvitations

      when %r{^issues}
        ::Api::Issues

      when %r{^repos}
        ::Api::Repositories

      when %r{^search/(users|repositories|code|commits|issues|topics|labels)(/|$)}
        ::Api::Search

      when %r{^internal/graphql/operations}
        ::Api::Internal::GraphQlOperations

      when %r{^exports/dsr/user/[^/]+}
        ::Api::DsrOperations

      when %r{^graphql(/|$)}
        # Don't match /api/v3 as a path for GraphQL
        if use_path_prefix? && env[API_PATH] == "/api/v3"
          ::Api::Root
        else
          ::Api::GraphQL
        end

      when %r{^staff/stafftools/}
        ::Api::Staff::Entitlements
      when %r{^staff/.*/?emails?(/|$)}
        ::Api::Staff::Emails
      when %r{^staff/repos/}
        ::Api::Staff::Repositories
      when %r{^staff/ghas_trial/}
        ::Api::Staff::GhasTrials
      when %r{^staff/copilot_trials/}
        ::Api::Staff::CopilotTrials
      when %r{^staff/licensing_model_transitions}
        ::Api::Staff::LicensingModelTransitions
      when %r{^staff/audit_log/}
        ::Api::Staff::AuditLog
      when %r{^staff/enterprises/}
        ::Api::Staff::Enterprises

      when %r{^hub/?$}
        ::Api::Hub

      when %r{^admin/ldap}
        ::Api::Admin::Ldap

      when %r{^admin/user}
        ::Api::Admin::UsersManager

      when %r{^admin/organization}
        ::Api::Admin::OrgsManager

      when %r{^admin/key}
        ::Api::Admin::Keys

      when %r{^admin/token}
        ::Api::Admin::Tokens

      when %r{^admin/pre-receive-environments}
        ::Api::Admin::PreReceiveEnvironments

      when %r{^admin/pre-receive-hooks}
        ::Api::Admin::PreReceiveHooks

      when %r{^admin/hooks}
        ::Api::Admin::Webhooks

      when %r{^authorizations(/|$)}, %r{^legacy/token}
        if GitHub.api_password_auth_supported?
          ::Api::Authorizations
        else
          ::Api::Root
        end
      when INTEGRATION_INSTALLATIONS_REGEX
        ::Api::IntegrationInstallations

      when %r{^installations/}
        ::Api::Integrations

      when %r{^app($)},
           %r{^app/hook/}
        ::Api::Integrations

      when INTEGRATIONS_REGEX
        ::Api::Integrations

      when %r{^app(/)}
        ::Api::GitHubApps

      when %r{^app-manifests}
        ::Api::IntegrationManifests

      when %r{^(desktop|desktop_internal)/.*}
        ::Api::Desktop

      when %r{^markdown}
        ::Api::Markdown

      when %r{^feeds(/|$)}
        ::Api::Feeds

      when %r{^languages(/|$)}
        ::Api::Languages

      when %r{^legacy(/|$)}
        ::Api::Legacy

      when %r{^alive_internal/.*}
        ::Api::Alive

      when %r{^applications/grants(/|$)}
        if GitHub.api_password_auth_supported?
          ::Api::Grants
        else
          ::Api::Root
        end

      when %r{^applications(/|$)}
        ::Api::Applications

      when %r{^gitignore(/|$)}
        ::Api::GitignoreTemplates

      when %r{^licenses(/|$)}
        ::Api::Licenses

      when %r{^codes_of_conduct(/|$)}
        ::Api::CodesOfConduct

      when %r{^meta(/|$)}
        ::Api::Meta

      when %r{^(octocat|zen)}
        ::Api::MonaLisaOctocat

      when %r{^_private/browser/}
        ::Api::BrowserReporting

      when %r{^marketplace_listing/stubbed(/|$)}
        ::Api::MarketplaceListing::Stubbed

      when %r{^marketplace_listing(/|$)}
        ::Api::MarketplaceListing

      when USER_EMAILS_REGEX
        ::Api::UserEmails

      when USER_FOLLOWERS_REGEX
        ::Api::UserFollowers

      when %r{^user/gpg_keys(/|$)},
           %r{^user/\d+/gpg_keys(/|$)}
        ::Api::UserGpgKeys

      when %r{^user/\d+/hovercard$}
        ::Api::UserHovercards

      when %r{^user/keys(/|$)},
           %r{^user/\d+/keys(/|$)}
        ::Api::UserPublicKeys

      when %r{^user/ssh_signing_keys(/|$)},
           %r{^user/\d+/ssh_signing_keys(/|$)}
        ::Api::UserSshSigningKeys

      when %r{^user/social_accounts(/|$)},
           %r{^user/\d+/social_accounts(/|$)}
        ::Api::UserSocialAccounts

      when %r{^user/knowledge-bases(/|$)}
        ::Api::KnowledgeBases

      when %r{^user}
        ::Api::Users

      when %r{^versions}
        ::Api::Versions

      when %r{^status}
        ::Api::Status

      when MOBILE_UPLOADS_REGEX
        ::Api::Mobile::Uploads

      when %r{^mobile/support-token}
        ::Api::Mobile::Support

      when %r{^vscs_internal/codespaces/repository/\d+/prebuild.*},
           %r{^codespaces_internal/prebuilds/repository/\d+}
        ::Api::Codespaces::Prebuilds

      when %r{^vscs_internal/},
           %r{^codespaces_internal/}
        ::Api::Codespaces::Private

      when COPILOT_REGEX
        ::Api::Copilot

      when %r{^vsc_internal/.*}
        ::Api::VscodeInternal

      when %r{^classroom/user/assignments}
        ::Api::Classroom::Assignments

      when %r{^classrooms}, %r{^assignments}
        ::Api::Classroom

      when %r{^advisory-database}
        ::Api::AdvisoryDatabase

      when %r{^advisories}
        ::Api::GlobalAdvisories

      when %r{^chunks}, %r{^code}, %r{^embeddings}, %r{^symbols}
        ::Api::ServiceProxy

      else
        ::Api::Root
      end
    end

    def select_app_without_instrumentation(env)
      # mark this as an API request
      env[ProcessCategoryKey] = env[ProcessCategoryDataDogKey] = ProcessCategory
      Failbot.push("gh.request.category": ProcessCategory)

      route_path = routable_path(env)

      app = if route_path.nil?
        ::Api::Root
      elsif route_path.start_with?("internal")
        select_internal_app(route_path)
      elsif route_path.start_with?("enterprise")
        select_enterprise_app(route_path)
      elsif route_path.start_with?("organizations")
        select_organization_app(route_path)
      elsif route_path.start_with?("repositories")
        select_repository_app(route_path)
      end

      if app.nil?
        app = select_other_app(route_path, env)
      end

      # Add the API app name to env for better stats gathering
      env["process.api_app"] = app.name.demodulize
      env["process.api.controller"] = app.name
      Rack::ConditionalGet.new(app)
    end

    # Converts the PATH_INFO into a path that is routable for the API.
    #
    # env - The Hash environment of the current Rack request.
    #
    # Returns the String path without a leading slash.
    def routable_path(env)
      path = env[PATH_INFO]
      env[ORIGINAL_PATH_INFO] = path

      id_path = convert_actions_org_names(env, path)
      id_path = convert_natural_keys_to_ids(env, id_path)
      id_path = convert_inline_refs_to_tailing_refs(env, id_path)
      id_path = convert_ambiguous_commits_ref_to_sha(env, id_path)
      id_path = convert_variant_analysis_repository_nwo_to_id(env, id_path)

      env[ThisRepositoryKey] ||= load_repository_from_path_param(env, id_path)
      env[PATH_INFO] = id_path
      env[PATH_INFO][1..-1]
    end

    def load_repository_from_path_param(env, path)
      if match = RepositoryIDRegex.match(path)
        ActiveRecord::Base.connected_to(role: :reading) do
          Repositories::Public.find_active(T.must(match[:repo_id]))
        end
      end
    end

    def convert_actions_org_names(env, path)
      return path unless GitHub.enterprise?
      return path unless (GitHub.actions_org && GitHub.actions_org != "actions".freeze) ||
        (GitHub.github_org && GitHub.github_org != "github".freeze)

      match = path =~ %r{^/repos/([^/]+)/([^/]+)/actions/resolve/(.*)}
      return path if match.nil?

      org = $1
      org = GitHub.actions_org if org == "actions".freeze
      org = GitHub.github_org if org == "github".freeze
      nwo = "#{org}/#{$2}"

      # Given that we lose access to the original action name through rewriting
      # the path, we should add it to the query string in the env.
      env[QUERY_STRING] = "_action=#{CGI::escape("#{$1}/#{$2}")}"
      env[PATH_INFO] = "/repos/#{nwo}/actions/resolve/#{$3}"
    end

    def convert_natural_keys_to_ids(env, path)
      case path
      when %r{^/repos/([^/]+)/([^/]+)(.*)}
        convert_repository_key_to_id(env, path, $1, $2, $3, "/repositories")
      when %r{^/installations/(\d+)/repos/([^/]+)/([^/]+)(.*)}
        convert_repository_key_to_id(env, path, $2, $3, $4, "/installations/#{$1}/repositories")
      when %r{^/orgs/([^/]+)/teams/([^/]+)/repos/([^/]+)/([^/]+)(.*)}
        convert_organization_and_team_and_repos_key_to_id(env, path, $1, $2, $3, $4, $5, "/organizations", "/team", "/repositories")
      when %r{^/orgs/([^/]+)(/[^/]+)?/teams/([^/]+)(.*)}
        convert_organization_and_team_key_to_id(env, path, $1, $3, $4, "/organizations", "#{$2}/team")
      when %r{^/orgs/([^/]+)/team/([^/]+)/copilot/usage(.*)}
        convert_organization_and_team_key_to_id(env, path, $1, $2, "/copilot/usage#{$3}", "/organizations", "/team")
      when %r{^/orgs/([^/]+)/team/(\d+)/repos/([^/]+)/([^/]+)(.*)}
        convert_organization_and_repos_key_to_id(env, path, $1, $2, $3, $4, $5, "/organizations", "/team", "/repositories")
      when %r{^/orgs/([^/]+)/members/([^/]+)/codespaces/?([^/]+)?(.*)}
        convert_organization_and_username_key_to_id(env, path, $1, $2, $3, $4, "/organizations", "/members", "/codespaces")
      when %r{^/orgs/([^/]+)/members/([^/]+)/copilot/?([^/]+)?(.*)}
        convert_organization_and_username_key_to_id_copilot(env, path, $1, $2, $3, "/organizations", "/members")
      when %r{^/orgs/([^/]+)/attestations/(.*)}
        convert_organization_and_username_key_to_id_attestations(env, path, $1, "/attestations/#{$2}")
      when %r{^/orgs/([^/]+)(.*)}
        convert_organization_key_to_id(env, path, $1, $2, "/organizations")
      when %r{^/organizations/(\d+)/teams/([^/]+)/repos/([^/]+)/([^/]+)(.*)}
        convert_team_and_repos_key_to_id(env, path, $1, $2, $3, $4, $5, "/organizations/#{$1}/team", "/repositories")
      when %r{^/organizations/(\d+)/teams/([^/]+)(.*)}
        convert_team_key_to_id(env, path, $1, $2, $3, "/organizations/#{$1}/team")
      when %r{^/organizations/(\d+)/team/(\d+)/repos/([^/]+)/([^/]+)(.*)}
        convert_repository_key_to_id(env, path, $3, $4, $5, "/organizations/#{$1}/team/#{$2}/repositories")
      when %r{^/enterprises/([^/]+)/team/([^/]+)(.*)}
        convert_enterprise_and_team_key_to_id(env, path, $1, $2, $3, "/enterprises", "/team")
      when %r{^/enterprises/([^/]+)/teams/([^/]+)(.*)}
        convert_enterprise_and_team_key_to_id(env, path, $1, $2, $3, "/enterprises", "/teams")
      when %r{^/enterprises/([^/]+)(.*)}
        convert_enterprise_key_to_id(env, path, $1, $2, "/enterprises")
      when %r{^/teams/(\d+)/repos/([^/]+)/([^/]+)(.*)}
        deprecated_route!(
          env,
          deprecation_date: Date.new(2020, 02, 01),
          sunset_date: Date.new(2021, 02, 01),
          info_url: "#{GitHub.developer_blog_url}/2020-01-21-moving-the-team-api-endpoints/",
        )
        convert_legacy_team_and_repository_key_to_id(env, path, $1, $2, $3, $4, "/organizations", "/team/#{$1}/repositories")
      when %r{^/teams/(\d+)(.*)}
        deprecated_route!(
          env,
          deprecation_date: Date.new(2020, 02, 01),
          sunset_date: Date.new(2021, 02, 01),
          info_url: "#{GitHub.developer_blog_url}/2020-01-21-moving-the-team-api-endpoints/",
        )
        convert_legacy_team_key_to_id(env, path, $1, $2, "/organizations", "/team")
      when %r{^/user/memberships/orgs/([^/]+)(.*)}
        convert_organization_key_to_id(env, path, $1, $2, "/user/memberships/organizations")
      when %r{^/users/([^/]+)(.*)}
        convert_user_key_to_id(env, path, $1, $2, "/user")
      when %r{^/internal/repos/([^/]+)/([^/]+)(.*)}
        convert_repository_key_to_id(env, path, $1, $2, $3, "/internal/repositories")
      when %r{^/internal/repositories/([^/]+)/([^/]+)(.*)/git/pushes\z}
        convert_repository_key_to_id(env, path, $1, $2, "#{$3}/git/pushes", "/internal/repositories")
      when %r{^/internal/repositories/([^/]+)/([^/]+)/?\z}
        convert_repository_key_to_id(env, path, $1, $2, nil, "/internal/repositories")
      when %r{^/internal/gists/([^/]+)/([^/]+)(.*)/git/pushes\z}
        convert_gist_key_to_id(env, path, $1, $2, "#{$3}/git/pushes", "/internal/gists")
      when %r{^/internal/gists/([^/]+)/([^/]+)(.*)\z}
        convert_gist_key_to_id(env, path, $1, $2, $3, "/internal/gists")
      when %r{^/internal/gists/([0-9a-f]{20,})(.*)\z}
        convert_gist_repo_name_to_id(env, path, $1, $2, "/internal/gists")
      when %r{^/internal/orgs/([^/]+)(.*)}
        convert_organization_key_to_id(env, path, $1, $2, "/internal/organizations")
      when %r{^/internal/users/([^/]+)(.*)}
        convert_user_key_to_id(env, path, $1, $2, "/internal/user")
      when %r{^/scim/v2/organizations/([^/]+)(.*)}
        convert_organization_key_to_id(env, path, $1, $2, "/scim/v2/organizations")
      when %r{^/scim/v2/enterprises/([^/]+)(.*)}
        convert_enterprise_key_to_id(env, path, $1, $2, "/scim/v2/enterprises")
      when %r{^/scim/v2/(Users)(.*)}
        convert_base_scim_path_to_enterprise(env, path, $1, $2, "/scim/v2/enterprises")
      when %r{^/scim/v2/(Groups)(.*)}
        convert_base_scim_path_to_enterprise(env, path, $1, $2, "/scim/v2/enterprises")
      when %r{^/staff/orgs/([^/]+)(.*)}
        convert_organization_key_to_id(env, path, $1, $2, "/staff/organizations")
      when %r{^/staff/users/([^/]+)(.*)}
        convert_user_key_to_id(env, path, $1, $2, "/staff/user")
      when %r{^/admin/users/([^/]+)(.*)}
        convert_user_key_to_id(env, path, $1, $2, "/admin/user")
      when %r{^/admin/organizations/([^/]+)(.*)}
        convert_organization_key_to_id(env, path, $1, $2, "/admin/organization")
      when %r{^/admin/ldap/users/([^/]+)(.*)}
        convert_user_key_to_id(env, path, $1, $2, "/admin/ldap/user")
      when %r{^/apps/([^/]+)(.*)}
        convert_app_slug_to_id(env, path, $1, $2, "/app")
      when %r{^/vscs_internal/user/([^/]+)(.*)}
        convert_user_key_to_id(env, path, $1, $2, "/vscs_internal/user")
      when %r{^/vscs_internal/repository/([^/]+)/([^/]+)(.*)}
        convert_repository_key_to_id(env, path, $1, $2, $3, "/vscs_internal/repository")
      when %r{^/vscs_internal/codespaces/repository/([^/]+)/([^/]+)(.*)}
        convert_repository_key_to_id(env, path, $1, $2, $3, "/vscs_internal/codespaces/repository")
      when %r{^/codespaces_internal/prebuilds/repository/([^/]+)/([^/]+)(.*)}
        convert_repository_key_to_id(env, path, $1, $2, $3, "/codespaces_internal/prebuilds/repository")
      when %r{^/user/([^/]+)/settings/(.*)}
        convert_user_key_to_id(env, path, $1, "/settings/#{$2}", "/user")
      when %r{^/organizations/([^/]+)/settings/(.*)}
        convert_organization_key_to_id(env, path, $1, "/settings/#{$2}", "/organizations")
      when %r{^/enterprises/([^/]+)/settings/(.*)}
        convert_enterprise_key_to_id(env, path, $1, "/settings/#{$2}", "/enterprises")
      when %r{^/internal/blackbird/repositories/([^/]+)/([^/]+)/?\z}
        convert_repository_key_to_id(env, path, $1, $2, nil, "/internal/blackbird/repositories")
      when %r{^/internal/blackbird/users/([^/]+)\z}
        convert_user_key_to_id(env, path, $1, nil, "/internal/blackbird/user")
      else
        env[UnconvertedPathKey] = true
        path
      end
    end

    def owner_scoped_github_apps_enabled?
      GitHub.flipper[:owner_scoped_github_apps].enabled?
    end

    def convert_user_key_to_id(env, path, login, extra, prefix)
      login = ::Api::LegacyEncode.decode(login)
      user = env[ThisUserKey] = begin
        ActiveRecord::Base.connected_to(role: :reading) do
          if owner_scoped_github_apps_enabled?
            if login.ends_with?(Bot::LOGIN_SUFFIX)
              Bot.find_by_login(login)
            elsif GitHub.multi_tenant_enterprise?
              User.find_by_login(login) || Mannequin.find_by_login(login)
            else
              User.find_by_login(login)
            end
          elsif GitHub.multi_tenant_enterprise?
            User.find_by_login(login) || Mannequin.find_by_login(login)
          else
            User.find_by_login(login)
          end
        end
      end
      env[PATH_INFO] = "#{prefix}/#{user.try(:id).to_i}#{extra}"
    end

    def convert_repository_key_to_id(env, path, login, name, extra, prefix)
      env[ThisRepositoryNameWithOwnerKey] = "#{login}/#{name}"

      repo = env[ThisRepositoryKey] = begin
        ActiveRecord::Base.connected_to(role: :reading) do
          Repository.nwo(login, name)
        end
      end
      env[PATH_INFO] = "#{prefix}/#{repo.try(:id).to_i}#{extra}"
    end

    def convert_gist_key_to_id(env, path, login, name, extra, prefix)
      gist = begin
        ActiveRecord::Base.connected_to(role: :reading) do
          Gist.with_name_with_owner(login, name)
        end
      end

      env[PATH_INFO] = "#{prefix}/#{gist.try(:id).to_i}#{extra}"
    end

    def convert_gist_repo_name_to_id(env, path, name, extra, prefix)
      gist = begin
        ActiveRecord::Base.connected_to(role: :reading) do
          Gist.find_by(repo_name: name)
        end
      end

      env[PATH_INFO] = "#{prefix}/#{gist.try(:id).to_i}#{extra}"
    end

    def convert_organization_key_to_id(env, path, login, extra, prefix)
      org = env[ThisUserKey] = begin
        ActiveRecord::Base.connected_to(role: :reading) do
          Organization.find_by_login(login)
        end
      end

      org_id = (org.try(:id) || login).to_i

      env[PATH_INFO] = "#{prefix}/#{org_id}#{extra}"
    end

    def convert_organization_and_username_key_to_id_copilot(env, path, org_login, user_login, extra, org_prefix, members_prefix)
      org = ActiveRecord::Base.connected_to(role: :reading) do
        Organization.find_by_login(org_login)
      end

      user_login = ::Api::LegacyEncode.decode(user_login)
      user = ActiveRecord::Base.connected_to(role: :reading) do
        User.find_by_login(user_login)
      end

      org_id = (org.try(:id) || org_login).to_i
      user_id = (user.try(:id) || user_login).to_i

      env[PATH_INFO] = "#{org_prefix}/#{org_id}#{members_prefix}/#{user_id}/copilot#{extra}"
    end

    # If the :org_login actually belongs to a user, redirect from /orgs/:org_login/attestations/:subject >
    # /user/:user_id/attestations/:subject
    #
    # Used by gh cli attestation command to fetch attestations for a ambiguous --owner slug without having to resolve
    # the type
    def convert_organization_and_username_key_to_id_attestations(env, path, login, extra)
      user_path = convert_user_key_to_id(env, path, login, extra, "/user")
      return user_path if env[ThisUserKey].try(:user?)

      convert_organization_key_to_id(env, path, login, extra, "/organizations")
    end

    def convert_organization_and_username_key_to_id(env, path, org_login, user_login, codespace_name, extra, prefix, member_prefix, codespaces_prefix)
      org = ActiveRecord::Base.connected_to(role: :reading) do
        Organization.find_by_login(org_login)
      end

      user_login = ::Api::LegacyEncode.decode(user_login)
      user = ActiveRecord::Base.connected_to(role: :reading) do
        User.find_by_login(user_login)
      end

      org_id = (org.try(:id) || org_login).to_i
      user_id = (user.try(:id) || user_login).to_i

      if codespace_name.present?
        env[PATH_INFO] = "#{prefix}/#{org_id}#{member_prefix}/#{user_id}#{codespaces_prefix}/#{codespace_name}#{extra}"
      else
        env[PATH_INFO] = "#{prefix}/#{org_id}#{member_prefix}/#{user_id}#{codespaces_prefix}#{extra}"
      end
    end

    def convert_team_and_repos_key_to_id(env, path, org_id, slug, login, name, extra, team_prefix, repo_prefix)
      ActiveRecord::Base.connected_to(role: :reading) do
        team = env[ThisTeamKey] = Team.find_by(organization_id: org_id, slug: slug)
        repo = env[ThisRepositoryKey] = Repository.nwo(login, name)
        env[PATH_INFO] = "#{team_prefix}/#{team.try(:id).to_i}#{repo_prefix}/#{repo.try(:id).to_i}#{extra}"
      end
    end

    def convert_team_key_to_id(env, path, org_id, slug, extra, prefix)
      ActiveRecord::Base.connected_to(role: :reading) do
        team = env[ThisTeamKey] = Team.find_by(organization_id: org_id, slug: slug)
        env[PATH_INFO] = "#{prefix}/#{team.try(:id).to_i}#{extra}"
      end
    end

    def convert_organization_and_team_and_repos_key_to_id(env, path, org_login, team_slug, repo_login, name, extra, org_prefix, team_prefix, repo_prefix)
      ActiveRecord::Base.connected_to(role: :reading) do
        org = Organization.find_by_login(org_login)
        if org && team = org.teams.find_by_slug(team_slug)
          env[ThisUserKey] = org
          env[ThisTeamKey] = team
          repo = env[ThisRepositoryKey] = Repository.nwo(repo_login, name)
        end
        env[PATH_INFO] = "#{org_prefix}/#{org.try(:id).to_i}#{team_prefix}/#{team.try(:id).to_i}#{repo_prefix}/#{repo.try(:id).to_i}#{extra}"
      end
    end

    def convert_organization_and_repos_key_to_id(env, path, org_login, team_id, repo_login, name, extra, org_prefix, team_prefix, repo_prefix)
      ActiveRecord::Base.connected_to(role: :reading) do
        org = Organization.find_by_login(org_login)
        if org && team = org.teams.find_by_id(team_id)
          env[ThisUserKey] = org
          env[ThisTeamKey] = team
          repo = env[ThisRepositoryKey] = Repository.nwo(repo_login, name)
        end
        env[PATH_INFO] = "#{org_prefix}/#{org.try(:id).to_i}#{team_prefix}/#{team.try(:id).to_i}#{repo_prefix}/#{repo.try(:id).to_i}#{extra}"
      end
    end

    def convert_organization_and_team_key_to_id(env, path, login, slug, extra, org_prefix, team_prefix)
      # Fix for teams named 'teams' (github/mEAO#125)
      if team_prefix == "/teams/team" && extra.blank?
        team_prefix = "/team"
        extra = "/#{slug}"
        slug = "teams"
      end

      ActiveRecord::Base.connected_to(role: :reading) do
        org = Organization.find_by_login(login)
        if org && team = org.teams.find_by_slug(slug)
          env[ThisUserKey] = org
          env[ThisTeamKey] = team
        end
        env[PATH_INFO] = "#{org_prefix}/#{org.try(:id).to_i}#{team_prefix}/#{team.try(:id).to_i}#{extra}"
      end
    end

    def convert_legacy_team_key_to_id(env, path, team_id, extra, org_prefix, team_prefix)
      ActiveRecord::Base.connected_to(role: :reading) do
        team = env[ThisTeamKey] = Team.find_by(id: team_id)
        env[PATH_INFO] = "#{org_prefix}/#{team.try(:organization_id).to_i}#{team_prefix}/#{team.try(:id).to_i}#{extra}"
      end
    end

    def convert_legacy_team_and_repository_key_to_id(env, path, team_id, login, name, extra, org_prefix, prefix)
      env[ThisRepositoryNameWithOwnerKey] = "#{login}/#{name}"
      ActiveRecord::Base.connected_to(role: :reading) do
        team = env[ThisTeamKey] = Team.find_by(id: team_id)
        repo = env[ThisRepositoryKey] = Repository.nwo(login, name)
        env[PATH_INFO] = "#{org_prefix}/#{team.try(:organization_id).to_i}#{prefix}/#{repo.try(:id).to_i}#{extra}"
      end
    end

    def convert_enterprise_key_to_id(env, path, slug_or_id, extra, prefix)
      enterprise = env[ThisUserKey] = begin
        ActiveRecord::Base.connected_to(role: :reading) do
          Business.find_by(slug: slug_or_id) || Business.find_by(id: slug_or_id)
        end
      end
      env[PATH_INFO] = "#{prefix}/#{enterprise.try(:id).to_i}#{extra}"
    end

    def convert_enterprise_and_team_key_to_id(
      env, path, business_slug_or_id, enterprise_team_slug_or_id, extra, business_prefix, enterprise_team_prefix)
      ActiveRecord::Base.connected_to(role: :reading) do
        business = Business.find_by(slug: business_slug_or_id) || Business.find_by(id: business_slug_or_id)
        env[ThisTeamKey] = enterprise_team = business&.enterprise_teams&.find_by(slug: enterprise_team_slug_or_id) ||
          business&.enterprise_teams&.find_by(id: enterprise_team_slug_or_id)
        env[PATH_INFO] = "#{business_prefix}/#{business.try(:id).to_i}#{enterprise_team_prefix}/#{enterprise_team.try(:id).to_i}#{extra}"
      end
    end

    def convert_base_scim_path_to_enterprise(env, path, resource, extra, prefix)
      return path unless GitHub.enterprise?
      enterprise = begin
        ActiveRecord::Base.connected_to(role: :reading) do
          GitHub.global_business
        end
      end
      env[PATH_INFO] = "#{prefix}/#{enterprise.try(:id).to_i}/#{resource}#{extra}"
    end

    def convert_app_slug_to_id(env, path, slug_or_owner, slug_or_extra, prefix)
      extra = T.let("", T.untyped)
      app = env[ThisAppKey] = begin
        ActiveRecord::Base.connected_to(role: :reading) do
          if owner_scoped_github_apps_enabled?
            # Remove leading slash if present
            slug = slug_or_extra.starts_with?("/") ? slug_or_extra[1..-1] : slug_or_extra
            extra = ""
            if GitHub.multi_tenant_enterprise?
              # Overrides of slug and owner for Proxima third-party apps
              # Proxima third-party apps are not accessible via /apps/:owner/:slug
              slug_or_owner = "" if slug_or_owner == GitHub.proxima_third_party_apps_owner_login
              # Proxima third-party apps are accessible via /apps/external-app/:slug
              slug_or_owner = GitHub.proxima_third_party_apps_owner_login if slug_or_owner == GitHub.proxima_external_apps_owner_slug
              # Proxima third-party apps are accessible via /apps/:slug
              if slug.empty?
                slug = slug_or_owner
                slug_or_owner = GitHub.proxima_third_party_apps_owner_login
              end
            end
            Integration.from_owner_and_slug(user_login: slug_or_owner, slug: slug)
          else
            extra = slug_or_extra
            Integration.find_by(slug: slug_or_owner)
          end
        end
      end

      env[PATH_INFO] = "#{prefix}/#{app.try(:id).to_i}#{extra}"
    end

    # Convert a path like /repositories/123/commits/branch/named/status to
    # /repositories/123/status/branch/named, unless repository 123 has
    # a ref named /branch/named/status.
    def convert_inline_refs_to_tailing_refs(env, path)
      return path unless match = TailingStatusRegex.match(path)
      potential_ref = "#{match[:ref]}/#{match[:status]}"

      repo = env[ThisRepositoryKey] ||= begin
        ActiveRecord::Base.connected_to(role: :reading) do
          Repository.find_by(id: match[:repo_id])
        end
      end

      if repo && repo.heads[potential_ref].nil?
        "/repositories/#{match[:repo_id]}/#{match[:status]}/#{match[:ref]}"
      else
        path
      end
    end

    # Several API endpoints accept a `:ref`, which can be a SHA, branch or tag.
    # Branch names can contain `/`, which means that we can end up with ambiguity
    # when a branch name might conflict with one of our API resources.
    #
    # E.g.:
    #
    # GET /repos/:owner/:repo/commits/:ref (Get the SHA-1 of a commit reference)
    # GET /repos/:owner/:repo/commits/:ref/check-suites (List the check suites for a commit reference)
    #
    # Given a branch named, for example, wip/check-suites, the "get a SHA-1" endpoint would be:
    #
    # GET /repos/owner/repo/commits/wip/check-suites
    #
    # The router can not know which of these is meant by just looking at the route pattern.
    #
    # This looks up the ambiguous ref to see if there's an existing branch with that name.
    # If there is, we disambiguate by swapping out the branch name with the SHA, which lets
    # the router unambiguously determine that the request is to the RepositoryCommits API rather
    # than the other API.
    #
    # This is used by the CheckSuites API and the CheckRuns API.
    # and should also refactor the Statuses API to use it.
    def convert_ambiguous_commits_ref_to_sha(env, path)
      return path unless match = AmbiguousCommitsAPIRefRegex.match(path)
      potential_ref = "#{match[:ref]}/#{match[:resource]}"

      repo = env[ThisRepositoryKey] ||= begin
        ActiveRecord::Base.connected_to(role: :reading) do
          Repository.find_by(id: match[:repo_id])
        end
      end

      if repo && repo.heads[potential_ref].present?
        sha = repo.heads[potential_ref].sha
        "/repositories/#{match[:repo_id]}/commits/#{sha}"
      elsif repo && repo.heads[match[:ref]].present?
        sha = repo.heads[match[:ref]].sha
        "/repositories/#{match[:repo_id]}/commits/#{sha}/#{match[:resource]}"
      else
        path
      end
    end

    # Convert a path like /repositories/60/code-scanning/codeql/variant-analyses/5/repos/some-user/some-other-repo/asdf
    # to /repositories/60/code-scanning/codeql/variant-analyses/5/repositories/78/asdf. This is done separately from
    # convert_natural_keys_to_ids to make use of the existing regex for the /repos/:owner/:repo/... conversion at the
    # start of the path.
    def convert_variant_analysis_repository_nwo_to_id(env, path)
      return path unless match = VariantAnalysisRegex.match(path)

      repo = ActiveRecord::Base.connected_to(role: :reading) do
        Repository.nwo(match[:owner], match[:name])
      end

      return path unless repo

      "#{match[:prefix]}/repositories/#{repo.id}#{match[:resource]}"
    end

    # Marks the current route as deprecated before routing it
    # To a Sinatra App. This enables us to conditionaly deprecate
    # a resource depending on the path used by the client.
    #
    # deprecation_date - The date at which this deprecation started.
    # sunset_date      - The date at which the endpoint may stop responding.
    # info_url         - An absolute URL to an HTML,
    #                    human readable description of the deprecation
    #
    def deprecated_route!(env, deprecation_date:, sunset_date:, info_url:)
      env[DEPRECATED_ROUTE] = {
        deprecation_date: deprecation_date,
        sunset_date: sunset_date,
        info_url: info_url,
      }
    end
  end
end
