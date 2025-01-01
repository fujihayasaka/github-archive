# typed: true
# frozen_string_literal: true

require "forwardable"

module GitHub
  class UrlBuilder
    attr_reader :host_name, :scheme, :no_api_prefix_with_suffix
    attr_writer :api_url, :internal_api_url, :codeload_host_name, :raw_host_name, :alive_ws_url
    extend Forwardable
    def_delegators "GitHub", :enterprise?, :employee_unicorn?, :garage_unicorn?, :use_api_path_prefix?

    def initialize(host_name:, smtp_domain: nil, noreply_address: nil, scheme: "https", no_api_prefix_with_suffix: false)
      @host_name = host_name
      @smtp_domain = smtp_domain
      @noreply_address = noreply_address
      @scheme = scheme
      @no_api_prefix_with_suffix = no_api_prefix_with_suffix
    end

    # The main GitHub site URL.
    #
    # Returns the URL string ("https://github.com", "http://github.localhost")
    def url
      @url ||= "#{scheme}://#{host_name}".freeze
    end

    def http_url
      @http_url ||= "http://#{host_name}".freeze
    end

    ##
    # Codeload (Download Server)

    # The codeload root URL. This value typically isn't written directly but
    # should be read anywhere the root URL for codeload is required. It returns
    # the http:// or https:// version of the URL based on whether the #ssl
    # config attribute is set.
    #
    # Returns the codeload URL string ("https://codeload.github.com",
    # "http://codeload.github.localhost", etc)
    def codeload_url
      @codeload_url ||= "#{scheme}://#{codeload_host_name}".freeze
    end

    # The codeload hostname and possibly port. No http:// prefix or protocol
    # information is included. By default, this is the configured host_name with
    # a "codeload." prefix.
    #
    # Returns the hostname string ("codeload.github.com",
    # "codeload.stg.github.com", etc)
    def codeload_host_name
      @codeload_host_name ||= case
      when enterprise?
        ENV["ENTERPRISE_CODELOAD_HOST_NAME"] || "codeload.#{host_name}".freeze
      else
        "codeload.#{host_name}".freeze
      end
    end

    # Raw hostname. No http:// prefix or protocol information is included.
    # No default b/c Enterprise might not use a FQDN.
    #
    # Returns String host or nil.
    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def raw_host_name
      @raw_host_name ||= case
      when GitHub.single_or_multi_tenant_enterprise?
        if GitHub.subdomain_isolation?
          "raw.#{user_content_host_name}".freeze
        end
      else
        "raw.#{user_content_host_name}".freeze
      end
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    # The raw site URL.
    #
    # production:  https://raw.githubusercontent.com
    # development: http://raw.githubusercontent.dev
    #
    # Returns the URL string or nil.
    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def raw_host_url
      @raw_host_url ||= if raw_host_name.present?
        "#{scheme}://#{raw_host_name}".freeze
      end
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    def memory_alpha_subdomain
      "objects-origin"
    end

    def memory_alpha_url
      subdomain = memory_alpha_subdomain
      if GitHub.multi_tenant_enterprise?
        domain = host_name
      else
        if !Rails.env.production?
          subdomain = "objects-staging-origin"
        end
        domain = "githubusercontent.com"
      end
      GitHub.environment.fetch("MEMORY_ALPHA_URL", "#{scheme}://#{subdomain}.#{domain}")
    end

    # The LFS hostname. This is the configured host_name with a "lfs." prefix.
    #
    # Don't call _lfs_server_url directly! Use GitHub.lfs_server_url, which is
    # set via env var on enterprise.
    #
    # Returns the hostname string ("lfs.github.com", "lfs.avocado-gmbh.ghe.com", etc)
    def _lfs_server_url
      @_lfs_server_url ||= "#{scheme}://lfs.#{host_name}".freeze
    end

    # The LFS storage hostname. This is the configured host_name with an
    # "objects-origin." prefix.
    #
    # Returns the hostname string ("objects-origin.avocado-gmbh.ghe.com", etc)
    def lfs_storage_host
      @lfs_storage_host ||= "#{memory_alpha_subdomain}.#{host_name}".freeze
    end

    # TODO: Ensure configurable for Enterprise.
    def smtp_domain
      @smtp_domain || host_name
    end

    # TODO: Ensure configurable for Enterprise.
    # Enterprise customers may want to customize the email address used as the
    # noreply sender.
    #
    # Returns an email address as a string. Default is noreply@<host_name>.
    def noreply_address
      if GitHub.enterprise?
        GitHub.noreply_address
      else
        @noreply_address || "noreply@#{smtp_domain}"
      end
    end

    # The From address for notifications.
    #
    # Returns an email address as a string.
    def notifications_sender_address
      "notifications@#{smtp_domain}"
    end

    # This is the email domain used for replyable notification emails sent from
    # the GitHub instance. Inbound email is processed by github/mail-replies
    # from this subdomain, and emails that match are posted to the GitHub instance.
    #
    # Returns the URL string ("reply.github.com")
    def mail_reply_host_name
      "reply.#{host_name}".freeze
    end

    # octocaptcha

    # Public: Returns the host used for GitHub octocaptcha.
    #
    # production:  octocaptcha.com
    # development: octocaptcha.localhost
    # enterprise: n/a (only enabled in dotcom)
    # enterprise with subdomain isolation: n/a (only enabled in dotcom)
    #
    # Returns the octocaptcha hostname string
    def octocaptcha_host_name
      if Rails.env.development? || Rails.env.test?
        "octocaptcha.localhost".freeze
      elsif GitHub.dynamic_lab?
        "#{GitHub.dynamic_lab_name.parameterize}.octocaptcha.review-lab.github.com".freeze
      else
        "octocaptcha.com".freeze
      end
    end

    # Public: Returns the url used for GitHub octocaptcha.
    #
    # production:  https://octocaptcha.com
    # development: http://octocaptcha.localhost
    #
    # origin = origin that octocaptcha.com will accept as a valid parent frame
    #          ex. my-branch.review-lab.github.com
    #
    # Returns the octocaptcha url string
    def octocaptcha_url
      "#{scheme}://#{octocaptcha_host_name}".freeze
    end

    # Public: Returns the octocaptcha iframe src url with params used for GitHub octocaptcha.
    #
    # ex
    # production:  https://octocaptcha.com?origin_page=github_signup
    # development: http://octocaptcha.localhost?origin_page=localhost
    #
    # Returns the octocaptcha url string
    def octocaptcha_url_with_src_params(origin_page, version: nil, captcha_demo: nil)
      octocaptcha_params = []

      # Set origin parameter for review-lab
      if ENV["STAFF_ENVIRONMENT_HOSTNAME"].present?
        staff_host = "#{scheme}://#{garage_api_host_name}".freeze
        octocaptcha_params << "origin=#{staff_host}"
      elsif Rails.env.development?
        octocaptcha_params << "origin=#{GitHub.url}"
      end

      # Set origin_page parameter for metrics
      octocaptcha_params << "origin_page=#{origin_page}" unless origin_page.blank?
      octocaptcha_params << "responsive=true"
      octocaptcha_params << "require_ack=true"
      octocaptcha_params << "version=#{version}" if version
      octocaptcha_params << "captcha_demo=true" if captcha_demo

      "#{octocaptcha_url}?#{octocaptcha_params.join("&")}"
    end

    ##
    # registry

    # Public: Returns the host used for GitHub Package Registry.
    #
    # production:  <registry_name>.pkg.github.com (ghcr.io for container registry)
    # development: <registry_name>.pkg.github.localhost
    # enterprise: github.com/_registry/<registry_name>
    # enterprise with subdomain isolation: <registry_name>.github.com
    #
    # Returns the hostname string
    def registry_host_name(registry_name)
      if GitHub.single_or_multi_tenant_enterprise?
        if GitHub.subdomain_isolation? || GitHub.multi_tenant_enterprise?
          return "#{registry_name}.#{host_name}"
        else
          return "#{registry_name}.#{host_name}" if registry_name == :containers
          return "#{host_name}" if registry_name.to_s == "docker"
          return "#{host_name}/_registry/#{registry_name}"
        end
      end
      if Rails.env.production? && registry_name == :containers
        return "ghcr.io"
      end
      if Rails.env.development? && registry_name == :containers
        return "github.localhost:8001"
      end
      "#{registry_name}.pkg.#{host_name}"
    end

    # Public: Returns the path used for GitHub nuget Package Registry.
    #
    # production:  https://nuget.pkg.github.com/:owner
    # development: https://nuget.pkg.github.localhost/:owner
    # enterprise:  https://github.com/_registry/nuget/:owner
    # enterprise with subdomain isolation: https://nuget.github.com/:owner
    #
    # Returns the nuget service base url :owner
    def nuget_service_base_url(owner)
      "#{registry_url(:nuget)}#{owner}"
    end

    # Public: Returns the URL used for GitHub Package Registry.
    #
    # production:  <registry_name>.pkg.github.com
    # development: <registry_name>.pkg.github.localhost
    # enterprise:
    #     With sub-domain isolation
    #       <registry_name>.<host_name>/
    #     Without sub-domain isolation
    #       <host_name>/_registry/<registry_name>
    #
    # Returns the url for <registry_name> registry service
    def registry_url(registry_name)
      "#{scheme}://#{registry_host_name(registry_name)}/"
    end

    # Public: Is GitHub Package Registry running on a subdomain?
    #
    # True if not on Enterprise, or on Enterprise with subdomain isolation.
    #
    # Returns a boolean.
    def registry_on_subdomain?
      return true if !enterprise?
      return true if GitHub.subdomain_isolation?
      false
    end

    ##
    # Alive

    # Public: Returns the host used for alive requests.
    #
    # production:  alive.github.com
    # review-lab:  alive.github.com
    # development: alive.github.localhost
    # enterprise:  Same host the app is running on.
    #
    # Returns String URL or nil.
    def alive_host
      @alive_host ||= if (host_from_env = ENV["ALIVE_HOST"])
        host_from_env
      elsif enterprise?
        host_name
      else
        "alive.#{host_name}"
      end
    end

    def alive_scheme
      GitHub.ssl? ? "wss" : "ws"
    end

    # Public: Returns the host used for alive requests.
    #
    # production:  wss://alive.github.com
    # development: ws://alive.github.localhost
    # enterprise:  ws(s)://github.com
    #
    # Returns String URL.
    def alive_ws_url
      @alive_ws_url ||= begin
        alive_ws_url = "#{alive_scheme}://#{alive_host}"
        alive_ws_url.freeze
      end
    end

    # The host name that the API is served from.
    #
    # Returns a String.
    def api_host_name
      @api_host_name ||= case
      when host_name_from_env = ENV.fetch("API_HOST_NAME", false)
        host_name_from_env.freeze
      when GitHub.single_tenant_enterprise? || (no_api_prefix_with_suffix && use_api_path_prefix?)
        host_name
      when garage_unicorn?
        garage_api_host_name
      else
        "api.#{host_name}".freeze
      end
    end

    # The URL where the V3 API is served from. This defaults to the configured
    # host_name with an "api." prefix.
    #
    # Returns the API url string (e.g. "https://api.github.com" for production)
    def api_url
      @api_url ||= "#{scheme}://#{api_host_name}#{api_root_path}".freeze
    end

    # The URL where the API is served from. This defaults to the configured
    # host_name with an "api." prefix.
    #
    # Returns the API url string (e.g. "https://api.github.com" for production)
    def graphql_api_url
      @graphql_api_url ||= "#{scheme}://#{api_host_name}#{graphql_api_root_path}".freeze
    end

    # The root path of the V3 API.
    #
    # Returns a String.
    def api_root_path
      @api_root_path ||= case
      when use_api_path_prefix?
        "/api/v3".freeze
      else
        "".freeze
      end
    end

    # The host name that the API is served from.
    #
    # Returns a String.
    def internal_api_host_name
      @internal_api_host_name ||= case
      when enterprise?
        host_name
      when garage_unicorn?
        garage_api_host_name
      when Rails.env.development?
        ENV.fetch("INTERNAL_API_HOST_NAME", "").freeze.presence || api_host_name
      else
        GitHub.environment["INTERNAL_API_HOST_NAME"]
      end
    end

    # The URL where the V3 API is served from. This defaults to the configured
    # host_name with an "api." prefix.
    #
    # Returns the API url string (e.g. "https://api.github.com" for production)
    def internal_api_url
      @internal_api_url ||= "#{scheme}://#{internal_api_host_name}#{internal_api_root_path}".freeze
    end

    # The root path of the V3 API.
    #
    # Returns a String.
    def internal_api_root_path
      if GitHub.multi_tenant_enterprise?
        return "".freeze
      end

      api_root_path
    end

    # The root path of the GraphQL API.
    #
    # Returns a String.
    def graphql_api_root_path
      @graphql_api_root_path ||= case
      when use_api_path_prefix?
        "/api/graphql".freeze
      else
        "/graphql".freeze
      end
    end

    # Wild card matching hostname matching githubusercontent.com subdomains.
    #
    # production:  *.githubusercontent.com
    # development: *.githubusercontent.dev
    #
    # Returns String host or nil.
    def user_content_host_wildcard
      return @user_content_host_wildcard if defined?(@user_content_host_wildcard)
      @user_content_host_wildcard = "*.#{user_content_host_name}"
    end

    # Hostname for githubusercontent.com.
    #
    # production:  githubusercontent.com
    # development: githubusercontent.dev
    #
    # Returns String host or nil.
    def user_content_host_name
      if Rails.env.development? || GitHub.single_or_multi_tenant_enterprise?
        host_name
      else
        "githubusercontent.com".freeze
      end
    end

    def stafftools_url
      @stafftools_url ||= case
      when GitHub.admin_host_name
        "#{scheme}://#{GitHub.admin_host_name}".freeze
      else
        url
      end
    end

    private

    def tld
      Rails.env.development? ? "dev" : "com"
    end

    class MissingGarageHostname < StandardError; end

    # Private: return the correct api host name for a garage instance
    def garage_api_host_name
      hostname = ENV["STAFF_ENVIRONMENT_HOSTNAME"]

      local_host_name = GitHub.local_host_name
      hostname ||= {
        "github-staff2-cp1-prd.iad.github.net" => "garage.github.com",
      }[local_host_name]

      unless hostname
        raise MissingGarageHostname, "No matching external hostname for garage host #{local_host_name}"
      end

      hostname
    end
  end
end
