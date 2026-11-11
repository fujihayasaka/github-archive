# typed: strict
# frozen_string_literal: true

module Copilot
  module Authorization
    class TradeRestrictor
      include Copilot::Authorization::TradeComplianceHelper
      include Scientist

      COMPLIANCED_TWIRP_PATH = T.let(
        "/twirp/trade_compliance.api.v1.TradeComplianceApi/CheckTradeCompliance",
        String,
      )

      class CompliancedResponse < T::Struct
        const :allowed, T::Boolean
        const :reason, String
        const :restriction_type, String
        const :screening_status, String
      end

      sig { returns(T.nilable(String)) }
      attr_reader :country_code

      sig { returns(T.nilable(String)) }
      attr_reader :region

      sig { returns(T.nilable(String)) }
      attr_reader :region_name

      sig { returns(T.nilable(String)) }
      attr_reader :city

      sig { returns(Symbol) }
      attr_reader :restriction_type

      sig { params(copilot_user: Copilot::User).void }
      def initialize(copilot_user)
        @copilot_user = copilot_user
        @restriction_type = T.let(:UNKNOWN_LOCATION, Symbol)
        @country_code  = T.let(nil, T.nilable(String))
        @region        = T.let(nil, T.nilable(String))
        @region_name   = T.let(nil, T.nilable(String))
        @city          = T.let(nil, T.nilable(String))
        @complianced_connection = T.let(nil, T.nilable(Faraday::Connection))
      end

      # we are handed a blob like this from glb:
      #
      # {
      #   "city":"Kyiv",
      #   "country_code":"UA",
      #   "country_name":"Ukraine",
      #   "ip_address":"176.36.152.210",
      #   "region":"30",
      #   "region_name":"Kyiv City",
      # }
      #
      # we care about the country code, region, and region name matching
      sig { params(context: Context, env: T::Hash[T.untyped, T.untyped]).returns(T::Boolean) } # rubocop:disable Sorbet/ForbidTUntyped
      def restricted?(context, env)
        GitHub.logger.with_named_tags("code.function" => "restricted?", "code.namespace" => self.class.name) do
          if check_trade_restricted
            GitHub.logger.info("User is trade_restricted")
            GitHub.dogstats.increment("copilot.access.trade_restricted")

            @restriction_type = :TRADE_RESTRICTED
            return true
          end

          GitHub.logger.info("User is not trade_restricted. checking if user originates from a copilot restricted country")

          @country_code = context[:country_code]
          @region       = context[:region]
          @region_name  = context[:region_name]
          @city         = context[:city]

          GitHub.logger.info(
            "Checking if GLB set context",
            "request.context" => context
          )

          # let's see if the glb was cool to us or not
          if @country_code.nil? || @region.nil? || @region_name.nil?
            # c'mon glb, you can do better than this
            GitHub.logger.info("GLB did not set context for us")

            GitHub.dogstats.increment("copilot.access.glb.empty")

            # let's load up the location from the ip
            location = GitHub::Location.look_up(GitHub.context[:actor_ip] || env["api.remote_ip"])

            if location.nil? # maybe this ip doesn't exist? this shouldn't ever happen but here we are
              GitHub.logger.info "Location lookup failed"
              GitHub.dogstats.increment("copilot.access.location_lookup_failed")

              # we default to unrestricted
              return false
            end

            @country_code = location.dig(:country_code)
            @region       = location.dig(:region)
            @region_name  = location.dig(:region_name)
            @city         = location.dig(:city)

            GitHub.logger.info "Location lookup succeeded"
            GitHub.dogstats.increment("copilot.access.location_lookup_succeeded")
          end

          GitHub.logger.with_named_tags(
            "gh.copilot.trade_restriction.country_code" => @country_code,
            "gh.copilot.trade_restriction.region" => @region,
            "gh.copilot.trade_restriction.region_name" => @region_name) do
            GitHub.logger.info("Checking if country code is blocked")

            # let's check this against our country list first
            if copilot_access_country_blocked?(account: @copilot_user.user_object, country_code: @country_code, region_name: @region_name, region_code: @region, city: @city)
              @restriction_type = :TRADE_RESTRICTED_COUNTRY
              return true
            end

            # now let's check the region
            if copilot_access_region_blocked?(account: @copilot_user.user_object, country_code: @country_code, region_name: @region_name, region_code: @region, city: @city)
              @restriction_type = :TRADE_RESTRICTED_COUNTRY
              return true
            end
          end

          false
        end
      rescue StandardError => e
        Copilot::ErrorReporter.report!(Copilot::Errors::AccessCheckError.from_error(e), copilot_user: @copilot_user)
        false
      end

      private

      sig { returns(T::Boolean) }
      def check_trade_restricted
        if FeatureFlag.vexi.enabled?(:copilot_complianced_trade_experiment, @copilot_user.user_object, default: false)
          result = T.cast(science("copilot.trade_check_via_complianced") do |e|
            e.use do
              control = trade_check_via_monolith
              GitHub.logger.info("trade_check control result",
                "code.namespace" => "Copilot::Authorization::TradeRestrictor",
                "code.function" => "check_trade_restricted",
                "experiment.name" => "copilot.trade_check_via_complianced",
                "gh.user.id" => @copilot_user.id,
                "gh.copilot.trade_check.control_result" => control,
              )
              control
            end
            e.try do
              trade_check_via_complianced
            end
            e.compare do |control, candidate|
              control == candidate
            end
            e.context({ user_id: @copilot_user.id })
          end, Symbol)
          result == :RESTRICTED
        else
          @copilot_user.trade_restricted?
        end
      end

      sig { returns(Symbol) }
      def trade_check_via_monolith
        @copilot_user.trade_restricted? ? :RESTRICTED : :UNRESTRICTED
      end

      sig { returns(Faraday::Connection) }
      def complianced_connection
        @complianced_connection ||= begin
          url = GitHub.service_mesh_enabled? ? GitHub.complianced_mesh_url : GitHub.complianced_url
          GitHub::FaradayClient.internal("complianced", url) do |conn|
            conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: GitHub.complianced_hmac_key
            conn.options[:timeout] = 5
            conn.options[:open_timeout] = 2
          end
        end
      end

      sig { returns(Symbol) }
      def trade_check_via_complianced
        response = complianced_connection.post(COMPLIANCED_TWIRP_PATH) do |req|
          req.headers["Content-Type"] = "application/json"
          req.body = JSON.generate({
            account_id: @copilot_user.id,
            account_type: 0,
            feature_type: 1,
          })
        end

        unless response.success?
          GitHub.dogstats.increment("copilot.complianced.trade_check.error")
          Failbot.report("complianced trade check error",
            app: "complianced",
            message: "HTTP #{response.status}",
            user_id: @copilot_user.id.to_s,
            "code.namespace": "Copilot::Authorization::TradeRestrictor",
            "code.function": "trade_check_via_complianced",
          )
          return :NOT_EVALUATED
        end

        data = JSON.parse(response.body)
        resp = CompliancedResponse.new(
          allowed: data.fetch("allowed"),
          reason: data.fetch("reason", ""),
          restriction_type: data.fetch("restriction_type", ""),
          screening_status: data.fetch("screening_status", ""),
        )
        result = resp.allowed ? :UNRESTRICTED : :RESTRICTED

        GitHub.logger.info("trade_check_via_complianced result",
          "code.namespace" => "Copilot::Authorization::TradeRestrictor",
          "code.function" => "trade_check_via_complianced",
          "experiment.name" => "copilot.trade_check_via_complianced",
          "gh.user.id" => @copilot_user.id,
          "gh.copilot.trade_check.result" => result,
          "gh.copilot.trade_check.allowed" => resp.allowed,
          "gh.copilot.trade_check.reason" => resp.reason,
          "gh.copilot.trade_check.restriction_type" => resp.restriction_type,
          "gh.copilot.trade_check.screening_status" => resp.screening_status,
        )

        result
      rescue StandardError => e
        GitHub.dogstats.increment("copilot.complianced.trade_check.exception",
          tags: ["exception_class:#{e.class.name}"])
        Failbot.report(e,
          app: "complianced",
          user_id: @copilot_user.user_object.id.to_s,
          "code.namespace": "Copilot::Authorization::TradeRestrictor",
          "code.function": "trade_check_via_complianced",
        )
        :NOT_EVALUATED
      end
    end
  end
end
