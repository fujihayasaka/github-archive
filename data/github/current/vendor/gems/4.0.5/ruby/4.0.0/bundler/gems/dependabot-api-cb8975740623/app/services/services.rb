# frozen_string_literal: true

require "middleware/hmac_authentication"

module Services
  # Wraps a Twirp::Service class with some helper methods and configuration
  # for error-handling, metrics, etc.
  class RackApp
    TWIRP_PREFIX = "twirp"

    attr_reader :app

    def initialize(twirp_service, app_handler)
      @app = build_rack_app(twirp_service, app_handler)
      @service_class = twirp_service
    end

    def mount_path
      File.join(TWIRP_PREFIX, @service_class.service_full_name)
    end

    private

    def build_rack_app(service, handler)
      service.new(handler.new).tap do |svc|
        svc.before do |rack_env, env|
          env[:request_start_time] = time_now

          Twirp::Error.unauthenticated("Unauthorized.") unless valid_hmac_token?(rack_env)
        end

        svc.on_success do |env|
          instrument_request(success: true, env: env)
        end

        svc.on_error do |twerr, env|
          # If an error is raised before we start to route a request
          # then the `before` block will not be invoked.
          #
          # These cases represent a 4xx error that has not reached the Twirp
          # app itself, so we can safely skip them as they do not reflect
          # actual timing information for the app.
          next if env[:request_start_time].blank?

          instrument_request(success: false, env: env, twerr: twerr)
        end

        svc.exception_raised { |error, env| report_error(error, env) }
      end
    end

    def instrument_request(success:, env:, twerr: nil)
      MetricsClient.timing(
        "twirp.request",
        duration(env),
        tags: metric_context_from_twirp(env).merge(
          success: success,
          error_code: twerr&.code,
        )
      )
    end

    def report_error(error, env)
      transaction = env[:rpc_method].to_s
      rollup = Digest::SHA256.hexdigest("#{error.class}#{transaction}")
      Dependabot::Exceptions.report(error, telemetry_context_from_twirp(env).merge(
                                             rollup: rollup,
                                             transaction: transaction,
                                           ))
    end

    def telemetry_context_from_twirp(env)
      {
        "rpc.method": env[:rpc_method],
        "http.request.header.content-type": env[:content_type],
      }
    end

    def metric_context_from_twirp(env)
      env.slice(
        :content_type,
        :rpc_method,
      )
    end

    def duration(env)
      time_now - env[:request_start_time]
    end

    def time_now
      Time.now.utc
    end

    def valid_hmac_token?(rack_env)
      token_validator.permitted?(rack_env: rack_env)
    end

    def token_validator
      @token_validator ||= Middleware::HmacAuthentication::TokenValidator.new
    end
  end

  def self.health
    @health ||= RackApp.new(DependabotApi::V1::HealthService,
                            HealthService::V1::Handler)
  end

  def self.update_config
    @update_config ||= RackApp.new(DependabotApi::V1::UpdateConfigsService,
                                   UpdateConfigsService::V1::Handler)
  end

  def self.update_jobs
    @update_jobs ||= RackApp.new(DependabotApi::V1::UpdateJobsService,
                                 UpdateJobsService::V1::Handler)
  end

  def self.repositories_service
    @repositories_service ||= RackApp.new(
      DependabotApi::V1::RepositoriesService,
      RepositoriesService::V1::Handler,
    )
  end

  def self.repository_access
    @repository_access ||= RackApp.new(
      DependabotApi::V1::RepositoryAccessServiceService,
      RepositoryAccessService::V1::Handler,
    )
  end

  def self.debug_service
    @debug_service ||= RackApp.new(
      DependabotApi::V1::DebugServiceService,
      DebugService::V1::Handler,
    )
  end

  def self.secret_service
    @secret_service ||= RackApp.new(
      DependabotApi::V1::SecretServiceService,
      SecretService::V1::Handler,
    )
  end

  def self.suggested_fixes_service
    @suggested_fixes_service ||= RackApp.new(
      DependabotApi::V1::SuggestedFixesService,
      SuggestedFixesService::V1::Handler,
    )
  end
end
