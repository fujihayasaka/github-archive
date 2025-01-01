# typed: true
# frozen_string_literal: true

require "github/current_tenant"

module GitHub
  module Middleware
    class TenantSelection
      SUFFIXED_REQUEST_BLOCKED_MESSAGE = "Unable to complete request that contains suffixed user or organization name in the path. Remove the suffix from the name and request again."

      GITAUTH_PATH = "/_gitauth"
      GITAUTH_COMMIT_REFS_PATH = "/_commit_refs"

      LEGACY_TENANT_IDENTIFIER_REQUEST_KEY = "tenant_context.legacy_tenant_identifier".freeze
      MISSING_TENANT_HEADER_REQUEST_KEY = "tenant_context.missing_tenant_header".freeze

      class InvalidTenantIDError < StandardError; end
      class SuffixedRequestError < StandardError; end

      def initialize(app)
        @app = app
      end

      def call(env)
        return @app.call(env) unless GitHub.multi_tenant_enterprise?

        # Force reset tenant context (including query scoping) to default states (null, scoped).
        GitHub::CurrentTenant.reset

        request = ActionDispatch::Request.new(env)
        set_tenant(request) do
          tenant_scope_request(request) do
            log_tenant_context(request) do
              @app.call(env)
            end
          end
        end
      rescue InvalidTenantIDError => e
        # Provided tenant identifier was not found.
        [422, { "Content-Type" => "text/plain" }, [e.message]]
      rescue SuffixedRequestError => e
        [404, { "Content-Type" => "text/plain" }, [e.message]]
      ensure
        # clean up
        GitHub::CurrentTenant.reset
      end

      private

      def set_tenant(request, &block)
        business = find_tenant(request)

        # Skip setting null tenant.
        # FIXME: We should be setting the null tenant here, but we have a lot of tests that
        # rely on the tenant being set before the request. We should fix those tests and then remove this.
        return yield unless business.present?

        GitHub::CurrentTenant.set(business) do
          yield
        end
      ensure
        report_missing_tenant_header(request)
      end

      def find_tenant(request)
        identifier, key = find_tenant_identifier(request)
        return unless identifier.present?

        business = ActiveRecord::Base.connected_to(role: :reading) do
          case key
          when :id
            Business.find(identifier)
          when :suffix
            Business.find_by(shortcode: identifier)
          else
            Business.find_by(slug: identifier)
          end
        end

        # If a tenant identifier was given but no tenant was found, raise an error.
        if business.nil? && !GitHub.flipper[:unknown_tenant_error_disabled].enabled?
          raise InvalidTenantIDError, "Couldn't find Business with #{key} = #{identifier}"
        end

        if business.present? && block_suffixed_request?(request, business)
          log_suffixed_request_blocked(request, business)
          raise SuffixedRequestError, SUFFIXED_REQUEST_BLOCKED_MESSAGE
        end

        business
      end

      def find_tenant_identifier_from_header(request)
        header_value = request.headers["HTTP_X_GITHUB_TENANT"].presence
        return parse_tenant_header_value(header_value) if header_value

        request.env[MISSING_TENANT_HEADER_REQUEST_KEY] = true

        [nil, :missing]
      end

      def find_tenant_identifier(request)
        # Prefer the `X-GitHub-Tenant` header.
        identifier, key = find_tenant_identifier_from_header(request)
        return [identifier, key] if identifier.present? && key != :missing

        # Exclusively use the `X-GitHub-Tenant` header unless the legacy identifiers feature flag is enabled.
        return [nil, :missing] unless allow_legacy_tenant_identifiers?

        case request.path
        when GITAUTH_PATH
          # This is specifically used for git operations to function in multi tenant mode.
          # In future iterations we'd like to find a consistent pattern that can be used
          # accross all services to persist the tenant information.
          hostname = request.POST["hostname"]
          return if hostname.blank?

          request.env[LEGACY_TENANT_IDENTIFIER_REQUEST_KEY] = "gitauth:hostname:#{hostname}"

          [hostname.split(".").first, :slug]
        when GITAUTH_COMMIT_REFS_PATH
          # This is specifically used for git operations to function in multi tenant mode.
          # In future iterations we'd like to find a consistent pattern that can be used
          # accross all services to persist the tenant information.
          begin
            body = GitAuth::CommitRefsRequestBody.new(request.body.read)
            ctx = GitHub::JSON.parse(body.commit_ref_ctx)
            request.env[LEGACY_TENANT_IDENTIFIER_REQUEST_KEY] = "gitauth_commit_refs:tenant:#{ctx["tenant"]}"
            [ctx["tenant"].presence, :slug]
          rescue ::JSON::ParserError
            [nil, nil] # unable to parse JSON, no tenant identifier to return
          ensure
            request.body.rewind # ensure we leave the body readable within the application
          end
        else
          if GitHub::Routers::Api.internal_api_host?(request.host)
            # Internal API requests are unscoped by default, so do not attempt to detect the tenant from the request.
            return [nil, :missing]
          end

          request.env[LEGACY_TENANT_IDENTIFIER_REQUEST_KEY] = "hostname:subdomain:#{request.subdomains.last}"

          [request.subdomains.last, :slug]
        end
      end

      def parse_tenant_header_value(value)
        if value["="]
          key, value = value.split("=", 2)
          case key
          when "id"
            [value, :id]
          when "sc", "suffix"
            [value, :suffix]
          else
            [value, :slug]
          end
        else
          [value, :slug]
        end
      end

      # Internal: Whether to identify the tenant from the X-GitHub-Tenant header exclusively or to allow inferring
      # tenant identity via legacy means (from hostname or GitAuth payloads).
      #
      # The `allow_legacy_tenant_identifiers` feature flag controls this check; by default, the X-GitHub-Tenant
      # header is the only valid identifier. If the feature flag is enabled, legacy identifiers are supported.
      #
      # Returns true when legacy identifiers are enabled (via feature flag), false otherwise.
      def allow_legacy_tenant_identifiers?
        GitHub.flipper[:allow_legacy_tenant_identifiers].enabled?
      end

      def report_missing_tenant_header(request)
        return unless request.env[MISSING_TENANT_HEADER_REQUEST_KEY]
        # ignore internal status checks (will never have the header)
        return if request.path_info.start_with?("/status")
        log_data = (request.env[Rack::RequestLogger::APPLICATION_LOG_DATA] || GitHub::Logger.empty).merge({
          "code.namespace" => "TenantSelection",
          "code.function" => "missing_tenant_header",
          "http.url" => request.url,
          "http.method" => request.request_method,
          "http.user_agent" => request.user_agent,
        })

        GitHub.logger.info(log_data)
      end

      # Tenant scoping is enabled by default. For internal API requests, we need to disable tenant scoping when
      # tenant context is not provided and scoping the request to a specific tenant is not possible.
      #
      # Internal API requests are not required to provide a tenant context.
      def tenant_scope_request(request)
        # keep scoping unless we are confident this request qualifies for unscoping
        return yield unless unscope_request_for_internal_services?(request)

        GitHub::CurrentTenant.unscope do
          yield
        end
      end

      def unscope_request_for_internal_services?(request)
        # Return false if the request is a tenant request.
        return false if GitHub::CurrentTenant.get.present?

        # Validate configuration allows unscoping in this environment.
        return false unless GitHub.proxima_internal_api_request_scoping_disabled?

        # Only requests targeting the internal-api host are allowed to be unscoped.
        # This includes both public and internal API endpoints.
        GitHub::Routers::Api.internal_api_host?(request.host)
      end

      def log_tenant_context(request)
        logging_context = GitHub::CurrentTenant.logging_context
        GitHub.logger.with_named_tags(logging_context) do
          yield
        end
      ensure
        log_data_for(request.env).merge!(GitHub::CurrentTenant.logging_context)
      end

      def block_suffixed_request?(request, business)
        # Only requests targeting the internal-api host and stafftools are allowed to have suffixed login and name_with_owner
        return false if GitHub::Routers::Api.internal_api_host?(request.host)
        return false if business.stafftools_tenant?
        shortcode = business.shortcode

        path = request.path
        return false unless path

        suffix_regex = %r{_#{shortcode}}
        # if path contains shortcode suffix, block the request
        return true if suffix_regex =~ path

        query_string = request.query_string
        return false unless query_string

        # if query string contain shortcode suffix, block the request
        return true if suffix_regex =~ query_string

        false
      end

      def log_suffixed_request_blocked(request, business)
        log_fields = {
          "code.namespace" => "GitHub::Middleware::TenantSelection",
          "code.function" => "log_suffixed_request_blocked",
          "http.url" => request.url,
          "http.method" => request.request_method,
          "http.user_agent" => request.user_agent,
          "gh.business.id" => business.id,
          "gh.business.shortcode" => business.shortcode,
          "gh.blocking_enabled" => true,
        }

        if request.referrer
          log_fields.merge({ "http.request.header.referer" => request.referrer })
        end

        # splunk
        GitHub.logger.error(log_fields)

        # send to datadog
        GitHub.dogstats.increment("tenant_selection.suffixed_request_blocked", tags: ["method:#{request.request_method}"])
      end

      def log_data_for(env)
        env[Rack::RequestLogger::APPLICATION_LOG_DATA] ||= GitHub::Logger.empty
      end
    end
  end
end
