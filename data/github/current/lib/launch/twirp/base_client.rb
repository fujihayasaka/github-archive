# typed: strict
# frozen_string_literal: true

require "github-launch"

module Launch
  module Twirp
    class BaseClient
      include GitHub::Memoizer

      extend T::Sig

      # The underlying Twirp client needs to be fairly dynamic
      # Subclasses of the base client will each have their own client
      # class based on `twirp_class`
      # Additionally, this type needs to satisfy NullClient and the
      # mock client used in tests
      # https://github.com/github/github/pull/271314 has some explorations on
      # how to solve this with interfaces, but for now we need to leave it untyped
      ClientType = T.type_alias { T.untyped }

      Entity = T.type_alias { T.any(Business, User, Repository) }
      IdentityEntity = T.type_alias { T.any(Entity, CheckSuite) }

      TWIRP_PATH = "twirp/"
      SERVICE_NAME = "github-launch"
      FAILBOT_APP_NAME = "github-launch"

      sig do
        params(
          launch_deployer_twirp_address: T.nilable(String),
          launch_deployer_hmac_secret: T.nilable(String),
          client_name: T.nilable(String),
          retry_options: T.nilable(T::Hash[Symbol, T.untyped]),
          request_timeout_secs: T.nilable(Float),
        ).void
      end
      def initialize(
        launch_deployer_twirp_address: GitHub.launch_deployer_twirp_address,
        launch_deployer_hmac_secret: GitHub.launch_deployer_hmac_secret,
        client_name: SERVICE_NAME,
        retry_options: nil,
        request_timeout_secs: 9.5
      )
        @launch_deployer_twirp_address = launch_deployer_twirp_address
        @launch_deployer_hmac_secret = launch_deployer_hmac_secret
        @client_name = client_name
        @retry_options = retry_options
        @request_timeout_secs = request_timeout_secs
      end

      # Wraps the TwirpClient#rpc method with common error response handling
      # behaviour for launch-deployer
      sig { params(method: Symbol, params: T.untyped).returns(TwirpResponse) }
      def rpc(method, params)
        TwirpHelper.rescue_from_twirp_errors(FAILBOT_APP_NAME, app: FAILBOT_APP_NAME) do
          client.rpc(method, params)
        end
      end

      sig do
        type_parameters(:R)
          .params(blk: T.proc.returns(::Twirp::ClientResp[T.type_parameter(:R)]))
          .returns(TwirpResponse)
      end
      def rescue_rpc(&blk)
        TwirpHelper.rescue_from_twirp_errors(FAILBOT_APP_NAME, app: FAILBOT_APP_NAME) do
          yield
        end
      end

      sig { params(entity: IdentityEntity).returns(String) }
      def global_id(entity)
        use_next_gid = !GitHub.enterprise?
        use_next_gid ? entity.next_global_id : entity.global_relay_id
      end

      sig { params(entity: IdentityEntity).returns(GitHub::Launch::Pbtypes::GitHub::Identity) }
      def identity(entity)
        GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: global_id(entity))
      end

      private

      sig { returns(T.class_of(::Twirp::Client)) }
      def twirp_class
        raise "#{self.class.name} must define 'twirp_class' to return a Twirp::Client class that describes the remote service."
      end

      # This method is used in cases where the API returns a 404 to return
      # an appropriate blank protobuf response
      sig { params(method: T.untyped).returns(T.untyped) }
      def empty_message(method)
        output_class = twirp_class.rpcs[method.to_s][:output_class]

        output_class.new
      end

      sig { returns(ClientType) }
      def client
        # If launch-deployer configuration has not been set for this GitHub install,
        # use a null connection as a circuit breaker so any client calls result
        # in a 503-like response.
        if launch_configured?
          factory_client
        else
          null_client
        end
      end

      sig { returns(T::Boolean) }
      def launch_configured?
        @launch_deployer_twirp_address.present? && @launch_deployer_hmac_secret.present?
      end

      sig { returns(ClientType) }
      memoize def null_client
        failbot_report(Launch::Twirp::Error.new("Launch Deployer configuration missing."))
        Launch::Twirp::NullClient.new
      end

      sig { returns(ClientType) }
      memoize def factory_client
        connection = GitHub::FaradayClient.internal(@client_name, connection_url, {
          request: {
            timeout: @request_timeout_secs,
            open_timeout: 0.15 # 150 ms
          }
        }) do |conn|
          conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: @launch_deployer_hmac_secret
          conn.use GitHub::FaradayMiddleware::Datadog, enable_path_tag: true
          if @retry_options.present?
            conn.use GitHub::FaradayMiddleware::Retries, **@retry_options
          else
            conn.disable GitHub::FaradayMiddleware::Retries
          end
          conn.use GitHub::FaradayMiddleware::Resilient, options: {
            sleep_window_seconds: 10,
            request_volume_threshold: 8,
            error_threshold_percentage: 20,
            window_size_in_seconds: 30,
            bucket_size_in_seconds: 5,
          }
        end
        twirp_class.new(connection)
      end

      sig { returns(String) }
      def connection_url
        return "" unless launch_configured?
        URI.join(T.must(@launch_deployer_twirp_address), TWIRP_PATH).to_s
      end

      sig { returns(String) }
      def launch_environment
        return "development" if Rails.env.development?

        "production"
      end

      sig { params(error: T.untyped).void }
      def failbot_report(error)
        Failbot.report(error, { app: FAILBOT_APP_NAME })
      end
    end
  end
end
