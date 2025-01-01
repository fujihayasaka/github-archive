# typed: true
# frozen_string_literal: true

# rubocop:disable Lint/DuplicateMethods

require "etc"
require "uri"
require "set"
require "socket"
require "public_suffix"
require "addressable/uri"

module GitHub
  # GitHub global configuration
  #
  # This is mixed into the GitHub module such that an attribute "blah" defined
  # here is available at GitHub.blah and GitHub.blah=. All GitHub specific global
  # configuration should be defined here and set via one of the files defined
  # below.
  #
  # The load order for config values is (each overriding the last):
  # - Default values defined in this module
  # - Overrides in config/environment.rb
  # - Overrides in config/environments/<env>.rb
  # - Overrides in RAILS_ROOT/config.yml
  #
  # The RAILS_ROOT/config.yml file may set any config attribute defined in this
  # module. It's used primarily to customize FI installations.
  #
  # After boot, these properties should be treated as static and MUST NOT be
  # altered.
  #
  # When adding new configuration items, please document them. Include
  # information on what they're used for, default values, and example values
  # for a couple different environments if possible.
  #
  # NOTE This file is loaded as part of the config/basic.rb lightweight environment.
  # Do not add any additional library requires here.
  module Config
    extend T::Helpers
    requires_ancestor { GitHub::Config::DependencyGraph }
    requires_ancestor { GitHub::Config::FirstPartyApps }
    requires_ancestor { GitHub::Config::ProximaSyncedThirdPartyApps }
    requires_ancestor { GitHub::Config::MultiTenantEnterprise }
    requires_ancestor { GitHub::Config::S3 }
    requires_ancestor { GitHub::Config::Metadata }
    requires_ancestor { GitHub::Config::Smtp }
    requires_ancestor { GitHub::Version }

    MAX_UI_PAGINATION_PAGE         = 100
    PRIMARY_FS_TEST_DIR            = "/data/repositories/0/lost+found"
    MONITORS_USER_ID               = 1162581 # the user id for our special Monitors account
    MIRROR_PUSHER                  = "hubot" # the login for recording mirror "pushes"
    DGIT_COPIES                    = 3 # default in development and test; usually different in prod
    DESKTOP_FETCH_INTERVAL         = 5 # in minutes
    DOCS_BASE_URL                  = "https://docs.github.com".freeze
    SUPPORT_BASE_URL               = "https://support.github.com".freeze
    DEVELOPER_BASE_URL             = "https://developer.github.com".freeze
    STAGING_DOMAIN                 = "github-staging-lab.com".freeze

    ENTERPRISE_ELASTOMER_INDEX_LOCK_BACKOFF_ATTEMPTS = 20
    ES_QUERY_TIMEOUT                          = "250ms"
    ES_DATACENTER                             = "default"
    ES_AUDIT_LOG_CLUSTER                      = "default"
    ES_AUDIT_LOG_CLUSTER_NEXT                 = "default"
    ES_MAX_DOC_SIZE                           = 384 * 1024 # 384KB
    ES_NUMBER_OF_REPLICAS                     = 2
    ES_READ_TIMEOUT                           = 2
    ES_OPEN_TIMEOUT                           = 0.3
    ES_DEFAULT_WORKER_COUNT                   = 1
    ES_SHARD_COUNT_FOR_AUDIT_LOG              = 1
    ES_SHARD_COUNT_FOR_CODE_SEARCH            = 1
    ES_SHARD_COUNT_FOR_COMMITS                = 1
    ES_SHARD_COUNT_FOR_ISSUES                 = 1
    ES_SHARD_COUNT_FOR_NOTIFICATIONS          = 1
    ES_SHARD_COUNT_FOR_PULL_REQUESTS          = 1
    ES_SHARD_COUNT_FOR_TOPICS                 = 1
    ES_SHARD_COUNT_FOR_LABELS                 = 1
    ES_SHARD_COUNT_FOR_MEMEX_PROJECT_ITEMS    = 1
    ES_SHARD_COUNT_FOR_RELEASES               = 1
    ES_SHARD_COUNT_FOR_REPOS                  = 1
    ES_SHARD_COUNT_FOR_DISCUSSIONS            = 1
    ES_SHARD_COUNT_FOR_TEAM_DISCUSSIONS       = 1
    ES_SHARD_COUNT_FOR_USERS                  = 1
    ES_SHARD_COUNT_FOR_SHOWCASES              = 1
    ES_SHARD_COUNT_FOR_GISTS                  = 1
    ES_SHARD_COUNT_FOR_WIKIS                  = 1
    ES_SHARD_COUNT_FOR_PROJECTS               = 1
    ES_SHARD_COUNT_FOR_MARKETPLACE_LISTINGS   = 1
    ES_SHARD_COUNT_FOR_REPOSITORY_ACTIONS     = 1
    ES_SHARD_COUNT_FOR_REGISTRY_PACKAGES      = 1
    ES_SHARD_COUNT_FOR_RMS_PACKAGES           = 1
    ES_SHARD_COUNT_FOR_VULNERABILITIES        = 1
    ES_SHARD_COUNT_FOR_ENTERPRISES            = 1
    ES_SHARD_COUNT_FOR_WORKFLOW_RUNS          = 1

    ES_MAX_REFRESH_LISTENERS_FOR_MEMEX_PROJECT_ITEMS = 1000

    CODESPACES_CANONICAL_SUBSCRIPTION             = "d833c9b9-c971-47f1-8156-c4236552bdfd"
    CODESPACES_CANONICAL_SUBSCRIPTION_LOCAL_DEV   = "887c141e-c717-4345-a2bd-c61f5939ee1c"

    MAX_BUSINESS_FOOTER_COUNT = 5

    SANITIZED_VALUE = "[FILTERED]".freeze
    params = %w(
      action category_slug controller direction dropdown_type feature
      gist_id id integration_id listing_slug login name number org
      organization_id owner page per_page person_login project_number repo
      repository repo_name sha since slug sort subject team_slug type
      user_id user_login utf8 client_id tab isOpenSelected period impactAnalysisTab
      startDate endDate
    )
    ALLOWED_PARAMETERS = /\A(#{params.join("|")})\z/

    # Set of known sites (datacenters) that can be return values of site_from_host.
    # Also update https://github.com/github/hydro-schemas/blob/master/proto/hydro/schemas/hydro/v1/envelope.proto
    # when this list is updated
    SITE_LIST = %w[
      ac4-iad
      ash1-iad
      va3-iad
      sdc42-sea
    ].map do |site|
      ["#{site}.github.net", site]
    end.to_h.freeze

    VSCS_ENVIRONMENTS = {
      production: {
        name: :production,
        display_name: "production",
        api_url: "https://online.visualstudio.com",
        pfs_auth_postback_host: "auth.preview.app.github.dev",
        web_portal_url_format: "https://%{name}.%{second_level_domain}.dev",
        dev_tunnels_domain: "app.%{second_level_domain}.dev",
      },
      latestprod: {
        name: :latestprod,
        display_name: "latest-prod",
        api_url: "https://latest.online.visualstudio.com",
        pfs_auth_postback_host: "auth.preview.app.github.dev",
        web_portal_url_format: "https://%{name}.latest.%{second_level_domain}.dev",
        dev_tunnels_domain: "app.%{second_level_domain}.dev",
      },
      ppe: {
        name: :ppe,
        display_name: "pre-production",
        api_url: "https://online-ppe.core.vsengsaas.visualstudio.com",
        pfs_auth_postback_host: "auth.ppe.preview.app.github.dev",
        web_portal_url_format: "https://%{name}.ppe.%{second_level_domain}.dev",
        dev_tunnels_domain: "app.ppe.%{second_level_domain}.dev",
      },
      latestppe: {
        name: :latestppe,
        display_name: "latest-ppe",
        api_url: "https://latest-online-ppe.core.vsengsaas.visualstudio.com",
        pfs_auth_postback_host: "auth.ppe.preview.app.github.dev",
        web_portal_url_format: "https://%{name}.latest-ppe.%{second_level_domain}.dev",
        dev_tunnels_domain: "app.ppe.%{second_level_domain}.dev",
      },
      development: {
        name: :development,
        display_name: "development",
        api_url: "https://online.dev.core.vsengsaas.visualstudio.com",
        pfs_auth_postback_host: "auth.dev.preview.app.github.dev",
        web_portal_url_format: "https://%{name}.dev.%{second_level_domain}.dev",
        dev_tunnels_domain: "app.dev.%{second_level_domain}.dev",
      },
      latestdev: {
        name: :latestdev,
        display_name: "latest-dev",
        api_url: "https://latest-westus2-ci-online.dev.core.vsengsaas.visualstudio.com",
        pfs_auth_postback_host: "auth.dev.preview.app.github.dev",
        web_portal_url_format: "https://%{name}.latest-dev.%{second_level_domain}.dev",
        dev_tunnels_domain: "app.dev.%{second_level_domain}.dev",
      },
      local: {
        name: :local,
        display_name: "local",
        api_url: "https://online.dev.core.vsengsaas.visualstudio.com",
        pfs_auth_postback_host: "auth.dev.preview.app.github.dev",
        web_portal_url_format: "http://%{name}.%{second_level_domain}.localhost:3000",
        dev_tunnels_domain: "app.dev.%{second_level_domain}.dev",
      },
      canary: {
        name: :canary,
        display_name: "canary",
        api_url: "https://canary.online.visualstudio.com",
        web_portal_url_format: "https://%{name}.canary.%{second_level_domain}.dev",
      }
    }.freeze

    LOCAL_IP_ADDRESSES = %w(127.0.0.1 ::1).freeze
    LOCAL_TRUSTED_PROXIES = %w(localhost 127.0.0.1 ::1).freeze

    # Raised on data access when a datastore is configured to be inaccessible,
    # e.g. in a secondary datacenter.
    class UnexpectedDatastoreAccess < StandardError; end
    class IntegrationMissingError < StandardError; end

    def site_heading(enterprise_managed_user: false)
      if employee_unicorn?
        "Lab"
      elsif enterprise? || enterprise_managed_user || multi_tenant_enterprise?
        "Enterprise"
      end
    end

    # The current runtime mode object. Used to determine whether we're running
    # under dotcom or enterprise mode and also allows dynamically switching
    # modes in development server environments.
    #
    # Returns a GitHub::Runtime object.
    def runtime
      @runtime ||= GitHub::Runtime.new
    end

    # Boolean attribute specifying whether the site is in SSL mode. This is
    # typically set true explicitly in production environments.
    #
    # Returns true if SSL is enabled for the site, false otherwise.
    def ssl?
      return @ssl if defined?(@ssl)
      ENV["GH_SSL"]
    end
    attr_writer :ssl
    alias ssl ssl?

    # Public: Return appropriate URI scheme for SSL mode.
    #
    # Returns String.
    def scheme
      ssl? ? "https" : "http"
    end

    # The x509 certificate for this Enterprise installation in PEM format.
    #
    # Returns a String that represents the certificate in PEM format.
    def ssl_certificate
      return @ssl_certificate if defined?(@ssl_certificate)

      if GitHub.enterprise? && (Rails.env.development? || Rails.env.test?)
        fake_cert_pem = "-----BEGIN CERTIFICATE-----\nMIIDlDCCAnygAwIBAgIJAOoPW0ZFhjwuMA0GCSqGSIb3DQEBCwUAMEQxGTAXBgNV\nBAMMEGdpdGh1Yi5sb2NhbGhvc3QxJzAlBgNVBAoMHkdpdEh1YiBTZWxmIFNpZ25l\nZCBDZXJ0aWZpY2F0ZTAeFw0xODAzMTQwODM5MjFaFw0yODAzMTEwODM5MjFaMEQx\nGTAXBgNVBAMMEGdpdGh1Yi5sb2NhbGhvc3QxJzAlBgNVBAoMHkdpdEh1YiBTZWxm\nIFNpZ25lZCBDZXJ0aWZpY2F0ZTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoC\nggEBALZc6x8cHdb7RfTkcDLx7f5t4MFg3dSCaXsYnledXqYgo6n/CeKXRzoUx+t5\nu7IzLSQ4V+B3nczR8D+Zmt0+T0ta8OBZ/K2vFOVxxK2ZnID4YZkvg6UnWJe0k2El\nzFVM23SclrDF40yETeKXGV3u0Eq4/LR6bEy1FSwCjtorgy6W77boOo9k3768QOTi\nac9clNl27xfAxvKmcfgbl4x0npIfj36X3kGXuqvemWbdP8qwnB6IK/DXahgvzlAJ\nvqMmm9bo8Em2iIKw1abgyfcPflG+/Fu+CwjmH+tohsoMn2JAg9oc+lxENIhtuVtg\nlEFqoHdeTtRIF5K4hotwxnP7NNsCAwEAAaOBiDCBhTAdBgNVHQ4EFgQUH3eO7bQK\nuZX+mxanQz/gnbTmPa4wHwYDVR0jBBgwFoAUH3eO7bQKuZX+mxanQz/gnbTmPa4w\nDAYDVR0TBAUwAwEB/zA1BgNVHREELjAshwR/AAABghBnaXRodWIubG9jYWxob3N0\nghIqLmdpdGh1Yi5sb2NhbGhvc3QwDQYJKoZIhvcNAQELBQADggEBAE9LIBq6pXm9\nDElS4ojDkzCI0oA5mnhFjMq9+IcOrdD2vY+/O0CdxPdXnNtJkPRYenr0S3270/3G\nKdxjyxRabnm6pXS52Ts7j4CwZZC3z/gIczYhLhfWWod28bYyoYEK/xBFBMc0XTcD\n4GPeAVNiz/jgD+ufn/L1iH9/TFHidyX+PfMTPQWAN9hteHnve5PG/oqG7So/GIHU\nVa5UcsrEd5iNTboIJ2FeuSuAtZwSbaK2iRzm4fLL9onW0CeTddLGjZrOvr3ETgqY\nfMnEzRG9Ybt81q7Q6MKA7TNsgbORVSwYUPW3aaR0OfvflNdS1BPSepLVeNsr6L8q\nDYItU51RJac=\n-----END CERTIFICATE-----\n"
        fake_x509 = OpenSSL::X509::Certificate.new(fake_cert_pem)
        # Make sure not_after is well in the future by default
        fake_x509.not_after = 1.year.from_now
        @ssl_certificate = fake_x509.to_pem
      end
    end
    attr_writer :ssl_certificate

    # Is the current environment connected to the public internet? This is
    # useful primarily in development environments where loading gravatars and
    # other external items may be skipped. This should always be set true
    # everywhere except in development and enterprise instances to prevent the
    # slow ping check.
    #
    # Returns true if external internet access is available, false otherwise.
    def online?
      return @online if defined?(@online)
      return false if enterprise?
      return google_reachable? if Rails.env.development?

      true
    end
    attr_writer :online
    alias online online?

    def google_reachable?
      @online = begin
        Timeout.timeout(1) do
          s = TCPSocket.new("google.com", 80)
          s.close
        end
        true
      rescue Errno::ECONNREFUSED
        true
      rescue Timeout::Error, StandardError # rubocop:todo Lint/GenericRescue
        false
      end
    end

    # The test environment's parallel execution number.
    #
    # Returns the environment number as a string but only in test environments.
    # In other environments this method returns nil.
    def test_environment_number
      GitHub::AppEnvironment.test? && (ENV["TEST_ENV_NUMBER"] || "0")
    end

    # Enable gravatar images throughout the site. Some enterprise customers
    # may want to disable this for security reasons.
    #
    # Returns true if gravatar images should be displayed, false otherwise.
    def gravatar_enabled?
      return false if fips_mode?
      return false if GitHub.multi_tenant_enterprise?
      return @gravatar_enabled if defined?(@gravatar_enabled)

      online?
    end

    def generate_gravatar_id(email)
      return "undefined" unless gravatar_enabled?
      Digest::MD5.hexdigest(email) # rubocop:disable GitHub/InsecureHashAlgorithm
    end
    attr_writer :gravatar_enabled

    # The base URL for all avatars. This server must implement the gravatar API. If passed
    # a string, it will determine which gravatar subdomain to use
    # (see https://github.com/github/github/issues/13687#issuecomment-22726044)
    #
    # string - An optional String that will be hashed to determine which Gravatar subdomain
    #          should be used (0, 1 or 2).
    #
    # Returns a gravatar base url
    def gravatar_url(string = nil)
      return @gravatar_url if defined? @gravatar_url
      subdomain = string ? Zlib.crc32(string.to_s) % 3 : 0
      "https://#{subdomain}.gravatar.com"
    end

    attr_writer :gravatar_url

    # Whether we are using gravatar.com or a custom avatar service.
    #
    # Returns true when gravatar_url ends with .gravatar.com
    def gravatar_service?
      gravatar_url =~ /\.gravatar\.com$/
    end

    # GpgVerify client instance
    #
    # Returns a GpgVerify instance
    def gpg
      @gpg ||= GpgVerify.new(gpgverify_url)
    end

    attr_writer :gpg

    # Host where the gpgverify HTTP service is running.
    #
    # Returns a url String.
    def gpgverify_url
      @gpgverify_url ||= "http://127.0.0.1:8686"
    end
    attr_writer :gpgverify_url

    def git_signing_smime_cert_store
      @git_signing_smime_cert_store ||= OpenSSL::X509::Store.new.tap do |store|
        store.add_file("/etc/ssl/certs/ca-certificates.crt")
      end
    end
    attr_writer :git_signing_smime_cert_store

    # Returns true if repositories require explictly accepted invitations when
    # adding a new member.
    def repo_invites_enabled?
      !GitHub.enterprise?
    end

    # The login of the owner of the GitHub-branded Actions org. Defaults to "actions-admin".
    # Populated by the ENTERPRISE_ACTIONS_ADMIN_LOGIN variable.
    attr_writer :actions_admin_login
    def actions_admin_login
      @actions_admin_login ||= "actions-admin"
    end

    # The login of the GHES SCIM provisioning built-in user.
    def ghes_scim_admin_login
      "scim-admin"
    end

    # The organization for GitHub Actions. Defaults to "actions".
    # Populated by the ENTERPRISE_ACTIONS_ACTIONS_ORG variable.
    attr_writer :actions_actions_org
    def actions_org
      @actions_actions_org if defined?(@actions_actions_org)
    end

    # The organization for GitHub-branded Actions. Defaults to "github".
    # Populated by the ENTERPRISE_ACTIONS_GITHUB_ORG variable.
    attr_writer :actions_github_org
    def github_org
      @actions_github_org if defined?(@actions_github_org)
    end

    # CAPI aka Copilot API URL for local development/staging endpoints. Copilot
    # API URLs should always be read from a Copilot::SKUIsolation instance in
    # the context of a user.
    attr_writer :copilot_api_override_url
    def copilot_api_override_url
      @copilot_api_override_url
    end

    # This is the internal URL for the copilot-api service. It should not be
    # used/shared with clients for user-initiated requests (React, editors,
    # etc). Please use Copilot::SKUIsolation for that purpose instead.
    sig { returns(String) }
    def copilot_api_internal_url
      return copilot_api_override_url if copilot_api_override_url

      # On Proxima, we use the tenant hostname.
      if GitHub.multi_tenant_enterprise?
        return "https://copilot-api.#{host_name_with_tenant}"
      end

      # We don't want this value in the environment vars because someone might
      # accidentally use it. The override setting is more explicit.
      "https://api.githubcopilot.com"
    end

    # Whether issues react is enabled with all features - sub-issues, issue types, and advanced search
    # This is specifically for GHES, and only enabled through the env var ENTERPRISE_ISSUES_REACT_GHES_ENABLED
    def issues_react_ghes_enabled?
      return @issues_react_ghes_enabled if defined?(@issues_react_ghes_enabled)
      false
    end
    attr_writer :issues_react_ghes_enabled

    def issues_advanced_search_enabled?(user)
      return true if GitHub.issues_react_ghes_enabled?
      user&.feature_enabled?(:issues_advanced_search)
    end

    # Whether GitHub Actions is enabled.
    # - Always enabled for dotcom.
    # - Disabled for Enterprise by default. Checks for ENTERPRISE_ACTIONS_ENABLED variable.
    def actions_enabled?
      return @actions_enabled if defined?(@actions_enabled)
      @actions_enabled = !enterprise?
    end
    attr_writer :actions_enabled

    # Whether GitHub Actions Larger Runners feature is enabled.
    # - Always enabled for dotcom.
    # - Always disabled for Enterprise.
    def actions_larger_runners_enabled?
      return @actions_larger_runners_enabled if defined?(@actions_larger_runners_enabled)
      @actions_larger_runners_enabled = begin
        return false if GitHub.enterprise?
        GitHub.actions_enabled?
      end
    end

    def actions_ims_stafftools_enabled?(user)
      return false if GitHub.enterprise?
      GitHub.actions_enabled? && user.feature_enabled?(:hosted_compute_ims_stafftools)
    end

    # Comma separated list of storage account names used by Actions to store logs and artifacts.
    # - specific to proxima stamp
    attr_accessor :actions_results_storage_accounts

    # Whether Projects New (née Memex) is enabled
    # - Always enabled for dotcom.
    # - Enabled for Enterprise by default. Checks for ENTERPRISE_PROJECTS_NEW_ENABLED environment variable.
    def projects_new_enabled?
      return @projects_new_enabled if defined?(@projects_new_enabled)
      @projects_new_enabled = true
    end
    attr_writer :projects_new_enabled

    # Schedule for projects new workflow scheduled runner
    # - 12 hours default. Checks for ENTERPRISE_PROJECTS_NEW_WORKFLOW_SCHEDULED_RUNNER_SCHEDULE environment variable.
    # - Configured in seconds.
    def projects_new_workflow_scheduled_runner_schedule
      return @projects_new_workflow_scheduled_runner_schedule if defined?(@projects_new_workflow_scheduled_runner_schedule)
      @projects_new_workflow_scheduled_runner_schedule = 12.hours
    end
    attr_writer :projects_new_workflow_scheduled_runner_schedule

    # Whether trust tiers are enabled.
    #
    # Only enabled in dotcom.
    #
    # Returns Boolean
    def trust_tiers_enabled?
      return @trust_tiers_enabled if defined? @trust_tiers_enabled
      @trust_tiers_enabled = !enterprise?
    end
    attr_writer :trust_tiers_enabled

    # Whether Checks retention job is enabled
    # - Always enabled for dotcom
    # - Disabled for Enterprise by default. Checks for ENTERPRISE_CHECKS_RETENTION_ENABLED variable.
    def checks_retention_enabled?
      return @checks_retention_enabled if defined?(@checks_retention_enabled)
      @checks_retention_enabled = !enterprise?
    end
    attr_writer :checks_retention_enabled

    # The threshold checks will be retained for before being archived
    # Populated by ENTERPRISE_CHECKS_RETENTION_ARCHIVE_THRESHOLD.
    def checks_retention_archive_threshold
      @checks_retention_archive_threshold if defined?(@checks_retention_archive_threshold)
    end
    attr_writer :checks_retention_archive_threshold

    # The threshold archived checks will be retained for before being hard deleted
    # Populated by ENTERPRISE_CHECKS_RETENTION_DELETE_THRESHOLD.
    def checks_retention_delete_threshold
      @checks_retention_delete_threshold if defined?(@checks_retention_delete_threshold)
    end
    attr_writer :checks_retention_delete_threshold

    # Whether GitHub Stacks is enabled.
    # - Always enabled for dotcom.
    # - Disabled for Enterprise by default.
    def stacks_enabled?
      return @stacks_enabled if defined?(@stacks_enabled)
      @stacks_enabled = !enterprise?
    end
    attr_writer :stacks_enabled

    # Whether the Developer Program is enabled.
    # - Always enabled for dotcom.
    # - Disabled for Enterprise.
    def developer_program_enabled?
      return @developer_program_enabled if defined?(@developer_program_enabled)
      @developer_program_enabled = !enterprise?
    end

    # Whether GitHub Insights is enabled.
    # - This always returns true for dotcom.
    # - Disabled for enterprise by default.
    def insights_enabled?
      return @insights_enabled if defined?(@insights_enabled)
      @insights_enabled = !enterprise?
    end
    attr_writer :insights_enabled

    # Whether GitHub Insights is enabled for GHAS metrics.
    # - This always returns true for dotcom.
    # - Disabled for enterprise by default.
    def insights_ghas_enabled?
      return @insights_ghas_enabled if defined?(@insights_ghas_enabled)
      @insights_ghas_enabled = !enterprise?
    end
    attr_writer :insights_ghas_enabled

    # Whether GitHub Insights is enabled for GHAS Alerts metrics.
    # - This always returns true for dotcom.
    # - Disabled for enterprise by default.
    def insights_ghas_alerts_enabled?
      return @insights_ghas_alerts_enabled if defined?(@insights_ghas_alerts_enabled)
      @insights_ghas_alerts_enabled = !enterprise?
    end
    attr_writer :insights_ghas_alerts_enabled

    # Whether GitHub Actions/Packages are pending setup on Enterprise Server
    # - This means the GHES version has Actions/Packages, but it still needs to be setup by an Administrator.
    def actions_packages_enterprise_setup_pending?
      return @actions_packages_enterprise_setup_pending if defined?(@actions_packages_enterprise_setup_pending)
      @actions_packages_enterprise_setup_pending = GitHub.enterprise? && Actions::TmpKV.for_key("ghes.actions_packages_setup_pending").get("ghes.actions_packages_setup_pending").value { false } && !GitHub.cluster_regular_enabled?
    end

    def cluster_regular_enabled?
      return false unless GitHub.enterprise?
      return @cluster_regular_enabled if defined?(@cluster_regular_enabled)
      @cluster_regular_enabled = false
    end
    attr_writer :cluster_regular_enabled

    # Store the private key for actions secrets. Only relevant for enterprise.
    # Populated by ENTERPRISE_ACTIONS_SECRETS_PRIVATE_KEY env variable.
    attr_accessor :actions_secrets_private_key

    def actions_secrets_public_key
      return @actions_secrets_public_key if defined?(@actions_secrets_public_key)

      unless GitHub.actions_secrets_private_key.empty?
        require "rbnacl"
        require "base64"

        key = RbNaCl::PrivateKey.new(Base64.decode64(GitHub.actions_secrets_private_key))
        @actions_secrets_public_key = Base64.strict_encode64(key.public_key)
      end
    end
    attr_writer :actions_secrets_public_key

    # The repository nwo to use for actions starter workflows.
    # Populated by ENTERPRISE_ACTIONS_STARTER_WORKFLOWS_NWO env variable for enterprise.
    def actions_starter_workflows_nwo
      return @actions_starter_workflows_nwo if defined?(@actions_starter_workflows_nwo)
      @actions_starter_workflows_nwo = "actions/starter-workflows" unless enterprise?
    end
    attr_writer :actions_starter_workflows_nwo

    # Whether GitHub Achievements is enabled
    def achievements_enabled?
      # GitHub Achievements does not make sense as a feature on Enterprise.
      !enterprise? && !multi_tenant_enterprise?
    end

    # Whether GitHub Sponsors is enabled
    def sponsors_enabled?
      # GitHub Sponsors does not make sense as a feature on Enterprise and requires billing.
      billing_enabled? && !enterprise? && !multi_tenant_enterprise?
    end

    # Public: Whether GitHub Marketplace is enabled
    def marketplace_enabled?
      !enterprise? && !multi_tenant_enterprise?
    end

    # Whether merge queues are enabled.
    def merge_queues_enabled?
      true
    end

    # Whether PATsV2 are enabled
    def patsv2_enabled?
      true
    end

    # Whether a user can report a piece of content on dotcom
    #
    # Returns Boolean.
    def can_report?
      !enterprise?
    end

    # Whether a hubber needs to provide a reason to view private logs
    #
    # Returns Boolean.
    def hubber_access_prompt_enabled?
      !enterprise?
    end

    # Whether Orgs SAML SSO session (external identity session) enforcement is
    # enabled in this environment.
    #
    # The feature is currently only enabled for GitHub.com (as it would be
    # redundant with GHE's SAML SSO support).
    #
    # Returns Boolean.
    def external_identity_session_enforcement_enabled?
      !enterprise?
    end

    # Whether the /.well-known/security.txt route should be enabled?
    #
    # #prodsec-response would prefer not to have it enabled for enterprise
    # to reduce spammy bug bounty submissions for exposed GHE instances
    def security_dot_txt_enabled?
      !enterprise?
    end

    # Whether we show language and UI controls related to terms of service.
    # Currently excludes enterprise environments.
    #
    # Returns a boolean.
    def terms_of_service_enabled?
      !enterprise?
    end

    # If we are using an external authentication mechanism, we can delegate
    # account lockouts to them.
    #
    # Returns true if account lockouts are enabled, false otherwise.
    def lockouts_enabled?
      (!@auth_limits_disabled || !Rails.env.test?) && !GitHub.auth.external?
    end

    def auth_limits_disabled=(disabled)
      @auth_limits_disabled = disabled
    end

    # Public: Indicates if the Explore section is enabled in this environment.
    #
    # Returns a Boolean.
    def explore_enabled?
      !multi_tenant_enterprise?
    end

    # Indicates whether we are checking user logins against reserved login
    # keywords.
    #
    # Returns true if checking of reserved login keywords is enabled, false otherwise.
    def reserved_login_keywords_enabled?
      # If we are running in test or development mode, we don't check logins
      # against reserved login keywords because we need to do things like create
      # the github organization (and "github" is a reserved login keyword).  We
      # also don't check reserved login keywords in enterprise and Proxima.
      return false if Rails.env.test?
      return false if Rails.env.development?
      !GitHub.single_or_multi_tenant_enterprise?
    end

    # Do we block JSON responses to non-XHR requests?
    def json_xhr_requirement_enabled?
      !Rails.env.test?
    end

    # The full path to the root directory where repositories are stored.
    def repository_root
      @repository_root ||=
        if GitHub::AppEnvironment.development?
          env = enterprise? ? "fi" : GitHub::AppEnvironment.env
          File.expand_path("#{GitHub::AppEnvironment.root}/repositories/#{env}")
        elsif GitHub::AppEnvironment.test?
          # tests get a clean repo root and each parallel test process gets its own
          # directory too based on the TEST_ENV_NUMBER.
          "#{GitHub::AppEnvironment.root}/repositories/test#{ENV['TEST_ENV_NUMBER']}"
        else
          "/data/repositories"
        end
    end
    attr_writer :repository_root

    # The git repository template used when creating new repositories on
    # disk. This contains hooks and any other files that should be present
    # in newly created or forked repositories.
    #
    # This is only relevant for GHES.
    #
    # Returns the full path to git repo template directory.
    attr_accessor :repository_template

    def gist3_repository_template
      @gist3_repository_template ||=
        if Rails.env.production?
          "/data/github/current/lib/git-core/gist-template".freeze
        else
          "#{Rails.root}/lib/git-core/gist-template".freeze
        end
    end
    attr_writer :gist3_repository_template

    # Determine if the app is running under GitHub Enterprise. This is
    # determined by the ENTERPRISE (or FI) environment variable being set.
    # Returns true for GHES.
    # prefer using single_tenant_enterprise? for GHES specific checks
    #
    # Returns true if running under Enterprise, false otherwise.
    def enterprise?
      return @enterprise if defined?(@enterprise)
      @enterprise = GitHub.runtime.enterprise?
    end
    attr_writer :enterprise
    alias fi? enterprise?

    # Public: Alias for determining if the application is running under
    # GitHub Enterprise mode which is a single-tenant enterprise mode.
    #
    # NOTE: This does not use `alias` because the `enterprise?` method
    # is directly stubbed in many tests which does not apply to aliases.
    def single_tenant_enterprise?
      enterprise?
    end

    # Determines if the app is running on a non-clustered Enterprise instance
    # Enterprise non-clustered returns true
    # Enterprise clustered returns false
    # github.com returns false
    def single_instance?
      return @single_instance if defined? @single_instance
      @single_instance = enterprise? && GitHub::AppEnvironment.development?
    end
    attr_writer :single_instance

    # Determine if the current request is not enterprise
    def dotcom_request?
      !enterprise?
    end

    # Determine if the app should only show the limited Admin Center UI
    #
    # Returns true if running under Enterprise
    def limited_admin_center?
      GitHub.enterprise?
    end

    def default_request_timeout
      @default_request_timeout ||= ENV.fetch("DEFAULT_REQUEST_TIMEOUT", "10").to_i
    end
    attr_writer :default_request_timeout

    # The read timeout for GitRPC
    attr_accessor :gitrpc_timeout
    attr_accessor :threepc_read_txn_timeout

    # The threshhold for slow web / API requests, in seconds.  Requests that
    # take longer than this threshold are sent to a slow bucket in failbot
    # for reporting.
    def slow_request_threshold
      @slow_request_threshold ||= 5.0
    end
    attr_writer :slow_request_threshold

    # Configures whether we send slow request needles to failbot
    def instrument_slow_requests?
      enterprise?
    end

    # Determine if the app is running as GitHub Enterprise mode.
    #
    # GitHub Enterprise Server (enterprise? == true)
    # Multi-tenant (enterprise? == false since this is dotcom mode)
    #
    # Returns Boolean
    def single_or_multi_tenant_enterprise?
      # enterprise? is true for GitHub Enterprise Server
      single_tenant_enterprise? ||
      # otherwise, check if we're running as multi-tenant mode
      multi_tenant_enterprise?
    end

    # Determines if the GCM Core Oauth app should be created
    # Used in enterprise:gcm_core:create rake task
    #
    # false for Dotcom and GHES
    def create_gcm_core_oauth_app?
      multi_tenant_enterprise?
    end

    # Determine if the app is running on a employee-only unicorn.
    #
    # Return true on staff1.rs
    def employee_unicorn?
      return @employee_unicorn if defined?(@employee_unicorn)
      @employee_unicorn = false
    end
    attr_writer :employee_unicorn

    # Determine if the app is running on the new-style employee-only unicorn.
    #
    # Return true on one of the garage hosts
    def garage_unicorn?
      return @garage_unicorn if defined?(@garage_unicorn)
      @garage_unicorn = false
    end
    attr_writer :garage_unicorn

    # Wait to ship these to ES until they're tested in dotcom
    def early_hints?
      !enterprise?
    end

    # Return the user-facing name for GitHub based on whether this is
    # GitHub.com, a GHES installation, or a multi-tenant deployment.
    #
    # Returns a String
    def flavor
      if enterprise? || multi_tenant_enterprise?
        "GitHub Enterprise"
      else
        "GitHub"
      end
    end

    # Return the user-facing name for GitHub based on whether or not
    # they're looking at GitHub.com or an Enterprise installation with unified
    # search enabled
    #
    # Returns a String
    def search_flavor
      if multi_tenant_enterprise? || (enterprise? && !GitHub::Connect.unified_search_enabled?)
        "GitHub Enterprise"
      else
        "GitHub"
      end
    end

    # committer_name to be used for web edits/merges/reverts.
    #
    # Returns a String.
    def web_committer_name
      flavor
    end

    # committer_email to be used for web edits/merges/reverts.
    #
    # Returns a String.
    def web_committer_email
      noreply_address
    end

    # Do we sign web commmit with gpgverify?
    #
    # Returns boolean.
    def web_commit_signing_enabled?
      return true unless enterprise?
      return true if GitHub.environment.fetch("ENTERPRISE_WEB_COMMIT_SIGNING_ENABLED", "false") == "true"
      false
    end

    # Do we persist commit signature verification?
    #
    # Returns boolean.
    def persistent_commit_signature_verification_enabled?
      return true unless enterprise?
      return true unless GitHub.environment.fetch("ENTERPRISE_PERSIST_COMMIT_SIGNATURE_VERIFICATION_ENABLED", "true") == "false"
      false
    end

    # Used to determine whether we verify emails hosted with a disposable email service.
    #
    # Returns boolean.
    def prevent_disposable_email_verification?
      return @prevent_disposable_email_verification if defined?(@prevent_disposable_email_verification)
      @prevent_disposable_email_verification = !enterprise?
    end
    attr_writer :prevent_disposable_email_verification

    # Used to determine the period of time below which an account is always
    # considered active and within which we look for activity when considering
    # how dormant the account is. See User#recently_active? and
    # User#exempt_from_dormancy?
    #
    # Returns a time period.
    def dormancy_threshold
      GitHub.enterprise? ? GitHub.enterprise_dormancy_threshold : 12.months
    end

    # Is caching of the most recent stratocaster event timestamp for users
    # enabled?
    #
    # Enabled by default on Enterprise, where we archive stratocaster_events
    # records older than a month. With this config setting enabled, we cache
    # users' most recent stratocaster event timestamp in GitHub.kv
    #
    # Disabled for dotcom.
    #
    # Returns true if enabled, otherwise false.
    def stratocaster_event_timestamp_cache_enabled?
      return @stratocaster_event_timestamp_cache_enabled if defined?(@stratocaster_event_timestamp_cache_enabled)
      @stratocaster_event_timestamp_cache_enabled = enterprise?
    end
    attr_writer :stratocaster_event_timestamp_cache_enabled

    # Is the public event timeline delayed? On GitHub.com we delay the public
    # event feed to allow our token scanning logic time to notify providers and
    # for them to act on the results.
    def public_event_timeline_delayed?
      !GitHub.enterprise?
    end

    # Determine if the "Dormant users" page in stafftools should be displayed.
    # This performs fairly intense operations against the entire users table,
    # so it shouldn't be used on .com.
    def bulk_dormant_user_suspension_enabled?
      return @bulk_dormant_user_suspension_enabled if defined?(@bulk_dormant_user_suspension_enabled)
      @bulk_dormant_user_suspension_enabled = GitHub.enterprise?
    end
    attr_writer :bulk_dormant_user_suspension_enabled

    # Trusted ports are used for GitHub Enterprise to allow some diagnostics
    # scripts to hit the API and some other staff-specific routes without
    # authenticating.
    #
    # Returns true if this feature is enabled, false otherwise.
    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def trusted_ports_enabled?
      @trusted_ports_enabled ||= enterprise?
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator
    attr_writer :trusted_ports_enabled

    # The ports we implicitly trust. Nginx should only be listening to
    # these ports on localhost.
    #
    # Returns an array of strings.
    def trusted_ports
      @trusted_ports ||= if GitHub.enterprise?
        %w(1337)
      else
        []
      end
    end

    # The ip addresses explicitly trusted by an enterprise installation.
    #
    # Returns an array of strings.
    def trusted_ips
      return @trusted_ips if defined?(@trusted_ips)
      LOCAL_IP_ADDRESSES
    end

    def trusted_ips=(ips)
      @trusted_ips = if !ips.blank? && ips =~ /^[\d\.\[\]\s]+$/
        LOCAL_IP_ADDRESSES | ips.tr("[]", "").split
      else
        LOCAL_IP_ADDRESSES
      end

      @trusted_ips
    end

    def trusted_proxies
      LOCAL_TRUSTED_PROXIES | trusted_ips
    end

    def staff_user_from_env(env)
      if cookie = GitHub::StaffOnlyCookie.read(Rack::Request.new(env).cookies)
        cookie.user
      end
    end

    ##
    # Host Names

    # The external GitHub hostname only. No http:// prefix or protocol
    # information is included.
    #
    # NOTE: For staff hosts, this will be the full staff host, including
    # `admin.github.com`, `mtodd.review-lab.github.com`, and `garage.github.com`.
    #
    # Returns the hostname string ("github.com", "github.localhost", etc.) or nil if
    # no host_name has been set.
    def host_name
      @host_name || ENV["GH_HOSTNAME"]
    end
    attr_writer :host_name

    def copilot_workspace_host_name
      "copilot-workspace.githubnext.com"
    end

    # For multi tenant enterprise only, we need return a host name url with tenant prefix
    # If tenant is not provided, we will use the current tenant from the context (if available)
    def host_name_with_tenant(tenant: nil)
      return host_name unless GitHub.multi_tenant_enterprise?
      return host_name if GitHub.review_lab?

      tenant ||= GitHub::CurrentTenant.get
      return host_name unless tenant.present?

      "#{tenant.slug}.#{host_name}"
    end

    # The main external GitHub hostname only. No http:// prefix or protocol
    # information is included.
    #
    # NOTE: This should exclude subdomains for staff hosts.
    #
    # Returns the hostname string ("github.com", "github.localhost", etc.) or nil if
    # no host_name has been set.
    def host_domain
      @host_domain ||=
        if host_name.present?
          PublicSuffix.domain(host_name)
        else
          "github.com"
        end
    end
    attr_writer :host_domain

    # Determines if emails are sent with the configured noreply address
    # as Enterprise always has, or the GitHub.com style of emails where
    # they are From: a notifications@ address
    attr_accessor :mail_use_noreply_addr

    # Hostname for githubusercontent.com.
    #
    # production:  githubusercontent.com
    # development: githubusercontent.dev
    #
    # Returns String host or nil.
    attr_accessor :user_content_host_name

    # The host name where the API accepts uploads.
    def api_upload_host_name
      @api_upload_host_name ||= if enterprise? || garage_unicorn?
        "#{host_name_with_tenant}/api/uploads".freeze
      else
        "uploads.#{host_name_with_tenant}".freeze
      end
    end

    # Choose which type of URL creator we need to return
    #
    # Returns an instance of GitHub::UrlBuilder
    def urls
      if GitHub.multi_tenant_enterprise?
        multi_tenant_url_builder
      else
        default_url_builder
      end
    end

    # Generate URLs for default GitHub instances.
    #
    # Returns a GitHub::UrlBuilder instance
    def default_url_builder
      @default_url_builder ||= GitHub::UrlBuilder.new(host_name: host_name, scheme: scheme)
    end

    def multi_tenant_url_builder
      GitHub::UrlBuilder.new(host_name: GitHub.host_name_with_tenant, scheme: scheme)
    end

    # Whether or not the URLs generated for API endpoints should include a path
    # prefix. By default, no prefix is included and API routes are expected to
    # be distinguished from other routes via their hostname.
    #
    # Returns a Boolean.
    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def use_api_path_prefix?
      return @use_api_path_prefix if defined?(@use_api_path_prefix) && !Rails.env.test?
      @use_api_path_prefix = (
        ENV.fetch("USE_API_PATH_PREFIX", "0") == "1" ||
        single_tenant_enterprise? ||
        garage_unicorn?
      )
    end

    # The host name that the API is served from.
    #
    # Retrurns a String.
    def api_host_name
      urls.api_host_name
    end

    # The root path of the API.
    #
    # Returns a String.
    def api_root_path
      urls.api_root_path
    end

    # The URL where the V3 API is served from. This defaults to the configured
    # host_name with an "api." prefix.
    #
    # Returns the API url string (e.g. "https://api.github.com" for production)
    def api_url
      urls.api_url
    end
    attr_writer :api_url

    # The host name that the internal API is served from.
    #
    # Retrurns a String.
    def internal_api_host_name
      urls.internal_api_host_name
    end

    # The root path of the API.
    #
    # Returns a String.
    def internal_api_root_path
      urls.internal_api_root_path
    end

    # The URL where the V3 Internal API is served from.
    # It uses its own pool of k8s resources.
    #
    # Returns the API url string (e.g. "https://api.github.com" for production)
    def internal_api_url
      urls.internal_api_url
    end

    # The URL where the V3 API is served from for githooks.
    #
    # Returns the API url string (e.g. "https://api.github.com" for production)
    def githooks_api_url
      internal_api_url
    end

    # The URL where the GraphQL API is served from. This defaults to the
    # configured host_name with an "api." prefix.
    #
    # Returns the API url string (e.g. "https://api.github.com" for production)
    def graphql_api_url
      urls.graphql_api_url
    end
    attr_writer :graphql_api_url

    # The host name that the public REST API is served from.
    #
    # Returns a String.
    def public_api_host_name
      urls.public_api_host_name
    end

    # The URL where the public REST API is served from.
    #
    # Returns the API url string (e.g. "https://api.github.com" for production)
    def public_api_url
      urls.public_api_url
    end

    attr_accessor :route_query_mapper_backend
    def route_query_mapper
      @route_query_mapper ||= begin
        backend = case GitHub.route_query_mapper_backend
        when :dev_mode_json
          Platform::RouteToQueryMapper::DevModeJsonBackend.new
        when :json
          Platform::RouteToQueryMapper::JsonBackend.new
        else
          fail "unknown query store backend #{GitHub.route_query_mapper_backend.inspect}"
        end

        Platform::RouteToQueryMapper.new(backend:)
      end
    end

    def api_upload_prefix
      @api_upload_prefix ||= begin
        host_and_path = api_upload_host_name
        (ssl? ? "https://" : "http://") + host_and_path
      end
    end

    # Determine whether API deprecation headers are.
    #
    # Returns true if enabled, false otherwise.
    def api_deprecation_headers_enabled?
      return @api_deprecation_headers_enabled if defined?(@api_deprecation_headers_enabled)
      @api_deprecation_headers_enabled = !GitHub.enterprise?
    end
    attr_writer :api_deprecation_headers_enabled

    def admin_host_name
      "admin.github.com"
    end
    attr_writer :admin_host_name

    def admin_host?
      !!@is_admin_host
    end
    attr_writer :is_admin_host

    def stafftools_url
      urls.stafftools_url
    end

    def insights_available?
      # a temporary hack to hide insights from all users in 2.19 after last minute
      # go-to-market postponement
      @insights_available ||= false # GitHub.enterprise?
    end
    attr_writer :insights_available

    def insights_url
      return nil unless insights_available?
      GitHub.kv.get("insights_url").value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    def insights_url=(value)
      return unless insights_available?
      GitHub.kv.set("insights_url", value) # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    def admin_frontend_enabled?
      return @admin_frontend_enabled if defined?(@admin_frontend_enabled)
      @admin_frontend_enabled = true
    end
    attr_writer :admin_frontend_enabled

    # The user id for our Monitors account, which is used to display things in the office
    # and often has some special privilege.
    #
    # Returns an integer id.
    def monitors_user_id
      @monitors_user_id || MONITORS_USER_ID
    end

    # The fetch interval in minutes for GitHub Desktop applications.
    #
    # Returns an integer representing minutes
    def desktop_fetch_interval
      @desktop_fetch_interval || DESKTOP_FETCH_INTERVAL
    end
    attr_writer :desktop_fetch_interval

    # The login for recording mirror pushes.
    #
    # Returns the String login name.
    def mirror_pusher
      return @mirror_pusher if defined?(@mirror_pusher)
      @mirror_pusher = MIRROR_PUSHER
    end
    attr_writer :mirror_pusher

    # Write only to healthy replicas (default on GHES 3.6 and prior)
    # This is a temporary emergency option in case customers like Intuit
    # continue to see issues with routes that are marked offline too
    # eagerly because we are writing to un-healthy replicas.
    #
    # More context on the Intuit issue:
    # https://github.com/github/git-systems/issues/1825
    def write_only_to_healthy_replicas
      @write_only_to_healthy_replicas ||= false
    end
    attr_writer :write_only_to_healthy_replicas

    # How many copies (replicas) of each repo network to aim for by
    # *default*. See `dgit_read_heavy_copies` for read-heavy repos.
    #
    # Returns a small, odd integer.
    def dgit_default_copies
      @dgit_default_copies ||= DGIT_COPIES
    end
    attr_writer :dgit_default_copies

    # Alternative setter for `dgit_default_copies`. Used by GHES
    # configuration.
    def dgit_copies=(n)
      @dgit_default_copies = n
    end

    # How many copies (replicas) of each repo network to aim for if
    # the repo is configured read-heavy.
    def dgit_read_heavy_copies
      @dgit_read_heavy_copies ||= DGIT_COPIES
    end
    attr_writer :dgit_read_heavy_copies

    # How many non-voting copies of each repo network to aim for.
    #
    # If nil, spokes will not care how many non-voting replicas exist.
    attr_accessor :dgit_non_voting_copies

    # How much RSS will the dgit maintenance scheduler allow itself to use?
    #
    # This size is in bytes. The baseline RSS of a background job worker is between
    # 500MB and 700MB. The dominant query in the maintenance scheduler uses
    # 350 - 400 bytes per network replica in the current query slice. In prod,
    # we typically look at a slice of 200,000 networks at a time, and each
    # has 6 replicas, which is 457MB, so the total process size would be
    # ~1157MB. There's a thread in God that kills any process over 4GB of
    # RSS on slowworker nodes, which is where the maint scheduler runs. So,
    # tell the maint worker to limit itself to 3GB. This should be high
    # enough that mysql query time is the limiting factor on slice size.
    #
    # In GHE, the baseline background job process size is the same. In general, GHE
    # instances have up to two replicas of less than 10,000 networks. In
    # this case, the result set will use fewer than 10 MB of RSS, which
    # isn't significant in a process that's already got 700MB of RSS. Also,
    # on these instances, the query slicer will never limit the queries (the
    # smallest slice size is 10,000 networks). For larger instances, with
    # e.g. 3 replicas of 100,000 networks, the result set size is 114 MB,
    # which means that the total worker RSS would be ~814 MB. So, make the
    # default maint RSS 1GB in GHE, since that will avoid any limiting in
    # all known cases today, but provide some protection for larger instances
    # in the future.
    def dgit_maint_max_rss
      @dgit_maint_max_rss ||=
        begin
          gb = 1024 * 1024 * 1024
          if Rails.env.test?
            100 * gb # effectively disabled
          elsif GitHub.enterprise?
            gb
          else
            3 * gb
          end
        end
    end
    attr_writer :dgit_maint_max_rss

    # How frequently should the timerd job run to pre-fill the
    # cached disk stats?
    #
    # This should be smaller than dgit_disk_stats_cache_ttl.
    attr_writer :dgit_disk_stats_interval
    def dgit_disk_stats_interval
      @dgit_disk_stats_interval || 60
    end

    # How long should GitHub::DGit.disk_stats and GitHub::DGit.parallel_disk_stats
    # cache their responses for?
    attr_writer :dgit_disk_stats_cache_ttl
    def dgit_disk_stats_cache_ttl
      @dgit_disk_stats_cache_ttl || 90
    end

    # How frequently should the timerd job run to compare
    # fileservers tables between the legacy and new Spokes
    # databases?
    attr_writer :dgit_fileservers_diffjob_interval
    def dgit_fileservers_diffjob_interval
      @dgit_fileservers_diffjob_interval || 60
    end

    # How many copies (replicas) of a repo are needed to accept a write.
    # `ncopies` indicates the actual number of replicas eligible to vote.
    #
    # When `ncopies` is more than the number of expected dgit copies for
    # the respective repo, then the quorum might be larger.  For example,
    # the normal number of copies is 5, but in some cases, a repo network
    # might have 6 copies, in which case it takes 4 (not 3) to make a
    # quorum.
    #
    # Returns a strict majority of the target number of copies.
    def dgit_quorum(ncopies)
      ncopies / 2 + 1
    end

    # Returns the quorum for repositories with the default number of copies.
    def dgit_default_quorum
      dgit_quorum(dgit_default_copies)
    end

    def dgit_git_daemon_port
      @dgit_git_daemon_port ||= if GitHub::AppEnvironment.development?
        9418
      elsif GitHub::AppEnvironment.test?
        9423 + test_environment_number.to_i
      else # production
        9419
      end
    end
    attr_writer :dgit_git_daemon_port

    def dgit_gitrpcd_port
      @dgit_gitrpcd_port ||= if GitHub::AppEnvironment.development?
        9480
      elsif GitHub::AppEnvironment.test?
        9485 + test_environment_number.to_i
      else # production
        9480
      end
    end
    attr_writer :dgit_gitrpcd_port

    # Should `GitHub::DGit.threepc_debug` output anything?
    def dgit_threepc_debug_enabled?
      return false if GitHub::AppEnvironment.test?
      @dgit_threepc_debug_enabled if defined?(@dgit_threepc_debug_enabled)
    end
    attr_writer :dgit_threepc_debug_enabled

    # How long should we wait to load a Gist snippet preview?
    def gist_snippet_timeout
      @gist_snippet_timeout ||= 1.25 # seconds
    end
    attr_writer :gist_snippet_timeout

    # The Gist hostname. No http:// prefix or protocol information is included.
    #
    # Returns the Gist hostname string ("gist.github.com"). Defaults to host_name.
    def gist_host_name
      @gist_host_name ||= host_name
    end
    attr_writer :gist_host_name

    # The Gist 3 hostname. No http:// prefix or protocol information is included.
    # Until we make the switch to Gist 3, we'll be running both side-by-side.
    #
    # Returns the Gist hostname string ("gist.github.com"). Defaults to host_name.
    def gist3_host_name
      @gist3_host_name ||= host_name
    end
    attr_writer :gist3_host_name

    # Is Gist running under its own subdomain like gist.github.com? If not, it is served from <url>/gists.
    def gist_domain?
      gist_host_name != host_name
    end

    # Is Gist 3 running under its own subdomain like gist3.github.com? If not, it is served from <url>/gists.
    def gist3_domain?
      gist3_host_name != host_name
    end

    # Gist OAuth Client credentials. Used for OAuth authentication in subdomain mode.
    attr_accessor :gist_oauth_client_id, :gist_oauth_secret_key

    # The Subversion / Slummin hostname. No http:// prefix or protocol
    # information is included. By default, this is the configured host_name.
    #
    # Returns the hostname string ("github.com", "stg.github.com", etc)
    def subversion_host_name
      host_name_with_tenant
    end
    attr_writer :subversion_host_name

    # The GitHub users hostname. No http:// prefix or protocol information is
    # included. By default, this is the configured host_name with a "users.noreply."
    # prefix.  This hostname is used for "stealth" emails.
    #
    # Returns the hostname string (ex: "users.noreply.github.com")
    def stealth_email_host_name
      return @stealth_email_host_name if defined?(:@stealth_email_host_name) && @stealth_email_host_name.present?
      host_name_without_port = host_name.gsub(/:\d+\z/, "")
      @stealth_email_host_name = "users.noreply.#{host_name_without_port}".freeze
    end
    attr_writer :stealth_email_host_name

    # The short name of the machine this process is currently executing on. Writing to
    # this config value is not recommended.
    def local_host_name_short
      if GitHub.kube?
        # 'kube-unknown' protects us from processes that didn't set the
        # env var properly, and hopefully also is greppable to find this comment
        long = ENV["KUBE_NODE_HOSTNAME"] || "kube-unknown"
      else
        long = local_host_name
      end
      @local_host_name_short ||= long.split(".", 2).first
    end
    attr_writer :local_host_name_short

    # The name of the machine this process is currently executing on.
    # Explicitly set on Enterprise to the configured node name.
    def local_host_name
      @local_host_name ||= (require "socket"; Socket.gethostname)
    end
    attr_writer :local_host_name

    # The role of the currently running process, request or job. Defaults to
    # :unassigned as a catch all for when the role is not setup. This is
    # explicitly set before web requests, background jobs, etc. to provide
    # context of where an action is happening from (like a sql query).
    # Keep it a Symbol so everyone knows what they are dealing with.
    #
    # Returns a Symbol of the currently set role for this process, request,
    # background job, etc.
    def role
      @role ||= begin
        from_env = ENV["GITHUB_CONFIG_ROLE"]

        if from_env.nil? || from_env.empty?
          :unassigned
        else
          from_env.to_sym
        end
      end
    end

    # Get a role from the host's Sites API role. You might ask "why isn't this
    # the default for #role"? Because there are a bunch of places where we used
    # to set GITHUB_CONFIG_ROLE god config and it may or may not have been picked
    # up by processes. In those cases, we need to be more explicit so that we
    # don't accidentally have mixed metrics.
    def role_from_host
      host_app = server_metadata["app"]
      host_role = server_metadata["role"]

      if host_app == "github"
        case host_role
        when "api", "registryfe", "stafftools", "dfs"
          host_role.to_sym
        when "fe"
          if local_host_name.start_with?("github-fe")
            :fe
          elsif local_host_name.start_with?("github-staff")
            :lab
          else
            :unassigned
          end
        when "staff"
          :lab
        else
          :unassigned
        end
      elsif host_app == "pages"
        case host_role
        when "dfs"
          # pages-dfs's timerd is a github/github process
          :pagesdfs
        else
          :unassigned
        end
      else
        :unassigned
      end
    end

    def role=(role)
      return @role if @role == role

      @role = role
      GitHub.reset_dogtags
      @role
    end

    def internal_api_role?
      GitHub.role.to_s == "internal-api"
    end

    def enforce_internal_api_access?
      return false if GitHub.enterprise?
      !Rails.env.development?
    end

    def component
      @component ||= begin
        from_env = ENV["GITHUB_CONFIG_COMPONENT"]

        if from_env.nil? || from_env.empty?
          :unassigned
        else
          from_env.to_sym
        end
      end
    end

    def component=(component)
      return @component if @component == component

      @component = component
      GitHub.reset_dogtags
      @component
    end

    def foreground?
      component == :unicorn
    end

    # The domain of the machine this process is currently executing on. Writing
    # to this config value is not recommended.
    def domain_name
      if kube?
        full_name = ENV["KUBE_NODE_HOSTNAME"] || "kube-unknown.unknown"
      else
        full_name = local_host_name
      end

      @domain_name ||= full_name.split(".", 2).last
    end
    attr_writer :domain_name

    # The short domain of the machine this process is currently executing on.
    # Writing to this config value is not recommended.
    def domain_name_short
      @domain_name_short ||= domain_name.split(".", 2).first
    end
    attr_writer :domain_name_short

    # These local git, pages and storage host names are used to avoid setting
    # the local partitions to `localhost`.
    def local_git_host_name
      @local_git_host_name || "localhost"
    end
    attr_writer :local_git_host_name

    def local_pages_host_name
      @local_pages_host_name || "localhost"
    end
    attr_writer :local_pages_host_name

    def local_storage_host_name
      @local_storage_host_name || "localhost"
    end
    attr_writer :local_storage_host_name

    # PRs content hostname. No http:// prefix or protocol information is included.
    # No default b/c Enterprise might not use a FQDN.
    #
    # Returns String host or nil.
    attr_accessor :prs_content_host_name

    # The PRs content site URL.
    #
    # production:  https://prs.githubusercontent.com
    # garage:      https://prs-garage.githubusercontent.com
    # development: http://prs.githubusercontent.dev
    #
    # Returns the URL string or nil.
    def prs_content_host_url
      @prs_content_host_url ||= prs_content_domain? ? "#{scheme}://#{prs_content_host_name}".freeze : nil
    end
    attr_writer :prs_content_host_url

    # Should pr diffs/patches be served from its own subdomain like prs.githubusercontent.com?
    def prs_content_domain?
      !prs_content_host_name.to_s.empty?
    end

    ##
    # URLs

    # The main GitHub site URL. It returns
    # the http:// or https:// version of the URL based on whether the #ssl
    # attribute is set.
    #
    # Returns the URL string ("https://github.com", "http://github.localhost")
    def url
      urls.url
    end

    # The status page URL.
    #
    # Returns String.
    def status_url
      Proxima.status_url_for_stamp
    end

    # Get the base help docs URL for the environment.
    # GitHub.com and GHES serve Help docs differently.
    #
    # Examples:
    # - GHES: "https://docs.github.com/enterprise-server@3.6", https://docs.github.com/enterprise-server@unknown, etc.
    # - GitHub.com: "https://docs.github.com"
    #
    # skip_enterprise - Boolean to indicate that on an enterprise installation
    # we should just link to the GitHub.com versioned documentation instead.
    # Defaults to false.
    #
    # ghec_exclusive - Boolean to indicate if this documentation is exclusive to
    # GitHub Enterprise Cloud.
    #
    # Returns String
    def help_url(skip_enterprise: false, ghec_exclusive: false)
      if GitHub.enterprise? && !skip_enterprise
        enterprise_help_landing_page
      elsif ghec_exclusive
        "#{DOCS_BASE_URL}/enterprise-cloud@latest"
      else
        DOCS_BASE_URL
      end
    end

    # Public: Get the base URL to contact support.
    #
    # Returns a String.
    def support_url
      SUPPORT_BASE_URL
    end

    # Public: Get a URL for users to contact support.
    #
    # url_params - optional Hash of URL parameters to include; values do not need to be escaped;
    # e.g., `{ subject: "Help please" }`
    #
    # Returns a String.
    def contact_support_url(url_params = {})
      path = "#{support_url}/contact"
      path += "?#{url_params.to_param}" if url_params.present?
      path
    end

    # Developer Help URL for the environment.
    #
    # Note: If you want to link to the Developer blog use `developer_blog_url`
    # instead.
    #
    # skip_enterprise - Boolean to indicate that on an enterprise installation
    # we should just link to the GitHub.com versioned documentation instead.
    # Defaults to false.
    #
    # Returns String
    def developer_help_url(skip_enterprise: false)
      if GitHub.enterprise? && !skip_enterprise
        enterprise_help_landing_page
      else
        DOCS_BASE_URL
      end
    end

    def status_check_url
      if GitHub.enterprise?
        "#{enterprise_help_landing_page}/github/collaborating-with-pull-requests/collaborating-on-repositories-with-code-quality-features/about-status-checks"
      else
        "#{GitHub.help_url}/rest/commits/statuses"
      end
    end

    # Old developer site URL.
    #
    # The developer site content was moved over to the docs.github.com site
    # except the content located on the blog. At least one test requires the
    # Developer blog base url. Use the developer_site_url for tests that
    # require the developer blog base URL.
    #
    # Returns the Developer site base URL string.
    def developer_site_url
      DEVELOPER_BASE_URL
    end

    # Developer blog URL.
    #
    # Note: The developer blog is deprecated. Use `github_blog` for the
    # current github blog url
    #
    # The developer blog deliberately isn't included with the GitHub Enterprise
    # versioned documentation. Use this method instead of `developer_help_url`
    # when you want to link to the Developer blog.
    #
    # Returns the Developer Blog URL String.
    def developer_blog_url
      "#{DEVELOPER_BASE_URL}/changes"
    end

    # Enterprise Help Admin URL.
    #
    # skip_version - Boolean indicating whether to ignore the version in the URL.
    # Defaults to false.
    #
    # Returns String
    def enterprise_admin_help_url(skip_version: false)
      "#{enterprise_help_landing_page(skip_version: skip_version)}/admin"
    end

    # Enterprise Help landing page URL.
    #
    # Examples:
    # - GHES: "https://docs.github.com/enterprise-server@3.6"
    #
    # skip_version - Boolean indicating whether to ignore the version in the URL.
    # Defaults to false.
    #
    # Returns String
    def enterprise_help_landing_page(skip_version: false)
      if !skip_version && GitHub.enterprise?
        "#{DOCS_BASE_URL}/enterprise-server@#{major_minor_version_number}"
      else
        "#{DOCS_BASE_URL}/enterprise-server@latest"
      end
    end

    # Define Terms and Privacy policy paths in one location
    # Used in routes.rb and user-facing views
    def terms_url
      "#{GitHub.help_url}/site-policy/github-terms/github-terms-of-service"
    end

    def privacy_url
      "#{GitHub.help_url}/site-policy/privacy-policies/github-privacy-statement"
    end

    # Markdown Docs URL
    #
    # Returns the URL String
    def markdown_docs_url
      "#{DOCS_BASE_URL}/github/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax"
    end

    # GitHub Stars program URL
    #
    # Returns the URL string "https://stars.github.com"
    def stars_program_url
      "https://stars.github.com"
    end

    # GitHub Stars Program URL
    #
    # Returns the URL string "https://stars.github.com"
    def stars_program_url
      "https://stars.github.com"
    end

    # GitHub Classroom URL.
    #
    # Returns the URL string ("https://classroom.github.com", "http://classroom.github.com/classrooms/new", etc.)
    def classroom_host
      "https://classroom.github.com"
    end

    # Feature Preview Help URL
    #
    # Returns the URL string
    def feature_preview_help_url
      "#{help_url}/en/github/getting-started-with-github/exploring-early-access-releases-with-feature-preview"
    end

    # Update personal credit card Help URL
    #
    # Returns the URL string
    def personal_cc_help_url
      "#{GitHub.help_url}/articles/updating-your-personal-account-s-credit-card"
    end

    # Update organization credit card Help URL
    #
    # Returns the URL string
    def org_cc_help_url
      "#{GitHub.help_url}/articles/updating-your-organization-s-credit-card"
    end

    # Update personal paypal Help URL
    #
    # Returns the URL string
    def personal_paypal_help_url
      "#{GitHub.help_url}/articles/updating-your-personal-account-s-paypal-information/"
    end

    # Update organization paypal Help URL
    #
    # Returns the URL string
    def org_paypal_help_url
      "#{GitHub.help_url}/articles/updating-your-organization-s-paypal-information"
    end

    # Enterprise accounts Help URL
    #
    # Returns the URL string
    def business_accounts_help_url
      if GitHub.enterprise?
        "#{GitHub.enterprise_admin_help_url}/overview/about-enterprise-accounts"
      else
        "#{GitHub.help_url}/github/setting-up-and-managing-your-enterprise/about-enterprise-accounts"
      end
    end

    # Trade Controls Help URL
    #
    # Returns the URL string
    def trade_controls_help_url
      "#{help_url}/en/github/site-policy/github-and-trade-controls"
    end

    # Services available URL for Trade Controls Restrictions
    #
    # Returns the URL string
    def trade_controls_services_available_url
      "#{help_url}/en/github/site-policy/github-and-trade-controls#what-is-available-and-not-available"
    end

    # Site Policy URL
    #
    # Returns String
    def site_policy_url
      "#{DOCS_BASE_URL}/en/github/site-policy"
    end

    # Frequently asked questions URL for Trade Controls Restrictions
    #
    # Returns the URL string
    def trade_controls_faq_url
      "#{trade_controls_help_url}#frequently-asked-questions"
    end

    # Live Chat domain URL
    #
    # Returns the URL string
    def support_assets_url
      if Rails.env.development? && ENV["CODESPACE_NAME"] && ENV["HELPHUB_DEV"]
        return "https://#{ENV["CODESPACE_NAME"]}-8280.githubpreview.dev"
      elsif Rails.env.development? || GitHub.dynamic_lab?
        return "https://helphub-assets-staging.githubapp.com"
      end
      "https://support-assets.github.com"
    end

    # Live Chat iframe URL
    #
    # Returns the URL string
    def support_assets_livechat_iframe_url
      (Rails.env.development? || GitHub.dynamic_lab?) ? "#{support_assets_url}/ghes-trial-live-chat-dev.html" : "#{support_assets_url}/ghes-trial-live-chat.html"
    end

    # Appeals form for Scheduled Organization Trade Controls Restrictions
    #
    # Returns the URL string
    def org_pending_enforcement_appeals_url
      "https://airtable.com/shrB2je5RBkqLEt5D"
    end

    # Update payment information URL
    #
    # Returns the URL string
    def payment_information_update_url
      "https://github.com/settings/billing/payment_information"
    end

    # GitHub privacy statement url
    #
    # Returns the URL string
    def privacy_statement_url
      "#{help_url}/articles/github-privacy-statement"
    end

    def spending_limit_url
      "#{help_url}/github/setting-up-and-managing-billing-and-payments-on-github/managing-your-spending-limit-for-github-actions"
    end

    def india_rbi_url
      "#{help_url}/en/early-access/billing/india-rbi-regulation"
    end

    def rbi_manual_payment_url
      "#{help_url}/billing/managing-billing-for-your-github-account/one-time-payments-for-customers-in-india"
    end

    def actions_manage_org_settings_help_url
      "#{help_url}/organizations/managing-organization-settings/disabling-or-limiting-github-actions-for-your-organization"
    end

    def actions_manage_repo_settings_help_url(ghec_exclusive: false)
      "#{help_url(ghec_exclusive: ghec_exclusive)}/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository"
    end

    # The directory containing subschemas for the GitHub API.
    #
    # Return a string path.
    def api_subschema_dir
      GitHub::AppEnvironment.root.join("app/api/schemas/v3/schemas")
    end

    # Enable rate limiting. Disabled by default in development, Enterprise, and shadow-lab.
    # override defaults with the RATE_LIMITING environment variable.
    def rate_limiting_enabled?
      return @rate_limiting_enabled unless @rate_limiting_enabled.nil?
      @rate_limiting_enabled = ENV["RATE_LIMITING"] ||
        (!Rails.env.development? && !enterprise? && !shadow_lab?)
    end
    attr_writer :rate_limiting_enabled

    # A list of users that are exempt from rate limits. Exempt means that we
    # apply *very* high rate limits as defined in `app/api/rate_limit_configuration.rb`
    #
    # Returns an array of user names
    def rate_limiting_exempt_users
      @rate_limiting_exempt_users ||= GitHub.enterprise? ? [] : ["hubot".freeze, "entitlements-reviewer".freeze, "entitlements".freeze]
    end
    attr_writer :rate_limiting_exempt_users

    # The asset host root URL. This defaults to url and is typically
    # overridden in production environments to enable asset loading from a
    # CDN / separate domain.
    #
    # May return "" if assets are served from the same domain.
    #
    # Returns the string URL ("https://blah.cloudfront.net", "", etc)
    def asset_host_url
      @asset_host_url ||= url
    end

    # Allow asset_host_url to be set as just a hostname.
    def asset_host_url=(url)
      if url.nil? || url == ""
        url = ""
      elsif url && url !~ /^https?:/
        url = "#{scheme}://#{url}"
      end
      @asset_host_url = url
    end

    # The braintree gateway URL, for #csp_connect_sources
    def braintreegateway_url
      @braintreegateway_url ||= if Rails.env.production?
        "https://api.braintreegateway.com"
      else
        "https://api.sandbox.braintreegateway.com"
      end
    end

    # The braintree analytics URL, for #csp_connect_sources
    def braintree_analytics_url
      @braintree_analytics_url ||= if Rails.env.production?
        "https://client-analytics.braintreegateway.com"
      else
        "https://client-analytics.sandbox.braintreegateway.com"
      end
    end

    # The paypal checkout URL for paypal button images, for #csp_image_sources
    def paypal_checkout_url
      @paypal_checkout_url ||= "https://checkout.paypal.com"
    end

    # The asset host to use for all email assets.
    #
    # GitHub.asset_host_url may be nil or blank when assets should be served from
    # the same origin. The mailer asset host is never blank and will fallback to
    # the full origin url.
    #
    # development: http://github.localhost
    # production:  https://github.githubassets.com
    # labs:        https://foo.review-lab.github.com
    #
    # Always returns a full URL String.
    def mailer_asset_host_url
      if asset_host_url.present?
        asset_host_url
      else
        url
      end
    end

    # The asset host to use for Alloy assets.
    #
    # GitHub.asset_host_url may be nil or blank when assets should be served from
    # the same origin. The Alloy asset host is never blank and will fallback to
    # the full origin url.
    #
    # development: http://github.localhost
    # production:  https://github.githubassets.com
    # labs:        https://foo.review-lab.github.com
    #
    # Always returns a full URL String.
    def alloy_asset_host_url
      if asset_host_url.present?
        asset_host_url
      else
        url
      end
    end

    # This returns the identicons host used to fetch the identicons avatar.
    #
    # Returns identicon hostname as a string. This string requires
    # a '/' for joining with path parts.
    def identicons_host
      @identicons_host ||= if GitHub.enterprise?
        GitHub.url
      else
        "https://identicons.github.com"
      end
    end
    attr_writer :identicons_host

    # This returns the identicons host used by the internal api.
    #
    # Returns identicon hostname as a string. This string requires
    # a '/' for joining with path parts.
    def internal_identicons_host
      @internal_identicons_host ||= if GitHub.enterprise?
        GitHub.url
      else
        "identicon:"
      end
    end
    attr_writer :internal_identicons_host


    # Collector url pointing to the moda deployment. Available to the public.
    def collector_public_url
      @collector_public_url ||= if octolytics_enabled?
        "#{scheme}://#{GitHub.collector_host}".freeze
      else
        nil
      end
    end
    attr_writer :collector_public_url

    # Marketing link
    #
    # Returns the dotcom URL for Enterprise + Proxima since all marketing pages only exist on dotcom
    # otherwise returns the absoltue path so links work in production + dev env.
    def marketing_link(path)
      if GitHub.enterprise? || GitHub.multi_tenant_enterprise? || GitHub.gist_domain?
        "https://github.com#{path}"
      else
        path
      end
    end

    def varnish_enabled
      return @varnish_enabled if defined?(@varnish_enabled)
      @varnish_enabled = !GitHub.enterprise?
    end
    alias varnish_enabled? varnish_enabled
    attr_writer :varnish_enabled

    # The internal Hookshot hostname.
    #
    # Returns the URL string.
    attr_accessor :hookshot_go_url, :staging_hookshot_go_url
    # This is required for enterprise where all hookshot-go requests have the namespace of /hookshot.
    attr_accessor :hookshot_path
    attr_accessor :webhook_forwarder_url

    # Secret token for the Hookshot endpoint: "/hooks/:guid/:id"
    attr_accessor :hookshot_token

    # Webhook Deliveries API URL, path and token for production environment
    attr_accessor :webhook_deliveries_url, :staging_webhook_deliveries_url
    attr_accessor :webhook_deliveries_token, :staging_webhook_deliveries_token
    attr_accessor :webhook_deliveries_path

    # The OauthApplication#id for porter.
    def porter_app_id
      return @porter_app_id if defined?(@porter_app_id)

      app = OauthApplication.find_by(
        user_id: trusted_oauth_apps_owner,
        name:    "github-importer-production",
      )

      @porter_app_id = if app
        app.id
      elsif Rails.env.development? || Rails.env.test?
        OauthApplication::PERSONAL_TOKENS_APPLICATION_ID
      end
    end
    attr_writer :porter_app_id

    # The URL template of an import in porter.
    attr_accessor :porter_url_template

    # The URL template of an import's stafftools in porter.
    attr_accessor :porter_repository_admin_url_template

    # The URL template of an users's stafftools in porter.
    attr_accessor :porter_user_admin_url_template

    # The token that unlocks the internal admin URLs.
    def porter_internal_api_token
      @porter_internal_api_token || "porter-development-token"
    end
    attr_writer :porter_internal_api_token

    # Returns true if porter is configured.
    def porter_available?
      porter_url_template.present? &&
        porter_repository_admin_url_template.present? &&
        porter_user_admin_url_template.present? &&
        !enterprise?
    end

    # Returns true if porter is configured.
    def porter_maintenance_mode?
      GitHub.flipper[:porter_maintenance_mode].enabled?
    end

    # Valid "flavors" of the `/contact` form
    #
    # Returns an Hash in the form of flavor-key => title
    def contact_form_flavors
      flavors = { "default" => "Get help with GitHub" }

      if GitHub.user_abuse_mitigation_enabled?
        flavors.merge!({
          "report-abuse"   => "Report abuse",
          "report-content" => "Report content",
        })
      end

      unless GitHub.enterprise?
        flavors.merge!({
          "dmca"                 => "Copyright claims (DMCA)",
          "dmca-notice"          => "DMCA takedown notice",
          "dmca-counter-notice"  => "DMCA counter notice",
          "privacy"              => "Privacy concerns",
          "reinstatement"        => "Appeal and Reinstatement",
          "sales"                => "Upgrade Request",
        })
      end

      flavors
    end

    # GitHub's physical office address for inclusion into
    # email footers, invoices, legal docs, etc.
    #
    # multiline - true or false.
    #
    # Returns an Array if multiline. Returns a String otherwise.
    def physical_address(multiline: false)
      address_parts = ["GitHub, Inc. 88 Colin P Kelly Jr Street", "San Francisco, CA 94107"]
      multiline ? address_parts : address_parts.join(", ")
    end

    # Credit Decision Engine external service related keys
    attr_accessor :credit_decision_engine_tenant_id
    attr_accessor :credit_decision_engine_client_id
    attr_accessor :credit_decision_engine_client_secret_primary
    attr_accessor :credit_decision_engine_client_secret_secondary
    attr_accessor :credit_decision_engine_intake_api_client_id
    attr_accessor :credit_decision_engine_intake_api_url
    attr_accessor :credit_decision_engine_queue_name
    attr_accessor :credit_decision_engine_connection_string
    attr_accessor :nimbus_hydro_client_cert
    attr_accessor :nimbus_hydro_client_key

    # Public: This is for controlled rollover of the authentication client secret
    #
    # Returns the String client secret to use for authentication
    def credit_decision_engine_client_secret
      if GitHub.flipper[:credit_decision_engine_client_secret_secondary].enabled?
        credit_decision_engine_client_secret_secondary
      else
        credit_decision_engine_client_secret_primary
      end
    end

    # SDN (Specially Designated Nationals) external service related keys
    attr_accessor :sdn_eis_api_sub_path
    attr_accessor :sdn_eis_api_base_url
    attr_accessor :ocp_apim_subscription_key
    attr_accessor :sdn_live_api_base_url
    attr_accessor :sdn_live_api_url_path
    attr_accessor :sdn_cohort_code
    attr_accessor :sdn_authentication_client_id
    attr_accessor :sdn_authentication_tenant_id
    attr_accessor :sdn_resource_eis
    attr_accessor :sdn_resource_live_api
    attr_accessor :sdn_authentication_base_url
    attr_accessor :sdn_authentication_token_key
    attr_accessor :sdn_authentication_client_secret_primary
    attr_accessor :sdn_authentication_client_secret_secondary

    # Public: This is for controlled rollover of the SDN authentication client secret
    #
    # Returns the String client secret to use for authentication
    def sdn_authentication_client_secret
      if GitHub.flipper[:sdn_authentication_client_secret_secondary].enabled?
        sdn_authentication_client_secret_secondary
      else
        sdn_authentication_client_secret_primary
      end
    end

    # Email for Trade Controls appeals messages
    #
    # Returns the email String
    def trade_appeals_email
      @trade_appeals_email ||= "trade-appeals@github.com"
    end
    attr_writer :trade_appeals_email

    # Email for GitHub Trade SAP BIS team messages
    #
    # Returns the email String
    def trade_sap_bis_email
      @trade_sap_bis_email ||= "trade-sap-bis-information@github.com"
    end
    attr_writer :trade_sap_bis_email

    # Email for Microsoft Trade Helpdesk messages
    #
    # Returns the email String
    def microsoft_trade_help_email
      @microsoft_trade_help_email ||= "tradehlp@microsoft.com"
    end
    attr_writer :microsoft_trade_help_email

    # Email for Trade Controls CELA(legal) notifications
    #
    # Returns an Array of email Strings
    def trade_cela_emails
      @trade_cela_emails ||= ["legal@github.com"]
    end
    attr_writer :trade_cela_emails

    # Email the point of contact from Security and Revenue support to notify of SDN true-match status
    #
    # Returns an Array of email Strings
    def true_match_notification_emails
      @true_match_notification_emails ||= ["trade-help-ops@github.com"]
    end
    attr_writer :true_match_notification_emails

    # Email for Marketplace messages
    #
    # Returns the email String.
    def marketplace_email
      @marketplace_email ||= "marketplace@github.com"
    end
    attr_writer :marketplace_email

    # Email for GitHub Open Source messages
    #
    # Returns the email String.
    def opensource_email
      @opensource_email ||= "opensource@github.com"
    end
    attr_writer :opensource_email

    # Email for sending out user engagement and learning materials
    #
    # Returns the email String.
    def guides_email
      @guides_email ||= "guides@github.com"
    end
    attr_writer :guides_email

    # Email for business development
    #
    # Returns the email string
    def partnerships_email
      @partnerships_email ||= "partnerships@github.com"
    end
    attr_writer :partnerships_email

    # Public: Email from which GitHub Sponsors invoices will be sent
    #
    # Returns the email string
    def invoices_email
      @invoices_email ||= "invoices@github.com"
    end
    attr_writer :invoices_email

    # Public: Email for accounts receivable
    #
    # Returns the email string
    def accounts_receivable_email
      @accounts_receivable_email ||= "ar@github.com"
    end
    attr_writer :accounts_receivable_email

    # Public: Email for GitHub for Startups program
    #
    # Returns String
    def startups_email
      @startups_email ||= "startups@github.com"
    end
    attr_writer :startups_email

    # Public: Email for GitHub for Startups renewals only
    #
    # Returns String
    def startup_renewals_email
      @startup_renewals_email ||= "startuprenewals@github.com"
    end
    attr_writer :startup_renewals_email

    ##
    # Background Job config

    # A prefix used for all background job queues. Used to segregate workers in lab
    # on staff1.
    #
    # Returns a string prefix if set, otherwise the empty string.
    def background_job_queue_prefix
      @background_job_queue_prefix ||= ""
    end
    attr_writer :background_job_queue_prefix

    # Resident memory limit for job worker processes. If memory usage exceeds
    # this value after a job is performed the process is shut down so that a
    # fresh process can take its place.
    #
    # Returns the memory limit in bytes or nil to signify no limit.
    def job_worker_graceful_memory_limit
      if defined?(@job_worker_graceful_memory_limit)
        @job_worker_graceful_memory_limit
      else
        @job_worker_graceful_memory_limit = nil
      end
    end
    attr_writer :job_worker_graceful_memory_limit

    # The camo image proxy URL. This is used to rewrite HTTP <img> tag URLs left
    # in user content (like comments and issue bodies) through the SSL image
    # proxy, avoiding browser mixed content warnings.
    #
    # This value defaults to the <asset_host_url>/img when not set explicitly.
    #
    # Returns the image proxy root URL string.
    #
    # See Also:
    #   https://github.com/atmos/camo
    #   https://github.com/github/camo
    def image_proxy_url
      default_url = if GitHub.multi_tenant_enterprise?
        "https://camo.#{host_name_with_tenant}"
      else
        "#{asset_host_url}/img".freeze
      end

      @image_proxy_url || default_url
    end
    attr_writer :image_proxy_url

    # The secret token key used to sign generated image proxy URLs.
    #
    # Returns the key as a String, or nil when no secret is set.
    attr_accessor :image_proxy_key

    # Determine whether img URLs should be rewritten through the camo image
    # proxy. This defaults to true when SSL is enabled and the
    # image_proxy_key value is set.
    #
    # Returns true when img URLs should be rewritten, false otherwise.
    def image_proxy_enabled?
      ssl? && image_proxy_key
    end

    # Domains who'se images will not be proxied through camo when used in user
    # content.
    def image_proxy_host_allowlist
      @image_proxy_host_allowlist ||= begin
        hosts = []

        # Allow any github.com image references. This needs to be cleaned up
        # if we want to remove 'self' from CSP img-src.
        hosts << host_name

        if GitHub.multi_tenant_enterprise? && !GitHub.review_lab?
          hosts << Regexp.new("\\.#{Regexp.escape(host_name)}\\z")
        end

        # Allow any references to *.githubusercontent.com sources.
        if user_content_host_name && user_content_host_name != host_name
          hosts << Regexp.new("\\.#{Regexp.escape(user_content_host_name)}\\z")
        end

        hosts << gist_host_name if gist_domain?

        hosts
      end
    end

    # Should external images be allowed to be loaded as subresouces outside
    # of our allowed set?
    #
    # Enabling this enforces the img-src CSP.
    #
    # Requires Camo image proxy configuration.
    def restrict_external_images?
      return @restrict_external_images if defined?(@restrict_external_images)
      @restrict_external_images = true
    end
    attr_writer :restrict_external_images

    # Should we included our allowed set of third party connect hosts in our
    # connect-src CSP directive?
    #
    # Enabling this results in a set of allowed third party hosts being
    # added to the connect-src CSP directive.
    def allow_third_party_connect_sources?
      return @allow_third_party_connect_sources if defined?(@allow_third_party_connect_sources)
      @allow_third_party_connect_sources = true
    end
    attr_writer :allow_third_party_connect_sources

    ##
    # Gist

    # Gist is enabled by default at /gist and can be run under a subdomain by
    # setting the Gist.host_name option. Explicitly disabling gist by setting
    # this option false removes all links in the UI.
    def gist_enabled(user = nil)
      # Disabling Gists for EMUS until we have full support. See: https://github.com/github/repos/issues/8656
      !(user && user.is_enterprise_managed?)
    end
    alias gist_enabled? gist_enabled
    attr_writer :gist_enabled

    # Are gists allowed to be created without owners?
    #
    # This defaults to false in DotCom, true in Enterprise.
    def anonymous_gist_creation_enabled
      return @anonymous_gist_creation_enabled if defined?(@anonymous_gist_creation_enabled)
      # This will flip to false as a default after we ship the "warning" PR.
      @anonymous_gist_creation_enabled = GitHub.enterprise?
    end
    alias anonymous_gist_creation_enabled? anonymous_gist_creation_enabled
    attr_writer :anonymous_gist_creation_enabled

    # The main gist raw URL. This value typically isn't written directly but
    # should be read anywhere the raw URL for gist is required. It returns the
    # http:// or https:// version of the raw URL based on whether the #ssl attribute
    # is set.
    #
    # Returns the gist raw URL string ("https://gist.githubusercontent.com",
    # "http://gist.github.localhost", etc)
    def gist_raw_url
      ssl? ? gist_raw_https_url : gist_url
    end

    # The main gist site URL. This value typically isn't written directly but
    # should be read anywhere the root URL for gist is required. It returns the
    # http:// or https:// version of the URL based on whether the #ssl attribute
    # is set.
    #
    # Returns the gist URL string ("https://gist.github.com",
    # "http://gist.github.localhost", etc)
    def gist_url
      ssl? ? gist_https_url : gist_http_url
    end

    # The non-SSL http version of the Gist URL. Not typically used directly. Use
    # gist_url instead so that http vs. https is determined dynamically.
    def gist_http_url
      if gist_domain?
        "http://#{gist_host_name}".freeze
      else
        "#{url}/gist"
      end
    end

    # The https version of the Gist URL. Not typically used directly. Use
    # gist_url instead so that http vs. https is determined dynamically.
    def gist_https_url
      if gist_domain?
        "https://#{gist_host_name}".freeze
      else
        "#{url}/gist"
      end
    end

    # The https version of the raw Gist URL. Not typically used directly. Use
    # gist_raw_url instead so that http vs. https is determined dynamically.
    def gist_raw_https_url
      if gist_domain?
        "https://gist.#{GitHub.user_content_host_name}".freeze
      else
        gist_https_url
      end
    end

    # The URL to GitHub's graphite instance.
    attr_accessor :graphite_url

    ##
    # Caching

    # View fragment cache prefix.
    #
    # Bump this to expire all view caches.
    def fragment_cache_version
      :views10
    end

    def tombstone_user_logins?
      !GitHub.single_or_multi_tenant_enterprise?
    end

    # Cache key for task lists
    #
    # Bump this if task list rendering has changed and you need to
    # expire any cached items w/ task lists
    def task_list_cache_version
      :task_list_1
    end

    # Ajax Poller version
    #
    # Bumping this will kill any active poller clients.
    #
    # See also ajax_poll.coffee
    def ajax_poller_version
      "2"
    end

    def audit_log_export_enabled?
      !GitHub.enterprise?
    end

    def organization_members_export_enabled?
      !GitHub.enterprise?
    end

    def pull_request_processing_indicator_enabled?
      !GitHub.enterprise?
    end

    # In Enterprise cluster environments, contains the primary datacenter
    # attribute.
    attr_accessor :primary_datacenter

    ##
    # elasticsearch

    # The elasticsearch http host and port. This is actually hitting HA Proxy which
    # will load-balance across the cluster.
    attr_accessor :elasticsearch_host

    # The elasticsearch host to use for audit logs.
    attr_accessor :elasticsearch_audit_log_host

    # Returns the URL (as a String) for communicating with ElasticSearch or
    # `nil` if the elasticsearch_host has not been set.
    def elasticsearch_url
      if ENV["TEST_ES_8"] || (Rails.env.development? && es8_reachable?)
        return "http://localhost:9400"
      end
      elasticsearch_host ? "http://#{elasticsearch_host}" : nil
    end

    def es8_reachable?
      @es8_reachable = begin
        Timeout.timeout(1) do
          s = TCPSocket.new("localhost", 9400)
          s.close
        end
        true
      rescue Errno::ECONNREFUSED, Timeout::Error, StandardError # rubocop:todo Lint/GenericRescue
        false
      end
    end
    attr_writer :es8_reachable

    # The elasticsearch query timeout.
    def es_query_timeout
      @es_query_timeout ||= ES_QUERY_TIMEOUT
    end
    attr_writer :es_query_timeout

    # The elasticsearch datacenter to use.
    def es_datacenter
      @es_datacenter ||= ES_DATACENTER
    end
    attr_writer :es_datacenter

    # The elasticsearch cluster to use for audit logs.
    def es_audit_log_cluster
      @es_audit_log_cluster ||=
        if Rails.env.test?
          ES_AUDIT_LOG_CLUSTER
        elsif ENV["TEST_ES_8"]
          "es8-cluster"
        else
          ES_AUDIT_LOG_CLUSTER
        end
    end
    attr_writer :es_audit_log_cluster

    # The elasticsearch cluster to use for writes for AuditEntry.
    def es_audit_log_cluster_next
      @es_audit_log_cluster_next ||= ES_AUDIT_LOG_CLUSTER_NEXT
    end
    attr_writer :es_audit_log_cluster_next

    # The Hash containing the name / config mapping for the available
    # Elasticsearch clusters. The config looks like this:
    #
    # {url: string, compress_body: bool, es_version: string}
    def es_clusters
      @es_clusters ||= {}
    end
    attr_writer :es_clusters

    # The number of shards to use when creating the `audit_log` index.
    def es_shard_count_for_audit_log
      @es_shard_count_for_audit_log ||= ES_SHARD_COUNT_FOR_AUDIT_LOG
    end
    attr_writer :es_shard_count_for_audit_log

    # The number of shards to use when creating the `code_search` index.
    def es_shard_count_for_code_search
      @es_shard_count_for_code_search ||= ES_SHARD_COUNT_FOR_CODE_SEARCH
    end
    attr_writer :es_shard_count_for_code_search

    # The number of shards to use when creating the `commits` index.
    def es_shard_count_for_commits
      @es_shard_count_for_commits ||= ES_SHARD_COUNT_FOR_COMMITS
    end
    attr_writer :es_shard_count_for_commits

    # The number of shards to use when creating the `issues` index.
    def es_shard_count_for_issues
      @es_shard_count_for_issues ||= ES_SHARD_COUNT_FOR_ISSUES
    end
    attr_writer :es_shard_count_for_issues

    # The number of shards to use when creating the `memex_project_items` index.
    def es_shard_count_for_memex_project_items
      @es_shard_count_for_memex_project_items ||= ES_SHARD_COUNT_FOR_MEMEX_PROJECT_ITEMS
    end
    attr_writer :es_shard_count_for_memex_project_items

    # The maximum number of refresh listeners to use for requests that specify refresh=wait_for
    # See https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-refresh.html#_refresh_wait_for
    def es_max_refresh_listeners_for_memex_project_items
      @es_max_refresh_listeners_for_memex_project_items ||= ES_MAX_REFRESH_LISTENERS_FOR_MEMEX_PROJECT_ITEMS
    end
    attr_writer :es_max_refresh_listeners_for_memex_project_items

    # The number of shards to use when creating the `notifications` index.
    def es_shard_count_for_notifications
      @es_shard_count_for_notifications ||= ES_SHARD_COUNT_FOR_NOTIFICATIONS
    end
    attr_writer :es_shard_count_for_notifications

    # The number of shards to use when creating the `issues` index.
    def es_shard_count_for_pull_requests
      @es_shard_count_for_pull_requests ||= ES_SHARD_COUNT_FOR_PULL_REQUESTS
    end
    attr_writer :es_shard_count_for_pull_requests

    # The number of shards to use when creating the `topics` index.
    def es_shard_count_for_topics
      @es_shard_count_for_topics ||= ES_SHARD_COUNT_FOR_TOPICS
    end
    attr_writer :es_shard_count_for_topics

    # The number of shards to use when creating the `labels` index.
    def es_shard_count_for_labels
      @es_shard_count_for_labels ||= ES_SHARD_COUNT_FOR_LABELS
    end
    attr_writer :es_shard_count_for_labels

    # The number of shards to use when creating the `releases` index.
    def es_shard_count_for_releases
      @es_shard_count_for_releases ||= ES_SHARD_COUNT_FOR_RELEASES
    end
    attr_writer :es_shard_count_for_releases

    # The number of shards to use when creating the `repos` index.
    def es_shard_count_for_repos
      @es_shard_count_for_repos ||= ES_SHARD_COUNT_FOR_REPOS
    end
    attr_writer :es_shard_count_for_repos

    # The number of shards to use when creating the `discussions` index.
    def es_shard_count_for_discussions
      @es_shard_count_for_discussions ||= ES_SHARD_COUNT_FOR_DISCUSSIONS
    end
    attr_writer :es_shard_count_for_discussions

    # The number of shards to use when creating the `team_discussions` index.
    def es_shard_count_for_team_discussions
      @es_shard_count_for_team_discussions ||= ES_SHARD_COUNT_FOR_TEAM_DISCUSSIONS
    end
    attr_writer :es_shard_count_for_team_discussions

    # The number of shards to use when creating the `users` index.
    def es_shard_count_for_users
      @es_shard_count_for_users ||= ES_SHARD_COUNT_FOR_USERS
    end
    attr_writer :es_shard_count_for_users

    # The number of shards to use when creating the `showcases` index.
    def es_shard_count_for_showcases
      @es_shard_count_for_showcases ||= ES_SHARD_COUNT_FOR_SHOWCASES
    end
    attr_writer :es_shard_count_for_showcases

    # The number of shards to use when creating the `gists` index.
    def es_shard_count_for_gists
      @es_shard_count_for_gists ||= ES_SHARD_COUNT_FOR_GISTS
    end
    attr_writer :es_shard_count_for_gists

    # The number of shards to use when creating the `wikis` index.
    def es_shard_count_for_wikis
      @es_shard_count_for_wikis ||= ES_SHARD_COUNT_FOR_WIKIS
    end
    attr_writer :es_shard_count_for_wikis

    # The number of shards to use when creating the `projects` index.
    def es_shard_count_for_projects
      @es_shard_count_for_projects ||= ES_SHARD_COUNT_FOR_PROJECTS
    end
    attr_writer :es_shard_count_for_projects

    # The number of shards to use when creating the `marketplace_listings` index.
    def es_shard_count_for_marketplace_listings
      @es_shard_count_for_marketplace_listings ||= ES_SHARD_COUNT_FOR_MARKETPLACE_LISTINGS
    end
    attr_writer :es_shard_count_for_marketplace_listings

    # The number of shards to use when creating the `repository_actions` index.
    def es_shard_count_for_repository_actions
      @es_shard_count_for_repository_actions ||= ES_SHARD_COUNT_FOR_REPOSITORY_ACTIONS
    end
    attr_writer :es_shard_count_for_repository_actions

    # The number of shards to use when creating the `registry_packages` index.
    def es_shard_count_for_registry_packages
      @es_shard_count_for_registry_packages ||= ES_SHARD_COUNT_FOR_REGISTRY_PACKAGES
    end
    attr_writer :es_shard_count_for_registry_packages

    # The number of shards to use when creating the `vulnerabilities` index.
    def es_shard_count_for_vulnerabilities
      @es_shard_count_for_vulnerabilities ||= ES_SHARD_COUNT_FOR_VULNERABILITIES
    end
    attr_writer :es_shard_count_for_vulnerabilities

    # The number of shards to use when creating the `enterprises` index.
    def es_shard_count_for_enterprises
      @es_shard_count_for_enterprises ||= ES_SHARD_COUNT_FOR_ENTERPRISES
    end
    attr_writer :es_shard_count_for_enterprises

    # The number of shards to use when creating the `workflow_runs` index.
    def es_shard_count_for_workflow_runs
      @es_shard_count_for_workflow_runs ||= ES_SHARD_COUNT_FOR_WORKFLOW_RUNS
    end
    attr_writer :es_shard_count_for_workflow_runs

    # Auto expand replicas for each search index.
    def es_auto_expand_replicas
      @es_auto_expand_replicas ||= false
    end
    attr_writer :es_auto_expand_replicas

    # The number of replicas to maintain for each search index.
    def es_number_of_replicas
      @es_number_of_replicas ||= ES_NUMBER_OF_REPLICAS
    end
    attr_writer :es_number_of_replicas

    # The request timeout for Elasticsearch connections in seconds.
    # Despite the method name, this is not just a read timeout. It's the total time
    # allowed for a request, including connection time, sending the request, and receiving
    # the response. Defaults to 2 seconds.
    def es_read_timeout
      @es_read_timeout ||= ES_READ_TIMEOUT
    end
    attr_writer :es_read_timeout

    # The connection open timeout for Elasticsearch connections in seconds.
    # Defaults to 0.3 seconds.
    def es_open_timeout
      @es_open_timeout ||= ES_OPEN_TIMEOUT
    end
    attr_writer :es_open_timeout

    # Default worker count to start repair jobs with. Defaults to 1.
    def es_default_worker_count
      @es_default_worker_count ||= ES_DEFAULT_WORKER_COUNT
    end
    attr_writer :es_default_worker_count

    # The maximum file size that we will index in the code-search index. Source
    # code files larger than this limit will _not_ have their contents indexed
    # and searchable. Other meta-data about the source code files (filename,
    # extension, language, etc) will still be searchable.
    def es_max_doc_size
      @es_max_doc_size ||= ES_MAX_DOC_SIZE
    end
    attr_writer :es_max_doc_size

    # These are the fields that won't be used to compute a has
    # version of an ES index.
    # e.g: %i(number_of_replicas auto_expand_replicas)
    def es_skip_settings_fields
      @es_skip_settings_fields ||= []
    end
    attr_writer :es_skip_settings_fields

    # Whether the Elasticsearch audit logger should be used.
    # This is only used in Enterprise for now. This
    # will be set by the ENTERPRISE_AUDIT_LOG_ES_LOGGER_ENABLED env variable
    def audit_log_es_logger_enabled?
      @audit_log_es_logger_enabled.nil? ? true : @audit_log_es_logger_enabled
    end
    attr_writer :audit_log_es_logger_enabled

    ##
    # Subversion

    # The Subversion / Slummin root URL. This value typically isn't written
    # directly but should be read anywhere the root URL for the subversion
    # server is required. It returns the http:// or https:// version of the
    # URL based on whether the #ssl config attribute is set.
    #
    # Returns the svn URL string ("https://svn.github.com",
    # "http://svn.github.localhost", etc)
    def subversion_url
      "#{scheme}://#{subversion_host_name}"
    end
    attr_writer :subversion_url

    def site_status_url
      "https://www.githubstatus.com"
    end

    def show_site_status?
      !enterprise?
    end

    # Whether to include Google site verification tags like this into pages:
    #
    # <meta name="google-site-verification" content="...">
    def site_verification_enabled?
      !enterprise?
    end

    ##
    # Google Analytics

    # When users view private repos on dotcom, then we don't want to leak the
    # repo name, owner, or file paths to Google Analytics.
    def anonymized_private_repo_analytics?
      !enterprise?
    end

    # Determine if Google Analytics should track ecommerce purchase events
    def track_ecommerce_analytics?
      !enterprise?
    end

    # Third party hosts being added to the connect-src CSP directive.
    #
    # Needs to be enabled via allow_third_party_connect_sources.
    #
    # IMPORTANT!!! CC @github/prodsec-engineering if you need to change this.
    def third_party_connect_sources
      return @third_party_connect_sources if defined?(@third_party_connect_sources)

      @third_party_connect_sources = [
        "https://github-cloud.s3.amazonaws.com",
        "https://#{GitHub.s3_repository_file_new_host}",
        "https://#{GitHub.s3_upload_manifest_file_new_host}",
        "https://#{GitHub.s3_user_asset_new_host}",
        "https://*.rel.tunnels.api.visualstudio.com",
        "wss://*.rel.tunnels.api.visualstudio.com"
      ]

      @third_party_connect_sources.freeze
    end

    # Custom setter to freeze the Object before setting it,
    # to prevent future modifications.
    def third_party_connect_sources=(sources)
      @third_party_connect_sources = Array(sources).freeze
    end

    # LiveReload server URL that is added to the connect-src CSP directive in development.
    def livereload_url
      "ws://127.0.0.1:35729/livereload".freeze if Rails.env.development?
    end

    # In development, we serve the webpack dev server websocket endpoints from the same domain.  This is generally
    # covered by the `self` CSP policy, but Safari does not follow the spec so we need to explicitly add the websocket
    # base path to connect-src. See https://bugs.webkit.org/show_bug.cgi?id=201591
    def webpack_dev_server_connect_url
      "ws://#{GitHub.host_name}".freeze if Rails.env.development?
    end

    # Webpack dev server is proxied via nginx during development.
    def webpack_dev_server_enabled?

      (Rails.env.development? || ENV["RUN_IN_BROWSER"]) && !vite_dev_server_enabled?
    end

    # Vite dev server is proxied via nginx during development.
    def vite_dev_server_enabled?
      Rails.env.development? && ENV["VITE"]
    end

    ##
    # Octolytics, the new traffic analyisis tool.
    # App ID
    attr_accessor :octolytics_app_id
    # Collector host for external clients
    attr_accessor :collector_host
    # Secret, for signing content that passes through the browser (e.g. the user id).
    attr_accessor :octolytics_secret
    # What octolytics environment should be used to pull report data from.
    attr_accessor :octolytics_reporter_env
    # Gist App ID
    attr_accessor :gist_octolytics_app_id
    # Gist Secret, for signing content that passes through the browser (e.g. the user id).
    attr_accessor :gist_octolytics_secret

    # Secret, for signing the visitor meta information
    attr_accessor :visitor_secret

    # Returns true if tracking on analytics is configured, false otherwise.
    def octolytics_enabled?
      collector_host.present?
    end

    ##
    # Pond
    attr_accessor :pond_shared_secret

    ##
    # GitHub Models

    # Determine whether github models are enabled. Defaults to enabled throughout the site. Disabled by default under
    # Enterprise environments
    #
    # Returns false if in enterprise or proxima, true otherwise.
    def models_enabled?
      !single_or_multi_tenant_enterprise?
    end

    ##
    # Billing/Braintree

    # Determine whether billing is enabled. Typically disabled under
    # the enterprise environment. Enable via `ghe-config` by setting
    # BILLING_ENABLED to `1`, and disable with `0`. Defaults to true if
    # no value is set.
    #
    # Returns true if billing is enabled, false otherwise.
    def billing_enabled?
      return true if proxima_billing_enabled? # Proxima is multi-tenant enterprise, but we want billing enabled
      return false if single_or_multi_tenant_enterprise?
      return @billing_enabled if defined?(@billing_enabled)
      @billing_enabled = ENV.fetch("BILLING_ENABLED", "1") == "1"
    end
    attr_writer :billing_enabled

    # Determines whether the current environment supports in-app purchases.
    # Billing must be enabled and the environment cant be enterprise or proxima.
    def iap_enabled?
      return @iap_enabled if defined?(@iap_enabled)

      @iap_enabled = billing_enabled? && !enterprise? && !multi_tenant_enterprise?
    end

    ##
    # Proxima Billing
    #
    # Because Proxima is multi-tenant enterprise, we need to explicitly set
    # the PROXIMA_BILLING env variable to enable billing.
    def proxima_billing_enabled?
      return @proxima_billing_enabled if defined?(@proxima_billing_enabled)
      @proxima_billing_enabled = ENV.fetch("PROXIMA_BILLING", "0") == "1"
    end

    # Determine whether fanout of enterprise agreement export is enabled.
    # Disabled if billing is disabled.
    #
    # Returns true if fanout of enterprise agreement export is enabled, false otherwise.
    def billing_enterprise_agreement_fanout_enabled?
      return false unless  billing_enabled?
      GitHub.flipper[:billing_enterprise_agreement_fanout_enabled].enabled?
    end
    attr_writer :billing_enterprise_agreement_fanout_enabled

    # Determine whether we want to make a request to Braintree for a client token use in PayPal
    # forms. Usually false for the :test environment.
    #
    # Returns true if client tokens are enabled
    def braintree_client_token_enabled?
      billing_enabled? && @braintree_client_token_enabled
    end
    attr_accessor :braintree_client_token_enabled

    # Determine the plan name assigned to users by default. Usually set to
    # "enterprise" under enterprise or "free" for others.
    #
    # See also GitHub::Plan and User#plan.
    #
    # Returns the String plan name.
    def default_plan_name
      return @default_plan_name if defined?(@default_plan_name)
      @default_plan_name =
        if enterprise?
          GitHub::Plan::ENTERPRISE
        else
          GitHub::Plan::FREE
        end
    end
    attr_writer :default_plan_name

    # Are Discussions enabled on this platform?
    # We want to continue testing discussions against the enterprise
    # mode so we can be ready to ship to enterprise without major changes.
    #
    # Returns true if discussions can possibly exist on this platform
    def discussions_available_on_platform?(is_test_mode: Rails.env.test?)
      return true if is_test_mode

      true
    end

    # Restrict signup to the default plan when enabled. Enabled by default
    # under FI environments, disabled everywhere else.
    #
    # Returns true if enabled, false otherwise.
    def enforce_default_plan?
      return @enforce_default_plan if defined?(@enforce_default_plan)
      @enforce_default_plan = enterprise?
    end
    attr_writer :enforce_default_plan

    # Braintree configuration.
    attr_accessor :braintree_environment
    attr_accessor :braintree_merchant_id
    attr_accessor :braintree_public_key
    attr_accessor :braintree_private_key
    attr_accessor :braintree_logger
    attr_accessor :braintree_client_side_encryption_key
    attr_accessor :braintree_host

    # Taxamo configuration
    attr_accessor :taxamo_api_host
    attr_accessor :taxamo_api_private_token

    # Zuora configuration
    attr_accessor :zuora_rest_server
    attr_accessor :zuora_access_key_id
    attr_accessor :zuora_secret_access_key
    attr_accessor :zuora_client_id
    attr_accessor :zuora_client_secret
    attr_accessor :zuora_apm_rest_server
    attr_accessor :zuora_apm_username
    attr_accessor :zuora_apm_api_token
    attr_accessor :zuorest_client
    attr_accessor :zuorest_background_worker_client
    attr_accessor :zuora_lfs_rate_plan_charge_ids
    attr_accessor :zuora_github_premium_support_charge_ids
    attr_accessor :zuora_github_premium_support_plus_charge_ids
    attr_accessor :zuora_github_premium_support_plus_msft_charge_ids
    attr_accessor :zuora_github_enterprise_campus_program_charge_ids
    attr_accessor :zuora_metered_refill_rate_plan_charge_ids
    attr_accessor :zuora_sales_serve_actions_product_charge_ids
    attr_accessor :zuora_sales_serve_packages_product_charge_ids
    attr_accessor :zuora_sales_serve_shared_storage_product_charge_ids
    attr_accessor :zuora_sales_serve_ghe_ghas_mapping
    attr_accessor :zuora_sales_serve_ghe_product_charge_ids
    attr_accessor :zuora_sales_serve_ghas_product_charge_ids
    attr_accessor :zuora_sales_serve_codespaces_product_charge_ids
    attr_accessor :zuora_webhook_username
    attr_accessor :zuora_webhook_password
    attr_accessor :zuora_webhook_new_password
    attr_accessor :zuora_payment_page_server
    attr_accessor :zuora_payment_page_uri
    attr_accessor :zuora_sponsors_payment_gateway_id
    attr_accessor :zuora_self_serve_communication_profile_id
    attr_accessor :zuora_other_payment_method_id
    attr_accessor :zuora_host
    attr_accessor :zuora_invoices_light_default_payment_page_id
    attr_accessor :zuora_invoices_light_preview_payment_page_id
    attr_accessor :zuora_settings_compact_auto_default_payment_page_id
    attr_accessor :zuora_settings_compact_auto_preview_payment_page_id
    attr_accessor :zuora_settings_compact_dark_default_payment_page_id
    attr_accessor :zuora_settings_compact_dark_preview_payment_page_id
    attr_accessor :zuora_settings_compact_light_default_payment_page_id
    attr_accessor :zuora_settings_compact_light_preview_payment_page_id
    attr_accessor :zuora_settings_regular_auto_default_payment_page_id
    attr_accessor :zuora_settings_regular_auto_preview_payment_page_id
    attr_accessor :zuora_settings_regular_dark_default_payment_page_id
    attr_accessor :zuora_settings_regular_dark_preview_payment_page_id
    attr_accessor :zuora_settings_regular_light_default_payment_page_id
    attr_accessor :zuora_settings_regular_light_preview_payment_page_id
    attr_accessor :zuora_sign_up_light_default_payment_page_id
    attr_accessor :zuora_sign_up_light_preview_payment_page_id

    # Stripe configuration
    attr_accessor :stripe_api_key
    attr_accessor :stripe_v3_api_key
    attr_accessor :stripe_client_id
    attr_accessor :stripe_platform_webhook_secret
    attr_accessor :stripe_v3_platform_webhook_secret
    attr_accessor :stripe_connect_webhook_secret

    # Patreon configuration
    attr_accessor :patreon_client_id
    attr_accessor :patreon_client_secret

    # Apple IAP configuration
    attr_accessor :apple_iap_shared_secret

    # Apple AppStore API configuration
    attr_accessor :apple_app_store_api_key_id
    attr_accessor :apple_app_store_api_key_contents
    attr_accessor :apple_app_store_api_issuer_id

    # To assist with local testing in-app purchases
    attr_accessor :apple_skip_receipt_validation

    # VSS subscription service bus configuration
    attr_accessor :vss_subscription_events_topic_name
    attr_accessor :vss_subscription_events_subscription_name
    attr_accessor :vss_subscription_events_connection_string

    # VSS status message service bus configuration
    attr_accessor :vss_status_messages_queue_name
    attr_accessor :vss_status_messages_connection_string

    # Open Exchange Rates
    attr_accessor :open_exchange_rates_app_id

    # Zendesk client configuration.
    attr_accessor :zendesk_api_url
    attr_accessor :zendesk_api_token
    attr_accessor :zendesk_brand_id
    attr_accessor :zendesk_fields

    # github/harmony-entitlement-api Braavos Support Entitlement configuration.
    attr_accessor :braavos_support_entitlement_url
    attr_accessor :braavos_support_entitlement_hmac

    # Running in hubber-codespaces. In hubber-codespaces test infrastructure are running
    # in containers, so that's flag that change behavior of initialization for services.
    attr_accessor :hcs_mode

    # Proxy for communication between dotcom and external hosts
    attr_writer :external_communication_proxy_host
    def external_communication_proxy_host
      if @external_communication_proxy_host.nil? && proxy_for_external_requests_required?
        raise "EXTERNAL_COMMUNICATION_PROXY_HOST setting should be set in this environment"
      end

      @external_communication_proxy_host
    end

    def proxy_for_external_requests_required?
      !GitHub.enterprise? && !GitHub.multi_tenant_enterprise? && !Rails.env.development?
    end

    # Secret for validating Voltron messages
    attr_accessor :voltron_secret

    # Ghost user login used to replace associated users of Issues-related
    # records (Issue, IssueComment and IssueEvent) when the original user
    # is deleted.
    #
    # Returns the String ghost User login.
    def ghost_user_login
      @ghost_user_login ||= "ghost"
    end

    # Staff user login used to be the actor for staff events
    #
    # Returns the String staff User login
    def staff_user_login
      @staff_user_login ||= "github-staff"
    end

    ##
    # Authentication

    attr_accessor :builtin_auth_fallback
    attr_accessor :enterprise_passkeys_enabled
    attr_accessor :enterprise_passkeys_upsell

    attr_accessor :cas_url

    attr_accessor :ldap_host, :ldap_port, :ldap_base,
                  :ldap_bind_dn, :ldap_password, :ldap_method,
                  :ldap_search_strategy,
                  :ldap_virtual_attributes, :ldap_virtual_attribute_member,
                  :ldap_recursive_group_search_fallback,
                  :ldap_posix_support,
                  :ldap_sync_enabled,
                  :ldap_user_sync_emails, :ldap_user_sync_keys, :ldap_user_sync_skip_empty_keys, :ldap_user_sync_gpg_keys,
                  :ldap_profile_uid, :ldap_profile_name, :ldap_profile_mail,
                  :ldap_profile_key, :ldap_profile_gpg_key

    attr_accessor :saml_sso_url,           # idP http endpoint for sso. We redirect to here with an AuthnRequest.
                  :saml_idp_initiated_sso, # if this is on, responses will not be checked for corresponding requests
                  :saml_disable_admin_demote, # if this is on, admin bit is ignored and users won't promoted or demoted.
                  :saml_issuer,            # idP issuer. Used to validate responses
                  :saml_name_id_format,    # NameID format to use, (:persistent or unspecified). Unspecified should be discouraged
                  :saml_certificate_file,  # idP certificate. Public key to validate idP responses.
                  :saml_signature_method,  # algorithm to use for AuthnRequest signatures.
                  :saml_digest_method,     # algotithm to use for AuthnRequest digests.
                  :saml_encrypted_assertions, # if this is on, SAML responses require assertions to be encrypted via saml_sp_pkcs12_file
                  :saml_encryption_method,    # algorithm to use for encrypted assertions.
                  :saml_key_transport_method, # algorithm to use for the key of encrypted assertions.
                  :saml_sp_pkcs12_file,    # SP keypair for signing AuthnRequests and Metadata as well as decrypting assertions
                  :saml_admin,             # attribute name in saml response for promoting/demoting admins. Default: 'administrator'
                  :saml_username_attr,     # attribute username in saml response for account login name. Default: 'NameID'
                  :saml_profile_name,      # attribute name in saml response for user full name. Default: 'full_name'
                  :saml_profile_mail,      # attribute name in saml response for user emails. Default: 'emails'
                  :saml_profile_ssh_key,   # attribute name in saml response for user public keys. Default: 'public_keys'
                  :saml_profile_gpg_key,   # attribute name in saml response for user GPG keys. Default: 'gpg_keys'
                  :saml_default_session_expiration, # default SAML::Session expiration in seconds, if not sent from IdP. Default: 1 week
                  :saml_legacy_validation_enabled, # if this is on, SAML responses will only include legacy encrypted assertions
                  :saml_legacy_pages_redirect_enabled # if this is on, SAML pages will not use meta refresh to redirect users

    # Public: Returns the verify_mode value used for SSL communications with
    # LDAP server.
    #
    # See http://ruby-doc.org/stdlib/libdoc/openssl/rdoc/OpenSSL/SSL/SSLContext.html#verify_mode
    # for available verify_mode values
    def ldap_tls_verify_mode
      @ldap_tls_verify_mode ||= OpenSSL::SSL::VERIFY_NONE
    end

    # Public: Sets the TLS verification mode. Value is expected to be an integer
    #
    # See http://ruby-doc.org/stdlib/libdoc/openssl/rdoc/OpenSSL/SSL/SSLContext.html#verify_mode
    # for available verify_mode values
    def ldap_tls_verify_mode=(verify_mode)
      @ldap_tls_verify_mode = verify_mode.to_i
    end

    # Public: Returns true when LDAP authentication is configured and LDAP Sync is enabled.
    # Managed via enterprise-manage.
    def ldap_sync_enabled?
      auth.ldap? && ldap_sync_enabled
    end

    # Authentication adapter options hash. See the adapter implementations under
    # GitHub::Authentication for information on possible options.
    def auth_options
      if auth_mode.to_sym == :saml
        {
          builtin_auth_fallback: builtin_auth_fallback,
          sso_url: saml_sso_url,
          idp_initiated_sso: saml_idp_initiated_sso,
          disable_admin_demote: saml_disable_admin_demote,
          issuer: saml_issuer,
          name_id_format: saml_name_id_format,
          signature_method: saml_signature_method,
          digest_method: saml_digest_method,
          encrypted_assertions: saml_encrypted_assertions?,
          encryption_method: saml_encryption_method,
          key_transport_method: saml_key_transport_method,
          idp_certificate_file: saml_certificate_file,
          sp_pkcs12_file: saml_sp_pkcs12_file,
          admin: saml_admin,
          user_name: saml_username_attr,
          display_name: saml_profile_name,
          emails: saml_profile_mail,
          ssh_keys: saml_profile_ssh_key,
          gpg_keys: saml_profile_gpg_key,
          sp_url: url,
          default_session_expiration: saml_default_session_expiration,
          legacy_validation_enabled: saml_legacy_validation_enabled,
        }
      else
        {
          builtin_auth_fallback: builtin_auth_fallback,
          # Used for SAML metdata, which should be available through non-SAML
          # auth adaptors so that it can be retrieved before fully configuring SAML.
          sp_url: url,
          name_id_format: saml_name_id_format || "urn:oasis:names:tc:SAML:2.0:nameid-format:persistent",
        }
      end
    end

    # Default to true if config is not set and if LDAP is used for authentication
    def reactivate_suspended_user?
      return false if !GitHub.enterprise?
      return false if !GitHub.auth.external?

      unless GitHub.config.get("auth.reactivate-suspended").nil?
        return GitHub.config.enabled?("auth.reactivate-suspended")
      end

      GitHub.auth.ldap?
    end

    # Default to true if config is not set and if LDAP is used for authentication
    def reactivate_suspended_user_on_sync?
      return false if !GitHub.enterprise?
      return false if !GitHub.auth.external?

      unless GitHub.config.get("auth.reactivate-suspended-on-sync").nil?
        return GitHub.config.enabled?("auth.reactivate-suspended-on-sync")
      end

      # If the config is not set then make it consistent with the reactivate suspended user config.
      # This is to ensure that customers that have reactivate suspended user disabled don't see a change of behavior
      # when upgrading to a GHES version with the new config
      GitHub.reactivate_suspended_user?
    end

    # Setting to disable password authentication for LDAP for Git operations
    def external_auth_token_required
      return false if !GitHub.enterprise?
      return false if !GitHub.auth.external?
      # External auth mechs other than LDAP do not support password auth
      return true if !GitHub.auth.ldap?

      return @external_auth_token_required if defined?(@external_auth_token_required)
      false
    end
    attr_writer :external_auth_token_required
    alias :external_auth_token_required? :external_auth_token_required

    # Algorithm to use for the SAML signature.
    #
    # As per the spec, https://www.w3.org/TR/xmldsig-core1/#sec-AlgID, there are
    # several values to cater for with: rsa-sha1 (discouraged), rsa-sha256,
    # rsa-sha384 and rsa-sha512 being the most commonly implemented.
    #
    # Default to rsa-sha256 as this is the recommended replacement for rsa-sha1.
    def saml_signature_method
      @saml_signature_method ||= "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"
    end

    # Allow the setting of one of four options with rsa-sha256 being enforced if
    # an invalid value is given.
    def saml_signature_method=(value)
      @saml_signature_method =
        case value
        when "rsa-sha1"
          "http://www.w3.org/2000/09/xmldsig#rsa-sha1"
        when "rsa-sha384", "rsa-sha512"
          "http://www.w3.org/2001/04/xmldsig-more##{value}"
        else
          "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"
        end
    end

    # Algorithm to use for the SAML digest.
    #
    # As per the spec, https://www.w3.org/TR/xmldsig-core1/#sec-AlgID, there are
    # several values to cater for with: sha1 (discouraged), sha256, and sha512
    # being the most commonly implemented.
    #
    # Default to sha256 as this is the recommended replacement for sha1.
    def saml_digest_method
      @saml_digest_method ||= "http://www.w3.org/2001/04/xmlenc#sha256"
    end

    # Allow the setting of one of five options with sha256 being enforced if
    # an invalid value is given.
    def saml_digest_method=(value)
      @saml_digest_method =
        if value == "sha1"
          "http://www.w3.org/2000/09/xmldsig#sha1"
        elsif value == "sha512"
          "http://www.w3.org/2001/04/xmlenc#sha512"
        else
          "http://www.w3.org/2001/04/xmlenc#sha256"
        end
    end

    def saml_name_id_format=(value)
      @saml_name_id_format =
        if value == "unspecified"
          "urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified"
        else
          "urn:oasis:names:tc:SAML:2.0:nameid-format:persistent"
        end
    end

    def saml_default_session_expiration
      @saml_default_session_expiration ||= 1.week
    end

    def saml_encrypted_assertions?
      return @saml_encrypted_assertions if defined?(@saml_encrypted_assertions)
      false
    end

    # Algorithm to use for SAML encrypted assertions.
    #
    # Spec: https://www.w3.org/TR/2002/REC-xmlenc-core-20021210/Overview.html#sec-Alg-Block
    # Note, that we don't support Triple DES at the moment as AES should be more secure.
    def saml_encryption_method
      @saml_encryption_method ||= "aes-256-cbc"
    end

    def saml_encryption_method=(value)
      @saml_encryption_method = value if %w[aes-128-cbc aes-192-cbc aes-256-cbc].include? value
    end

    # Algorithm to use for the key that is used to encrypt SAML assertions.
    #
    # Spec: https://www.w3.org/TR/2002/REC-xmlenc-core-20021210/Overview.html#sec-Alg-KeyTransport
    # Note, that we don't support RSA Version 1.5 as RSA OAEP should be more secure.
    def saml_key_transport_method
      @saml_key_transport_method ||= "rsa-oaep"
    end

    def saml_key_transport_method=(value)
      @saml_key_transport_method = value if ["rsa-oaep"].include? value
    end

    def sso_credential_authorization_help_url
      @sso_credential_authorization_help_url ||= GitHub.environment["GITHUB_SSO_CREDENTIAL_AUTHORIZATION_HELP_URL"] ||
        "#{GitHub.help_url}/articles/authenticating-to-a-github-organization-with-saml-single-sign-on/"
    end

    def iam_with_saml_sso_help_url
      @iam_with_saml_sso_help_url ||= GitHub.environment["GITHUB_IAM_WITH_SAML_SSO_HELP_URL"] ||
        GitHub.help_url
    end

    def saml_legacy_pages_redirect_enabled?
      !!saml_legacy_pages_redirect_enabled
    end

    def ldap_base=(ldap_base)
      if !ldap_base.respond_to?(:each)
        # If the domain base list comes from an environment variable we need to split it up.
        ldap_base = String(ldap_base).split(";")
      end
      @ldap_base = ldap_base
    end
    attr_reader :ldap_base

    # Public: LDAP Admin group defines which users are administrators based on
    # group membership.
    def ldap_admin_group=(group)
      @ldap_auth_groups = nil
      @ldap_admin_group = group
    end
    attr_reader :ldap_admin_group

    # Public: LDAP user groups defines membership requirements for
    # authenticating users.
    def ldap_user_groups=(ldap_user_groups)
      if !ldap_user_groups.respond_to?(:each)
        # If the user groups list comes from an environment variable we need to split it up.
        ldap_user_groups = String(ldap_user_groups).split(";")
      end
      ldap_user_groups.compact!
      @ldap_auth_groups = nil
      @ldap_user_groups = ldap_user_groups
    end
    attr_reader :ldap_user_groups

    # Public: LDAP Groups users must belong to in order to successfully
    # authenticate.
    #
    # Returns an empty Array if authentication is not scoped to groups.
    # Returns an Array of group String names, including the admin group.
    def ldap_auth_groups
      return [] if ldap_user_groups.blank?
      @ldap_auth_groups ||= begin
        groups = ldap_user_groups + Array(ldap_admin_group)
        groups.uniq!
        groups.reject!(&:blank?)
        groups
      end
    end

    # Public: LDAP Search Strategy for Team Sync Member Search and
    # authentication restricted group Membership Validation.
    #
    # Defaults to `detect` to force detection of the optimal strategy.
    def ldap_search_strategy
      @ldap_search_strategy ||= "detect"
    end

    # Public: Defines the maximum depth of recursion the Recursive search
    # strategy can descend. Only used to the Recursive strategy.
    #
    # Pulls the value from the `ldap.search_strategy_depth` global config.
    #
    # Returns nil or the configured Integer depth.
    def ldap_search_strategy_depth
      if depth = GitHub.config.get("ldap.search_strategy_depth")
        depth.to_i
      end
    end

    # The LDAP User Sync job interval in Integer of hours.
    # Defaults to every 4 hours. See: LdapUserSyncJob.
    def ldap_user_sync_interval
      @ldap_user_sync_interval ||= 4
    end

    # Set the LDAP User Sync job interval.
    # Requires an interval greater than zero.
    def ldap_user_sync_interval=(interval)
      @ldap_user_sync_interval = interval.to_i if interval.to_i > 0
    end

    # The LDAP Team Sync job interval in Integer of hours.
    # Defaults to every 4 hours. See: LdapTeamSyncJob.
    def ldap_team_sync_interval
      @ldap_team_sync_interval ||= 4
    end

    # Set the LDAP Team Sync job interval.
    # Requires an interval greater than zero.
    def ldap_team_sync_interval=(interval)
      @ldap_team_sync_interval = interval.to_i if interval.to_i > 0
    end

    # The Audit Log requires a specific set of loggers
    # depending on the environment
    def audit_log_production_env?
      @audit_log_production_env ||= Rails.env.production?
    end
    attr_writer :audit_log_production_env

    def audit_log_test_env?
      @audit_log_test_env ||= Rails.env.test?
    end
    attr_writer :audit_log_test_env

    def audit_log_dev_env?
      @audit_log_dev_env ||= Rails.env.development?
    end
    attr_writer :audit_log_dev_env

    def audit_log_staging_env?
      @audit_log_staging_env ||= Rails.env.staging?
    end
    attr_writer :audit_log_staging_env

    # The maximum number of concurrent jobs per subject to export
    # web exports.
    def audit_web_export_max_concurrent_jobs_subject
      @audit_web_export_max_concurrent_jobs_subject ||= 10
    end

    # Set the maximum number of concurrent jobs per subject to export
    # web exports.
    def audit_web_export_max_concurrent_jobs_subject=(jobs)
      @audit_web_export_max_concurrent_jobs_subject = jobs.to_i if jobs.to_i > 0
    end

    # The maximum number of concurrent jobs per subject to export
    # git events.
    def audit_git_export_max_concurrent_jobs_subject
      @audit_git_export_max_concurrent_jobs_subject ||= 10
    end

    # Set the maximum number of concurrent jobs per subject to export
    # git events.
    def audit_git_export_max_concurrent_jobs_subject=(jobs)
      @audit_git_export_max_concurrent_jobs_subject = jobs.to_i if jobs.to_i > 0
    end

    # The timeout for audit log jobs that perform web exports
    def audit_web_export_timeout
      @audit_web_export_timeout_minutes ||= 60.minutes
    end

    # Set the timeout for audit log jobs that perform web exports
    def audit_web_export_timeout=(timeout)
      @audit_web_export_timeout_minutes = timeout.to_i if timeout.to_i > 0
    end

    # The timeout for audit log jobs that export git events
    def audit_git_export_timeout
      @audit_git_export_timeout_minutes ||= 60.minutes
    end

    # Set the timeout for audit log jobs that export git events
    def audit_git_export_timeout=(timeout)
      @audit_git_export_timeout_minutes = timeout.to_i if timeout.to_i > 0
    end

    # Whether the LDAP server supports virtual attributes like memberOf.
    def ldap_virtual_attributes
      return @ldap_virtual_attributes if defined?(@ldap_virtual_attributes)
      @ldap_virtual_attributes = false
    end

    # Whether the LDAP group membership check should fallback to the slow non
    # virtual attribute implementation when virtual attributes are disabled.
    # This is false by default to prevent bad performance.
    def ldap_recursive_group_search_fallback
      return @ldap_recursive_group_search_fallback if defined?(@ldap_recursive_group_search_fallback)
      @ldap_recursive_group_search_fallback = false
    end

    # Whether the LDAP group membership check should include posixGroup
    # conditions.
    # This is true by default.
    def ldap_posix_support
      return @ldap_posix_support if defined?(@ldap_posix_support)
      @ldap_posix_support = true
    end

    # The amount of time we allow for LDAP authentication requests before timing out
    def ldap_auth_timeout
      @ldap_auth_timeout ||= 10
    end

    # Set the amount of time we allow for LDAP authentication requests before timing out
    def ldap_auth_timeout=(value)
      @ldap_auth_timeout = value if value > 0 && value <= GitHub.default_request_timeout
    end

    def auth_mode
      @auth_mode ||= :default
    end

    def auth_mode=(mode)
      @auth_adaptor = nil
      @auth_mode = mode
    end

    # default password for user
    attr_accessor :default_password

    # Historically, the minimum password length is 7. This is still the default
    # in every environment besides dotcom production where 8 characters are
    # required.
    def password_minimum_length
      @password_minimum_length ||= 7
    end
    attr_writer :password_minimum_length

    def password_maximum_length
      @password_maximum_length ||= 72
    end
    attr_writer :password_maximum_length

    def employee_password_minimum_length
      @employee_password_minimum_length ||= password_minimum_length
    end
    attr_writer :employee_password_minimum_length

    def employee_password_minimum_entropy
      @employee_password_minimum_entropy ||= 0
    end
    attr_writer :employee_password_minimum_entropy

    def password_lowercase_requirement
      @password_lowercase_requirement ||= 1
    end
    attr_writer :password_lowercase_requirement

    def password_uppercase_requirement
      @password_uppercase_requirement ||= 0
    end
    attr_writer :password_uppercase_requirement

    def password_digit_requirement
      @password_digit_requirement ||= 1
    end
    attr_writer :password_digit_requirement

    def password_special_character_requirement
      @password_special_character_requirement ||= 0
    end
    attr_writer :password_special_character_requirement


    # Instantiate the Authentication object for handling auth configuration and inquiries.
    #
    # Returns an Authentication.
    def auth_modes
      @auth_modes ||= {
        default: GitHub::Authentication::Default,
        ldap: GitHub::Authentication::LDAP,
        cas: GitHub::Authentication::CAS,
        github_oauth: GitHub::Authentication::GitHubOauth,
        saml: GitHub::Authentication::SAML,
      }
    end

    # The instantiated Authentication adapter.
    def auth
      @auth_adaptor ||= auth_modes[auth_mode.to_sym].new(auth_options)
    end

    # Is the site admin role managed by an external authentication system
    # (currently either LDAP or SAML)?
    #
    # If managed externally, we generally don't allow manual promoting/demoting
    # site admins.
    #
    # Returns a Boolean.
    def site_admin_role_managed_externally?
      (GitHub.auth.ldap? && GitHub.ldap_admin_group.present?) ||
        (GitHub.auth.saml? && !GitHub.saml_disable_admin_demote)
    end

    # Determines whether this is the very first time an Enterprise installation
    # is being accessed. This is primarily used to determine whether or not the
    # user being created should be auto-promoted to site admin status (the first
    # user on installations are auto-promoted). You can pass in the env variable
    # ENTERPRISE_FIRST_RUN to emulate this in development (hence the attr_writer).
    #
    # Returns true if no users have been created yet on the installation.
    def enterprise_first_run?
      # This nil check instead of `defined?` allows the attr_writer to reset
      # this memoized value in tests by setting first_run to nil.
      if @first_run.nil?
        license = GitHub.enterprise? ? GitHub::Enterprise.license(sync_global_business: false) : nil
        if license && license.seats_used == 0
          # Don't memoize a true value, this needs to be checked until
          # seats_used is greater than zero.
          true
        else
          # Now that there is at least one seat used, no more checks are
          # required. Memoize the result.
          @first_run = false
        end
      else
        @first_run
      end
    end
    attr_writer :first_run

    # The first run check ensures that the customer creates a user as the first
    # step when accessing the installation.
    #
    # - For external authentication, this step isn't required.
    #
    # To avoid an infinite redirect loop, we skip the check under those
    # circumstances.
    def first_run_exempt_from_signup?
      GitHub.auth.external?
    end


    # Available log levels.
    RAILS_LOG_LEVELS = [:debug, :info, :warn, :error, :fatal]

    # The log level used by the application. Possible log levels are :debug, :info,
    # :warn, :error, and :fatal. This value is set by github/config/environments/<env>.rb
    # scripts but can be adjusted under enterprise by the ENTERPRISE_RAILS_LOG_LEVEL
    # environment variable or by modifying the RAILS_ROOT/config.yml file.
    #
    # Returns the configured log level as a symbol. If no log level is set
    # explicitly, :info is returned.
    def rails_log_level
      @rails_log_level ||= :info
    end

    # Set the rails_log_level, verifying the value given.
    #
    # value - One of the LOG_LEVEL symbol values or a number between 0 and 4.
    #
    # Raises a TypeError when the value is not a supported log level.
    def rails_log_level=(value)
      value = value.to_i if value.is_a?(String) && value =~ /[0-4]/
      value = value.to_sym if value.is_a?(String)
      value = RAILS_LOG_LEVELS[value] if value.is_a?(Integer)

      if RAILS_LOG_LEVELS.include?(value)
        @rails_log_level = value
      else
        raise TypeError, "Illegal value: #{value.inspect}"
      end
    end

    def rails_log_stderr=(bool)
      @rails_log_stderr = bool
    end

    def rails_log_stderr?
      @rails_log_stderr == true
    end

    # Unicorn master/worker attributes
    attr_accessor :unicorn_master_start_time
    attr_accessor :unicorn_worker_start_time
    attr_accessor :unicorn_master_pid
    attr_accessor :unicorn_worker_request_count
    attr_accessor :unicorn_worker_number
    attr_accessor :unicorn_worker_pid

    # Determine whether Private Mode is enabled for GitHub (FI). Private Mode
    # locks down the site- users must be logged in to view and use GitHub, and
    # new user signups are restricted to admins only. This also disables
    # various other functionality for the sake of a private GitHub (such as
    # serving repositories over git://). It also causes all atom feeds to include
    # login/token parameters, just like private feeds (see github/enterprise#244).
    #
    # Returns a Boolean.
    def private_mode
      return @private_mode if defined?(@private_mode)
      @private_mode = GitHub.enterprise? && !(ENV["PRIVATE_MODE"]).to_s.empty?
    end
    attr_writer :private_mode

    # Is Private Mode enabled?
    def private_mode_enabled?
      private_mode
    end

    # A GHES-specific setting that enables an alternative search path for installations that want
    # to include a greater number of repositories in search results by default. This could have performance
    # implications and is only recommended if an installation feels the default repository search
    # is either too restrictive or frequently misses expected results.
    def enterprise_repo_search_filter_enabled?
      return @enterprise_repo_search_filter_enabled if defined?(@enterprise_repo_search_filter_enabled)
      @enterprise_repo_search_filter_enabled = GitHub.single_tenant_enterprise? && %w[1 true].include?(
        GitHub.environment.fetch("ENTERPRISE_REPO_SEARCH_FILTER_ENABLED", nil).to_s
      )
    end

    def elastomer_index_lock_backoff_attempts
      env_setting = ENV["ENTERPRISE_ELASTOMER_INDEX_LOCK_BACKOFF_ATTEMPTS"]&.to_i
      @elastomer_index_lock_backoff_attempts = env_setting || ENTERPRISE_ELASTOMER_INDEX_LOCK_BACKOFF_ATTEMPTS
    end
    attr_writer :elastomer_index_lock_backoff_attempts

    # Whether or not we want to use the channel event builder for PRs live updates
    # This is specifically for GHES, and populated by the env var ENTERPRISE_USE_CHANNEL_EVENT_BUILDER
    # GHES admins disable the channel event builder by running this:
    # ghe-config app.github.pull-requests-channel-event-builder-enabled false && ghe-config-apply
    def use_channel_event_builder?
      return @use_channel_event_builder if defined?(@use_channel_event_builder)
      true
    end
    attr_writer :use_channel_event_builder

    # Determines whether or not we want to guard actions performed through
    # stafftools under an dedicated staff user.
    #
    # Returns a Boolean.
    def guard_audit_log_staff_actor?
      return @guard_audit_log_staff_actor if defined?(@guard_audit_log_staff_actor)
      @guard_audit_log_staff_actor = !GitHub.enterprise?
    end
    attr_writer :guard_audit_log_staff_actor

    def guarded_audit_log_staff_actor_entry(actor)
      if actor.is_a?(User)
        actor_id = actor.id
        actor = actor.display_login
      end

      entry = {}
      if guard_audit_log_staff_actor?
        entry[:staff_actor]    = actor    if actor
        entry[:staff_actor_id] = actor_id if actor_id
        entry[:actor]          = User.staff_user.display_login
        entry[:actor_id]       = User.staff_user.id
      else
        entry[:actor]    = actor    if actor
        entry[:actor_id] = actor_id if actor_id
      end
      entry
    end

    # Guard audit log entries for support operations performed through the console
    def guard_console_staff_actor!
      supportocat = if Rails.env.development?
        User.find_by_login(ENV["USER"])
      elsif GitHub.enterprise?
        User.find_by_login("ghost")
      else
        User.find_by_login(ENV["SUDO_USER"]) #production shell server
      end
      @guard_console_staff_actor = { actor: supportocat.display_login, actor_id: supportocat.id }
      IRB.CurrentContext.irb_name = "#{User.staff_user.login}%#{supportocat.login}"
    end

    def guard_console_staff_actor
      @guard_console_staff_actor || { actor: nil, actor_id: nil }
    end
    attr_writer :guard_console_staff_actor

    def guard_console_staff_actor?
      guard_console_staff_actor[:actor]
    end

    # Determine whether subdomain isolation is enabled for GitHub (FI).
    # Subdomain isolation places various components of GitHub (raw, uploads,
    # pages, etc) on their own subdomain. This prevents user controlled content
    # from executing in the same origin as the rest of GitHub. As a result,
    # attacks such as XSS on these subdomains are much less critical as they
    # will be unable to access content on the main GitHub site and will not be
    # able to perform security sensitive operations (accessing repos, etc).
    #
    # Returns a Boolean.
    def subdomain_isolation
      return @subdomain_isolation if defined?(@subdomain_isolation)
      @subdomain_isolation = true
    end
    attr_writer :subdomain_isolation
    alias :subdomain_isolation? :subdomain_isolation

    # Using Private Mode and Subdomains for maximum privacy and security.
    #
    # Causes private mode authentication cookies to be set on *.githubhostname.
    #
    # Enabled when both using Enterprise isolated subdomains and Private Mode.
    def subdomain_private_mode_enabled?
      private_mode_enabled? && subdomain_isolation?
    end

    # Public: Do we set `crossorigin=with-credentials` for asset bundles in
    # this environment?
    #
    # Returns a Boolean.
    def asset_crossorigin_with_credentials?
      enterprise?
    end

    # Determine whether to create repositories in DGit by default
    #
    # Returns true if it's enabled, false otherwise
    def dgit_intake_enabled?
      if defined?(@dgit_intake_enabled)
        return @dgit_intake_enabled
      end
      @dgit_intake_enabled = true
    end
    attr_writer :dgit_intake_enabled

    # ID of the GitHub Enterprise Site Administrator Oauth App ID, which is
    # the owner of Api::Admin::UsersManager tokens used for user impersonation.
    #
    # Returns int ID, or nil if the app doesn't exist and can't be created
    def enterprise_admin_oauth_app_id
      return nil unless GitHub.enterprise?
      @enterprise_admin_oauth_app_id ||=
        if app = OauthApplication.where({
          user_id: GitHub.trusted_apps_owner_id,
          name: "GitHub Site Administrator",
          }).first
          app.id
        elsif app = OauthApplication.register_trusted_application(
          "GitHub Site Administrator",
          SecureRandom.hex(10),
          SecureRandom.hex(20),
          "https://developer.github.com/v3/enterprise/users/",
          "https://developer.github.com/v3/enterprise/users/",
          )
          app.id
        else
          nil
        end
    end

    ##
    # Custom Hooks (Enterprise)

    # Location where custom git hooks data lives.
    def custom_hooks_dir
      @custom_hooks_dir ||= if Rails.env.production?
        "/data/user/git-hooks"
      elsif Rails.env.test?
        ENV["TEST_HOOK_DIR"] || "#{Rails.root}/git-hooks"
      else
        "#{Rails.root}/git-hooks"
      end
    end
    attr_writer :custom_hooks_dir

    # Are custom pre-receive hooks enabled in this environment?
    #
    # Only enabled on GHES.
    #
    # Returns Boolean.
    def pre_receive_hooks_enabled?
      GitHub.enterprise?
    end

    # The password cost factor for Bcrypt
    def bcrypt_password_cost
      @bcrypt_password_cost ||= BCrypt::Engine::DEFAULT_COST
    end
    attr_writer :bcrypt_password_cost

    def pbkdf2_iterations
      @pbkdf2_iterations ||= 200_000
    end
    attr_writer :pbkdf2_iterations

    def argon2_time_cost
      @argon2_time_cost ||= 3
    end
    attr_writer :argon2_time_cost

    def argon2_memory_cost
      @argon2_memory_cost ||= 14
    end
    attr_writer :argon2_memory_cost

    # The secret(s) used as additional input for password hashing.
    # First secret is always used for updated passwords, the second
    # one is also allowed to be used. Multiple entries can be used
    # to roll these as people log in over time.

    # user_password_secrets is a secondary salt used for user password authentication. For users with passwords, we
    # store a hash and salt of the password in the database. To further improve the security of the password storage,
    # an additional salt is needed. This is USER_PASSWORD_SECRETS. The intention behind having two salts is that they
    # are logically separated. One salt is in the database, another salt is in the application server. Without both
    # salts, it is infeasible to even brute-force guessing the password hashes. An actor would need both access to the
    # database as well as the application server secret to begin to mount a brute-force attack. Even with both salts
    # from the server and database, the password hashing scheme that is used makes this extremely difficult.

    # This secret was exposed as part of incident 6209 and granted an exception from being rotated as part of the
    # incident response. This secret was classified as low risk because this second salt is an additional layer of
    # security, and considered optional. Because this salt is an input into how passwords are stored, we cannot change
    # the salt immediately. Since passwords are hashed, the earliest opportunity we have to update the user’s stored
    # password with a new salt is when they give us their password during login, password reset, or changing their
    # password. The first step to remediating this secret was to put a new salt in place that was used going forward.
    # As users log in or change their password, their stored hash was updated to using this new salt. However, the old
    # salt must remain available for users that have not logged in since the salt was updated. We chose to not force
    # users to input their passwords to force the update to the new salt. The salt is a defense-in-depth mechanism.
    # Accounts that log in and get the new salt will benefit from the new salt, and the old salt does them no harm.
    # More details on the exemption approval: https://github.com/github/security-exceptions/pull/1582
    def user_password_secrets
      @user_password_secrets ||=
        ENV["USER_PASSWORD_SECRETS"].to_s.split
    end
    attr_writer :user_password_secrets

    # two_factor_salt was a salt used for TOTP (App-based 2FA) code generation. Each user that uses TOTP has a secret
    # stored in the database. This secret is also used to derive recovery codes for users. As an additional layer of
    # security, the TOTP secret is mixed with an application server salt. This splits knowledge of the TOTP secret
    # between the database and the application server. Having a database dump of the user’s TOTP secret would not be
    # enough without also obtaining the application server salt.

    # This salt is not something prescribed or documented as part of the TOTP specification, it is a defense-in-depth
    # mechanism. TOTP relies on a shared secret between the user’s TOTP app and GitHub. Changing the salt would mean
    # GitHub and the user’s app would no longer have a common shared secret, and the user would not be able to use
    # their 2FA setup. It would also mean users would need to re-generate their recovery codes.

    # This secret was exposed as part of incident 6209 and granted an exception from being rotated as part of the
    # incident response. It was determined that rotation was not required because column encryption provides a similar
    # mechanism of protecting the values in the database by requiring knowledge of the application server secret, so \
    # the value gained from it is small. Column encryption however has a better story around rotation, and can be done
    # transparently with no user interaction.
    # More details on the exemption approval: https://github.com/github/security-exceptions/pull/1581
    #
    # Salting 2FA secrets is only supported in dotcom - these value is nil in proxima and GHES
    #
    # We've decided to support TOTP salt rotation: https://github.com/github/authentication/issues/3990
    # This salt is an input for generating the real, 32 byte string that we send to the user as a shared secret (mashed_secret).
    # We can only use the new salt when users reconfigure 2FA, or when new 2FA users enroll and will have to continue
    # to support the old salt unless we want to invalidate all existing 2FA configurations.
    #
    # We're starting this work by splitting the original two_factor_salt secret into three: for recovery_codes, sms and app otp separately
    #
    # recovery_code_salts is a json map of actively used salts for recovery codes
    # recovery_code_salt_version is the preferred salt version for new configurations
    attr_accessor :recovery_code_salts
    attr_accessor :recovery_code_salt_version
    attr_accessor :app_otp_salts
    attr_accessor :app_otp_salt_version
    # sms_otp_salts is an array since the sms scenario doesn't require tracking the salt version
    attr_accessor :sms_otp_salts

    # The key we use to encrypt SAML provider recovery keys in the database
    attr_accessor :saml_provider_salt

    # The app id to use for FIDO U2F. This points to
    # u2f_registrations#trusted_facets which tells U2F devices to trust a set of
    # domains to share registrations.
    #
    # Some environments (i.e. Codespaces) don't have a `u2f_app_id`, so we
    # return `nil` to indicate that it shouldn't be used.
    #
    # Returns a String URL or nil
    def u2f_app_id
      return nil if ENV["CODESPACES"]
      "#{url}/u2f/trusted_facets"
    end

    # Calculates whether a security key operation is allowed on the given
    # origin. Allowed domains are:
    #
    # - The U2F "trusted facets" domains. For github.com, these are (per
    #   https://github.com/u2f/trusted_facets):
    #   - https://github.com
    #   - https://garage.github.com
    #   - https://admin.github.com
    # - Dynamic lab domains
    #
    # Returns a Boolean.
    def webauthn_allowed_origin?(origin)
      # Ideally we would get the host name of the deployment and pass this to
      # the webauthn library instead of checking the origin ourselves.
      # `GitHub.host_name` is supposed to tell us that host name, but it
      # actually... doesn't (https://github.com/github/github/issues/113982). We
      # could try compute the expected host name from scratch and check `domain`
      # strictly against it, but the methods available to us are broken/brittle.
      # So we settle for an allowlist check.
      uri = Addressable::URI.parse(origin)
      return false unless uri.scheme == scheme
      return true if u2f_trusted_facets.include?(origin)
      # Don't perform lab domain checks for Codespaces
      return true if ENV["CODESPACES"]
      # Don't perform lab domain checks for enterprise.
      !enterprise? && !!dynamic_lab_domain?(uri.hostname)
    end

    # The RP ID (relying party ID) to use for webauthn:
    # https://www.w3.org/TR/webauthn/#rp-id This is usually the main domain
    # where GitHub is hosted. However, subdomains of `github.com` also have an
    # RP ID of `github.com` so that security keys can be shared across admin/lab
    # domains.
    #
    # For Codespaces, we use `nil` to indicate that the RP ID should not be
    # specified, which means WebAuthn will default to the "effective domain":
    # https://w3c.github.io/webauthn/#CreateCred-DetermineRpId
    # This is not an issue unless we need WebAuthn to work across multiple (sub)domains.
    #
    # For proxima we need to use the full domain + tenant context. Ex: staffship-01.ghe.com instead of ghe.com, so
    # that the webauthn clients don't suggest or support passkeys across tenants, even if they won't work.
    #
    # Returns a String URL or nil
    def webauthn_rp_id
      return nil if ENV["CODESPACES"]
      return host_name if GitHub.enterprise?
      return host_name_with_tenant if GitHub.multi_tenant_enterprise?

      host_domain
    end

    # The list of domains that are trusted to share U2F devices. In production
    # this includes staging/admin domains. On enterprise and development this
    # is just the app's URL itself.
    #
    # Returns an Array of String URLs.
    def u2f_trusted_facets
      @u2f_trusted_facets ||= [url].freeze
    end
    attr_writer :u2f_trusted_facets

    ##
    # Failbot / Exceptions reporting.

    # Failbot customization. Under most environments, the default config
    # that's provided out of the box by the Failbot library is sensible but in
    # some cases (FI), it is useful to override it.
    #
    # Default to writing JSON-encoded exceptions to log/exceptions.log under FI
    # environments. Other environments use whatever the default Failbot config
    # of the current RAILS_ENV is.
    #
    # Returns the Failbot custom config Hash to be passed to Failbot.setup.
    def failbot
      default_settings = { "FAILBOT_EXCEPTION_FORMAT" => failbot_exception_format }
      @failbot ||=
        if GitHub::AppEnvironment.test?
          default_settings.merge!({
            "FAILBOT_BACKEND" => "memory",
          })
        elsif GitHub::AppEnvironment.development? || enterprise?
          default_settings.merge!({
            "FAILBOT_BACKEND" => "file",
            "FAILBOT_BACKEND_FILE_PATH" => failbot_log_path,
          })
        else
          default_settings.merge!({
            "FAILBOT_BACKEND" => "memory",
          })
        end
    end
    attr_writer :failbot

    def failbot_exception_format
      GitHub.enterprise? ? :haystack : :structured
    end

    # Failbot log file location, if applicable.
    def failbot_log_path
      "#{GitHub::AppEnvironment.root}/log/exceptions.log"
    end

    attr_reader :hostname
    def hostname
      @hostname ||= ENV.fetch("KUBE_NODE_HOSTNAME", Socket.gethostname)
    end

    ##
    # Miscellaneous feature flags typically disabled under FI environments.

    # Determine whether the blog is enabled. This is disabled under FI
    # environments but enabled everywhere else.
    #
    # Returns true if it is enabled, false otherwise.
    def blog_enabled?
      return @blog_enabled if defined?(@blog_enabled)
      @blog_enabled = !enterprise?
    end
    attr_writer :blog_enabled

    # GitHub blog URL, if applicable.
    def blog_url
      "https://github.blog".freeze
    end

    # Determine whether to show things related to licensing in GitHub. This is
    # primarily the license picker and auto-license population during repository
    # creation.
    #
    # Returns true if the license picker should be displayed, false otherwise.
    def license_picker_enabled?
      return @license_picker_enabled if defined?(@license_picker_enabled)

      @license_picker_enabled = !enterprise?
    end
    attr_writer :license_picker_enabled

    # Whether community profiles are enabled.
    #
    # Returns true if community profiles are enabled, otherwise false.
    def community_profile_enabled?
      @community_profile_enabled ||= !enterprise?
    end
    attr_writer :community_profile_enabled

    # Whether namespaces should be retired upon user account deletion.
    #
    # Returns true if retired namespaces on deletion is enabled, otherwise false.
    def retired_namespaces_on_deletion_enabled?
      @retired_namespaces_on_deletion_enabled ||= !enterprise?
    end
    attr_writer :retired_namespaces_on_deletion_enabled

    # Custom tabs allow repository admins to configure custom repository tabs
    # displayed in the repository navigation, that point to an arbitraty URL.
    # This is enabled under Enterprise environments but disabled everywhere else.
    #
    # Returns true if enabled, false otherwise.
    def custom_tabs_enabled?
      return @custom_tabs_enabled if defined?(@custom_tabs_enabled)
      @custom_tabs_enabled = enterprise?
    end
    attr_writer :custom_tabs_enabled

    # Allow users to enter a short professional bio and mark themselves as being
    # hireable. This is disabled by default under FI environments and enabled
    # everywhere else, altough we're not taking advantage of this data yet.
    #
    # Returns true if enabled, false otherwise.
    def job_profiles_enabled?
      return @job_profiles_enabled if defined?(@job_profiles_enabled)
      @job_profiles_enabled = !enterprise?
    end
    attr_writer :job_profiles_enabled

    # Determine whether restrictions around spammy users are enforced
    # throughout the site. Disabled by default under Enterprise environments, enabled
    # everywhere else.
    #
    # Returns true if enabled, false otherwise.
    def spamminess_check_enabled?
      !single_or_multi_tenant_enterprise?
    end

    # Is there a single global business for this environment rather than
    # multiple businesses?
    #
    # Returns boolean.
    def single_business_environment?
      enterprise?
    end

    # Determine whether the site admin has the ability to see private repositories
    #
    # Returns boolean.
    def site_admin_can_see_private_repo?
      enterprise?
    end

    # The default base slug for an enterprise account.
    def default_business_base_slug
      if single_business_environment?
        "global-enterprise".freeze
      else
        "enterprise".freeze
      end
    end

    # Setting to restrict contractors from default access to internal
    # repositories that is normally given with membership to the Business
    # in a single Business environment.
    #
    # This setting is used to restrict contractor access to internally visible
    # repositories. Contractors must be granted explicit access to internally
    # visible repositories (no implicit read given).
    #
    # Contractors are identified by the `EnterpriseAttestation.contractor?`
    # check. An API is provided to manage contractor attestations.
    #
    # Defaults to `false`.
    def restrict_contractors_from_default_access_to_internal_repos?
      return false unless single_business_environment?
      return @restrict_contractors_from_default_access_to_internal_repos if defined?(@restrict_contractors_from_default_access_to_internal_repos)
      @restrict_contractors_from_default_access_to_internal_repos = false
    end
    attr_writer :restrict_contractors_from_default_access_to_internal_repos

    # The global Business object if this is a single business environment
    # otherwise nil.
    def global_business
      return unless single_business_environment?

      Business.take
    end

    # How long do we memoize spam patterns during Spam checking?
    #
    # We default to 0 if no value is set in the environment.
    #
    # Returns an integer.
    def spam_pattern_memoization_ttl_in_seconds
      return @spam_pattern_memoization_ttl_in_seconds if defined?(@spam_pattern_memoization_ttl_in_seconds)
      @spam_pattern_memoization_ttl_in_seconds = (ENV["SPAM_PATTERNS_MEMOIZED_TTL_IN_SECONDS"] || 0).to_i
    end
    attr_writer :spam_pattern_memoization_ttl_in_seconds

    # Should we report user-creation data to Octolytics?
    #
    # Returns false in enterprise.
    def user_creation_analytics_enabled?
      octolytics_enabled? && !enterprise?
    end

    # Determine whether suspended users are hidden from other users. Enabled
    # by default under all environments.
    #
    # Returns true if enabled, false otherwise.
    def suspended_users_visible?
      return @suspended_users_visible if defined?(@suspended_users_visible)
      @suspended_users_visible = true
    end
    attr_writer :suspended_users_visible

    # Determine whether to show the enterprise suspend form.
    def show_enterprise_suspend_form?
      enterprise?
    end

    # Determine whether to show the suspended/spammy alerts at the top of the
    # profile page. Enabled by default for enterprise only
    #
    # Returns true if enabled, false otherwise
    def show_user_profile_alerts?
      return @show_user_profile_alerts if defined?(@show_user_profile_alerts)
      @show_user_profile_alerts = enterprise?
    end
    attr_writer :show_user_profile_alerts

    # Determine whether /admin is enabled. Redirects to Staff Tools when
    # disabled. Disable by default under Enterprise environments, enabled everywhere
    # else.
    #
    # Returns true if enabled, false otherwise.
    def admin_enabled?
      return @admin_enabled if defined?(@admin_enabled)
      @admin_enabled = !enterprise?
    end
    attr_writer :admin_enabled

    # Determine whether /setup is enabled. Enabled by default in Enterprise,
    # disabled for dotcom.
    #
    # Returns true if enabled, false otherwise.
    def management_console_enabled?
      return @management_console_enabled if defined?(@management_console_enabled)
      @management_console_enabled = enterprise?
    end
    attr_writer :management_console_enabled

    # Determine whether the instance wide audit log is enabled. Currently dotcom
    # only.
    #
    # Returns true if enabled, false otherwise.
    def instance_audit_log_enabled?
      return @instance_audit_log_enabled if defined?(@instance_audit_log_enabled)
      @instance_audit_log_enabled = enterprise?
    end
    attr_writer :instance_audit_log_enabled

    # Determine whether reports are enabled. Current only used
    # in Enterprise.
    #
    # Returns true if enabled, false otherwise.
    def reports_enabled?
      return @reports_enabled if defined?(@reports_enabled)
      @reports_enabled = GitHub.enterprise?
    end
    attr_writer :reports_enabled

    # Determine whether large blobs should be rejected or not.
    # We currently don't reject large blobs in Enterprise.
    #
    # Returns true if enabled, false otherwise.
    def large_blob_rejection_enabled?
      return @large_blob_rejection_enabled if defined?(@large_blob_rejection_enabled)
      @large_blob_rejection_enabled = true
    end
    attr_writer :large_blob_rejection_enabled

    # Is the rejection of 40 character hex names for refs enabled?
    def reject_sha_like_refs?
      return @reject_sha_like_refs if defined?(@reject_sha_like_refs)
      @reject_sha_like_refs = true
    end
    attr_writer :reject_sha_like_refs

    # The maximum length of reference names.
    #
    # This is defined as the minimum size for the `pushes.refs` database
    # column.  Refs longer than this will be truncated and cause query
    # warnings.
    def maximum_ref_length
      @maximum_ref_length ||= 255
    end
    attr_writer :maximum_ref_length

    # The maximal number of Git LFS objects that are checked in *one* push.
    # Pushes exceeding that number will only be spot checked.
    def lfs_integrity_max_oids
      @lfs_integrity_max_oids ||= 10000
    end
    attr_writer :lfs_integrity_max_oids

    # Determine whether organization OAuth application policies are available.
    # (This feature is currently available only in dotcom environments.)
    #
    # Returns true if enabled, false otherwise.
    def oauth_application_policies_enabled?
      !enterprise?
    end

    # Determines if orgs can automatically receive a set of
    # beta features (such as Actions/GPR/etc...)
    #
    # Returns true if enabled, false otherwise.
    def organization_beta_enrollment_enabled?
      !enterprise?
    end

    # Determines if advanced security and secret scanning can be enabled for enterprise
    # managed users.
    #
    # Enabled by default, unless explicitly disabled via ghe config apply.
    def ghas_for_enterprise_users_enabled?
      return @ghas_for_enterprise_users_enabled if defined?(@ghas_for_enterprise_users_enabled)
      @ghas_for_enterprise_users_enabled = true
    end
    attr_writer :ghas_for_enterprise_users_enabled

    # Determines if security center is available to ingest security product features
    #
    # Enabled by default, unless explicitly disabled via ghe config apply.
    def security_center_for_emus_enabled?
      return @security_center_for_emus_enabled if defined?(@security_center_for_emus_enabled)
      @security_center_for_emus_enabled = true
    end
    attr_writer :security_center_for_emus_enabled

    # Determines if secret scanning should display secrets detected in all content types - including issues, pull requests and discussions.
    #
    # Enabled by default, unless explicitly disabled via ghe config apply.
    def secret_scanning_for_all_content_types_enabled?
      return @secret_scanning_for_all_content_types_enabled if defined?(@secret_scanning_for_all_content_types_enabled)
      @secret_scanning_for_all_content_types_enabled = true
    end
    attr_writer :secret_scanning_for_all_content_types_enabled

    # Determine the no of scans that can be run per repo at the same time.
    # Enabled by default (with a value of 1), can be changed via ghe config apply.
    #
    # Returns true if enabled, false otherwise.
    def secret_scanning_max_scans_per_repo
      return @secret_scanning_max_scans_per_repo if defined?(@secret_scanning_max_scans_per_repo)
      @secret_scanning_max_scans_per_repo = 1
    end
    attr_writer :secret_scanning_max_scans_per_repo

    # Determine the no of custom pattern that can defined at the repo level
    # Enabled by default (with a value of 100), can be changed via ghe config apply.
    #
    # Returns true if enabled, false otherwise.
    def secret_scanning_max_custom_patterns_per_repo
      return @secret_scanning_max_custom_patterns_per_repo if defined?(@secret_scanning_max_custom_patterns_per_repo)
      @secret_scanning_max_custom_patterns_per_repo = 100
    end
    attr_writer :secret_scanning_max_custom_patterns_per_repo

    # Determine the no of custom pattern that can defined at the org level
    # Enabled by default (with a value of 500), can be changed via ghe config apply.
    #
    # Returns true if enabled, false otherwise.
    def secret_scanning_max_custom_patterns_per_org
      return @secret_scanning_max_custom_patterns_per_org if defined?(@secret_scanning_max_custom_patterns_per_org)
      @secret_scanning_max_custom_patterns_per_org = 500
    end
    attr_writer :secret_scanning_max_custom_patterns_per_org

    # Determine the no of custom pattern that can defined at the enterprise level
    # Enabled by default (with a value of 500), can be changed via ghe config apply.
    #
    # Returns true if enabled, false otherwise.
    def secret_scanning_max_custom_patterns_per_business
      return @secret_scanning_max_custom_patterns_per_business if defined?(@secret_scanning_max_custom_patterns_per_business)
      @secret_scanning_max_custom_patterns_per_business = 500
    end
    attr_writer :secret_scanning_max_custom_patterns_per_business

    # Determine the no of additional post processing expressions that can be defined for a custom pattern.
    # Enabled by default (with a value of 10), can be changed via ghe config apply.
    #
    # Returns true if enabled, false otherwise.
    def secret_scanning_max_post_processing_expressions_per_pattern
      return @secret_scanning_max_post_processing_expressions_per_pattern if defined?(@secret_scanning_max_post_processing_expressions_per_pattern)
      @secret_scanning_max_post_processing_expressions_per_pattern = 10
    end
    attr_writer :secret_scanning_max_post_processing_expressions_per_pattern


    # Determine the no of backfill scans that can be run at the same time.
    # Enabled by default (with a value of 20), can be changed via ghe config apply.
    #
    # Returns true if enabled, false otherwise.
    def secret_scanning_max_backfill_scans
      return @secret_scanning_max_backfill_scans if defined?(@secret_scanning_max_backfill_scans)
      @secret_scanning_max_backfill_scans = enterprise? ? 10 : 20
    end
    attr_writer :secret_scanning_max_backfill_scans

    # Determine the no. of incremental scans that can be run at the same time.
    # Enabled by default (with a value of 100), can be changed via ghe config apply.
    def secret_scanning_max_incremental_scans
      return @secret_scanning_max_incremental_scans if defined?(@secret_scanning_max_incremental_scans)
      @secret_scanning_max_incremental_scans = 100 if enterprise?
    end
    attr_writer :secret_scanning_max_incremental_scans

    # Determine the no of candidate matches that can be returned for a scan.
    # Enabled by default (with a value of 16000), can be changed via ghe config apply.
    #
    # Returns true if enabled, false otherwise.
    def secret_scanning_max_candidate_matches
      return @secret_scanning_max_candidate_matches if defined?(@secret_scanning_max_candidate_matches)
      @secret_scanning_max_candidate_matches = enterprise? ? 64000 : 16000
    end
    attr_writer :secret_scanning_max_candidate_matches

    # Determine the no of results to report for a dry run scan on a custom pattern
    #
    # Returns 1000 unless explicitly specified via ghe config apply.
    def secret_scanning_max_dry_run_results
      return @secret_scanning_max_dry_run_results if defined?(@secret_scanning_max_dry_run_results)
      @secret_scanning_max_dry_run_results = 1000
    end
    attr_writer :secret_scanning_max_dry_run_results

    # Determine the maximum number of selected repositories for an org or business level dry run
    #
    # Returns 10 unless explicitly specified via ghe config apply.
    def secret_scanning_max_dry_run_selected_repositories
      return @secret_scanning_max_dry_run_selected_repositories if defined?(@secret_scanning_max_dry_run_selected_repositories)
      @secret_scanning_max_dry_run_selected_repositories = 10
    end
    attr_writer :secret_scanning_max_dry_run_selected_repositories

    def secret_scanning_email_settings_enabled?
      return @secret_scanning_email_settings_enabled if defined?(@secret_scanning_email_settings_enabled)
      @secret_scanning_email_settings_enabled = !GitHub.enterprise?
    end
    attr_writer :secret_scanning_email_settings_enabled

    # Determine if site admins can adjust the scanning scheduler intervals (in minutes)
    # Set to 5 in dotcom, 10 in enterprise, except if explicitly enabled via ghe config apply.
    def scanning_scheduler_interval
      return @scanning_scheduler_interval if defined?(@scanning_scheduler_interval)
      @scanning_scheduler_interval = enterprise? ? 10 : 5
    end
    attr_writer :scanning_scheduler_interval

    # Should tokens not be sent to third party URLs?
    #
    # Returns true if enabled, false otherwise.
    def skip_secret_scanning_third_party_reporting?
      return @skip_secret_scanning_third_party_reporting if defined?(@skip_secret_scanning_third_party_reporting)
      @skip_secret_scanning_third_party_reporting = enterprise? || dynamic_lab?
    end
    attr_writer :skip_secret_scanning_third_party_reporting

    # Should we skip running secret scanning in branch protection / rules engine evaluations?
    #
    # Always false by default, except for tests to avoid unnecessary overhead
    # Test files should disable this explicitly if testing secret scanning flows
    def skip_secret_scanning_in_rules_engine?
      return @skip_secret_scanning_in_rules_engine if defined?(@skip_secret_scanning_in_rules_engine)
      @skip_secret_scanning_in_rules_engine = false
    end
    attr_writer :skip_secret_scanning_in_rules_engine

    # Determine if use spokes API for commits
    #
    # Enabled by default for enterprise and dotcom, unless explicitly disabled
    def secret_scanning_use_spokes_enabled?
      return @secret_scanning_use_spokes_enabled if defined?(@secret_scanning_use_spokes_enabled)
      @secret_scanning_use_spokes_enabled = true
    end
    attr_writer :secret_scanning_use_spokes_enabled

    def secret_scanning_validity_checks_available_on_instance?
      !GitHub.single_or_multi_tenant_enterprise?
    end

    # Determine if code scanning is enabled.
    # Enabled by default in dotcom, disabled for enterprise, except if explicitly enabled via ghe config apply.
    #
    # Returns true if enabled, false otherwise.
    def code_scanning_enabled?
      return @code_scanning_enabled if defined?(@code_scanning_enabled)
      @code_scanning_enabled = !enterprise?
    end
    attr_writer :code_scanning_enabled

    # Determine if site admins can initiate secret scanning
    # Enabled by default in dotcom, disabled for enterprise, except if explicitly enabled via ghe config apply.
    #
    # Returns true if enabled, false otherwise.
    def configuration_secret_scanning_enabled?
      return @secret_scanning_enabled if defined?(@secret_scanning_enabled)
      @secret_scanning_enabled = Rails.env.test? || !enterprise?
    end
    attr_writer :secret_scanning_enabled

    # Determine if GHES licenses can check for code_security_enabled and secret_protection_enabled
    # Enabled by default in enterprise, disabled (and irrelevant) for dotcom
    #
    # Returns true if enabled, false otherwise.
    def ghas_sku_split_enabled?
      return @ghas_sku_split_enabled if defined?(@ghas_sku_split_enabled)
      @ghas_sku_split_enabled = enterprise?
    end
    attr_writer :ghas_sku_split_enabled

    # Determine if site admins can initiate a site-wide ssh key audit.
    # Enabled by default in Enterprise, disabled for dotcom.
    #
    # Returns true if enabled, false otherwise.
    def ssh_audit_enabled?
      return @ssh_audit_enabled if defined?(@ssh_audit_enabled)
      @ssh_audit_enabled = enterprise?
    end
    attr_writer :ssh_audit_enabled

    # Determine whether repo transfers require approval.
    #
    # Returns true if enabled, false otherwise.
    def repository_transfer_requests_enabled?
      return @repository_transfer_requests_enabled if defined?(@repository_transfer_requests_enabled)
      @repository_transfer_requests_enabled = !enterprise?
    end
    attr_writer :repository_transfer_requests_enabled

    # Determine whether employee-only features are available. Disabled by
    # default under Enterprise environments, enabled everywhere else.
    #
    # Returns true if enabled, false otherwise.
    def preview_features_enabled?
      return @preview_features_enabled if defined?(@preview_features_enabled)
      @preview_features_enabled = !enterprise?
    end
    attr_writer :preview_features_enabled

    # Whether public-push repositories are enabled.
    # See: https://github.com/github/github/pull/15785
    def public_push_enabled?
      GitHub.enterprise?
    end

    # Determine whether anonymous git access can be enabled on repositories.
    def anonymous_git_access_available?
      GitHub.private_mode_enabled?
    end

    # Whether browser stats collecting is enabled
    def browser_stats_enabled?
      return @browser_stats_enabled if defined?(@browser_stats_enabled)
      @browser_stats_enabled = true
    end
    attr_writer :browser_stats_enabled

    # The API URL to post browser stats to.
    def browser_stats_url
      [api_url, "_private", "browser", "stats"].join("/")
    end

    # The API URL that JavaScript exceptions are reported to.
    def browser_errors_url
      [api_url, "_private", "browser", "errors"].join("/")
    end

    # The name of the session cookie used for rails sessions.
    #
    # Returns '_gh_sess' by default under dotcom mode and '_gh_ent' under
    # enterprise mode.
    def session_key
      @session_key ||=
        if GitHub.runtime.enterprise?
          "_gh_ent"
        else
          "_gh_sess"
        end
    end
    attr_writer :session_key

    # The secret token for both rails and rack session signatures. This value is
    # also used by enterprise-manage's sessions.
    attr_accessor :session_secret

    # The timeout for user sessions, in seconds.
    #
    # Defaults to 2 weeks.
    def user_session_timeout
      @user_session_timeout ||= 2.weeks
    end
    attr_writer :user_session_timeout

    # Window of time between user session access log writes
    #
    # Defaults to 1 day.
    def user_session_access_throttling
      @user_session_access_throttling ||= 1.day
    end
    attr_writer :user_session_access_throttling

    # The secret token used for signing Alive socket IDs and twirp requests
    attr_accessor :longpoll_socket_id_secret

    # The key used to encrypt attributes sent to Alive
    attr_accessor :alive_encryption_key

    ##
    # Network Graph

    # Maximum number of commits (dots) to show on the Network Graph.
    def network_graph_history_limit
      @network_graph_history_limit ||= enterprise? ? 50_000 : 5_000
    end
    attr_writer :network_graph_history_limit

    # Maximum number of forks in a network to show. These are the
    # most popular and active forks that are selected
    def network_graph_fork_limit
      @network_graph_fork_limit ||= 100
    end
    attr_writer :network_graph_fork_limit

    # Maximum number of branches in a single repository to show
    # in the network graph. These are the most recently active
    # branches
    def network_graph_branch_limit
      @network_graph_branch_limit ||= 2_000
    end
    attr_writer :network_graph_branch_limit

    # The limit of how many times an email check request can happen per
    # ip address.
    #
    # Returns a fixnum limit that can be combined with a ttl.
    def email_check_rate_limit
      @email_check_rate_limit ||= enterprise? ? 120 : 5000
    end
    attr_writer :email_check_rate_limit

    # The lifespan of an email check rate limit.
    #
    # Returns a fixnum representing time in seconds.
    def email_check_ttl
      @email_check_ttl ||= enterprise? ? 1.minute : 1.hour
    end
    attr_writer :email_check_ttl

    # The Enterprise configuration id. An integer timestamp representing the
    # last time the configuration chef run was started. This is exposed at
    # /status.json and is useful for determining if the app is running under
    # the expected or newer configuration version.
    def configuration_id
      @configuration_id.to_i rescue nil
    end
    attr_writer :configuration_id

    # The port the git daemon in listening on locally. In production the default
    # git port (9418) is used. On enterprise git_proxy needs to consume 9418 so
    # the daemon must listen on something else.
    #
    # Returns 9418 in production.
    def git_daemon_port
      @git_daemon_port ||= 9418
    end
    attr_writer :git_daemon_port

    # The fingerprints of the host key. Constant on production, unique per
    # server on enterprise.
    #
    # Return the fingerprint of the RSA host key.
    def ssh_host_key_fingerprints
      fingerprints = {
        "SHA256_ECDSA" => "p2QAMXNIC1TJYWeIOttrVc98/R1BUFWu3/LiyKgUfQM",
        "SHA256_ED25519" => "+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU",
      }
      if GitHub.flipper[:ssh_new_rsa].enabled?
        fingerprints["SHA256_RSA"] = "uNiVztksCsDhcc0u9e8BujQXVUpKZIDTMczCvj3tD2s"
      else
        fingerprints["SHA256_RSA"] = "nThbg6kXUpJWGl7E1IGOCspRomTxdCARLviKw6E5SY8"
      end
      fingerprints
    end

    # The SSH host keys. Only used on dotcom.
    #
    # This is specified as a list to allow us to perform rotations of keys where
    # we have multiple of the same type at once.
    #
    # Return the fingerprint of the RSA host key.
    def ssh_host_keys
      keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl",
        "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=",
      ]
      if GitHub.flipper[:ssh_new_rsa].enabled?
        keys << "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk="
      else
        keys << "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLmvU31/yMf+Se8xhHTvKSCZIFImWwoG6mbUoWf9nzpIoaSjB+weqqUUmpaaasXVal72J+UX2B+2RPW3RcT0eOzQgqlJL3RKrTJvdsjE3JEAvGq3lGHSZXy28G3skua2SmVi/w4yCE6gbODqnTWlg7+wC604ydGXA8VJiS5ap43JXiUFFAaQ=="
      end
      keys
    end

    # New accounts are created through the signup page on enterprise instances.
    # Not used by some external auth providers, or when in private mode, or when
    # explicitly disabled during setup.
    #
    # Returns boolean
    def signup_enabled?
      return false if multi_tenant_enterprise?
      return true unless enterprise?

      !GitHub.private_mode_enabled? && GitHub.auth.signup_enabled? && GitHub.signup_enabled
    end

    # In Enterprise, admins can explicitly disable signups.
    attr_accessor :signup_enabled

    # In Enterprise, realtime backups are manually enabled
    def realtime_backups_enabled?
      !!@realtime_backups_enabled
    end
    attr_writer :realtime_backups_enabled

    # In Enterprise we hide the ability to block users and report
    # abuse.
    def user_abuse_mitigation_enabled?
      return @user_abuse_mitigation_enabled if defined?(@user_abuse_mitigation_enabled)
      @user_abuse_mitigation_enabled = !enterprise?
    end
    attr_writer :user_abuse_mitigation_enabled

    # Timeout for long running Git operations in templates (e.g.,
    # rendering diffs and commit lists in pull requests).
    def git_template_timeout
      @git_template_timeout ||= 10
    end
    attr_writer :git_template_timeout

    # Stealth email is disabled on Enterprise instances.
    def stealth_email_enabled?
      !enterprise?
    end

    # Allow turning on/off email replies to notifications.
    #
    # Returns Boolean.
    def email_replies_enabled?
      return @email_replies_enabled if defined?(@email_replies_enabled)
      @email_replies_enabled = true
    end
    attr_writer :email_replies_enabled

    # Email verification is disabled on Enterprise instances
    def email_verification_enabled?
      return false if single_or_multi_tenant_enterprise?
      true
    end

    # Choosing a commit email is disabled on Enterprise because
    # email verification and commit signing are also disabled on Enterprise.
    def choose_commit_email_enabled?
      !enterprise?
    end

    # Mandatory email verification is turned off in dev and test, and anywhere
    # email verification is disabled.
    #
    # Force with the ENABLE_MANDATORY_VERIFICATION environment variable, e.g.:
    #
    #   ENABLE_MANDATORY_VERIFICATION=1 script/server
    def mandatory_email_verification_enabled?
      return true if !!ENV["ENABLE_MANDATORY_VERIFICATION"]
      email_verification_enabled? && !(Rails.env.test? || Rails.env.development?)
    end

    # Email preference center is disabled on Enterprise instances
    # because we don't need to send marketing newsletters to those users.
    def email_preference_center_enabled?
      !enterprise?
    end

    def email_preferences_center_elections_email_enabled?
      !GitHub.enterprise? && !Rails.env.production? && !Rails.env.test?
    end

    # Determine whether or not to check user email addresses for
    # genericness before counting contributions.
    def email_detect_generic_domains?
      @email_detect_generic_domains ||= !enterprise?
    end
    attr_writer :email_detect_generic_domains

    # The MailChimp integration is disabled on Enterprise.
    def mailchimp_enabled?
      !enterprise?
    end

    # As is the sendgrid integration
    def sendgrid_enabled?
      !enterprise?
    end

    # We require a password confirmation on signup in Enterprise
    # because email delivery might not be enabled for the instance,
    # which means that a user couldn't reset their password via email.
    def password_confirmation_required?
      enterprise?
    end

    # We ask users identity questions on dotcom during signup.
    # Disabled on Enterprise.
    def user_identification_enabled?
      !enterprise?
    end

    # Live Update XHR Socket poller
    #
    # Can be flipped off if the web socket connections are going nuts.
    def live_updates_enabled?
      return @live_updates_enabled if defined?(@live_updates_enabled)
      @live_updates_enabled = true
    end
    attr_writer :live_updates_enabled

    # Check to see if we are restricted by licenses.
    #
    # In other words, if this is a GHES installation.
    #
    # Determines what to show in the root of /stafftools.
    def licensed_mode?
      enterprise?
    end

    # The path to the local .ghl file on Enterprise instances.
    def license_path
      return unless enterprise?

      @license_path ||= if Rails.env.production?
        File.join(enterprise_config_dir, "enterprise.ghl")
      else
        path = Rails.root.join("..", "enterprise2", "test.ghl").to_s
        raise IOError, "Test license not found; is enterprise2 present?" if Rails.env.development? && !File.exist?(path)
        path
      end
    end
    # attr_writer :license_path unless Rails.env.production?
    attr_writer :license_path unless GitHub::AppEnvironment.production?

    # Path to the license .gpg key shipped as part of an Enterprise .ova.
    def license_key
      @license_key ||= File.join(enterprise_config_dir, "license.gpg")
    end
    attr_writer :license_key unless GitHub::AppEnvironment.production?

    # Path to the customer .gpg key uploaded as part of the Enterprise license.
    def customer_key
      @customer_key ||= File.join(enterprise_config_dir, "customer.gpg")
    end
    attr_writer :customer_key unless GitHub::AppEnvironment.production?

    # The configuration directory holding Enterprise related files like the
    # .ghl license, customer gpg key, and license gpg key.
    #
    # Returns the path to the config dir for the current Enterprise series.
    def enterprise_config_dir
      "/data/enterprise"
    end

    # Placeholder to abstract the fact that GitHub access control is done
    # through GitHub::AccessControl.
    def access
      Egress::AccessControl
    end

    # Configuration for enforcing active session limits
    def active_session_limit_enabled?
      !enterprise?
    end

    # enterprise-web URL
    attr_accessor :enterprise_web_url

    # enterprise-web admin URL
    attr_accessor :enterprise_web_admin_url

    # enterprise-web HMAC
    attr_accessor :enterprise_web_hmac

    def enterprise_support_url
      "#{enterprise_web_url}/support"
    end

    # S3 Access key for alambic
    attr_accessor :s3_alambic_access_key

    # S3 Secret key for alambic
    attr_accessor :s3_alambic_secret_key

    # Sets the URL for accessing Alambic.
    # TODO(storage): deprecated by alambic cluster
    attr_accessor :alambic_url

    # Sets the URL for purging CDN keys.
    attr_accessor :alambic_cdn_url

    # Sets the API token for purging CDN data through Alambic.
    attr_accessor :alambic_cdn_token

    # Sets the URL prefix for uploading assets to the "assets" Alambic service.
    # TODO(storage): deprecated by alambic cluster
    attr_accessor :alambic_uploads_url

    # URL for accessing the LFS server
    def lfs_server_url
      @lfs_server_url || urls._lfs_server_url
    end
    # used on enterprise to set the url from ENTERPRISE_LFS_SERVER_URL
    attr_writer :lfs_server_url

    # An array of HMAC keys used to verify requests sent to the Internal API.
    def internal_api_hmac_keys
      @internal_api_hmac_keys ||= [
        ENV["INTERNAL_API_HMAC_KEY"],
        ENV["INTERNAL_API_SECONDARY_HMAC_KEY"]
      ].join(" ").split
    end
    attr_writer :internal_api_hmac_keys

    # Sets the HMAC key used to verify avatar requests in Proxima. This key must be different for each stamp.
    attr_accessor :alambic_avatars_hmac_key

    # Used to validate requests to bots' avatars
    def company_specific_entity_acronym
      "ghcse"
    end

    # Sets the HMAC key used to generate an HMAC token to authenticate with the Authzd APIs.
    def authzd_api_hmac_key
      @authzd_api_hmac_key ||=
        ENV["API_INTERNAL_TWIRP_HMAC_KEYS_FOR_AUTHZD"].to_s
    end
    attr_writer :authzd_api_hmac_key

    # Sets the HMAC keys used to verify GitAuth tokens. The value that should be
    # used for new token should be first.
    def gitauth_token_hmac_keys
      @gitauth_token_hmac_keys ||=
        ENV["GITAUTH_TOKEN_HMAC_KEYS"].to_s.split
    end
    attr_writer :gitauth_token_hmac_keys

    # Private images hmac key
    # Sets a private secret that's used for jwt signing with Fastly
    def private_user_images_cdn_key
      @private_user_images_cdn_key ||= ENV["PRIVATE_USER_IMAGES_CDN_KEY_5"].to_s
    end
    attr_writer :private_user_images_cdn_key

    # Private avatars hmac key
    # Sets a private secret that's used for jwt signing with Fastly
    def private_avatars_cdn_key
      @private_avatars_cdn_key ||= ENV["PRIVATE_AVATARS_CDN_KEY_1"].to_s
    end
    attr_writer :private_avatars_cdn_key

    # Private Azure Blob Storage Assets hmac key
    # Sets a private secret that's used for jwt signing with Fastly
    def private_abs_asset_cdn_key
      @private_abs_asset_cdn_key ||= ENV["PRIVATE_ABS_ASSET_CDN_KEY_1"].to_s
    end
    attr_writer :private_abs_asset_cdn_key

    def api_internal_pages_hmac_keys
      @api_internal_pages_hmac_keys ||=
        ENV["API_INTERNAL_PAGES_ROUTER_HMAC_KEYS"].to_s.split
    end
    attr_writer :api_internal_pages_hmac_keys

    def api_internal_storage_uploadable_hmac_keys
      @api_internal_storage_uploadable_hmac_keys ||=
        ENV["API_INTERNAL_STORAGE_UPLOADABLE_HMAC_KEYS"].to_s.split
    end
    attr_writer :api_internal_storage_uploadable_hmac_keys

    def api_internal_raw_hmac_keys
      @api_internal_raw_hmac_keys ||=
        ENV["API_INTERNAL_RAW_HMAC_KEYS"].to_s.split
    end
    attr_writer :api_internal_raw_hmac_keys

    def api_internal_archive_hmac_keys
      @api_internal_archive_hmac_keys ||=
        ENV["API_INTERNAL_ARCHIVE_HMAC_KEYS"].to_s.split
    end
    attr_writer :api_internal_archive_hmac_keys

    def api_internal_blackbird_hmac_keys
      @api_internal_blackbird_hmac_keys ||=
        ENV["API_INTERNAL_BLACKBIRD_HMAC_KEYS"].to_s.split
    end
    attr_writer :api_internal_blackbird_hmac_keys

    def api_internal_actions_image_deployment_hmac_keys
      @api_internal_actions_image_deployment_hmac_keys ||=
        ENV["API_INTERNAL_ACTIONS_IMAGE_DEPLOYMENT_HMAC_KEYS"].to_s.split
    end
    attr_writer :api_internal_actions_image_deployment_hmac_keys

    def api_internal_entra_user_licensed_for_ghe_hmac_keys
      @api_internal_entra_user_licensed_for_ghe_hmac_keys ||=
        ENV["API_INTERNAL_ENTRA_USER_LICENSED_FOR_GHE_HMAC_KEYS"].to_s.split
    end
    attr_writer :api_internal_entra_user_licensed_for_ghe_hmac_keys

    def api_internal_azure_enterprises_hmac_keys
      api_internal_entra_user_licensed_for_ghe_hmac_keys
    end
    attr_writer :api_internal_azure_enterprises_hmac_keys

    def api_internal_global_flags_hmac_keys
      @api_internal_global_flags_hmac_keys ||=
        ENV["API_INTERNAL_GLOBAL_FLAGS_HMAC_KEYS"].to_s.split
    end
    attr_writer :api_internal_global_flags_hmac_keys

    def api_internal_multi_part_policies_hmac_keys
      @api_internal_multi_part_policies_hmac_keys ||=
        ENV["API_INTERNAL_MULTI_PART_POLICIES_HMAC_KEYS"].to_s.split
    end
    attr_writer :api_internal_multi_part_policies_hmac_keys

    def api_internal_lfs_hmac_keys
      @api_internal_lfs_hmac_keys ||=
        ENV["API_INTERNAL_LFS_HMAC_KEYS"].to_s.split
    end
    attr_writer :api_internal_lfs_hmac_keys

    def api_internal_media_app_hmac_keys
      @api_internal_media_app_hmac_keys ||=
        ENV["API_INTERNAL_MEDIA_APP_HMAC_KEYS"].to_s.split
    end
    attr_writer :api_internal_media_app_hmac_keys

    def api_internal_marketplace_analytics_hmac_keys
      @api_internal_marketplace_analytics_hmac_keys ||=
        ENV["API_INTERNAL_MARKETPLACE_ANALYTICS_HMAC_KEYS"].to_s.split
    end
    attr_writer :api_internal_marketplace_analytics_hmac_keys

    def api_internal_porter_callbacks_hmac_keys
      @api_internal_porter_callbacks_hmac_keys ||=
        ENV["API_INTERNAL_PORTER_CALLBACKS_HMAC_KEYS"].to_s.split
    end
    attr_writer :api_internal_porter_callbacks_hmac_keys

    def api_internal_email_bounce_hmac_keys
      @api_internal_email_bounce_hmac_keys ||=
        ENV["API_INTERNAL_EMAIL_BOUNCE_HMAC_KEYS"].to_s.split
    end
    attr_writer :api_internal_email_bounce_hmac_keys

    def api_internal_assets_uploadable_hmac_keys
      @api_internal_assets_uploadable_hmac_keys ||=
        ENV["API_INTERNAL_ASSETS_UPLOADABLE_HMAC_KEYS"].to_s.split
    end
    attr_writer :api_internal_assets_uploadable_hmac_keys

    def api_internal_avatars_hmac_keys
      @api_internal_avatars_hmac_keys ||=
        ENV["API_INTERNAL_AVATARS_HMAC_KEYS"].to_s.split
    end
    attr_writer :api_internal_avatars_hmac_keys

    def api_internal_assets_hmac_keys
      @api_internal_assets_hmac_keys ||=
        ENV["API_INTERNAL_ASSETS_HMAC_KEYS"].to_s.split
    end
    attr_writer :api_internal_assets_hmac_keys

    def api_internal_replicas_hmac_keys
      @api_internal_replicas_hmac_keys ||=
        ENV["API_INTERNAL_SPOKESD_HMAC_KEYS"].to_s.split
    end
    attr_writer :api_internal_replicas_hmac_keys

    def api_internal_repositories_hmac_keys
      @api_internal_repositories_hmac_keys ||=
        [
          ENV["API_INTERNAL_REPOSITORIES_HMAC_KEYS"],
          ENV["API_INTERNAL_BABELD_HMAC_KEYS"],
          ENV["API_INTERNAL_SPOKESD_HMAC_KEYS"],
          ENV["API_INTERNAL_TWIRP_HMAC_KEYS_FOR_TURBOSCAN"],
        ].join(" ").split
    end
    attr_writer :api_internal_repositories_hmac_keys

    def api_internal_wikis_hmac_keys
      @api_internal_wikis_hmac_keys ||=
        [
          ENV["API_INTERNAL_REPOSITORIES_HMAC_KEYS"],
          ENV["API_INTERNAL_SPOKESD_HMAC_KEYS"],
        ].join(" ").split
    end
    attr_writer :api_internal_wikis_hmac_keys

    def api_internal_gists_hmac_keys
      @api_internal_gists_hmac_keys ||=
        [
          ENV["API_INTERNAL_GISTS_HMAC_KEYS"],
          ENV["API_INTERNAL_BABELD_HMAC_KEYS"],
          ENV["API_INTERNAL_SPOKESD_HMAC_KEYS"],
        ].join(" ").split
    end
    attr_writer :api_internal_gists_hmac_keys

    def api_internal_pre_receive_hooks_hmac_keys
      @api_internal_pre_receive_hooks_hmac_keys ||=
        ENV["API_INTERNAL_PRE_RECEIVE_HOOKS_HMAC_KEYS"].to_s.split
    end
    attr_writer :api_internal_pre_receive_hooks_hmac_keys

    def api_internal_aleph_hmac_keys
      @api_internal_aleph_hmac_keys ||=
        ENV["API_INTERNAL_ALEPH_HMAC_KEYS"].to_s.split
    end
    attr_writer :api_internal_aleph_hmac_keys

    def api_internal_actions_hmac_keys
      @api_internal_actions_hmac_keys ||=
          ENV["API_INTERNAL_ACTIONS_HMAC_KEYS"].to_s.split
    end
    attr_writer :api_internal_actions_hmac_keys

    def api_internal_ui_manifests_hmac_keys
      @api_internal_ui_manifests_hmac_keys ||=
        ENV["API_INTERNAL_UI_MANIFESTS_HMAC_KEYS"].to_s.split
    end
    attr_writer :api_internal_ui_manifests_hmac_keys

    # Sets the HMAC key used for signing to authenticate with VSCS in production.
    def api_internal_codespaces_vscs_production_hmac_key
      @api_internal_codespaces_vscs_production_hmac_key ||= api_internal_codespaces_vscs_production_hmac_keys.first
    end
    attr_writer :api_internal_codespaces_vscs_production_hmac_key

    # Sets the HMAC key used for signing to authenticate with VSCS in PPE.
    def api_internal_codespaces_vscs_ppe_hmac_key
      @api_internal_codespaces_vscs_ppe_hmac_key ||= api_internal_codespaces_vscs_ppe_hmac_keys.first
    end
    attr_writer :api_internal_codespaces_vscs_ppe_hmac_key

    # Sets the HMAC key used for signing to authenticate with VSCS in development.
    def api_internal_codespaces_vscs_development_hmac_key
      @api_internal_codespaces_vscs_development_hmac_key ||= api_internal_codespaces_vscs_development_hmac_keys.first
    end
    attr_writer :api_internal_codespaces_vscs_development_hmac_key

    # Sets the HMAC keys used with VSCS in production.
    def api_internal_codespaces_vscs_production_hmac_keys
      @api_internal_codespaces_vscs_production_hmac_keys ||= ENV["API_INTERNAL_CODESPACES_PRODUCTION_HMAC_KEYS"].to_s.split
    end
    attr_writer :api_internal_codespaces_vscs_production_hmac_keys

    # Sets the HMAC keys used with VSCS in PPE.
    def api_internal_codespaces_vscs_ppe_hmac_keys
      @api_internal_codespaces_vscs_ppe_hmac_keys ||= ENV["API_INTERNAL_CODESPACES_PPE_HMAC_KEYS"].to_s.split
    end
    attr_writer :api_internal_codespaces_vscs_ppe_hmac_keys

    # Sets the HMAC keys used with VSCS in development.
    def api_internal_codespaces_vscs_development_hmac_keys
      @api_internal_codespaces_vscs_development_hmac_keys ||= ENV["API_INTERNAL_CODESPACES_DEVELOPMENT_HMAC_KEYS"].to_s.split
    end
    attr_writer :api_internal_codespaces_vscs_development_hmac_keys

    def api_internal_codespaces_vscs_hmac_keys
      @api_internal_codespaces_vscs_hmac_keys ||=
        api_internal_codespaces_vscs_production_hmac_keys +
        api_internal_codespaces_vscs_ppe_hmac_keys +
        api_internal_codespaces_vscs_development_hmac_keys
    end
    attr_writer :api_internal_codespaces_vscs_hmac_keys

    def api_internal_quarantine_hmac_keys
      @api_internal_quarantine_hmac_keys ||=
          ENV["API_INTERNAL_QUARANTINE_HMAC_KEYS"].to_s.split
    end
    attr_writer :api_internal_quarantine_hmac_keys

    def api_internal_neutron_hmac_keys
      @api_internal_neutron_hmac_keys ||= begin
        prod = ENV["API_INTERNAL_NEUTRON_PRODUCTION_HMAC_KEYS"].to_s.split
        dev = ENV["API_INTERNAL_NEUTRON_DEV_HMAC_KEYS"].to_s.split
        prod + dev
      end
    end
    attr_writer :api_internal_neutron_hmac_keys

    # Sets the HMAC keys used with Copilot API.
    def api_internal_copilot_api_hmac_keys
      @api_internal_copilot_api_hmac_keys ||=
          ENV["API_INTERNAL_COPILOT_API_HMAC_KEYS"].to_s.split
    end
    attr_writer :api_internal_copilot_api_hmac_keys

    def issues_graph_hmac_key
      @issues_graph_hmac_key ||=
          ENV["ISSUES_GRAPH_HMAC_KEY"].to_s
    end
    attr_writer :issues_graph_hmac_key

    # Sets the HMAC keys used to generate an HMAC token to authenticate with the Alloy APIs.
    def alloy_api_hmac_key
      @alloy_api_hmac_key ||=
        ENV["ALLOY_API_HMAC_KEY"].to_s
    end
    attr_writer :alloy_api_hmac_key

    def api_internal_apps_hmac_keys
      @api_internal_apps_hmac_keys ||= GitHub::Config::AppsPrivilegedAPI.hmac_secrets
    end

    # Sets the secrets for the spamurai timestamps.
    def spamurai_timestamp_secrets
      return @spamurai_timestamp_secrets if defined?(@spamurai_timestamp_secrets)
      @spamurai_timestamp_secrets = ENV["SPAMURAI_TIMESTAMP_SECRETS"].to_s.split
    end
    attr_writer :spamurai_timestamp_secrets

    # For asking about LDAP entitlements
    def platform_health_entitlements_ldap_client
      return @platform_health_entitlements_ldap_client if defined?(@platform_health_entitlements_ldap_client)
      @platform_health_entitlements_ldap_client = GitHub::EntitlementsLdap.new(
        uri: ENV["PLATFORM_HEALTH_ENTITLEMENTS_LDAP_URI"],
        username: ENV["PLATFORM_HEALTH_ENTITLEMENTS_LDAP_BINDDN"],
        password: ENV["PLATFORM_HEALTH_ENTITLEMENTS_LDAP_BINDPW"],
      ).client
    end
    attr_writer :platform_health_entitlements_ldap_client

    # Sets the ?v param on avatar urls.  Changing this will force break all
    # avatar server and browser caches.
    attr_accessor :alambic_avatar_version

    # Sets the ?v param on avatar urls for a portion of URLS
    attr_accessor :alambic_next_avatar_version

    # Sets the ?b param on avatar urls.  Changing this will force break all
    # browser caches.
    attr_accessor :alambic_browser_avatar_version

    # Sets the ?b param on avatar urls for a portion of URLS
    attr_accessor :alambic_next_browser_avatar_version

    # Sets the % chance that the next avatar version is used
    attr_accessor :alambic_next_avatar_chance

    # Sets the string user login
    attr_accessor :alambic_fallback_user

    # Sets the URL path to purge (using GitHub.alambic_cdn_url as the host)
    attr_writer :alambic_cdn_purge_path

    # Sets the number of seconds to delay an avatar purge.
    attr_accessor :alambic_cdn_delay

    # Sets the default path prefix for alambic content.  See the defaults set
    # in the different runtime environments (test, dev, prod, enterprise).
    # TODO(storage): deprecated by alambic cluster
    attr_accessor :alambic_path_prefix

    # Sets whether to force the Media::Blob prefix or use the default one.
    # Defaults to false in production, and true everywhere else.
    # TODO(storage): deprecated by alambic cluster
    attr_accessor :alambic_use_media_prefix

    # Sets the API token for replicating assest through Alambic
    attr_accessor :alambic_replication_token

    # Sets a shared token with github/lfs-server for internal api actions
    attr_accessor :lfs_server_token

    attr_accessor :git_lfs_enabled

    def alambic_cdn_purge_path
      @alambic_cdn_purge_path ||= "purge"
    end

    # Gets the CSP host to grant access to Alambic services.
    def alambic_csp_host
      url_origin(alambic_uploads_url)
    end

    # Sets the URL prefix for downloading assets from the "assets" Alambic
    # service.
    #
    # TODO(storage): deprecated by alambic cluster
    #
    # ex: https://alambic-origin.github.com/assets
    attr_accessor :alambic_assets_url

    # Sets the URL prefix for uploading and downloading objects through the
    # "storage" Alambic service.
    attr_accessor :storage_cluster_url

    # Get the storage cluster host for CSP purposes.
    def storage_cluster_host
      url_origin(storage_cluster_url)
    end

    attr_accessor :memory_alpha_fastly_url
    attr_accessor :spn_memory_alpha_tenant_id
    attr_accessor :spn_memory_alpha_client_id
    attr_accessor :spn_memory_alpha_client_secret
    attr_accessor :release_assets_storage_acount

    def memory_alpha_fastly_host
      parsed = Addressable::URI.parse(memory_alpha_fastly_url)
      parsed.host
    end

    # Returns the Memory Alpha URL based on the current Rails environment and the current GitHub environment.
    def memory_alpha_url
      urls.memory_alpha_url.downcase
    end

    def memory_alpha_scheme
      parsed = Addressable::URI.parse(memory_alpha_url)
      parsed.scheme
    end

    def memory_alpha_host
      parsed = Addressable::URI.parse(memory_alpha_url)
      parsed.host
    end

    def memory_alpha_port
      parsed = Addressable::URI.parse(memory_alpha_url)
      parsed.port
    end

    attr_accessor :uploadable_storage_account
    attr_accessor :uploadable_access_key

    def lfs_storage_host
      urls.lfs_storage_host
    end

    def lfs_storage_host_protocol
      # In development the memory alpha server serves only HTTP.
      if Rails.env.development?
        "http"
      else
        "https"
      end
    end

    attr_accessor :lfs_storage_account
    attr_accessor :lfs_access_key

    # Sets the URL prefix for downloading objects through the "storage"
    # Alambic service. If nil, fall back to #storage_cluster_url. GHE with
    # Private mode should set this to a route that verifies private mode through
    # cookies, instead of the API.
    attr_accessor :storage_private_mode_url

    # Sets the URL prefix for downloading objects through the "storage"
    # Alambic service. If nil, fall back to #storage_cluster_url. GHE in a
    # repository cache location should set this to a route that resolves to
    # that location instead of the primary GHE instance.
    #
    # ex: https://morocco.github.example.com/storage
    attr_accessor :storage_cache_location_url

    # Sets the URL format for the root url for Alambic to replicate objects.
    # Should yield a full URL.
    #
    # ex: "http://%s:8080/storage/replicate"
    #
    #   GitHub.storage_replicate_fmt % "ghe-alambic-fe1"
    #   # => http://ghe-alambic-fe1:8080/storage/replicate
    attr_accessor :storage_replicate_fmt

    # Sets the path for the EnterpriseStorageClusterUpgrade transition.
    attr_accessor :storage_transition_path

    attr_writer :storage_cluster_enabled
    attr_writer :storage_auto_localhost_replica
    attr_writer :storage_legacy_path

    def storage_cluster_enabled?
      !!@storage_cluster_enabled
    end

    # Enables the private assets feature for the GHES storage cluster.
    attr_writer :storage_cluster_private_assets_enabled
    def storage_cluster_private_assets_enabled?
      !!@storage_cluster_private_assets_enabled
    end

    def ghes_cluster_enabled?
      enterprise? && storage_cluster_enabled?
    end

    # Get the number of read-only replicas that are included
    # in a storage upload; these replicas are not required for a
    # successful cluster consensus.
    #
    # @return [Integer] the number of read-only replicas in a storage upload
    def storage_non_voting_replica_count
      return @storage_non_voting_replica_count.to_i if @storage_non_voting_replica_count

      @storage_non_voting_replica_count = 0
    end

    # Set the number of readonly replicas that are included in a storage upload.
    # These replicas are not required for a successful cluster consensus.
    #
    # @param int [Integer] the value to set #storage_non_voting_replica_count to, must
    #    cast to an Integer
    # @return [Integer] the number of read-only replicas in a storage upload
    def storage_non_voting_replica_count=(int)
      # nil will not strictly cast to an Integer; #to_i takes
      # liberties that Integer() does not and we *want* this method
      # to raise an exception if we try to assign something
      # patently ridiculous to it. nil isn't entirely ridiculous,
      # so we check for that and let Integer() handle the rest.
      @storage_non_voting_replica_count = int.nil? ? 0 : Integer(int)
    end

    # Get the number of replicas that are included in a storage upload;
    # this should never be less than 1 and the setter will enforce that
    # behavior.
    #
    # @return [Integer] the number of storage replicas
    def storage_replica_count
      return @storage_replica_count.to_i if @storage_replica_count

      # there should never be less than 1 storage replica
      @storage_replica_count = 1
    end

    # Set the number of replicas that are included in a storage upload
    #
    # @param int [Integer] the value of storage upload replicas,
    #     must cast to an Integer greater than or equal to 1
    # @return [Integer] the number of replicas in a storage upload
    def storage_replica_count=(int)
      # there should never be less than 1 replica, but because this
      # is an old method there is a chance that this will end up being
      # assigned 0 or nil somewhere in the codebase.
      @storage_replica_count = (int.nil? || Integer(int) < 1) ? 1 : Integer(int)
    end

    def storage_auto_localhost_replica?
      if @storage_auto_localhost_replica.nil?
        @storage_auto_localhost_replica = !Rails.env.production?
      end
      @storage_auto_localhost_replica
    end

    def storage_legacy_path
      @storage_legacy_path ||= File.join(Rails.root, "tmp/objects")
    end

    # Sets the URL prefix for the Avatar proxy
    #
    # ex: https://avatars.github.com
    attr_accessor :alambic_avatar_url

    attr_accessor :alambic_private_avatar_url

    def alambic_assets_host
      url_origin(alambic_assets_url)
    end

    # Gets just the scheme + host + port of a URL for the CSP policy.
    def url_origin(url)
      origin = Addressable::URI.parse(url).origin if url
      origin == "null" ? nil : origin
    end

    def avatar_version(key = nil)
      nxt = alambic_next_avatar_version
      return alambic_avatar_version if !(nxt && next_avatar_version?(key))
      nxt
    end

    def browser_avatar_version(key = nil)
      nxt = alambic_next_browser_avatar_version
      return alambic_browser_avatar_version if !(nxt && next_avatar_version?(key))
      nxt
    end

    def next_avatar_version?(key = nil)
      chance = alambic_next_avatar_chance.to_i
      return false unless chance > 0

      if key
        Zlib.crc32(key) % 100 < chance
      else
        rand(100) < chance
      end
    end

    # Prefetch DNS entries for our asset domains.
    #
    # https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/X-DNS-Prefetch-Control
    #
    #     <link rel="dns-prefetch" href="//github.githubassets.com">
    #
    # Returns an Array of String host names to prefetch.
    def dns_prefetch_hosts
      @dns_prefetch_hosts ||= [
        asset_host_url,
        alambic_avatar_url,
        s3_asset_bucket_host,
        user_images_cdn_url,
      ].select(&:present?).freeze
    end

    # Preconnect entries for our asset domains.
    # Should be kept short (Lighthouse recommends max 2 entries).
    # Used together with DNS prefecth (which has slightly broader browser support).
    #
    # https://developer.mozilla.org/en-US/docs/Web/Performance/dns-prefetch
    # https://developer.mozilla.org/en-US/docs/Web/HTML/Link_types/preconnect
    #
    #     <link rel="preconnect" href="//github.githubassets.com" crossorigin>
    #
    # Returns an Array of String host names to preconnect to.
    def preconnect_hosts
      @preconnect_hosts ||= [
        alambic_avatar_url,
      ].select(&:present?).freeze
    end

    def preconnect_hosts_crossorigin
      @preconnect_hosts_crossorigin ||= [
        asset_host_url,
      ].select(&:present?).freeze
    end

    # Public - disable NetGraph generation
    # The network graph generation makes the Enterprise VM unusable.
    # Using this flag we can disable the building for each push.
    #
    # Return true if the graph can be built.
    def network_graph_building_enabled?
      !enterprise?
    end

    # Whether any uploads are accepted.
    #
    # Returns true if enabled, false otherwise.
    def uploads_enabled?
      storage_cluster_enabled? || s3_uploads_enabled?
    end

    # Upload assets to S3, so that they may be served by Amazon and not us.
    # Disabled by default under FI environments, enabled everwhere else.
    #
    # Returns true if enabled, false otherwise.
    def s3_uploads_enabled?
      return @s3_uploads_enabled unless @s3_uploads_enabled.nil?
      @s3_uploads_enabled = s3_uploads_enabled!
    end
    attr_writer :s3_uploads_enabled

    def s3_uploads_enabled!
      !enterprise? && online?
    end

    def asset_url_host
      @asset_url_host ||= s3_asset_host
    end
    attr_writer :asset_url_host

    def s3_asset_host
      @s3_asset_host ||= begin
        if s3_environment_config[:asset_host_name]
          "https://#{s3_environment_config[:asset_host_name]}/"
        else
          "#{s3_asset_bucket_host}/"
        end
      end
    end
    attr_writer :s3_asset_host

    def s3_asset_bucket_host
      @s3_asset_bucket_host ||= "https://#{s3_environment_config[:asset_bucket_name]}.s3.amazonaws.com"
    end

    def s3_asset_bucket_name
      s3_environment_config[:asset_bucket_name]
    end

    def file_asset_host
      @file_asset_host ||= "/"
    end
    attr_writer :file_asset_host

    # Sets the local file system path to store uploaded files.
    #
    # Returns a String path.
    def file_asset_path
      @file_asset_path ||= if Rails.env.test?
        (Rails.root + "test/fixtures/assets#{test_environment_number}").to_s
      elsif enterprise? && Rails.env.production?
        "/data/assets"
      else
        (Rails.root + "public").to_s
      end
    end
    attr_writer :file_asset_path

    def video_asset_allowlist
      return @video_asset_allowlist if defined?(@video_asset_allowlist) && !GitHub.multi_tenant_enterprise?
      @video_asset_allowlist = if include_alambic_asset_storage_paths?
        # Development mode
        [
          GitHub.url, # Secured user assets enabled
          alambic_assets_host, # Secured user assets disabled
          GitHub.user_images_cdn_url, # Secured user assets enabled
          GitHub.private_user_images_cdn_url, # Secured user assets enabled
          "https://#{GitHub.s3_user_asset_new_host}",
        ]
      elsif GitHub.multi_tenant_enterprise?
        [
          GitHub.url,
          GitHub.memory_alpha_url,
          # Storage url for the signed memory alpha link used for video unfurling,
          # e.g. memoryalphastaffwus201.blob.core.windows.net
          "https://#{GitHub.uploadable_storage_account}.blob.core.windows.net"
        ]
      elsif Rails.env.test?
        # Test mode
        [GitHub.s3_user_asset_new_host]
      elsif storage_cluster_enabled?
        # Enterprise
        [storage_cluster_host, GitHub.url]
      else
        # Production - we need to allow both the displayed url present in markdown and the cdn url so the browser can fetch the content.
        [
          GitHub.url, # When secured_images is enabled, this is the displayed url used to authenticate the user.
          GitHub.user_images_cdn_url, # When secured_images is enabled, this is the source url. When it is disabled, this is the displayed url and the source url.
          GitHub.secured_user_images_cdn_url,
          GitHub.user_images_cdn_url, # when private images auth is enabled i.e secure_user_assets_auth_check
          GitHub.private_user_images_cdn_url, # when private images auth is enabled i.e secure_user_assets_auth_check
          "https://#{GitHub.s3_user_asset_new_host}", # when private images auth is enabled and the CDN is not used
          GitHub.gist_url, # for private assets in gists
        ]
      end
    end
    attr_writer :video_asset_allowlist

    # Sets the local file system path to store storage files.
    # This is only used in enterprise.
    #
    # Returns a String path
    def storage_data_path
      @storage_data_path ||= if enterprise?
        "/data/user/storage"
      else
        file_asset_path
      end
    end
    attr_writer :storage_data_path

    # Uri base path to the external assets.
    #
    # Returns a String path
    def asset_base_path
      return @asset_base_path if defined?(@asset_base_path)
      @asset_base_path = "assets"
    end
    attr_writer :asset_base_path

    # Uri base path to the external task logs.
    #
    # Returns a String path
    def task_log_base_path
      return @task_log_base_path if defined?(@task_log_base_path)
      @task_log_base_path = "task-logs"
    end
    attr_writer :task_log_base_path

    # Uri base path to the external releases.
    #
    # Returns a String path
    def release_asset_base_path
      return @release_asset_base_path if defined?(@release_asset_base_path)
      @release_asset_base_path = "releases"
    end
    attr_writer :release_asset_base_path

    # Uri base path to marketplace listing assets.
    #
    # Returns a String path
    def marketplace_listing_asset_base_path
      if defined? @marketplace_listing_asset_base_path
        return @marketplace_listing_asset_base_path
      end
      @marketplace_listing_asset_base_path = "marketplace_listings"
    end
    attr_writer :marketplace_listing_asset_base_path

    # Uri base path to the external showcase assets
    #
    # Returns a String path
    def showcase_asset_base_path
      return @showcase_asset_base_path if defined?(@showcase_asset_base_path)
      @showcase_asset_base_path = "showcases"
    end
    attr_writer :showcase_asset_base_path

    # Configuration attributes to use github.com as SSO for GitHub Enterprise.
    attr_accessor :github_oauth_client_id
    attr_accessor :github_oauth_secret_key
    attr_accessor :github_oauth_organization
    attr_accessor :github_oauth_team

    # The alphanumeric sender ID used as the "from" value for some SMS messages (when supported by the country/provider/carrier).
    def sms_alphanumeric_sender_id
      "github"
    end

    # The sender ID Vonage(used to be called Nexmo) uses as the "from" value for SMS messages to the US and Canada.
    def vonage_sms_us_canada_sender_id
      "12132633354"
    end

    # A sender ID Vonage (aka Nexmo) uses as the "from" value for SMS messages sent to the UAE.
    def vonage_sms_uae_sender_id
      "Github"
    end

    # Rotate among a few numbers for international recipients.
    def sms_numbers
      @sms_numbers ||= {
        twilio: %w[
          4152339579
          4152339591
          4152339592
          4152339559
          4152339562
          4152339556
          4152339119
          4152339144
          4152339117
          4152339138
          4152339155
          4152339104
          4154888210
          4154888243
          4154888269
          4154888273
          4154888272
          4154888317
          4154888313
          4154888399
          4154888349
          4154888318
        ],
        nexmo: [
          sms_alphanumeric_sender_id,
        ],
        test: %w[
          1231231234
          2342342345
          3453453456
        ],
        local: [
          "1010101010",
        ],
      }
    end
    attr_writer :sms_numbers

    def sms_short_code
      @sms_short_code ||= 448482
    end
    attr_writer :sms_short_code

    # Twilio API information
    attr_accessor :twilio_sid
    attr_accessor :twilio_token
    attr_accessor :twilio_callback_url

    # Nexmo API information
    attr_accessor :nexmo_api_key
    attr_accessor :nexmo_api_secret
    attr_accessor :nexmo_callback_url

    # Determine whether site_admin scope is required for API resources that make
    # use of the site_admin scope. (This scope is used by API resources that are
    # only accessible to site admins).
    #
    # site_admin scope is NOT required by default in Enterprise environments. It
    # is required by default everywhere else.
    #
    # Returns a Boolean.
    def require_site_admin_scope
      return @require_site_admin_scope if defined?(@require_site_admin_scope)
      @require_site_admin_scope = (!!ENV["REQUIRE_SITE_ADMIN_SCOPE"] || !enterprise?)
    end
    attr_writer :require_site_admin_scope
    alias :require_site_admin_scope? :require_site_admin_scope

    attr_writer :stafftools_sessions_enabled
    def stafftools_sessions_enabled?
      return @stafftools_sessions_enabled if defined?(@stafftools_sessions_enabled)
      @stafftools_sessions_enabled = !enterprise?
    end

    attr_writer :hookshot_enabled
    def hookshot_enabled?
      @hookshot_enabled ||= !enterprise?
    end

    attr_writer :hook_limit
    def hook_limit
      @hook_limit ||= enterprise? ? 250 : 20
    end

    def can_override_hook_limit?
      Rails.env.test?
    end

    # Are repositories stored in name-with-owner order on disk?
    attr_writer :nwo_repo_storage
    def nwo_repo_storage?
      enterprise?
    end

    def proxima_internal_api_unique_logins_required?
      return @proxima_internal_api_unique_logins_required if defined? @proxima_internal_api_unique_logins_required
      @proxima_internal_api_unique_logins_required = ENV.fetch("PROXIMA_INTERNAL_API_UNIQUE_LOGINS_REQUIRED", "0") == "1"
    end

    def proxima_internal_api_request_scoping_disabled?
      # Assume requests without the tenant context header in local dev are from internal services.
      return true if Rails.env.development?
      ENV.fetch("PROXIMA_REQUEST_SCOPING_DISABLED", "0") == "1"
    end

    def proxima_internal_api_private_mode_bypass_enabled?
      return false unless GitHub.multi_tenant_enterprise?
      ENV.fetch("PROXIMA_INTERNAL_API_PRIVATE_MODE_BYPASS", "0") == "1"
    end

    def proxima_emu_test_mode?
      Rails.env.test? && TestEnv.test_with_all_emus?
    end

    # Public: Check if the current environment is a GitHub MT environment and test mode is enabled.
    #
    # Returns Boolean
    def multi_tenant_enterprise_test_mode?
      GitHub.multi_tenant_enterprise? && Rails.env.test?
    end

    # Determine whether private image upload CDN is enabled.
    #
    # Returns true if enabled, false otherwise.
    def private_image_upload_cdn_enabled?
      return @private_image_upload_cdn_enabled if defined? @private_image_upload_cdn_enabled
      private_image_upload_cdn_enabled = GitHub.private_user_images_cdn_key.present? && GitHub.private_user_images_cdn_url.present?
    end

    # Determine whether public UserAsset upload CDN is enabled.
    #
    # Returns true if enabled, false otherwise.
    def public_image_upload_cdn_enabled?
      return @public_image_upload_cdn_enabled if defined? @public_image_upload_cdn_enabled
      public_image_upload_cdn_enabled = GitHub.user_images_cdn_url.present?
    end

    # https://support.microsoft.com/en-us/help/4501231/microsoft-account-link-your-github-account
    def microsoft_linked_identity_app_id
      681659
    end

    def traffic_graphs_enabled?
      @traffic_graphs_enabled ||= !enterprise?
    end
    attr_writer :traffic_graphs_enabled

    # Whether a (non admin) user can create organizations on the install
    # The user handling bits are in model_settings_dependency.
    #
    # Returns true for .com, uses setting if it exists.
    def user_can_create_organizations?
      !GitHub.enterprise? || GitHub.org_creation_enabled?
    end

    # Whether Enterprise only API functionality should be enabled
    def enterprise_only_api_enabled?
      GitHub.enterprise?
    end

    # Whether or not you can disable git ssh access controls
    def can_disable_git_ssh_access?
      GitHub.enterprise?
    end

    def interaction_limits_enabled?
      !GitHub.enterprise?
    end

    def code_review_limits_enabled?
      !GitHub.enterprise?
    end

    def organization_moderators_enabled?
      !GitHub.enterprise?
    end

    def git_password_auth_supported?
      GitHub.enterprise?
    end

    def api_password_auth_supported?
      GitHub.enterprise?
    end

    def git_weak_ssh_rsa_deadline
      return @git_weak_ssh_rsa_deadline if defined? @git_weak_rsa_deadline
      value = ENV["GIT_WEAK_SSH_RSA_DEADLINE"]
      @git_weak_ssh_rsa_deadline = if value.nil?
        [nil, nil]
      else
        value.split(" ", 2).map { |x| x.nil? ? nil : Time.parse(x) }
      end
    end

    def git_protocol_enabled?
      return @git_protocol_enabled if defined? @git_protocol_enabled
      @git_protocol_enabled = (ENV["GIT_PROTOCOL_ENABLED"].to_i != 0)
    end

    def git_repld_enabled?
      return @git_repld_enabled if defined? @git_repld_enabled
      @git_repld_enabled = false
    end
    attr_writer :git_repld_enabled

    # Are business organization invitations available?
    def business_organization_invitations_available?
      !GitHub.single_business_environment?
    end

    # Whether business member invitations can be bypassed.
    #
    # This feature is enabled in the single business environment (GitHub
    # Enterprise) which allows global business admins to add new business
    # admins directly rather than using an invitation flow.
    def bypass_business_member_invites_enabled?
      GitHub.single_business_environment?
    end

    # Whether organization invitations can be bypassed.
    #
    # This feature is enabled on Enterprise in order to
    # allow Owners to add employees directly to their Organizations.
    def bypass_org_invites_enabled?
      GitHub.enterprise?
    end

    # Whether verified/approved domains are enabled in the current environemnt?
    def verified_domains_enabled?
      true
    end

    # The organization invitation rate limit for new organizations (less than
    # a month old).
    def org_invite_rate_limit_untrusted
      @org_invite_rate_limit_untrusted ||= (ENV["ORG_INVITE_RATE_LIMIT_UNTRUSTED"] || 50).to_i
    end

    # The organization invitation rate limit for organizations older than the
    # required age minimum.
    def org_invite_rate_limit_trusted
      @org_invite_rate_limit_trusted ||= (ENV["ORG_INVITE_RATE_LIMIT_TRUSTED"] || 500).to_i
    end

    # The organization invitation rate limit for organizations on paying plans.
    def org_invite_rate_limit_paying
      @org_invite_rate_limit_paying ||= (ENV["ORG_INVITE_RATE_LIMIT_PAYING"] || 500).to_i
    end

    def repository_invitation_rate_limit
      @repository_invitation_rate_limit ||= (ENV["REPOSITORY_INVITATION_RATE_LIMIT"] || 50).to_i
    end

    # Are user invitations enabled in this environment?
    #
    # User invitations are currently only enabled on Enterprise, as long as
    # the current setup allows built-in users (e.g., built-in auth itself or
    # an external auth with the fallback to built-in users enabled)
    def user_invites_enabled?
      GitHub.enterprise? && GitHub.auth.allow_builtin_users?
    end

    # Devtools don't currently exist in Enterprise
    def devtools_enabled?
      @devtools_enabled = !enterprise?
    end
    attr_writer :devtools_enabled

    # If graphite is disabled, `GitHub.stats` is configured with a client that
    # is a no-op for every operation.
    def graphite_disabled?
      return true if GitHub::AppEnvironment.test?
      ENV["GRAPHITE_DISABLED"] == "1"
    end

    # The list of stats hosts to connect to.
    # Configured in `environments/*.rb`
    attr_accessor :stats_hosts

    # A allowlist of allowed stats keys. Only applied if this is set, otherwise
    # no allowlist occurs.
    attr_accessor :stats_allowlist

    # Is datadog metric reporting enabled or not. dogstats is configured with a
    # client that noops all calls if this is not true.
    def datadog_enabled?
      return @datadog_enabled if defined?(@datadog_enabled)
      @datadog_enabled = true
    end
    attr_accessor :datadog_enabled

    # String URL of the aleph code navigation service
    attr_accessor :aleph_url

    # String URL of the aleph slow code navigation service
    attr_accessor :aleph_slow_url

    # String HMAC key required for calling the aleph code navigation service.
    attr_accessor :aleph_api_hmac_key

    # Alpeh code navigation is only available on github.com right now.
    def aleph_code_navigation_enabled?
      return @aleph_code_navigation_enabled if defined? @aleph_code_navigation_enabled
      @aleph_code_navigation_enabled = !GitHub.enterprise?
    end

    # String URL of the blackbird middleware query service (Go based)
    attr_accessor :blackbird_url
    attr_accessor :blackbird_lab_url
    attr_accessor :blackbird_hmac_key
    # Whether to use mocked data for the blackbird service
    attr_accessor :blackbird_use_fake_data
    attr_accessor :blackbird_use_fake_legacy_data

    # Configuration options for the v2 blackbird query service (Rust based)
    attr_accessor :blackbird_lexical_search_url
    attr_accessor :blackbird_lexical_search_lab_url
    attr_accessor :blackbird_lexical_search_hmac_key

    # Configuration options for blackbird analysis
    attr_accessor :blackbird_disable_analysis
    attr_accessor :blackbird_mw_analysis_url
    attr_accessor :blackbird_mw_analysis_lab_url
    attr_accessor :blackbird_mw_analysis_hmac_key

    # Configuration options for blackbird embeddings search
    attr_accessor :blackbird_semantic_search_url
    attr_accessor :blackbird_semantic_search_lab_url
    attr_accessor :blackbird_semantic_search_hmac_key

    # Configuration options for windbeam service
    attr_accessor :windbeam_twirp_url
    attr_accessor :windbeam_hmac_key

    # String URL of the treelights syntax highlighting service
    attr_accessor :treelights_url

    # Credentials for mobile in-app purchases.
    attr_accessor :google_iap_service_account_key

    # Temporary configurations for more stringent issue creation rate limits.
    attr_accessor :issue_creation_rate_limit_configuration
    attr_accessor :discussion_creation_rate_limit_configuration

    # Configuration for the authnd service.
    attr_accessor :authnd_service_url
    attr_accessor :authnd_service_connection_timeout
    attr_accessor :authnd_service_response_timeout
    attr_accessor :authnd_service_hmac_key
    attr_accessor :authnd_token_exchange_secret
    attr_accessor :authnd_issue_token_retryable
    attr_accessor :authnd_request_max_attempts
    attr_accessor :authnd_request_wait_seconds
    attr_accessor :authnd_retry_proto_errors

    # Secret Scanning
    attr_accessor :secret_scanning_v1_api_encryption_keys_delimited
    attr_accessor :secret_scanning_encrypted_secrets_delimited_shared_transit_keys
    attr_accessor :secret_scanning_user_content_delimited_encryption_root_keys

    # Securitty Center
    attr_accessor :security_center_export_azure_spn_client_secret
    attr_accessor :security_center_export_azure_spn_client_id
    attr_accessor :security_center_export_azure_spn_tenant_id
    attr_accessor :security_center_export_azure_storage_account_name
    attr_accessor :security_center_export_azure_storage_access_key
    attr_accessor :security_center_export_azure_blob_container

    # Codespaces
    attr_accessor :codespaces_app_key
    attr_accessor :codespaces_vm_secrets_app_key
    attr_accessor :codespaces_vscs_environment
    attr_accessor :codespaces_per_minute_rate_limit
    attr_accessor :codespaces_per_user_sales_demo_limit
    attr_accessor :codespaces_automated_testing_limit
    attr_accessor :codespaces_dockerhub_registry
    attr_accessor :codespaces_canonical_subscription
    attr_accessor :codespaces_storage_accounts
    attr_accessor :codespaces_token_encryption_key
    attr_accessor :codespaces_serverless_url
    attr_accessor :codespaces_serverless_allowed_auth_redirect_hosts
    attr_accessor :codespaces_serverless_developer_restricted_auth_redirect_hosts
    attr_accessor :codespaces_serverless_default_auth_redirect_host
    attr_accessor :codespaces_stamp_azure_geo

    # Copilot
    attr_accessor :copilot_jetbrains_language_server_auth_app_key
    attr_accessor :copilot_xcode_language_server_auth_app_key

    # Classroom
    attr_accessor :classroom_api_service_url
    attr_accessor :classroom_hmac_key

    # Configuration for the notifyd service.
    attr_accessor :notifyd_production_url
    attr_accessor :notifyd_hmac_key

    # Codespaces is not enabled in GHES
    # Codespaces is always enabled in tests, so that we continue to test Proxima scenarios
    # But we're temporarily pausing support for Proxima, so hide Codespaces from Proxima customers
    def codespaces_serverless_editor_enabled?
      return false if GitHub.enterprise?
      return true if Rails.env.test?  # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      !GitHub.multi_tenant_enterprise?
    end

    def ghas_enabled?
      GitHub.billing_enabled?
    end

    # Deployments configuration
    attr_accessor :deployments_dashboard_enabled
    def deployments_dashboard_enabled?
      GitHub.enterprise? && GitHub.deployments_dashboard_enabled
    end

    # Dependabot configuration
    attr_accessor :dependabot_url
    attr_accessor :dependabot_hmac_key

    attr_accessor :hosted_compute_ims_url_curated
    attr_accessor :hosted_compute_ims_url_customer
    attr_accessor :hosted_compute_ims_hmac_key

    # PackageRegistry configuration
    attr_accessor :package_registry_url
    attr_accessor :package_registry_metadata_hmac_key
    attr_accessor :package_registry_action_packages_hmac_key

    # ContainerRegistry configuration
    attr_accessor :container_registry_url
    attr_accessor :container_registry_hmac_key

    # Token scanning service configuration
    attr_accessor :token_scanning_url
    attr_accessor :token_scanning_scans_api_url
    attr_accessor :token_scanning_staging_url
    attr_accessor :token_scanning_hmac_key

    # Trust Metadata API configuration
    attr_accessor :trust_metadata_url
    attr_accessor :trust_metadata_hmac_key
    attr_accessor :trust_metadata_client_id

    # Octoshift configuration
    attr_accessor :octoshift_url
    attr_accessor :octoshift_hmac_key

    attr_accessor :octoshift_staging_url
    attr_accessor :octoshift_staging_hmac_key

    attr_accessor :octoshift_review_lab_url
    attr_accessor :octoshift_review_lab_hmac_key

    attr_accessor :octoshift_load_testing_url
    attr_accessor :octoshift_load_testing_hmac_key

    attr_accessor :octoshift_importable_creation_rate_limit_configuration
    attr_accessor :octoshift_freno_max_replication_delay_ms

    # MigrationsVNext (ELM) configuration
    attr_accessor :migrations_vnext_hmac_key

    # GitHub Source Migrator
    attr_accessor :git_src_migrator_url
    attr_accessor :git_src_migrator_hmac_key

    attr_accessor :git_src_migrator_staging_url
    attr_accessor :git_src_migrator_staging_hmac_key

    attr_accessor :git_src_migrator_review_lab_url
    attr_accessor :git_src_migrator_review_lab_hmac_key

    # Export API configuration
    attr_accessor :migrations_blob_storage_type
    attr_accessor :migrations_azure_connection_string
    attr_accessor :migrations_aws_access_key
    attr_accessor :migrations_aws_secret_key
    attr_accessor :migrations_s3_bucket
    attr_accessor :migrations_aws_service_url

    # GitHub-owned storage for Octoshift
    attr_accessor :gei_archives_blob_storage_type
    attr_accessor :gei_archives_aws_access_key_id
    attr_accessor :gei_archives_aws_secret_access_key

    # Meuse configuration
    attr_accessor :meuse_hmac_secret_key

    # Billing Platform configuration
    attr_accessor :billing_platform_hmac_secret_key
    attr_accessor :billing_platform_host

    # Licensing configuration
    attr_accessor :licensing_azure_spn_tenant_id
    attr_accessor :licensing_azure_spn_client_id
    attr_accessor :licensing_azure_spn_client_secret
    attr_accessor :licensing_azure_storage_account_name

    # Licensify configuration
    attr_accessor :licensify_hmac_key
    attr_accessor :licensify_host

    # Metered Billing
    attr_accessor :metered_billing_azure_spn_client_secret
    attr_accessor :metered_billing_azure_spn_client_id
    attr_accessor :metered_billing_azure_spn_tenant_id
    attr_accessor :metered_billing_azure_storage_account_name

    # Account Management Billing
    attr_accessor :account_management_azure_spn_client_secret
    attr_accessor :account_management_azure_spn_client_id
    attr_accessor :account_management_azure_spn_tenant_id
    attr_accessor :account_management_azure_storage_account_name

    # actions-usage-metrics configuration
    attr_accessor :actions_usage_metrics_host
    attr_accessor :actions_usage_metrics_lab_hmac_key
    attr_accessor :actions_usage_metrics_production_hmac_key

    # GitBackups configuration
    attr_accessor :gitbackupsd_url

    # TurboGHAS configuration
    attr_accessor :turboghas_freno_max_replication_delay_ms

    # Can users opt in to view repos that have been flagged as
    # objectionable?
    def opt_in_to_restricted_repo_enabled?
      !enterprise?
    end

    # Global advisories URL - Enterprise doesn't serve global advisories so
    # when the full URL is required, we need to use https://github.com.
    #
    # Returns the URL string ("https://github.com", or whatever GitHub.url returns)
    def global_advisories_url
      if enterprise?
        "#{GitHub.dotcom_host_protocol}://#{GitHub.dotcom_host_name}"
      else
        url
      end
    end

    # Private Registry Secrets configuration
    attr_accessor :private_registry_secrets_app_key


    # ======================================================================== #
    #                         END OF CONFIG OPTIONS                            #
    # ======================================================================== #

    ##
    # Utilities

    # The environment configuration. In dotcom production, this is backed by the
    # gpanel `.app-config/production.plain` file directly rather than using ENV,
    # and supports per-datacenter prefixes.
    # In all other cases it's simply a wrapper for ENV.
    def environment
      return @environment if @environment
      @environment = Config::PrefixEnvironment.new
    end
    attr_writer :environment

    # Reload the config.yml values and set each config attribute.
    def reload_config
      import_yaml_config "#{GitHub::AppEnvironment.root}/config.yml"
    end

    # Load config written to disk by heaven gPanel support
    def reload_gpanel_config
      gpanel_config = "#{GitHub::AppEnvironment.root}/.app-config/#{GitHub::AppEnvironment.env}.rb"
      if File.file? gpanel_config
        load gpanel_config
        @environment = nil
      end
    end

    # Reset all memoized configuration variables to an undefined state, causing
    # them to be re-established the next time their accessed. This also calls
    # #reload_config to load in config values from the global and environment
    # config.yml files.
    def reset_config!
      instance_variables.each { |varname| remove_instance_variable(varname) }
      # reset ldap so we can reload the config.
      load_environment_config
    end

    # Loads the environment specific config file. The RAILS_ROOT/config.yml
    # values are loaded twice: before the environment config so that global
    # config is initially available for the environment file, and after the
    # environment config so that global values override environment values.
    def load_environment_config
      if defined? GitHub::AppEnvironment.env
        reload_config

        reload_gpanel_config

        # Enterprise doesn't ship production.rb environment file to avoid exposing
        # sensitive credentials.
        load "github/config/environments/default.rb" if multi_tenant_enterprise?
        load "github/config/environments/#{GitHub::AppEnvironment.env}.rb" unless GitHub::AppEnvironment.production? && single_or_multi_tenant_enterprise?
        load "github/config/environments/enterprise.rb" if single_tenant_enterprise?

        # load the config.yml values in over the environment specific config.
        reload_config
      else
        raise LoadError, "GitHub::AppEnvironment.env is not set"
      end
    end

    # Imports config values from the YAML file specified into the current
    # config. The config file may include values for any attributes defined in
    # this module.
    #
    # file - The string path to the YAML file to load.
    #
    # Returns nothing.
    # Raises RuntimeError when the config file includes an unknown key.
    #
    # Examples:
    #   The following YAML file would cause the ssl config attribute to be set
    #   true and the host_name attribute to be set to "github.apple.com":
    #
    #   ssl:       true
    #   host_name: github.apple.com
    def import_yaml_config(file)
      load_yaml_config(file).each do |key, value|
        if respond_to?("#{key}=")
          __send__(:"#{key}=", value) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
        else
          fail "unknown config value: #{key.inspect}"
        end
      end
    end

    # Load a YAML file if it exists and return its deserialized contents.
    #
    # Returns a Hash of config values.
    def load_yaml_config(file)
      if !GitHub::AppEnvironment.test? && File.exist?(file)
        require "yaml"
        YAML.load_file(file) || {}
      else
        {}
      end
    end

    # Public: Determine whether the limit in mentioned users in
    # comments/issues/pull request... is enabled or no.
    #
    # Enterprise is the most common case where we want to disable the spam
    # validation because the number of users are determined by the license.
    def prevent_mention_spam?
      !enterprise?
    end

    # Revoke OAuth accesses and SSH keys for new staff?
    def new_staff_precautions?
      !GitHub.single_or_multi_tenant_enterprise?
    end

    # We only want to enforce employee requirements when this is *not*
    # Enterprise.
    def require_employee_for_site_admin?
      !GitHub.single_or_multi_tenant_enterprise?
    end

    def require_two_factor_for_site_admin?
      return @require_two_factor_for_site_admin if defined? @require_two_factor_for_site_admin

      if Rails.env.development? || Rails.env.test? || GitHub.environment["DISABLE_TWO_FACTOR_FOR_SITE_ADMIN"]
        @require_two_factor_for_site_admin = false
      else
        @require_two_factor_for_site_admin = !single_or_multi_tenant_enterprise? || GitHub.global_business&.two_factor_requirement_enabled?
      end
    end
    attr_writer :require_two_factor_for_site_admin

    # No 2FA SMS in enterprise
    def two_factor_sms_enabled?
      !enterprise?
    end

    def sign_in_analysis_enabled?
      !single_or_multi_tenant_enterprise?
    end

    def passkeys_enabled?
      return false unless GitHub.ssl
      return false if enterprise? && (!GitHub.enterprise_passkeys_enabled || !GitHub.auth.allow_builtin_users?)
      true
    end

    # If we are tracking authentication records and devices, IP-based rate
    # limits aren't as effective as device verification.
    def web_ip_lockouts_enabled?
      !sign_in_analysis_enabled?
    end

    def weak_password_checking_enabled?
      !enterprise?
    end

    def strict_authentication_records?
      sign_in_analysis_enabled? && Rails.env.test?
    end

    # See https://developer.github.com/changes/2019-11-05-deprecated-passwords-and-authorizations-api/
    def authorization_apis_and_password_authentication_deprecated?
      !GitHub.enterprise?
    end

    # Disable Mirror repos on Enterprise
    def mirrors_enabled?
      !enterprise?
    end

    # Enable unlimited git.maxobjectsize in Enterprise
    def unlimited_max_object_size_enabled?
      enterprise?
    end

    # A large number of users in an assignee list (e.g. in the pull request view)
    # can lead to a timeout. Therefore we limit the number to 1500 on dotcom.
    # This is calculated based on all but the very largest organizations/teams in
    # the installation as of 2015-03-06, plus a couple hundred for wiggle room.
    # Without this limit, the show_menu_content assignees partial won't load in
    # time.
    # On GHES customers have sometimes more users. Since GHES has a higher timeout
    # too we can be more gracious with this limit.
    def assignees_list_limit
      @assignees_list_limit ||= 1500
    end
    attr_writer :assignees_list_limit

    def cluster_web_server?
      return @cluster_web_server if defined? @cluster_web_server
      @cluster_web_server = false
    end
    attr_writer :cluster_web_server

    def cluster_git_server?
      return @cluster_git_server if defined? @cluster_git_server
      @cluster_git_server = false
    end
    attr_writer :cluster_git_server

    def cluster_pages_server?
      return @cluster_pages_server if defined? @cluster_pages_server
      @cluster_pages_server = false
    end
    attr_writer :cluster_pages_server

    # Base IPs for our physical datacenter that are used for
    # multiple purposes such as Git, Web, API & hooks
    def base_ips
      [
        "192.30.252.0/22",
        "185.199.108.0/22",
        "140.82.112.0/20",
        "143.55.64.0/20",
        "2a0a:a440::/29",
        "2606:50c0::/32",
      ]
    end

    # IP addresses that service hooks are sent from.
    #
    # This is returned from the API endpoint
    # and listed on the service hooks page.
    def hook_ips
      base_ips
    end

    # IPs used for web access. This is our datacenters plus vPOPs addresses for web traffic.
    def web_ips
      base_ips + [
        # azure-brazilsouth
        "20.201.28.151/32",
        # azure-southeastasia
        "20.205.243.166/32",
        # azure-southafricanorth
        "20.87.245.0/32",
        # edge-ae-01
        "4.237.22.38/32",
        # azure-centralindia
        "20.207.73.82/32",
        # azure-japaneast
        "20.27.177.113/32",
        # azure-koreacentral
        "20.200.245.247/32",
        # azure-test-vpop,
        "20.175.192.147/32",
        # azure-uaenorth
        "20.233.83.145/32",
        # edge-wus2-01
        "20.29.134.23/32",
        # edge-frc-01
        "20.199.39.232/32",
        # edge-ilc-01
        "20.217.135.5/32",
        # edge-sdc-01
        "4.225.11.198/32",
        # edge-ne-01
        "4.208.26.197/32",
        # edge-uks-01
        "20.26.156.215/32",
      ]
    end

    # Normal Git traffic goes over github.com so it's the same as the web UI IPs,
    # except for the git-ssh-over-port-443 IPs (ssh.github.com) which can also be used.
    def git_ips
      web_ips + [
        # azure-brazilsouth
        "20.201.28.152/32",
        # azure-southeastasia
        "20.205.243.160/32",
        # azure-southafricanorth
        "20.87.245.4/32",
        # edge-ae-01
        "4.237.22.40/32",
        # azure-centralindia
        "20.207.73.83/32",
        # azure-japaneast
        "20.27.177.118/32",
        # azure-koreacentral
        "20.200.245.248/32",
        # azure-test-vpop,
        "20.175.192.146/32",
        # azure-uaenorth
        "20.233.83.149/32",
        # edge-wus2-01
        "20.29.134.19/32",
        # edge-frc-01
        "20.199.39.227/32",
        # edge-ilc-01
        "20.217.135.4/32",
        # edge-sdc-01
        "4.225.11.200/32",
        # edge-ne-01
        "4.208.26.198/32",
        # edge-uks-01
        "20.26.156.214/32",
      ]
    end

    # IPs used for API access. This is our datacenters plus vPOPs addresses for API traffic.
    def api_ips
      base_ips + [
        # azure-brazilsouth
        "20.201.28.148/32",
        # azure-southeastasia
        "20.205.243.168/32",
        # azure-southafricanorth
        "20.87.245.6/32",
        # edge-ae-01
        "4.237.22.34/32",
        # azure-centralindia
        "20.207.73.85/32",
        # azure-japaneast
        "20.27.177.116/32",
        # azure-koreacentral
        "20.200.245.245/32",
        # azure-test-vpop,
        "20.175.192.149/32",
        # azure-uaenorth
        "20.233.83.146/32",
        # edge-wus2-01
        "20.29.134.17/32",
        # edge-frc-01
        "20.199.39.228/32",
        # edge-ilc-01
        "20.217.135.0/32",
        # edge-sdc-01
        "4.225.11.201/32",
        # edge-ne-01
        "4.208.26.200/32",
        # edge-uks-01
        "20.26.156.210/32",
      ]
    end

    def packages_ips
      [
        # fr5-fra
        "140.82.121.33/32",
        "140.82.121.34/32",
        # ac4-iad
        "140.82.113.33/32",
        "140.82.113.34/32",
        # ash1-iad
        "140.82.112.33/32",
        "140.82.112.34/32",
        # va3-iad
        "140.82.114.33/32",
        "140.82.114.34/32",
        # sdc42-sea
        "192.30.255.164/31",
        # azure-brazilsouth
        "20.201.28.144/32",
        # azure-southeastasia
        "20.205.243.164/32",
        # azure-southafricanorth
        "20.87.245.1/32",
        # edge-ae-01
        "4.237.22.32/32",
        # azure-centralindia
        "20.207.73.86/32",
        # azure-japaneast
        "20.27.177.117/32",
        # azure-koreacentral
        "20.200.245.241/32",
        # azure-test-vpop,
        "20.175.192.150/32",
        # azure-uaenorth
        "20.233.83.147/32",
        # edge-wus2-01
        "20.29.134.18/32",
        # edge-frc-01
        "20.199.39.231/32",
        # edge-ilc-01
        "20.217.135.1/32",
        # edge-sdc-01
        "4.225.11.196/32",
        # edge-ne-01
        "4.208.26.196/32",
        # edge-uks-01
        "20.26.156.211/32",
      ]
    end

    # IP addresses for GitHub Pages' A records.
    def pages_a_record_ips
      [
        "192.30.252.153/32",  # our data center
        "192.30.252.154/32",
        "185.199.108.153/32", # broadcast by Fastly
        "185.199.109.153/32",
        "185.199.110.153/32",
        "185.199.111.153/32",
        "2606:50c0:8000::153/128",
        "2606:50c0:8001::153/128",
        "2606:50c0:8002::153/128",
        "2606:50c0:8003::153/128",
      ]
    end

    # IP addresses that GitHub Importer connects from.
    def github_source_importer_ips
      [
        "52.23.85.212/32", # nat-04b9886849dac338a eni-19e78fb8 vpc-e8d38291 / vpc-us-east-1
        "52.0.228.224/32", # nat-0886764cc12487f84 eni-35cbc29e vpc-e8d38291 / vpc-us-east-1
        "52.22.155.48/32", # nat-04cb773927da3638c eni-687b8ebc vpc-e8d38291 / vpc-us-east-1
        "20.75.217.40/29", # GitHub Actions runner `git-src-migrator-source-imports` owned by the `git-src-migrator-actions` organization for `git-src-migrator` migrations
        "20.69.67.168/29", # GitHub Actions runner `git-src-migrator-source-imports` owned by the `git-src-migrator-actions` organization for `git-src-migrator` migrations
      ]
    end

    # IP addresses that GitHub Enterprise Importer uses for outbound connections
    def github_enterprise_importer_ips
      hook_ips + [
        # GitHub Actions large runners owned by the `git-src-migrator-actions` organization
        "40.71.233.224/28",
        "20.125.12.8/29",
      ]
    end

    def dependabot_ips
      [
        "18.213.123.130/32",
        "3.217.79.163/32",
        "3.217.93.44/32",
      ]
    end

    # IP addresses required for Copilot IDE Code Completions and Copilot IDE Chat
    def copilot_ips
      base_ips + [ # base_ips incorporates kube-public in the DCs
        "20.85.130.105/32", # azure-eastus kube-public
        "4.237.22.41/32", # edge-ae-01 kube-public
        "4.249.131.160/32", # edge-cus-01 kube-public
        "20.199.39.224/32", # edge-frc-01 kube-public
        "52.175.140.176/32", # edge-jpw-01 kube-public
        "4.225.11.192/32", # edge-sdc-01 kube-public
        "20.250.119.64/32", # edge-szn-01 kube-public
        "138.91.182.224/32", # edge-wus-01 kube-public
        "13.107.5.93/32", # default.exp-tas.com
      ]
    end

    # Domain names for given products, wildcard (single-level subdomain SSL style)
    # Intended for use by administrators of networks that do SSL inspection
    # and filter based on hostname
    # referenced from docs:
    #     allowing-access-to-githubs-services-from-a-restricted-network.md
    # and published in meta API
    def dnsdomains
      dns_domains = {
        "website" =>
          [
            "*.github.com",
            "*.github.dev",
            "*.github.io",
            "*.githubassets.com",
            "*.githubusercontent.com",
        ],
        "codespaces" =>
          [
            "*.github.com",
            "*.api.github.com",
            "*.azureedge.net",
            "*.github.dev",
            "*.msecnd.net",
            "*.visualstudio.com",
            "*.vscode-webview.net",
            "*.windows.net",
            "*.microsoft.com",
          ],
        "copilot" =>
          [
            "*.github.com",
            "*.githubusercontent.com",
            "default.exp-tas.com",
            "*.githubcopilot.com",
          ],
        "packages" =>
          [
            "mavenregistryv2prod.blob.core.windows.net",
            "npmregistryv2prod.blob.core.windows.net",
            "nugetregistryv2prod.blob.core.windows.net",
            "rubygemsregistryv2prod.blob.core.windows.net",
            "npm.pkg.github.com",
            "npm-proxy.pkg.github.com",
            "npm-beta-proxy.pkg.github.com",
            "npm-beta.pkg.github.com",
            "nuget.pkg.github.com",
            "rubygems.pkg.github.com",
            "maven.pkg.github.com",
            "docker.pkg.github.com",
            "docker-proxy.pkg.github.com",
            "containers.pkg.github.com",
            "*.github.com",
            "*.pkg.github.com",
            "*.ghcr.io",
            "*.githubassets.com",
            "*.githubusercontent.com",
          ],
        # deprecated list of domains, see actions_all_domains.rb for the live list
        "actions" =>
          [
            "*.actions.githubusercontent.com",
            "productionresultssa0.blob.core.windows.net",
            "productionresultssa1.blob.core.windows.net",
            "productionresultssa2.blob.core.windows.net",
            "productionresultssa3.blob.core.windows.net",
            "productionresultssa4.blob.core.windows.net",
            "productionresultssa5.blob.core.windows.net",
            "productionresultssa6.blob.core.windows.net",
            "productionresultssa7.blob.core.windows.net",
            "productionresultssa8.blob.core.windows.net",
            "productionresultssa9.blob.core.windows.net",
            "productionresultssa10.blob.core.windows.net",
            "productionresultssa11.blob.core.windows.net",
            "productionresultssa12.blob.core.windows.net",
            "productionresultssa13.blob.core.windows.net",
            "productionresultssa14.blob.core.windows.net",
            "productionresultssa15.blob.core.windows.net",
            "productionresultssa16.blob.core.windows.net",
            "productionresultssa17.blob.core.windows.net",
            "productionresultssa18.blob.core.windows.net",
            "productionresultssa19.blob.core.windows.net",
            "gel7acprodeus1file0.blob.core.windows.net",
            "si05acprodeus1file1.blob.core.windows.net",
            "aw97acprodeus1file2.blob.core.windows.net",
            "mp1yacprodeus1file3.blob.core.windows.net",
            "n06iacprodeus1file4.blob.core.windows.net",
            "ki6cacprodeus1file5.blob.core.windows.net",
            "95s5acprodeus1file6.blob.core.windows.net",
            "gk2hacprodeus1file7.blob.core.windows.net",
            "vth0acprodeus2file0.blob.core.windows.net",
            "frsnacprodeus2file1.blob.core.windows.net",
            "4qfyacprodeus2file2.blob.core.windows.net",
            "kv4gacprodeus2file3.blob.core.windows.net",
            "1k4dacprodeus2file4.blob.core.windows.net",
            "sd5kacprodeus2file5.blob.core.windows.net",
            "y2oiacprodeus2file6.blob.core.windows.net",
            "prtcacprodeus2file7.blob.core.windows.net",
          ] + GitHub.actions_scale_unit_domains,
        "artifact_attestations" => GitHub::Config::ArtifactAttestations.meta_info,
      }

      if GitHub.flipper[:actions_inbound_meta].enabled?
        dns_domains["actions_inbound"] = GitHub::Config::ActionsInbound.meta_info
      end

      dns_domains
    end

    # Public: Is scientist enabled?
    #
    # In enterprise, returns false
    # In production, checks the configured region
    # Otherwise returns true
    def scientist_enabled?
      if GitHub.enterprise?
        false
      elsif Rails.env.production?
        scientist_region == GitHub.server_region
      else
        true
      end
    end

    # Public: What region is scientist enabled for?
    #
    # Until such time as scientist's back-end storage system is changed
    # to handle multiple region, only run scientist in one region,
    # configured via SCIENTIST_REGION.
    def scientist_region
      GitHub.environment["SCIENTIST_REGION"]
    end

    # Public: Is performance profiling enabled?
    attr_accessor :profiling_enabled
    alias profiling_enabled? profiling_enabled

    # Public: Is the performance stats UI enabled?
    attr_accessor :stats_ui_enabled
    alias stats_ui_enabled? stats_ui_enabled

    # Public: which repository networks do we never want to be considered public?
    #
    # This allows us to provide an extra level of protection to make sure GitHub's
    # most sensitive repositories aren't accidentally turned public.  So, even
    # if visibility is toggled on these, they will always be treated as private
    # repositories.
    def never_public_networks
      return [].freeze if GitHub.enterprise?

      ["github/github", "github/puppet"].freeze
    end

    # Public: the ids of the repository networks we never want to be considered public
    def never_public_network_ids
      return @never_public_network_ids if defined? @never_public_network_ids

      networks = GitHub.never_public_networks
      ids = networks.map { |nwo| Repository.nwo(nwo).try(:network_id) }
      @never_public_network_ids = ids.compact.uniq.freeze
    end

    def reset_never_public_network_ids
      remove_instance_variable :@never_public_network_ids if defined? @never_public_network_ids
    end

    # Public: which repositories do we never want to delete?
    #
    # This allows us to provide an extra level of protection to make sure GitHub's
    # most sensitive repositories aren't accidentally deleted.
    def never_delete
      return [].freeze if GitHub.enterprise?

      ["github/github", "github/puppet"].freeze
    end

    # Public: the ids of the repositories we never want to delete
    def never_delete_ids
      return @never_delete_ids if defined? @never_delete_ids

      repos = GitHub.never_delete
      ids = repos.map { |nwo| Repository.nwo(nwo).try(:id) }
      @never_delete_ids = ids.compact.uniq.freeze
    end

    def reset_never_delete_ids
      remove_instance_variable :@never_delete_ids if defined? @never_delete_ids
    end

    # Accounts or people that work for GitHub that we don't want
    # to publicly display as staff or be present on the team page.
    def hidden_teamsters
      @hidden_teamsters ||= %w(evilshawn ghmonitor gregose-tmp hubot ice799 maki1022 mayashino monitors StreamingEagle boxen-ci btoews)
    end

    def hidden_teamster?(user)
      hidden_teamsters.include?(user.login)
    end

    def max_business_footer_count
      MAX_BUSINESS_FOOTER_COUNT
    end

    def max_ui_pagination_page
      MAX_UI_PAGINATION_PAGE
    end

    # Disabled by default in development and Enterprise.
    def content_creation_rate_limiting_enabled?
      return @content_creation_rate_limiting_enabled if defined?(@content_creation_rate_limiting_enabled)
      @content_creation_rate_limiting_enabled = !(GitHub.enterprise? || Rails.env.development? || ENV["CONTENT_CREATION_RATE_LIMITING_DISABLED"].present?)
    end
    attr_writer :content_creation_rate_limiting_enabled

    # Request parameters to filter from logs and exceptions
    #
    # These are filtered by Rails based on a substring match
    def filtered_params
      [:password, :token, :credit_card, :value, :oauth_verifier, :bt_signature, :client_secret]
    end

    # Closure for creating an allowlist for Rails log filtering.
    # We only log things in the allowlist here.
    def filtered_params_proc
      lambda do |key, value|
        unless key =~ ALLOWED_PARAMETERS
          value.replace(SANITIZED_VALUE) if value.respond_to?(:replace)
        end
      end
    end

    def rails_version_major
      Rails::VERSION::MAJOR
    end
    private :rails_version_major

    def rails_version_minor
      Rails::VERSION::MINOR
    end
    private :rails_version_minor

    def origin_verification_enabled?
      # Codespaces forward requests from
      # ID-PORT.apps.codespaces.githubusercontent.com URL to localhost which
      # breaks origin verification.
      return false if ENV["CODESPACES"]
      !enterprise?
    end

    # When SameSite cookie support is first deployed, any initial request that
    # does CSRF validation will fail, since the strict SameSite cookie will not
    # be set yet. This isn't a problem for dotcom, as we currently hide this
    # feature behind a feature flag. So, we will have several weeks to allow all
    # users to start receiving both the normal session cookie AND the new strict
    # SameSite cookie. As a result, we can be confident everyone already has
    # both cookies when we ship the feature. But, on Enterprise, this isn't the
    # case. So, for now, we will disable support. Maybe we can enable it after a
    # few releases and/or if we warn people when they upgrade.
    def same_site_cookie_verification_enabled?
      !enterprise? && same_site_cookie_enabled?
    end

    # Even if we are not validating SameSite cookies (i.e.
    # `same_site_cookie_verification_enabled?` is `false`), we can still set the
    # cookie for future use. However, since we are using cookie prefixes with
    # our SameSite cookie implementation, we choose to only set the SameSite
    # cookie for installations that have SSL enabled.
    def same_site_cookie_enabled?
      ssl?
    end

    def cookie_allowlist_enforced?
      Rails.env.development? || Rails.env.test? || GitHub.flipper[:cookie_allowlist_enforcement].enabled?
    end

    # For environments where we control the IPs in use we leverage IP
    # restrictions as a belt and suspenders protection.
    def remote_ip_restrictions_enabled?
      !enterprise?
    end

    def experiments_graphql_enabled?
      return @experiments_graphql_enabled if defined?(@experiments_graphql_enabled)
      @experiments_graphql_enabled = true
    end
    attr_writer :experiments_graphql_enabled

    def flipper_graphql_enabled?
      return @flipper_graphql_enabled if defined?(@flipper_graphql_enabled)
      @flipper_graphql_enabled = true
    end
    attr_writer :flipper_graphql_enabled

    def flipper_ui_enabled?
      return @flipper_ui_enabled if defined?(@flipper_ui_enabled)
      @flipper_ui_enabled = true
    end
    attr_writer :flipper_ui_enabled

    # In production, the feature flipper cache is never cleared, and is just allowed
    # to expire. But in non-production environments, we may want feature flipper changes to actors
    # to be applied immediately (e.g. in tests), so that's what this flag controls.
    attr_accessor :flippers_should_clear_actor_cache

    def request_limiting_enabled?
      @request_limiting_enabled
    end
    attr_writer :request_limiting_enabled

    def chatterbox_enabled?
      return @chatterbox_enabled if defined?(@chatterbox_enabled)
      @chatterbox_enabled = true
    end
    attr_writer :chatterbox_enabled

    def allow_cross_origin_referrer_leak?
      !enterprise?
    end

    def read_only?
      return true if Thread.current[:github_read_only_mode]
      return @read_only if defined?(@read_only)

      @read_only = File.exist?(Rails.root.join("tmp/readonly.txt"))
    end
    attr_writer :read_only

    def job_coordination_redis_disabled?
      return @job_coordination_redis_disabled unless @job_coordination_redis_disabled.nil?

      @job_coordination_redis_disabled = GitHub.environment["#{GitHub.role.upcase}_JOB_COORDINATION_REDIS_DISABLED"] == "1"
    end

    def reset_job_coordination_redis_disabled
      @job_coordination_redis_disabled = nil
    end

    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def rate_limiter_redis_disabled?
      @rate_limiter_redis_disabled ||= GitHub.environment["#{GitHub.role.upcase}_RATE_LIMITER_REDIS_DISABLED"] == "1"
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    def reset_rate_limiter_redis_disabled
      @rate_limiter_redis_disabled = nil
    end

    # Given a github host, attempt to determine the site. Originally added to
    # allow for tagging the rpc_site on all MySQL queries to aid in determining
    # cross-site queries.
    #
    # Examples:
    #
    #   GitHub.site_from_host("db-mysql-9082342.ash-iad.github.net") => "ash1-iad"
    #   GitHub.site_from_host("db-mysql-c0c881d.sdc42-sea.github.net") => "sdc42-sea"
    #
    # Returns String representing the site of the host.
    def site_from_host(host)
      # end_with? in a loop is 5x faster than using a regex in the current
      # worst case (with 3 sites). If we ever have more than 15 sites this
      # should be revisited.
      SITE_LIST.each do |suffix, site|
        return site if host.end_with?(suffix)
      end if host
      "unknown"
    end

    def serviceowners
      return @serviceowners if defined?(@serviceowners)

      @serviceowners = if !GitHub.enterprise?
        begin
          GitHub::Serviceowners.new
        rescue Errno::ENOENT
          nil
        end
      end
    end

    def packageowners
      return @packageowners if defined?(@packageowners)

      @packageowners = GitHub::Serviceowners::Packageowners.new
      @packageowners.populate_tables # warm up cache
      @packageowners
    end

    def programmatic_access_definitions
      return @programmatic_access_definitions if defined?(@programmatic_access_definitions)

      if Rails.env.production?
        @programmatic_access_definitions = Apps::ProgrammaticAccessDefinitions.empty
        return @programmatic_access_definitions
      end

      @programmatic_access_definitions = if programmatic_access_definitions_path.exist?
        Apps::ProgrammaticAccessDefinitions.new(Apps::ProgrammaticAccessDefinitions.load_yaml)
      else
        Apps::ProgrammaticAccessDefinitions.empty
      end
    end

    def programmatic_access_definitions_path
      @programmatic_access_definitions_path ||= Rails.root.join("config/access_control/programmatic_access.yaml")
    end

    # Is operator mode enabled for all users?
    #
    # When operator mode is enabled, debugging output is displayed to the
    # client during Git push operations.
    def global_operator_mode_enabled?
      !!@global_operator_mode_enabled
    end
    attr_writer :global_operator_mode_enabled

    # Ops gets paged if there's < 10 GB available
    SHARD_SLACK_SPACE = 15.0 * (1 << 30)

    ENTERPRISE_SHARD_SLACK_SPACE = 2 * (1 << 30)

    # The amount of slack disk space required
    # on fileservers, in KB.
    def shard_slack_space
      gb = if GitHub.enterprise?
        ENTERPRISE_SHARD_SLACK_SPACE
      else
        SHARD_SLACK_SPACE
      end

      gb / (1 << 10)
    end

    # What port should we use in the upstream for proxies when pointing mysql
    # in the app at toxiproxy. Checks for env var, then falls back to mysql's
    # default port.
    #
    # NOTE: This is only used for develompment, test and ci to simulate network
    # issues by proxying through toxiproxy.
    def toxiproxy_upstream_mysql_port
      @toxiproxy_upstream_mysql_port ||= ENV.fetch("TOXIPROXY_UPSTREAM_MYSQL_PORT", 3306)
    end
    attr_writer :toxiproxy_upstream_mysql_port

    def cas_host
      url_origin(cas_url)
    end

    # Allow overriding the number of accesses an OAuth application is allowed to
    # create for a given app/user/scope combination.
    def oauth_access_limit_overrides_enabled?
      Rails.env.production? && !enterprise?
    end

    # Whether or not this server will primarily run gitauth requests
    def gitauth_host?
      !!ENV["GITAUTH"]
    end

    # The number of unicorn workers to run on an enterprise instance.
    def enterprise_unicorn_worker_count
      if gitauth_host?
        (ENV["ENTERPRISE_GITAUTH_WORKERS"] || 1).to_i
      else
        (ENV["ENTERPRISE_GITHUB_WORKERS"] || 4).to_i
      end
    end

    # This host is a staff host
    def staff_host?
      ENV["STAFF_ENVIRONMENT"] != nil || local_host_name.split(".").first =~ /^github-staff\d+/
    end

    # Checks if the staff host is a review lab
    def review_lab?
      lab_type == "review-lab"
    end

    # Traffic mirroring
    # Checks if the deployment is shadow lab
    def shadow_lab?
      deployed_to == "shadow-lab"
    end

    def deploy_to_frontend_unicorn?
      ENV["OTEL_SERVICE_NAME"] == "github-unicorn"
    end

    # The parsed contents of /etc/github/metadata.json (a Hash), or nil
    def server_metadata
      return @_parsed_metadata_json if defined?(@_parsed_metadata_json)
      begin
        @_parsed_metadata_json = read_metadata
      rescue # rubocop:todo Lint/GenericRescue
        @_parsed_metadata_json = {}
      end
    end

    # The region where the server is located
    def server_region
      return @server_region if defined?(@server_region)
      @server_region = server_metadata["region"]
    end
    attr_writer :server_region

    # The site where the server is located
    def server_site
      return @server_site if defined?(@server_site)
      @server_site = server_metadata["site"]
    end
    attr_writer :server_site

    # This host is running in production
    def production_host?
      server_metadata["env"] == "production"
    end

    # The number of unicorn workers to spin up for this server.
    def unicorn_worker_count
      if (worker_count = ENV["GH_UNICORN_WORKER_COUNT"])
        return worker_count.to_i
      end

      worker_count = begin
        Integer(File.read("/etc/github/unicorn_worker_count"))
      rescue Errno::ENOENT, Errno::EPERM, ArgumentError
        nil
      end
      unless worker_count.nil?
        return worker_count
      end

      if GitHub.enterprise? && GitHub::AppEnvironment.production?
        return enterprise_unicorn_worker_count
      end

      if staff_host?
        return 6
      end

      if gitauth_host?
        return (ENV["GITAUTH_WORKER_COUNT"] || 1).to_i unless GitHub::AppEnvironment.production?
        return 12 if production_host?
        return 2
      end

      if GitHub::AppEnvironment.production?
        return (2 * Etc.nprocessors) if production_host?
        return 4
      end
      2
    end

    # Should unicorn do its check_client_connection thing?
    # https://engineering.shopify.com/17489012-what-does-your-webserver-do-when-a-user-hits-refresh#axzz2q3YWu2Jr
    # Enable Unicorn check_client_connection configuration. See this issue for more details:
    # https://github.com/github/performance-engineering/issues/1250
    def unicorn_check_client_connection?
      GitHub::AppEnvironment.development? || GitHub::AppEnvironment.test? || ENV["UNICORN_CHECK_CLIENT_CONNECTION_ENABLED"] == "1"
    end

    def update_protected_branches_setting_enabled?
      return @update_protected_branches_setting_enabled if defined?(@update_protected_branches_setting_enabled)
      false
    end
    attr_writer :update_protected_branches_setting_enabled

    def diff_analysis_url
      ENV["DIFF_ANALYSIS_URL"] || @diff_analysis_url
    end
    attr_writer :diff_analysis_url

    # Returns true if Elastomer (Elasticsearch) based code search should be used.
    def use_elastomer_code_search?
      single_tenant_enterprise?
    end

    # Returns true if we are in the production profiling lab or if we are in the LUC dedicated nodes with profiling
    # capabilities
    def continuous_profiling?
      (server_metadata["kubernetes_node_pool"] == "performance-testing" && ENV["LUC_PERFORMANCE"] == "1") || server_metadata["kubernetes_node_pool"] == "profiling-lab"
    end

    # Returns `true` if indexing of source code is currently enabled. Returns
    # `false` if it has been disabled.
    #
    # Defaults to true if KV is unavailable.
    def code_search_indexing_enabled?
      1 == Search::KV.store.get(::Search::CODE_SEARCH_INDEXING_KEY).value { 1 }.to_i
    end

    def repository_advisories_enabled?
      # TODO: Temporarily de-memoized in order to FF proxima functionality
      #
      ## return @repository_advisories_enabled if defined? @repository_advisories_enabled
      @repository_advisories_enabled = if GitHub.multi_tenant_enterprise?
        GitHub.flipper[:proxima_repository_advisories].enabled?
      elsif dotcom_request?
        true
      else
        !!ENV["ENTERPRISE_REPOSITORY_ADVISORIES"]
      end
    end

    # Private Vulnerability Reporting is only applicable to public, open-source repositories,
    # thus it is not applicable to Single or Multi-Tenant enterprise environments.
    def private_vulnerability_reporting_enabled?
      return @private_vulnerability_reporting_enabled if defined? @private_vulnerability_reporting_enabled
      @private_vulnerability_reporting_enabled = !GitHub.single_or_multi_tenant_enterprise? && repository_advisories_enabled?
    end

    # Determine if Dependabot is enabled.
    # Enabled by default in dotcom, disabled for enterprise, except if explicitly enabled via ghe config apply.
    #
    # Returns true if enabled, false otherwise.
    def dependabot_enabled?
      return @dependabot_enabled if defined? @dependabot_enabled
      @dependabot_enabled = !GitHub.enterprise?
    end
    attr_writer :dependabot_enabled

    # Determin if Dependabot rules is enabled.
    # Enabled by default in dotcom and enterprise, except if explicitly disabled via ghe config apply (in enterprise)
    #
    # Returns true if enabled, false otherwise.
    def dependabot_rules_enabled?
      return @dependabot_rules_enabled if defined? @dependabot_rules_enabled
      @dependabot_rules_enabled = !GitHub.enterprise?
    end
    attr_writer :dependabot_rules_enabled

    # Munger is an application that provides access to data from the data
    # science pipeline: https://github.com/github/munger
    # It is used for things like getting topic suggestions in the GitHub.com
    # environment and doesn't run on Enterprise.
    def munger_available?
      return false if enterprise?
      return true if Rails.env.test?
      munger_url.present?
    end

    # The topics data API is supplied by the github/munger application
    attr_accessor :munger_url

    # Whether to log the call stack when auto_fqdn is called
    attr_accessor :log_auto_fqdn_caller

    # Whether or not this is a Kubernetes cluster. To determine this, we look
    # for a file created by the ServiceAccountAdmissionController.
    # https://kubernetes.io/docs/admin/service-accounts-admin/#service-account-admission-controller
    def kube?
      return @kube if defined?(@kube)
      namespace_file = "/var/run/secrets/kubernetes.io/serviceaccount/namespace"
      @kube = File.file?(namespace_file)
    end

    def kubernetes_cluster_name
      server_metadata["kubernetes_cluster_name"]
    end

    def lab_type
      ENV["STAFF_ENVIRONMENT"]
    end

    # Shared ready-state file for the last unicorn worker to indicate starup
    # success and unlock the /status endpoint in kube installations.
    def kube_workers_ready_file
      Rails.root.join("tmp/unicorn-workers.ready")
    end

    # Dynamic labs can be created on-the-fly by users for exploratory testing,
    # and thus don't have a fixed domain. This method can be used to determine
    # whether or not the application is running in such a context, detected by
    # the presence of a DYNAMIC_LAB_NAME and/or DYNAMIC_LAB_NAME environment
    # variable. The *type* of lab can be determined with the lab_type method.
    def dynamic_lab?
      ENV.has_key?("DYNAMIC_LAB_NAME")
    end

    # Dynamic labs are expected to be configured to serve requests on domains
    # like *.(staging|review)-lab.github.com. This method takes a domain string
    # argument and returns true if it looks like a dynamic lab domain. Use this
    # method only in situations where the dynamic_lab? is not sufficient.
    def dynamic_lab_domain?(domain)
      domain && domain.end_with?("-lab.github.com")
    end

    # Returns the root of the lab domain for use in cookies. Like
    # dynamic_lab_domain?, this method is designed to support multiple
    # dynamic labs on domains like *.(staging|review)-lab.github.com.
    def dynamic_lab_cookie_domain(domain)
      lab_domain_match = domain.match(/(\.(\w+)-lab\.github\.com)\z/)
      if lab_domain_match
        lab_domain_match[1]
      else
        raise ArgumentError
      end
    end

    # The value of the DYNAMIC_LAB_NAME environment variable. Will return an
    # empty string unless dynamic_lab? is true
    def dynamic_lab_name
      ENV.fetch("DYNAMIC_LAB_NAME", "")
    end

    # A temporary measure to assess if we're in a staging-lab. Using this until
    # dynamic_lab? returns true for staging labs
    def staging_lab?
      GitHub.host_domain == STAGING_DOMAIN
    end

    def kubernetes_namespace
      @kubernetes_namespace ||= ENV.fetch("KUBE_NAMESPACE", "unknown")
    end

    def kubernetes_pod_name
      @kubernetes_pod_name ||= ENV.fetch("FAILBOT_CONTEXT_KUBE_POD_NAME", "unknown")
    end

    def platform_graphql_service_tokens
      @platform_graphql_service_tokens ||= []
    end
    attr_writer :platform_graphql_service_tokens

    def platform_graphql_logging_enabled?
      @platform_graphql_logging_enabled || !GitHub.enterprise?
    end
    attr_writer :platform_graphql_logging_enabled

    def valid_graphql_service_token?(token)
      valid_token = T.let(false, T::Boolean)
      GitHub.platform_graphql_service_tokens.each do |t|
        if SecurityUtils.secure_compare(t, token)
          valid_token = true
        end
      end
      valid_token
    end

    def hookshot_payload_size_limit
      @hookshot_payload_size_limit = ENV.fetch("HOOKSHOT_PAYLOAD_SIZE_LIMIT", 26214400).to_i
    end
    attr_writer :hookshot_payload_size_limit

    def repository_quotas_enabled?
      return false if GitHub.enterprise?
      return @repository_quotas_enabled if defined?(@repository_quotas_enabled)
      @repository_quotas_enabled = true
    end
    attr_writer :repository_quotas_enabled

    # Public: Chunk size for web sockets. Breaks down a collection of web socket
    # related redis operations into a bounded chunk. Note that this number does
    # not equal the exact number of redis operations to pipeline, but rather the
    # collection size to pipeline of which each item in the collection could
    # cause one or more redis operations.
    def web_socket_chunk_size
      @web_socket_chunk_size ||= ENV.fetch("WEB_SOCKET_CHUNK_SIZE", 25_000).to_i
    end
    attr_writer :web_socket_chunk_size

    # Whether webhooks for User events are enabled
    def user_hooks_enabled?
      @user_hooks_enabled.nil? ? enterprise? : @user_hooks_enabled
    end
    attr_writer :user_hooks_enabled

    # Whether ghe-specific org hooks are enabled
    def extended_org_hooks_enabled?
      @extended_org_hooks_enabled.nil? ? enterprise? : @extended_org_hooks_enabled
    end
    attr_writer :extended_org_hooks_enabled

    # Public: The heaven enviroment the app is currently deployed to. Possible values
    # include `production` and `production/canary`. If the env var isn't set then we fall
    # back to the regular rails env.
    def heaven_env
      @heaven_env ||= ENV.fetch("HEAVEN_DEPLOYED_ENV", GitHub::AppEnvironment.env)
    end
    attr_writer :heaven_env

    def heaven_env_reset
      @heaven_env = nil
    end

    # Public: Figure out the specific env that the app is currently deployed to. This will
    # return the specific lab env (e.g. "garage", "lab", etc) or the production
    # env (e.g. "production", "prod/canary")
    def deployed_to
      @deployed_to ||= begin
        # kube will always have the correct env set from the heaven deploy
        return GitHub.heaven_env if GitHub.kube?

        # non-kube non-lab envs can use the default heaven env
        return GitHub.heaven_env unless GitHub.role_from_host == :lab

        # non-kube lab envs like garage should look at the sever metadata
        env = server_metadata.fetch("attributes", {})
        env = env.fetch("github", {})
        env.fetch("environment", :unknown)
      end
    end

    # Public: Format deployment environment for Failbot and Sentry
    def failbot_deployed_to
      return @failbot_deployed_to if defined?(@failbot_deployed_to)

      @failbot_deployed_to = GitHub.deployed_to.gsub(/\Aproduction\//, "")
    end

    # Public: Batch size for subscribing users. Breaks down an array of users into a bounded size.
    def subscribed_users_batch_size
      @subscribed_users_batch_size ||= ENV.fetch("SUBSCRIBED_USERS_BATCH_SIZE", 100).to_i
    end

    def deployed_to_reset
      @deployed_to = nil
    end

    # Public: Is GitHub Connect available in the current environment?
    #
    # GitHub Connect allows a GHES installation to request a connection to
    # GitHub.com for deeper integration.
    def dotcom_connection_enabled?
      return @dotcom_connection_enabled if defined?(@dotcom_connection_enabled)
      @dotcom_connection_enabled = GitHub.enterprise?
    end
    attr_writer :dotcom_connection_enabled

    # Public: Is GitHub Connect allowed to connect to Proxima?
    # Populated by the ENTERPRISE_GITHUB_CONNECT_GHE_COM_ENABLED env var on GHES instances
    def github_connect_ghe_com_enabled?
      return @github_connect_ghe_com_enabled if defined?(@github_connect_ghe_com_enabled)
      false
    end
    attr_writer :github_connect_ghe_com_enabled

    # The customer's proxima subdomain for GitHub Connect
    # Configured via the ENTERPRISE_GITHUB_CONNECT_GHE_COM_SUBDOMAIN env var on GHES instances
    def github_connect_ghe_com_subdomain
      return @github_connect_ghe_com_subdomain if defined?(@github_connect_ghe_com_subdomain)
      nil
    end
    attr_writer :github_connect_ghe_com_subdomain

    # Public: Allows GitHub Enterprise users to connect their account with
    # dotcom after the Enterprise instance has been connected.
    def dotcom_user_connection_enabled?
      return @dotcom_user_connection_enabled if defined?(@dotcom_user_connection_enabled)
      GitHub.dotcom_private_search_enabled? || GitHub.dotcom_contributions_enabled?
    end
    attr_writer :dotcom_user_connection_enabled

    def chatops_endpoint_enabled?
      return @chatops_endpoint_enabled if defined?(@chatops_endpoint_enabled)
      @chatops_endpoint_enabled = !GitHub.enterprise?
    end
    attr_writer :chatops_endpoint_enabled

    # Public: Allows GitHub Enterprise administrators to enable unified
    # contributions after the Enterprise instance has been connected.
    def dotcom_contributions_configurable?
      return @dotcom_contributions_configurable if defined?(@dotcom_contributions_configurable)
      license = GitHub.enterprise? ? GitHub::Enterprise.license(sync_global_business: false) : nil
      @dotcom_contributions_configurable = license &&
        (license.github_connect_support? ||
         (!license.custom_terms.nil? && license.custom_terms?))
    end
    attr_writer :dotcom_contributions_configurable

    # Public: Allows GitHub Enterprise administrators to enable downloadable
    # Actions after the Enterprise instance has been connected.
    def dotcom_actions_download_configurable?
      return @dotcom_actions_download_configurable if defined?(@dotcom_actions_download_configurable)
      @dotcom_actions_download_configurable = GitHub.actions_enabled?
    end

    def dotcom_host_name
      @dotcom_host_name ||= if github_connect_ghe_com_enabled? && github_connect_ghe_com_subdomain.present?
        "#{github_connect_ghe_com_subdomain}.ghe.com"
      else
        "github.com"
      end
    end
    attr_writer :dotcom_host_name

    def dotcom_host_name_string
      return "GitHub.com" if dotcom_host_name == "github.com"
      dotcom_host_name
    end
    attr_writer :dotcom_host_name_string

    def dotcom_host_protocol
      @dotcom_host_protocol ||= "https"
    end
    attr_writer :dotcom_host_protocol

    def dotcom_api_host_name
      @dotcom_api_host_name ||= "api.#{dotcom_host_name}"
    end
    attr_writer :dotcom_api_host_name

    def dotcom_upload_host_name
      @dotcom_upload_host_name ||= "uploads.#{dotcom_host_name}"
    end
    attr_writer :dotcom_upload_host_name

    # Prefix added to REST API calls from Enterprise to dotcom
    # (defaults to empty, but review lab requires "/api/v3")
    def dotcom_rest_api_prefix
      @dotcom_rest_api_prefix ||= ""
    end
    attr_writer :dotcom_rest_api_prefix

    # Prefix added to GraphQL API calls from Enterprise to dotcom
    # (defaults to "/graphql", but review lab requires "/api/graphql")
    def dotcom_graphql_api_prefix
      @dotcom_graphql_api_prefix ||= "/graphql"
    end
    attr_writer :dotcom_graphql_api_prefix

    # Headers added to requests from Enterprise to dotcom
    # (e.g., "User-Agent: <review lab SHA>\nSomeOtherHeader: value")
    def dotcom_request_headers
      @dotcom_request_headers ||= ""
    end
    attr_writer :dotcom_request_headers

    def funcaptcha_enabled?
      if ENV["CODESPACES"]
        return !!ENV["OCTOCAPTCHA_ENABLED"]
      end

      !enterprise? && !!funcaptcha_public_key && !!funcaptcha_private_key
    end

    def funcaptcha_public_key
      return @funcaptcha_public_key if defined?(@funcaptcha_public_key)

      @funcaptcha_public_key = ENV["FUNCAPTCHA_PUBLIC_KEY"]
    end

    def funcaptcha_private_key
      return @funcaptcha_private_key if defined?(@funcaptcha_private_key)

      @funcaptcha_private_key = ENV["FUNCAPTCHA_PRIVATE_KEY"]
    end

    def funcaptcha_public_key_version_2
      return @funcaptcha_public_key_version_2 if defined?(@funcaptcha_public_key_version_2)

      @funcaptcha_public_key_version_2 = ENV["FUNCAPTCHA_PUBLIC_KEY_VERSION_2"]
    end

    def funcaptcha_private_key_version_2
      return @funcaptcha_private_key_version_2 if defined?(@funcaptcha_private_key_version_2)

      @funcaptcha_private_key_version_2 = ENV["FUNCAPTCHA_PRIVATE_KEY_VERSION_2"]
    end

    def funcaptcha_public_key_2
      return @funcaptcha_public_key_2 if defined?(@funcaptcha_public_key_2)

      @funcaptcha_public_key_2 = ENV["FUNCAPTCHA_PUBLIC_KEY_2"]
    end

    def funcaptcha_private_key_2
      return @funcaptcha_private_key_2 if defined?(@funcaptcha_private_key_2)

      @funcaptcha_private_key_2 = ENV["FUNCAPTCHA_PRIVATE_KEY_2"]
    end

    def funcaptcha_public_key_2_version_2
      return @funcaptcha_public_key_2_version_2 if defined?(@funcaptcha_public_key_2_version_2)

      @funcaptcha_public_key_2_version_2 = ENV["FUNCAPTCHA_PUBLIC_KEY_2_VERSION_2"]
    end

    def funcaptcha_private_key_2_version_2
      return @funcaptcha_private_key_2_version_2 if defined?(@funcaptcha_private_key_2_version_2)

      @funcaptcha_private_key_2_version_2 = ENV["FUNCAPTCHA_PRIVATE_KEY_2_VERSION_2"]
    end

    def funcaptcha_public_key_3
      return @funcaptcha_public_key_3 if defined?(@funcaptcha_public_key_3)

      @funcaptcha_public_key_3 = ENV["FUNCAPTCHA_PUBLIC_KEY_3"]
    end

    def funcaptcha_private_key_3
      return @funcaptcha_private_key_3 if defined?(@funcaptcha_private_key_3)

      @funcaptcha_private_key_3 = ENV["FUNCAPTCHA_PRIVATE_KEY_3"]
    end

    def funcaptcha_data_exchange_key
      return @funcaptcha_data_exchange_key if defined?(@funcaptcha_data_exchange_key)

      @funcaptcha_data_exchange_key = ENV["FUNCAPTCHA_DATA_EXCHANGE_KEY"]
    end

    # Demo key used for styling purposes only. There is no associated private
    # key so this cannot be used to solve captchas.
    def funcaptcha_public_key_demo
      "CF9A4149-AA60-4EC4-80B8-D5AFAA05A79B"
    end

    # Demo key used for styling purposes only. There is no associated private
    # key so this cannot be used to solve captchas.
    def funcaptcha_public_key_2_demo
      "8D0BD982-2E3E-45ED-BCDA-44744CC8DCCF"
    end

    def dotcom_ssl_verify?
      return @dotcom_ssl_verify if defined?(@dotcom_ssl_verify)
      @dotcom_ssl_verify = true
    end
    attr_writer :dotcom_ssl_verify

    def http_proxy_config
      return @http_proxy_config if defined?(@http_proxy_config)
      @http_proxy_config = ENV["GH_HTTP_PROXY"]
    end
    attr_writer :http_proxy_config

    def no_proxy_config
      return @no_proxy_config if defined?(@no_proxy_config)
      @no_proxy_config = ENV["GH_NO_PROXY"]
    end
    attr_writer :no_proxy_config

    def download_everything_button_enabled?
      !enterprise?
    end

    def launch_grpc_ssl_enabled?
      !GitHub.enterprise?
    end

    # Aqueduct config for ActiveJob
    attr_accessor :aqueduct_gateway_url
    attr_accessor :aqueduct_primary_url
    attr_accessor :aqueduct_secondary_url
    attr_accessor :aqueduct_github_send_secret
    attr_accessor :aqueduct_github_receive_secrets
    attr_accessor :aqueduct_github_api_key
    attr_accessor :aqueduct_github_api_key_version

    attr_accessor :aqueduct_billing_platform_api_key
    attr_accessor :aqueduct_billing_platform_api_key_version

    # Aqueduct config for sending jobs to the hookshot-go service
    attr_accessor :aqueduct_hookshot_url
    attr_accessor :aqueduct_hookshot_staging_url
    attr_accessor :aqueduct_hookshot_api_key
    attr_accessor :aqueduct_hookshot_api_key_version
    attr_accessor :aqueduct_hookshot_staging_api_key
    attr_accessor :aqueduct_hookshot_staging_api_key_version

    # Aqueduct config for sending jobs to the actions-production app
    attr_accessor :aqueduct_actions_api_key
    attr_accessor :aqueduct_actions_api_key_version

    # Aqueduct config for sending jobs to the chatops-production app
    attr_accessor :aqueduct_chatops_api_key
    attr_accessor :aqueduct_chatops_api_key_version

    # Aqueduct config for sending jobs to notifyd service
    attr_accessor :aqueduct_notifyd_url
    attr_accessor :aqueduct_notifyd_api_key
    attr_accessor :aqueduct_notifyd_api_key_version

    # Aqueduct config for sending jobs to the pages-deployer service
    attr_accessor :aqueduct_pages_deployer_api_key
    attr_accessor :aqueduct_pages_deployer_api_key_version

    # Public: An aqueduct client configured to point at the aqueduct gateway.
    #
    # Returns a GitHub::Aqueduct::Client.
    def aqueduct_gateway
      @aqueduct_gateway ||= build_aqueduct_client(
        url: aqueduct_gateway_url,
        circuit_breaker: aqueduct_gateway_circuit_breaker,
        send_hmac_secret: aqueduct_github_send_secret.presence,
        receive_hmac_secrets: aqueduct_github_receive_secrets.presence,
        api_key: aqueduct_github_api_key.presence,
        api_key_version: aqueduct_github_api_key_version.presence,
      )
    end

    def aqueduct_gateway_circuit_breaker
      @aqueduct_gateway_circuit_breaker ||= build_aqueduct_circuit_breaker("aqueduct_gateway")
    end

    # Public: An aqueduct client configured to point at the primary aqueduct cluster.
    #
    # Returns an GitHub::Aqueduct::Client.
    def aqueduct_primary
      @aqueduct_primary ||= build_aqueduct_client(
        url: aqueduct_primary_url,
        circuit_breaker: aqueduct_primary_circuit_breaker,
        send_hmac_secret: aqueduct_github_send_secret.presence,
        receive_hmac_secrets: aqueduct_github_receive_secrets.presence,
        api_key: aqueduct_github_api_key.presence,
        api_key_version: aqueduct_github_api_key_version.presence,
      )
    end

    def aqueduct_primary_circuit_breaker
      @aqueduct_primary_circuit_breaker ||= build_aqueduct_circuit_breaker("aqueduct_primary")
    end

    # Public: An aqueduct client configured to point at the secondary aqueduct cluster.
    #
    # Returns an GitHub::Aqueduct::Client.
    def aqueduct_secondary
      @aqueduct_secondary ||= build_aqueduct_client(
        url: aqueduct_secondary_url,
        circuit_breaker: aqueduct_secondary_circuit_breaker,
        send_hmac_secret: aqueduct_github_send_secret.presence,
        receive_hmac_secrets: aqueduct_github_receive_secrets.presence,
        api_key: aqueduct_github_api_key.presence,
        api_key_version: aqueduct_github_api_key_version.presence,
      )
    end

    def aqueduct_secondary_circuit_breaker
      @aqueduct_secondary_circuit_breaker ||= build_aqueduct_circuit_breaker("aqueduct_secondary")
    end

    def build_aqueduct_circuit_breaker(name)
      Resilient::CircuitBreaker.get(name, {
        instrumenter: GitHub,
        sleep_window_seconds: 10,
        request_volume_threshold: 3,
        error_threshold_percentage: 50,
        # At the time of writing we have about 8 enquques per min per unicorn worker, this means that if 4 requests fail in a row we'll trip the breaker
        # Where the 8 comes from: https://data.githubapp.com/sql/0100f53b-ade0-4280-9f53-0597dfe74a37#
        # This number is a bit of SWAG, but at worst this means that the breaker doesn't open as much leading to elevated enquque times
        # but not preventing jobs from making it out of the system, so setting a higher error % seems safe.
      })
    end

    def build_aqueduct_client(app: aqueduct_app_name, client_id: aqueduct_client_id, url: aqueduct_gateway_url, circuit_breaker: aqueduct_gateway_circuit_breaker, **kwargs)
      GitHub::Aqueduct::Client.new(
        app: app,
        url: url,
        site: GitHub.server_site || "localhost",
        timeout: foreground? ? 2 : 5,
        receive_timeout: 10,
        send_retries: 1,
        client_id: client_id,
        tags: aqueduct_tags,
        circuit_breaker: circuit_breaker,
        **kwargs
      ) do |faraday|
        faraday.adapter :persistent_excon,
          tcp_nodelay: true,
          keepalive: {
            time: 60,
            intvl: 5,
            probes: 3,
          }
      end
    end

    def aqueduct_app_name
      if dynamic_lab?
        "github-review-lab"
      else
        "github-#{GitHub::AppEnvironment.env}"
      end
    end

    def aqueduct_client_id
      if GitHub.kube?
        "#{GitHub.kubernetes_cluster_name}-#{Socket.gethostname}-#{Process.pid}"
      else
        "#{Socket.gethostname}-#{Process.pid}"
      end
    end

    def aqueduct_tags
      if GitHub.kube?
        kube_hostname_tokens = Socket.gethostname.split("-")
        # Last two are deployment hash and pod hash. For example highworker-58969cb7c8-zx5bv would get tokenized to
        # [highworker, 58969cb7c8, zx5bv]
        kube_deployment = kube_hostname_tokens.first(kube_hostname_tokens.length - 2).join("-")
        { "app-role" => "kube-#{kube_deployment}" }
      else
        host_app = GitHub.server_metadata["app"]
        host_role = GitHub.server_metadata["role"]
        { "app-role" => "#{host_app}-#{host_role}" }
      end
    end

    def aqueduct_worker_backend(actor: nil, prioritize_by: nil)
      return ::Aqueduct::Worker::AqueductBackend.new(client: aqueduct_primary) if GitHub.enterprise?

      GitHub::Aqueduct::CompositeBackend.new(
        primary: ::Aqueduct::Worker::AqueductBackend.new(client: aqueduct_primary),
        secondary: ::Aqueduct::Worker::AqueductBackend.new(client: aqueduct_secondary),
        gateway: ::Aqueduct::Worker::AqueductBackend.new(client: aqueduct_gateway),
        actor: actor,
        prioritize_by: prioritize_by,
      )
    end

    def at_least_one_aqueduct_secondary_worker?
      @at_least_one_aqueduct_secondary_worker
    end
    attr_writer :at_least_one_aqueduct_secondary_worker

    def enable_aqueduct_status_server?
      !Rails.env.test?
    end

    def aqueduct_worker_backoff_on_queues_empty?
      GitHub.local_host_name.start_with?("github-dfs") && Process.pid % 10 != 0
    end

    def pond_client
      @pond_client ||= Octolytics::Pond.new(
        secret: GitHub.pond_shared_secret,
        url: ENV.fetch("OCTOLYTICS_POND_URL", "https://pond.service.iad.github.net"),
      )
    end

    # Whether or not to raise when an unknown plan feature is encountered
    # In production, we don't want to raise an exception and instead report the
    # error through Failbot.
    #
    # In other envionments, we want to raise an exception since it could point
    # to a typo in the code and its useful in development and testing
    def raise_on_unknown_plan_feature?
      !GitHub::AppEnvironment.production?
    end

    # Whether or not to raise when an unexpected queue name is encountered when
    # enqueing a job through ActiveJob. This is intended to prevent jobs being
    # queued to queues that aren't being worked by workers. This scenario should
    # ideally be caught in the linters, but just in case it's not, this
    # explicit check will give additional guarantees.
    #
    # Raising an exception is disabled in production in order to prevent job
    # loss, but needles are reported as a way to find and eliminate any
    # misconfigured queues.
    def raise_on_unrecognized_queue?
      Rails.env.test?
    end

    # Whether or not requests are to an environment that supports routing
    # requests to Kubernetes
    def kubernetes_backend_available?
      Rails.env.production? &&
          !single_or_multi_tenant_enterprise? &&
          !garage_unicorn?
    end

    def enterprise_user_license_list_private_keys
      @enterprise_user_license_list_private_keys ||= ENV["ENTERPRISE_USER_LICENSE_LIST_PRIVATE_KEYS"].to_s.split(",")
    end
    attr_writer :enterprise_user_license_list_private_keys

    def enterprise_user_license_list_public_key
      @enterprise_user_license_list_public_key ||= File.read(Rails.root.join("config/user-license-list.pub"))
    end
    attr_writer :enterprise_user_license_list_public_key

    # Is the IP allow lists feature available?
    #
    # By default, enabled on GitHub.com, disabled on GHES.
    #
    # Can be stealth-enabled in GHES using:
    #
    # ghe-config app.github.ip-allowlists-available 1 && ghe-config-apply
    #
    # Returns Boolean.
    def ip_allowlists_available?
      return @ip_allowlists_available if defined?(@ip_allowlists_available)
      @ip_allowlists_available = !enterprise?
    end
    attr_writer :ip_allowlists_available

    # Is the IdP allow Conditional Access Policy available?
    #
    # By default, enabled on GitHub.com, disabled on GHES, since OIDC is not supported on GHES yet.
    #
    # Returns Boolean.
    def idp_cap_available?
      return @idp_cap_available if defined?(@idp_cap_available)
      @idp_cap_available = !enterprise?
    end

    # Are we hiding the contribution graph (and related UI elements) in
    # /profile?
    #
    # By default false (not hiding) on GitHub.com and GHES.
    #
    # Populated by the ENTERPRISE_CONTRIBUTION_GRAPH_DISABLED env var on GHES
    # instances, and thus can be stealth-activated in those with:
    #
    # ghe-config app.github.contribution-graph-disabled 1 && ghe-config-apply
    #
    # Returns Boolean.
    def contribution_graph_disabled?
      return @contribution_graph_disabled if defined?(@contribution_graph_disabled)
      @contribution_graph_disabled = false
    end
    attr_writer :contribution_graph_disabled

    # Public: This is the number of days a user is given to accept an invite.
    #
    # Returns Integer.
    def invitation_expiry_period
      7
    end

    # Public: This is the number of days after the invitation expiration date
    # that we want to consider for invitations to appear in "recently expired"
    # invitation scopes such as OrganizationInvitation.recently_expired and
    # BusinessAdministratorInvitation.recently_expired. This avoids having an unbound
    # filter in the scope, letting us write SQL similar to this instead:
    #
    # created_at BETWEEN invitation_expiry_cutoff.days.ago AND invitation_expiry_period.days.ago
    #
    # Returns Integer.
    def invitation_expiry_cutoff
      invitation_expiry_period + 2
    end

    attr_accessor :qintel_api_key, :qintel_api_secret, :qintel_api_proxy

    # Should FailbotKeyFilter raise when it encounters disallowed keys?
    def raise_on_failbot_filter?
      false
    end

    # Should FailbotKeyTagger convert context keys to sentry tags
    # It should only be enabled in production environment
    def enable_failbot_tags?
      return @enable_failbot_tags if defined?(@enable_failbot_tags)
      @enable_failbot_tags = ENV["GH_ENABLE_FAILBOT_TAGS"].present? || (GitHub::AppEnvironment.production? && !GitHub.enterprise?)
    end
    attr_writer :enable_failbot_tags

    # Should Failbot be scrubbed for sensitive data before reporting?
    def enable_failbot_scrubbing?
      return @enable_failbot_scrubbing if defined?(@enable_failbot_scrubbing)
      @enable_failbot_scrubbing = true
    end
    attr_writer :enable_failbot_scrubbing

    # Should allow localhost, 127.0.0.1/8 or 0.0.0.0/8 ipaddress range for webhook
    # delivery
    def allow_webhook_loopback_addresses?
      return @allow_webhook_loopback_addresses if defined?(@allow_webhook_loopback_addresses)
      @allow_webhook_loopback_addresses = false
    end
    attr_writer :allow_webhook_loopback_addresses

    # Public: The Stripe Connect dashboard base URL for use with Sponsors.
    #
    # Returns a String.
    def stripe_connect_dashboard_base_url
      return unless GitHub.sponsors_enabled?

      if GitHub::AppEnvironment.production?
        "https://dashboard.stripe.com"
      else
        "https://dashboard.stripe.com/test"
      end
    end

    # Public: The URL to view invoices in the Stripe dashboard.
    #
    # Returns a String.
    def stripe_invoices_base_url
      return unless GitHub.billing_enabled?

      if GitHub::AppEnvironment.production?
        "https://dashboard.stripe.com/invoices"
      else
        "https://dashboard.stripe.com/test/invoices"
      end
    end

    # Public: The URL to view invoices in the Stripe dashboard.
    #
    # Returns a String.
    def stripe_payments_base_url
      return unless GitHub.billing_enabled?

      if GitHub::AppEnvironment.production?
        "https://dashboard.stripe.com/payments"
      else
        "https://dashboard.stripe.com/test/payments"
      end
    end

    # The ID for GitHub's Facebook app.
    def facebook_app_id
      1401488693436528
    end

    # The ID for GitHub's iOS app.
    def ios_app_id
      1477376905
    end

    def og_image_generator_base_url
      if Rails.env.production?
        "https://opengraph.githubassets.com"
      else
        "http://localhost:7071"
      end
    end

    def figma_image_thumbnail_url
      "https://s3-alpha.figma.com/thumbnails/"
    end

    def figma_full_image_url
      "https://figma-alpha-api.s3.us-west-2.amazonaws.com/images/"
    end

    # Only in local dev, drag-and-drop asset upload uses a local alambic URL, e.g.
    # http://alambic.github.localhost/storage/user/7/files/abaea580-9f49-11ea-9b81-d306d6a03db9
    # This flag enables asset uploads to work correctly end-to-end.
    def include_alambic_asset_storage_paths?
      Rails.env.development?
    end

    def bypass_failbot_filter_logic?
      GitHub.enterprise?
    end

    def lazy_load_hydro?
      # Lazy loading should only happen locally since it is certainly
      # needed on CI
      GitHub::AppEnvironment.test? && !ENV["TEST_TIMERD"] && !TestEnv.github_ci?
    end

    def lazy_find_inline_svg_files?
      GitHub::AppEnvironment.development? || GitHub::AppEnvironment.test? && !Rails.configuration.eager_load
    end

    def staffbar_service_info_enabled?
      !GitHub.enterprise?
    end

    def fips_mode?
      return @fips_mode if defined?(@fips_mode)
      @fips_mode = false
    end
    attr_writer :fips_mode

    def svnbridge_available?
      !fips_mode?
    end

    def keep_legacy_bcrypt_password?
      !GitHub.enterprise?
    end

    # We only wish to allow actual admins of github.com stafftools to
    # generate SLA reports (and they wouldn't work in GHES anyways,
    # since GH Presto is not available outside our network).
    def sla_reports_available?
      !GitHub.enterprise?
    end

    attr_accessor :slack_integration_secret

    def slack_integration_api_url
      if GitHub.multi_tenant_enterprise?
        "https://slack.#{GitHub.host_name_with_tenant}"
      else
        slack_integration.url
      end
    end

    def slack_integration_global_api_url
      if GitHub.multi_tenant_enterprise?
        "https://slack-ghe.#{GitHub.dotcom_host_name}"
      else
        slack_integration.url
      end
    end

    def slack_integration
      Apps::Privileged.integration(:slack) || raise(IntegrationMissingError, "Slack Integration did not exist")
    end

    # Are downloadable compliance reports available in this environment?
    def compliance_reports_available?
      !GitHub.enterprise?
    end

    # Returns the user-facing name for outside collaborators.
    def outside_collaborators_flavor
      "outside collaborators"
    end

    def memcache_messagepack_rollout_percentage
      @memcache_messagepack_rollout_percentage ||= GitHub.environment.fetch("MEMCACHE_MESSAGEPACK_ROLLOUT_PERCENTAGE", "0").to_i
    end

    # Is the default attribute mapping for saml display_name disabled?
    #
    # Disabled in GHES, enabled on dotcom
    #
    # Returns Boolean.
    def saml_display_name_default_attribute_mapping_disabled?
      GitHub.enterprise?
    end

    # Contentful
    attr_accessor :contentful_image_host_url
    attr_accessor :contentful_asset_host_url
    attr_accessor :contentful_download_host_url
    attr_accessor :contentful_force_auto_dynamic_entries
    attr_accessor :contentful_readme_space_id
    attr_accessor :contentful_readme_delivery_token
    attr_accessor :contentful_readme_environment
    attr_accessor :contentful_marketing_space_id
    attr_accessor :contentful_marketing_delivery_token
    attr_accessor :contentful_marketing_environment
    attr_accessor :contentful_customer_stories_space_id
    attr_accessor :contentful_customer_stories_delivery_token
    attr_accessor :contentful_customer_stories_environment

    def contentful_readme_image_host_url
      @contentful_readme_image_host_url ||= "#{GitHub.contentful_image_host_url}/#{GitHub.contentful_readme_space_id}/"
    end

    def contentful_readme_asset_host_url
      @contentful_readme_asset_host_url ||= "#{GitHub.contentful_asset_host_url}/#{GitHub.contentful_readme_space_id}/"
    end

    def contentful_readme_download_host_url
      @contentful_readme_download_host_url ||= "#{GitHub.contentful_download_host_url}/#{GitHub.contentful_readme_space_id}/"
    end

    def contentful_marketing_image_host_url
      @contentful_marketing_image_host_url ||= "#{GitHub.contentful_image_host_url}/#{GitHub.contentful_marketing_space_id}/"
    end

    def contentful_marketing_asset_host_url
      @contentful_marketing_asset_host_url ||= "#{GitHub.contentful_asset_host_url}/#{GitHub.contentful_marketing_space_id}/"
    end

    def contentful_marketing_download_host_url
      @contentful_marketing_download_host_url ||= "#{GitHub.contentful_download_host_url}/#{GitHub.contentful_marketing_space_id}/"
    end

    def contentful_customer_stories_image_host_url
      @contentful_customer_stories_image_host_url ||= "#{GitHub.contentful_image_host_url}/#{GitHub.contentful_customer_stories_space_id}/"
    end

    def contentful_force_auto_dynamic_entries?
      contentful_force_auto_dynamic_entries
    end

    # MFST CPM (Content Permissions Master)
    attr_accessor :cpm_email_preference_center_tenant_id
    attr_accessor :cpm_email_preference_center_client_id
    attr_accessor :cpm_email_preference_center_client_secret
    attr_accessor :cpm_email_preference_center_object_id
    attr_accessor :cpm_email_preference_center_app_resource_id
    attr_accessor :cpm_email_preference_center_url

    # MSFT Lead Ingestion API
    attr_accessor :lead_ingestion_tenant_id
    attr_accessor :lead_ingestion_client_id
    attr_accessor :lead_ingestion_client_secret
    attr_accessor :lead_ingestion_object_id
    attr_accessor :lead_ingestion_app_resource_id
    attr_accessor :lead_ingestion_url

    # Marketing Forms API
    attr_accessor :marketing_forms_api_host_url
    attr_accessor :marketing_forms_api_hmac_key
    attr_accessor :marketing_forms_api_internal_url

    # Marketing forms configurations
    attr_accessor :enterprise_contact_campaign_id
    attr_accessor :enterprise_contact_source
    attr_accessor :enterprise_contact_status
    attr_accessor :ghas_trial_campaign_id
    attr_accessor :ghas_trial_source
    attr_accessor :ghas_trial_status

    attr_accessor :ghec_trial_campaign_id
    attr_accessor :ghec_trial_source
    attr_accessor :ghec_trial_status

    attr_accessor :copilot_trial_campaign_id
    attr_accessor :copilot_trial_lead_source
    attr_accessor :copilot_trial_sf_status
    attr_accessor :copilot_trial_cancel_campaign_id

    # Octocaptcha API
    attr_accessor :octocaptcha_api_hmac_secret
    attr_accessor :octocaptcha_api_hmac_secret_v2

    # Dotcom fans out by default, enterprise does not, but we can override either with an env.
    def fan_out_synchronize_pull_request_jobs?
      return @fan_out_synchronize_pull_request_jobs if defined?(@fan_out_synchronize_pull_request_jobs)
      @fan_out_synchronize_pull_request_jobs = if enterprise?
        ENV["FAN_OUT_SYNC_PR_JOBS"] # only do it if the override env is set
      else
        !ENV["NO_FAN_OUT_SYNC_PR_JOBS"] # do it unless the override env is set
      end
    end

    # GraphQL query analyzers & validation are disabled by default as they impact performance
    # Re-enable via `ANALYZE_INTERNAL_GRAPHQL=1` for development
    def analyze_internal_graphql?
      return @analyze_internal_graphql if defined?(@analyze_internal_graphql)
      @analyze_internal_graphql = !!ENV["ANALYZE_INTERNAL_GRAPHQL"] && !Rails.env.production?
    end
    attr_writer :analyze_internal_graphql

    # Disable SQL statement checking in test environments unless explicitly enabled
    def statement_checking_enabled?
      return @statement_checking_enabled if defined?(@statement_checking_enabled)
      @statement_checking_enabled = ENV["PERFORM_STATEMENT_CHECKING"] == "1"
    end
    attr_writer :statement_checking_enabled

    attr_accessor :oidc_azure_ad_client_certificate_current_encoded
    attr_accessor :oidc_azure_ad_client_certificate_previous_encoded

    attr_accessor :issues_graph_api_url

    attr_accessor :cps_network_service_url
    attr_accessor :cps_network_service_hmac_secrets
    attr_accessor :cps_network_url

    attr_accessor :copilot_swe_agent_url

    attr_accessor :encrypted_column_keying_material
    attr_accessor :encrypted_column_current_encryption_key

    # Can a repository invitation be sent via email?
    #
    # Disabled in GHES, enabled in dotcom.
    #
    # Returns Boolean
    def email_invitations_enabled?
      !GitHub.enterprise?
    end

    # The environment for githooks configuration
    #
    # This controls what configuration environment hooks, which are packaged as
    # part of gitrpcd, will attempt to use.  In multi-tentant enterprise
    # environments this may need to be overridden.
    def githooks_env
      @githooks_env ||= Rails.env
    end
    attr_writer :githooks_env

    attr_accessor :missing_user_notice_behavior

    # Alloy
    attr_accessor :alloy_url

    def publish_events_to_delorean?
      return @publish_events_to_delorean if defined?(@publish_events_to_delorean)
      @publish_events_to_delorean = Rails.env.production? && !GitHub.enterprise?
    end

    def delorean_client
      @delorean_client ||= begin
        require "delorean_client"
        DeloreanClient.new(base_url: "https://delorean-production.service.iad.github.net")
      end
    end

    # Feature Management

    # Set the name of the current stamp. If not set, returns dotcom.
    def set_feature_management_current_stamp
      @feature_management_current_stamp = GitHub.environment.fetch("FEATURE_MANAGEMENT_CURRENT_STAMP", "dotcom")
    end
    attr_accessor :feature_management_current_stamp

    # Set the HMAC key for the Feature Flag Hub (this is the Sync API HMAC key)
    def set_feature_management_feature_flag_hub_hmac_key
      @feature_management_feature_flag_hub_hmac_key = GitHub.environment.fetch("FEATURE_MANAGEMENT_FEATURE_FLAG_HUB_SYNC_HMAC_KEY", nil)
    end
    attr_accessor :feature_management_feature_flag_hub_hmac_key

    # Set the HMAC key for the Feature Flag Hub (this is the Management API HMAC key)
    def set_feature_management_feature_flag_hub_mgmt_hmac_key
      @feature_management_feature_flag_hub_mgmt_hmac_key = GitHub.environment.fetch("FEATURE_MANAGEMENT_FEATURE_FLAG_HUB_MGMT_HMAC_KEY", nil)
    end
    attr_accessor :feature_management_feature_flag_hub_mgmt_hmac_key

    # Set the HMAC key for the Feature Flag Hub (this is the Checks API HMAC key)
    def set_feature_management_feature_flag_hub_checks_hmac_key
      @feature_management_feature_flag_hub_checks_hmac_key = GitHub.environment.fetch("FEATURE_MANAGEMENT_FEATURE_FLAG_HUB_CHECKS_HMAC_KEY", nil)
    end
    attr_accessor :feature_management_feature_flag_hub_checks_hmac_key

    # Set the Review lab HMAC key for the Feature Flag Hub (this is the staging-dotcom Checks API HMAC key)
    def set_feature_management_feature_flag_hub_checks_review_lab_hmac_key
      @feature_management_feature_flag_hub_checks_review_lab_hmac_key = GitHub.environment.fetch("FEATURE_MANAGEMENT_FEATURE_FLAG_HUB_CHECKS_REVIEW_LAB_HMAC_KEY", nil)
    end
    attr_accessor :feature_management_feature_flag_hub_checks_review_lab_hmac_key

    # Set the url key for the Feature Flag Hub
    def set_feature_management_feature_flag_hub_url
      url = GitHub.environment.fetch("FEATURE_MANAGEMENT_FEATURE_FLAG_HUB_URL", nil)
      if url.nil?
        if Rails.env.test?
          url = "https://fake-feature-flag-hub-url.github.com"
        end

        if GitHub.use_fm_lite?
          url = "http://api.github.localhost:8090/twirp"
        end
      end
      @feature_management_feature_flag_hub_url = url
    end
    attr_accessor :feature_management_feature_flag_hub_url

    # Set the url key for Feature Flag Data
    def set_feature_management_feature_flag_data_url
      url = GitHub.environment.fetch("FEATURE_FLAG_DATA_URL", nil)
      if url.nil?
        if GitHub.use_fm_lite?
          url = "http://api.github.localhost:8090/twirp"
        end

        if Rails.env.production? && !GitHub.enterprise?
          stamp = Proxima.current_stamp_or_dotcom
          if stamp == "dotcom"
            url = "https://feature-flag-data-dotcom.service.iad.github.net/twirp"
          elsif !GitHub.kube?
            # If we are not in a kubernetes deployment, always use the non istio url.
            url = "https://feature-flag-data-#{stamp}.service.#{stamp}.github.net/twirp"
          else
            url = "http://feature-flag-data.feature-flag-data-#{stamp}.svc.cluster.local:8010/twirp"
          end
        end
      end
      @feature_management_feature_flag_data_url = url
    end
    attr_accessor :feature_management_feature_flag_data_url

    # Set the HMAC key for the Feature Flag Data (this is the Checks API HMAC key)
    def set_feature_management_feature_flag_data_checks_hmac_shared_key
      @feature_management_feature_flag_data_checks_hmac_shared_key = GitHub.environment.fetch("FEATURE_FLAG_DATA_CHECKS_API_HMAC_SHARED_KEY", nil)
    end
    attr_accessor :feature_management_feature_flag_data_checks_hmac_shared_key

    # Set the environment variable to indicate whether or not to use flipper or vexi for feature flags
    def set_use_flipper_vexi_proxy_redirect(default = false)
      @use_flipper_vexi_proxy_redirect = GitHub.environment.fetch("USE_FLIPPER_VEXI_PROXY_REDIRECT", default.to_s) == "true"
    end
    attr_accessor :use_flipper_vexi_proxy_redirect

    # Should Vexi be using the Feature Management Lite backend?
    def use_fm_lite?
      return true if ENV["USE_FM_LITE"] == "1"
      return false if ENV["USE_FM_LITE"] == "0"
      return false if GitHub.single_tenant_enterprise?
      Rails.env.development?
    end

    # This is used where the cookie private_mode_user_session is made available at boot time.
    # Adding Rails.env.test? allows to easily test the use of private_mode_user_session.
    def allow_private_mode_user_session_cookie?
      return true if subdomain_private_mode_enabled?
      Rails.env.test?
    end

    # Should we use the Nodeinfo protocol to identify the Fediverse software hosting a social account on a user's
    # profile?
    def nodeinfo_probe_enabled?
      # Disabled on Enterprise to prevent SSRF attacks.
      !enterprise?
    end

    # Should we disable optional clusters?
    # Used to determine whether optional clusters should be disabled while running tests.
    def disable_optional_clusters?
      return @disable_optional_clusters if defined?(@disable_optional_clusters)
      @disable_optional_clusters = (ENV["DISABLE_OPTIONAL_CLUSTERS"] == "1")
    end
    attr_writer :disable_optional_clusters

    # Is the System All Repo Org Roles feature enabled?
    #
    # By default, enabled on GitHub.com, disabled on GHES.
    # Returns Boolean.
    def system_all_repo_roles_enabled?
      !single_tenant_enterprise?
    end

    def timeout_middleware_enabled?
      return @timeout_middleware_enabled if defined?(@timeout_middleware_enabled)
      @timeout_middleware_enabled = Rails.env.production?
    end
    attr_writer :timeout_middleware_enabled

    # Populated by the ENTERPRISE_CREATE_REPO_PERF variable.
    #
    # GHES admins can enable this feature by running:
    # ghe-config app.github.create-repo-perf true && ghe-config-apply
    def create_repo_perf?
      return @create_repo_perf if defined?(@create_repo_perf)
      @create_repo_perf = enterprise? && GitHub.environment.fetch("ENTERPRISE_CREATE_REPO_PERF", "false") == "true"
    end

    # Determine if Enterprise Security Manager is enabled
    #
    # Disabled by default for enterprise and dotcom, unless explicitly enabled
    def esm_enabled?
      return @esm_enabled if defined?(@esm_enabled)
      @esm_enabled = Rails.env.development? && GitHub.flipper[:esm_enabled].enabled?
    end
    attr_writer :esm_enabled

    # An override for the maximum number of organizations that can be synced via ESM.
    # If provided, this will override the default value.
    def esm_max_sync_organizations_override
      @esm_max_sync_organizations_override
    end

    def esm_max_sync_organizations_override=(int)
      config_value_as_int = int.to_i
      @esm_max_sync_organizations_override = config_value_as_int if config_value_as_int > 0
    end

    # The number of orgs a single EnterpriseTeamOrganizationReconciliationJobRunner will process
    #
    # Defaults to 10
    def max_orgs_per_et_org_reconciliation_runner
      return @max_orgs_per_et_org_reconciliation_runner if defined?(@max_orgs_per_et_org_reconciliation_runner)

      @max_orgs_per_et_org_reconciliation_runner = 10
    end

    def max_orgs_per_et_org_reconciliation_runner=(int)
      config_value_as_int = int.to_i
      @max_orgs_per_et_org_reconciliation_runner = config_value_as_int if config_value_as_int > 0
    end

    # The number of EnterpriseTeamOrganizationReconciliationJobRunners that will run at the same time for a business
    #
    # Defaults to 1
    def max_concurrent_et_org_reconciliation_runners
      return @max_concurrent_et_org_reconciliation_runners if defined?(@max_concurrent_et_org_reconciliation_runners)

      @max_concurrent_et_org_reconciliation_runners = 1
    end

    def max_concurrent_et_org_reconciliation_runners=(int)
      config_value_as_int = int.to_i
      @max_concurrent_et_org_reconciliation_runners = config_value_as_int if config_value_as_int > 0
    end

    # The number of BackgroundInstrumentationJobs that will run at the same time
    #
    # Defaults to 100 (this will probably be changed in the future)
    def max_concurrent_background_instrumentation_jobs
      return @max_concurrent_background_instrumentation_jobs if defined?(@max_concurrent_background_instrumentation_jobs)

      @max_concurrent_background_instrumentation_jobs = 100
    end

    def max_concurrent_background_instrumentation_jobs=(int)
      config_value_as_int = int.to_i
      @max_concurrent_background_instrumentation_jobs = config_value_as_int if config_value_as_int > 0
    end

    # Populated by the ENTERPRISE_ENQUEUE_INVALID_JOBS_PER_ENVIRONMENT variable or alternatively enabled with a dotcom feature flag.
    # (disabled by default)
    #
    # GHES admins can enable this feature by running:
    # ghe-config app.github.enqueue-invalid-jobs-per-environment true && ghe-config-apply
    def enqueue_invalid_jobs_per_environment_enabled
      return @enqueue_invalid_jobs_per_environment_enabled if defined?(@enqueue_invalid_jobs_per_environment_enabled)
      @enqueue_invalid_jobs_per_environment_enabled = false
    end
    alias enqueue_invalid_jobs_per_environment_enabled? enqueue_invalid_jobs_per_environment_enabled
    attr_writer :enqueue_invalid_jobs_per_environment_enabled

    # The prefix to be used for filenames for this environment.
    #
    # Used when storing assets.
    #
    # Returns String.
    def filename_prefix_for_env
      Rails.env.production? ? "prod" : "dev"
    end

    # If true, will update query violation files with newly recorded violations
    def record_domain_query_violations?
      return @record_domain_query_violations if defined?(@record_domain_query_violations)
      @record_domain_query_violations = (ENV["DOMAIN_QUERY_VIOLATIONS"] == "1")
    end

    def graphql_at_least_version(minimum_version, current_version = GraphQL::VERSION)
      if minimum_version.split(".").size > current_version.split(".").size
        raise "Please only provide a minimum version which is smaller or equal to the current version string minimum_version: #{minimum_version} current_version: #{current_version}"
      end

      gql_version_parts = current_version.split(".").map(&:to_i)
      minimum_version_parts = minimum_version.split(".").map(&:to_i)

      minimum_version_parts.each_with_index do |part, index|
        if T.must(gql_version_parts[index]) < part
          return false
        end
      end
      true
    end

    def graphql_at_exact_version(version, current_version = GraphQL::VERSION)
      if version.split(".").size != current_version.split(".").size
        raise "Please only provide a version which is equal to the current version string version: #{version} current_version: #{current_version}"
      end

      gql_version_parts = current_version.split(".").map(&:to_i)
      version_parts = version.split(".").map(&:to_i)

      version_parts.each_with_index do |part, index|
        if T.must(gql_version_parts[index]) != part
          return false
        end
      end
      true
    end

    # A mapping of stamp to HMAC key for each Proxima stamp.  A symmetric key is synchronized between the Dotcom 'production'
    # Vault and the Proxima Vault for each service in the given stamp.  That key is used to sign and verify JWT tokens
    # for the purposes of increase rate limits for unauthenticated requests for stamp-bound, first-part services in Proxima.
    # - See ProximaServiceTokens and ProximaServiceIdentities.
    def proxima_service_identity_secret_keys
      return @proxima_service_identity_secret_keys if defined?(@proxima_service_identity_secret_keys)

      @proxima_service_identity_secret_keys =
        Proxima::ALL_STAMPS.each_with_object({}) do |stamp, h|
          key = "PROXIMA_SERVICE_IDENTITY_SECRET_KEY_#{stamp.underscore.upcase}"
          h[stamp] = ENV[key]
        end
    end
    attr_writer :proxima_service_identity_secret_keys

    # "PROXIMA_SERVICE_IDENTITY_SECRET_KEY" is federated to by convention for github applications in proxima stamps, configured
    # here: https://github.com/github/secrets-federation/blob/395adce0bcf771e1e878058b26e97bfbe610c432/config/federation/github/production/federation.yaml#L302-L305.
    # This is generally expected to have a value on stamps who are generating tokens to communicate with dotcom production.
    def proxima_service_identity_default_secret_key
      return @proxima_service_identity_default_secret_key if defined?(@proxima_service_identity_default_secret_key)

      @proxima_service_identity_default_secret_key = ENV["PROXIMA_SERVICE_IDENTITY_SECRET_KEY"]
      raise "PROXIMA_SERVICE_IDENTITY_SECRET_KEY is not configured for this stamp" unless @proxima_service_identity_default_secret_key
      @proxima_service_identity_default_secret_key
    end
    attr_writer :proxima_service_identity_default_secret_key

    def domain_interface_caching?
      return @domain_interface_caching if defined?(@domain_interface_caching)
      @domain_interface_caching = true
    end
    attr_writer :domain_interface_caching

    # Populated by the ENTERPRISE_WEB_SOCKETS_RATE_LIMIT variable or alternatively enabled with a dotcom feature flag.
    # (defaults to rate limiting on the 100th request)
    #
    # GHES admins can configure this rate limit by running:
    # ghe-config app.github.web-sockets-rate-limit 50 && ghe-config-apply
    # GHES admins can disable this rate limit by running:
    # ghe-config app.github.web-sockets-rate-limit 0 && ghe-config-apply
    def web_sockets_rate_limit
      return @web_sockets_rate_limit if defined?(@web_sockets_rate_limit)
      @web_sockets_rate_limit = [0, GitHub.environment.fetch("ENTERPRISE_WEB_SOCKETS_RATE_LIMIT", "99").to_i].max
    end

    # Allow the rebase_merge_allowed setting to be the canonical repository
    # setting determining whether rebase commits are generated on merge commit
    # calculation.
    #
    # This is in response to Salesforce needing to continually disable rebase
    # commit generation between GHES releases, and is a potential precursor to
    # changing the way we allow customers to skip rebase commit generation in
    # both enterprise and non-enterprise environments.
    #
    # More context on the Salesforce issue:
    # https://github.com/github/ghes/issues/11427
    #
    # Additional context in a pull requests issue:
    # https://github.com/github/pull-requests/issues/19821
    def skip_rebase_commit_generation_from_rebase_merge_settings
      @skip_rebase_commit_generation_from_rebase_merge_settings ||= false
    end
    attr_writer :skip_rebase_commit_generation_from_rebase_merge_settings

    # Enable push debug logging in GHES to assist with debugging webhook and PR update issues.
    # Set via ENTERPRISE_PUSH_DEBUG_LOGGING_ENABLED environment variable.
    attr_accessor :push_debug_logging_enabled
  end
end

# bring in otherwise untouched modules
require "github/config/dependency_graph"
require "github/config/first_party_apps"
require "github/config/datacenter"
require "github/config/prefix_environment"
require "github/config/proxima_synced_third_party_apps"
require "github/config/fastly"
require "github/config/importers"
require "github/config/kredz"
require "github/config/varz"
require "github/config/launch"
require "github/config/legacy_textile_formatting"
require "github/config/dreamlifter"
require "github/config/migration"
require "github/config/render"
require "github/config/smtp"
require "github/config/spokes"
require "github/config/spokesd"
require "github/config/support_link"
require "github/config/logging"
require "github/config/pages"
require "github/config/request_limits"
require "github/config/rate_limits"
require "github/config/opentelemetry"
require "github/config/hydro"
require "github/config/redis"
require "github/config/group_syncer"
require "github/config/dependabot"
require "github/config/education"
require "github/config/twirp"
require "github/config/driftwood"
require "github/config/pull_requests"
require "github/config/repositories"
require "github/config/s3"
require "github/config/registry"
require "github/config/system_roles"
require "github/config/fine_grained_permissions"
require "github/config/fine_grained_resources"
require "github/config/elasticsearch"
require "github/config/open_api"
require "github/config/audit_log_curator"
require "github/config/audit_log"
require "github/config/billing"
require "github/config/after_response"
require "github/config/features"
require "github/config/api_versioning"
require "github/config/insights"
require "github/config/http_fluentbit"
require "github/config/code_scanning"
require "github/config/codeql_variant_analysis"
require "github/config/octoshift_storage"
require "github/config/oidc_providers"
require "github/config/bing_indexnow"
require "github/config/chatops"
require "github/config/issues_graph_api"
require "github/config/memex"
require "github/config/merge_queue"
require "github/config/merge_commit_update_refs"
require "github/config/request_timeout"
require "github/config/codespaces"
require "github/config/copilot"
require "github/config/azure"
require "github/config/multi_tenant_enterprise"
require "github/config/notebooks"
require "github/config/viewscreen"
require "github/config/freno"
require "github/config/actions_results"
require "github/config/conduit"
require "github/config/actions_broker"
require "github/config/actions_broker_worker"
require "github/config/actions_all_domains"
require "github/config/actions_jwt_auth"
require "github/config/actions_runner_admin"
require "github/config/actions_run_service"
require "github/config/actions_scale_unit_domains"
require "github/config/proxima"
require "github/config/proxima_login_experience"
require "github/config/copilot_api"
require "github/config/git_src_migrator"
require "github/config/projects"
require "github/config/apps_privileged_api"
require "github/config/enterprise_accounts"
require "github/config/orca"
require "github/config/orcid"
require "github/config/models"
require "github/config/gotauth"
require "github/config/reposd"
require "github/config/artifact_attestations"
require "github/config/api_insights"
require "github/config/migrations_vnext"
require "github/config/commit_contributions"
require "github/config/copilot_metrics"
require "github/config/figma"
