# typed: false
# frozen_string_literal: true

##
# Pages configuration.

module GitHub
  module Config
    module Pages
      # Flag indicating whether Pages are enabled in this environment. This is
      # set by the ENTERPRISE_PAGES_ENABLED environment variable in the
      # enterprise environment, which is populated via the pages.enabled
      # configuration value.
      #
      # Returns Boolean indicating whether Pages are enabled.
      def pages_enabled?
        return @pages_enabled if defined?(@pages_enabled)
        @pages_enabled = true
      end
      attr_writer :pages_enabled

      # Flag indicating whether Pages are published publicly in a GHES
      # environment. This is set by the ENTERPRISE_PUBLIC_PAGES environment
      # variable in the enterprise environment, which is populated via the
      # core.public-pages configuration value.
      #
      # Returns Boolean indicating whether Pages are public.
      def public_pages?
        return @public_pages if defined?(@public_pages)
        @public_pages = false
      end
      attr_writer :public_pages

      # Flag indication whether private pages are enabled, which is always false
      # in enterprise.
      #
      # Returns a Boolean
      def private_pages_enabled?
        !GitHub.enterprise?
      end

      # Flag indicating whether pages owners can prove ownership of a domain name
      # through DNS records
      #
      # Returns a Boolean
      def pages_domain_protection_enabled?
        return false if GitHub.single_tenant_enterprise?
        return false if GitHub.multi_tenant_enterprise?
        true
      end

      # Root directory where fully-built Pages sites are served from. This
      # defaults to the tmp/pages directory under RAILS_ROOT, but is typically
      # overridden in production environments.
      #
      # Returns the full path to the Pages directory as a String.
      def pages_dir
        @pages_dir ||=
          if Rails.env.test?
            # NOTE we are randomizing the path to make sure concurrent builds have different paths. See #111803
            File.expand_path("#{Rails.root}/tmp/#{SecureRandom.uuid}/pages#{test_environment_number}").freeze
          else
            return "/data/pages" if GitHub.multi_tenant_enterprise?
            File.expand_path("#{Rails.root}/tmp/pages").freeze
          end
      end
      attr_writer :pages_dir

      # Directory which contains the copy of pages-jekyll code.
      #
      # Returns the full path to the Pages application code directory as a String.
      def pages_jekyll_dir
        return ENV["GH_PAGES_JEKYLL_DIR"] if ENV["GH_PAGES_JEKYLL_DIR"]
        @pages_jekyll_dir ||=
          if File.exist?("/data/pages-jekyll/current")
            File.realpath("/data/pages-jekyll/current").freeze
          else
            "/data/pages-jekyll"
          end
      end

      # Temporary directory where Pages sites are built before being copied to the
      # pages_dir. This defaults to the tmp/pagebuild/<environment> directory, but
      # is typically overridden in production environments.
      #
      # Returns the full path to the Pages build directory as a String.
      def pages_build_dir
        @pages_build_dir ||=
          if Rails.env.test?
            File.expand_path("#{Rails.root}/tmp/pagebuild/#{Rails.env}#{test_environment_number}").freeze
          else
            File.expand_path("#{Rails.root}/tmp/pagebuild/#{Rails.env}").freeze
          end
      end
      attr_writer :pages_build_dir

      # The maximum size of a built pages site in bytes. Set to 0 to disable
      # the size limit.
      def pages_site_size_limit
        @pages_site_size_limit ||= (10 * 1024 * 1024 * 1024) # 10 GB
      end
      attr_writer :pages_site_size_limit

      # ID of the GitHub Pages Oauth App
      #
      # Returns int ID the application ID, or nil if app doesn't exist
      def pages_app_id
        @pages_app_id ||= OauthApplication.where(
          user_id: trusted_oauth_apps_owner,
          name: Apps::Internal::Pages::OAUTH_APP_NAME,
        ).pluck(:id).first
      end
      attr_writer :pages_app_id

      # Public: The GitHub App (Integration).
      def pages_github_app
        @pages_github_app ||= Integration.where(
          owner_id: trusted_oauth_apps_owner,
          name: pages_github_app_name,
        ).first
      end

      # Public: The name of the Pages GitHub App.
      def pages_github_app_name
        Apps::Internal::Pages::INTEGRATION_NAME
      end

      # Public: The slug of the Pages GitHub App.
      def pages_github_app_slug
        @pages_github_app_slug ||= "github-pages"
      end

      # Public: The name used when creating a CheckRun.
      def pages_check_run_name
        @pages_check_run_name ||= "Page Build"
      end

      def pages_github_app_available?
        !GitHub.enterprise?
      end

      def pages_help_url
        "#{GitHub.help_url}/categories/github-pages-basics"
      end

      def pages_visibility_help_url
        "#{GitHub.help_url}/github/working-with-github-pages/changing-the-visibility-of-your-github-pages-site"
      end

      def pages_custom_domain_help_url
        "#{GitHub.help_url}/github/working-with-github-pages/configuring-a-custom-domain-for-your-github-pages-site"
      end

      # GitHub Pages Auth Url
      #
      # Returns the URL string
      def pages_auth_url
        if GitHub.multi_tenant_enterprise?
          "https://pages.#{GitHub::CurrentTenant.get}.ghe.com"
        else
          "https://pages-auth.github.com"
        end
      end

      def pages_auth_host_name
        if GitHub.multi_tenant_enterprise?
          "pages.#{GitHub::CurrentTenant.get}.ghe.com"
        else
          "pages-auth.github.com"
        end
      end

      attr_accessor :pages_replica_count
      attr_accessor :pages_azure_replica_count
      attr_accessor :pages_dfs_datacenters
      attr_accessor :pages_replica_count_per_datacenters


      def pages_replication_strategy
        @pages_replication_strategy ||= if Rails.env.production? && !enterprise?
          GitHub::Pages::ReplicationStrategy.new(
            data_centers: %w(ac4 ash1 va3),
            replica_counts: [2, 2, 1],
          )
        else
          GitHub::Pages::ReplicationStrategy.new
        end
      end
      attr_writer :pages_replication_strategy

      def pages_beta_replication_strategy
        @pages_beta_replication_strategy ||= if Rails.env.production? && !enterprise?
          GitHub::Pages::ReplicationStrategy.new(
            data_centers: %w(ac4 ash1 va3),
            replica_counts: [2, 2, 1],
          )
        else
          GitHub::Pages::ReplicationStrategy.new
        end
      end
      attr_writer :pages_beta_replication_strategy

      # Gets the number of readonly replicas that are included in a page build,
      # but not required for a successful consensus.
      attr_accessor :pages_non_voting_replica_count

      # Do we support custom pages CNAMEs in this environment?
      #
      # When custom CNAMEs are enabled, pages sites are served from
      # USERNAME.github.io, or a custom domain the user provides in a `CNAME` file.
      #
      # When custom CNAMEs are disabled, pages sites are served from
      # /pages/USERNAME/REPO and any `CNAME` file is ignored.
      #
      def pages_custom_cnames?
        !(enterprise? || GitHub.multi_tenant_enterprise?)
      end

      # Orgs/users that are owned by GitHub and should be allowed to use
      # `github.com` urls.
      #
      # Returns an Array of String User/Organization logins.
      def github_owned_pages
        @github_owned_pages ||= []
      end

      # The GitHub Pages hostname only.
      #
      # Returns the hostname string ("githubpages.com", "github.io", etc.) or nil
      # if no host_name has been set.
      def pages_host_name_v1
        @pages_host_name ||= GitHub.host_name
      end
      attr_writer :pages_host_name

      # The GitHub Pages hostname we are migrating to
      #
      # Returns the hostname string (i.e. "github.io") if we are in an environment
      # that supports it,  or nil if no host_name has been set.
      def pages_host_name_v2
        return pages_host_name_proxima if GitHub.multi_tenant_enterprise?
        @pages_host_name_v2 ||= if enterprise?
          if GitHub.subdomain_isolation?
            "pages.#{GitHub.host_name}"
          else
            GitHub.host_name
          end
        else
          "github.io".freeze
        end
      end
      attr_writer :pages_host_name_v2

      # The GitHub Pages hostname for Multi-Tenant
      #
      # Returns the hostname with the tenant name (i.e. pages.{tenant}.ghe.com) if we are in an environment
      # that supports it, or nil if no tenant_host_name has been set.
      def pages_host_name_proxima
        "pages.#{GitHub.host_name_with_tenant}"
      end
      attr_writer :pages_host_name_proxima

      def pages_preview_hostname
        @pages_preview_hostname ||= "drafts.github.io"
      end
      attr_writer :pages_preview_hostname

      # Do we support HTTPS redirects for pages sites?
      #
      # Returns boolean.
      def pages_https_redirect_enabled?
        !enterprise?
      end

      # Pages for repositories created after this time will require HTTPS if they
      # are served from github.io.
      #
      # This is only used it tests for now, so it's set to an hour from now.
      #
      # Returns a Time instance.
      def pages_https_required_after
        @pages_https_required_after ||= Time.parse("2016-06-15 12:00:00 PDT")
      end

      # Domains that we have SSL certs for on Fastly.
      #
      # Returns an Array of Strings.
      def pages_https_domains
        if enterprise?
          []
        else
          %w(
            blog.atom.io
            electron.atom.io
            flight-manual.atom.io

            brew.sh
            docs.brew.sh

            choosealicense.com
            codeconf.com
            github.co.jp
            githubengineering.com
            githubuniverse.com
            git-merge.com
            opensource.guide
            svnhub.com
          )
        end
      end

      def pages_custom_domain_https_enabled?
        pages_custom_cnames? && acme_enabled?
      end

      def pages_failbot_backend_file_path
        @pages_failbot_backend_file_path ||= "#{Rails.root}/log/pages-exceptions.log"
      end
      attr_writer :pages_failbot_backend_file_path

      # Do we support creating Let's Encrypt certificates for CNAME pages.
      def acme_enabled?
        !enterprise?
      end

      # ACME protocol endpoint for getting Pages certificates.
      def acme_directory
        return "https://acme-v02.api.letsencrypt.org/directory" if Rails.env.production?
        "https://acme-staging-v02.api.letsencrypt.org/directory"
      end

      # Key for Let's Encrypt certificates.
      def acme_cert_key
        return @acme_cert_key if defined?(@acme_cert_key)

        raw_acme_cert_key = ENV["GITHUB_ACME_LETS_ENCRYPT_CERT_KEY"]
        raise ArgumentError.new("Expected acme cert key to be set in vault") unless raw_acme_cert_key.present?
        @acme_cert_key ||= OpenSSL::PKey::RSA.new(raw_acme_cert_key)
      end

      def acme_account_key
        return @acme_account_key if defined?(@acme_account_key)

        acme_account_key_pem = ENV["GITHUB_ACME_LETS_ENCRYPT_ACCOUNT_KEY"]
        raise ArgumentError.new("Expected acme account key to be set in vault") unless acme_account_key_pem.present?
        @acme_account_key ||= OpenSSL::PKey::EC.new(acme_account_key_pem)
      end

      def acme_secondary_key
        return @acme_secondary_key if defined?(@acme_secondary_key)

        acme_secondary_key_pem = ENV["GITHUB_ACME_LETS_ENCRYPT_SECONDARY_ACCOUNT_KEY"]
        return if acme_secondary_key_pem.blank?
        begin
          @acme_secondary_key ||= OpenSSL::PKey::EC.new(acme_secondary_key_pem)
        rescue OpenSSL::PKey::ECError
          # If the key is not a valid key, we should not use it.
          @acme_secondary_key = nil
        end
      end

      # ACME client for getting Pages certificates.
      # To support key rotation, if the secondary key is set and valid EC key
      # the client will be initialized with it first.
      def acme
        @acme ||= AcmeClient.new(
          primary_key: acme_account_key,
          secondary_key: acme_secondary_key,
          directory: acme_directory
        )
      end

      # A collection of domains for which certificates may not be issued.
      #
      # Returns an Array of domain names. Check the domain with `domain_name.end_with?(denylist_entry)`
      def acme_denylist
        @acme_denylist ||= [
          ".siteleaf.net".freeze,
          ".stack.network".freeze,
          ".streamdata.io".freeze,
        ].freeze
      end

      ###
      ## Dpages maintenance.

      # The maximum number of DpagesRepairSite jobs the DpagesMaintenanceScheduler should enqueue per run.
      def dpages_maintenance_scheduler_batch_size
        @dpages_maintenance_scheduler_batch_size ||= 1000
      end
      attr_writer :dpages_maintenance_scheduler_batch_size

      # The maximum amount of time the DpagesMaintenanceScheduler job has to execute before timing out.
      def dpages_maintenance_scheduler_maximum_execution_time
        @dpages_maintenance_scheduler_maximum_execution_time ||= 30.minutes
      end
      attr_writer :dpages_maintenance_scheduler_maximum_execution_time

      # The interval for scheduling new DpagesMaintenanceScheduler jobs.
      def dpages_maintenance_scheduler_schedule_interval
        @dpages_maintenance_scheduler_schedule_interval ||= 5.minutes
      end
      attr_writer :dpages_maintenance_scheduler_schedule_interval

      # The maximum number of DpagesEvacuateSite jobs the DpagesEvacuationScheduler should enqueue per run.
      def dpages_evacuations_scheduler_batch_size
        @dpages_evacuations_scheduler_batch_size ||= 500
      end

      def deploy_pages_action_tag
        @deploy_pages_action_branch = GitHub.environment.fetch("DEPLOY_PAGES_ACTION_TAG", "v4")
      end
      attr_writer :deploy_pages_action_branch

      def upload_pages_artifact_action_tag
        @upload_pages_artifact_action_tag = GitHub.environment.fetch("UPLOAD_PAGES_ARTIFACT_ACTION_TAG", "v3")
      end
      attr_writer :upload_pages_artifact_action_tag

      def build_pages_action_tag
        @build_pages_action_branch = GitHub.environment.fetch("BUILD_PAGES_ACTION_TAG", "v1")
      end
      attr_writer :build_pages_action_branch

      attr_writer :dpages_evacuations_scheduler_batch_size

      # Sets the HMAC key used to authenticate with the Pages build service
      attr_accessor :pages_builds_hmac_key

      # The URL of a Pages deployer service
      attr_accessor :pages_deployer_url

      # The HMAC key used to authenticate with the Pages deployer service
      attr_accessor :pages_deployer_hmac_key

      def pages_lazy_builds_enabled?
        return @pages_lazy_builds_enabled if defined?(@pages_lazy_builds_enabled)
        @pages_lazy_builds_enabled = GitHub.enterprise?
      end
    end
  end

  extend Config::Pages
end
