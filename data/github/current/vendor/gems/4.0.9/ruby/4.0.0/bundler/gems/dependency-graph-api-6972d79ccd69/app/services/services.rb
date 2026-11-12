require "digest"
require_relative "../../lib/current_request.rb"

module Services
  # Wraps a Twirp::Service class with some helper methods and configuration
  # for error-handling, metrics, etc.
  class RackApp
    TWIRP_PREFIX = "twirp".freeze
    DG_API_APP_NAME = "dependency-graph-api".freeze

    attr_reader :app

    def initialize(twirp_service, app_handler, service_prefix = "")
      @app = build_rack_app(twirp_service, app_handler)
      @service_class = twirp_service
      @service_prefix = service_prefix
    end

    def mount_path
      File.join(TWIRP_PREFIX, @service_prefix + @service_class.service_full_name)
    end

    private

    def build_rack_app(service, handler)
      service.new(handler.new).tap do |svc|
        svc.before do |rack_env, env|
          env[:request_start_time] = time_now
          service_full_name = @service_class.service_full_name
          rpc_method = env[:rpc_method].to_s
          rack_span = OpenTelemetry::Instrumentation::Rack.current_span
          rack_span.name = "#{service_full_name}/#{rpc_method}"

          attrs = {
            "rpc.system" => "twirp",
            "rpc.service" => service_full_name,
            "rpc.method" => rpc_method
          }

          rack_span.add_attributes(attrs)

          Failbot.reset_context
          Failbot.push(attrs)

          init_context(rack_env, env, handler.name)
        end

        svc.on_success do |env|
          instrument_request(success: true, env: env, status_code: 200)
          Failbot.reset_context
        end

        svc.on_error do |twerr, env|
          if Rails.env.development? && twerr.cause.present?
            puts twerr.cause.backtrace.join("\n")
          end

          rack_span = OpenTelemetry::Instrumentation::Rack.current_span
          rack_span.set_attribute("error", true)
          rack_span.add_event("error", attributes: { "error" => twerr.to_s })

          # If an error is raised before we start to route a request
          # then the `before` block will not be invoked.
          #
          # These cases represent a 4xx error that has not reached the Twirp
          # app itself, so we can safely skip them as they do not reflect
          # actual timing information for the app.
          next if env[:request_start_time].blank?

          status_code = (twerr&.code).present? ? Twirp::ERROR_CODES_TO_HTTP_STATUS[twerr&.code] : nil
          instrument_request(success: false, env: env, status_code: status_code)
        end

        svc.exception_raised do |error, env|
          report_error(error, env)
          Failbot.reset_context
        end
      end
    end

    def instrument_request(success:, env:, status_code: nil)
      Instrument.timing(
        "twirp.request",
        duration(env),
        **context_from_twirp(env).merge(
          success: success,
          status_code:  status_code,
        )
      )
      Instrument.distribution(
        "twirp.request.dist.time",
        duration(env),
        **context_from_twirp(env).merge(
          success: success,
          status_code:  status_code,
        )
      )
    end

    def report_error(error, env)
      action = env[:rpc_method].to_s
      rollup = Digest::SHA256.hexdigest("#{error.class}#{action}")
      Failbot.report(error, context_from_twirp(env).merge(
        "rollup" => rollup,
        "rpc.method" => action,
        ))
    end

    def context_from_twirp(env)
      env.slice(
        :content_type,
        :rpc_method,
        :user_type
        )
    end

    def duration(env)
      time_now - env[:request_start_time]
    end

    def time_now
      Time.now.utc
    end

    def init_context(rack_env, env, handler_name)
      env[:HTTP_X_GitHub_Request_Id] = rack_env["HTTP_X_GITHUB_REQUEST_ID"]
      DependencyGraphAPI::CurrentRequest.request_id = env[:HTTP_X_GitHub_Request_Id]
      env[:HTTP_X_GitHub_User] = rack_env["HTTP_X_GITHUB_USER"]
      env[:HTTP_X_GitHub_Session_Id] = rack_env["HTTP_X_GITHUB_SESSION_ID"]
      env[:HTTP_X_GitHub_Is_Public] = rack_env["HTTP_X_GITHUB_IS_PUBLIC"]
      env[:HTTP_User_Agent] = rack_env["HTTP_USER_AGENT"]
      env[:RPC_Handler] = handler_name
      env[:user_type] = rack_env["HTTP_GITHUB-DEPGRAPH-USER-TYPE"] || "unknown"
    end
  end

  def self.health
    @health ||= RackApp.new(DependencyGraphAPI::V1::HealthAPIService,
                            HealthService::V1::Handler,
                            "health/")
  end

  def self.snapshots
    @snapshots ||= RackApp.new(DependencyGraphAPI::V1::SnapshotAPIService,
                                   SnapshotService::V1::Handler,
                                   "snapshots/")
  end

  def self.dependency_snapshots
    @dependency_snapshots ||= RackApp.new(DependencyGraphAPI::V1::DependencySnapshotAPIService,
                               DependencySnapshotService::V1::Handler,
                               "dependency-snapshots/")
  end

  def self.repositories
    @repositories ||= RackApp.new(DependencyGraphAPI::V1::RepositoryService,
                                   RepositoryService::V1::Handler,
                                   "repositories/")
  end

  def self.repository_dependencies
    @repository_dependencies ||= RackApp.new(DependencyGraphAPI::V1::RepositoryDependenciesAPIService,
                                   RepositoryDependenciesService::V1::Handler,
                                   "repository-dependencies/")
  end

  def self.repository_sbom
    @repository_sbom ||= RackApp.new(DependencyGraphAPI::V1::RepositorySBOMService,
                                     RepositorySBOMService::V1::Handler,
                                     "repository-sbom/")
  end

  def self.experimental
    @experimental ||= RackApp.new(DependencyGraphAPI::V1::ExperimentalAPIService,
                                     ExperimentalService::V1::Handler,
                                     "experimental/")
  end

  def self.packages
    @packages ||= RackApp.new(DependencyGraphAPI::V1::PackagesAPIService, PackagesService::V1::Handler, "packages/")
  end

  def self.dgp
    @dgp ||= RackApp.new(DependencyGraphAPI::V1::DgpAPIService, DgpService::V1::Handler, "dgp/")
  end
end
