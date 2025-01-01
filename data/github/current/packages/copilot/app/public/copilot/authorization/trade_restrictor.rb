# typed: strict
# frozen_string_literal: true

module Copilot
  module Authorization
    class TradeRestrictor
      include Copilot::Authorization::TradeComplianceHelper

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
          if @copilot_user.trade_restricted?
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
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        Copilot::ErrorReporter.report!(Copilot::Errors::AccessCheckError.from_error(e), copilot_user: @copilot_user)
        false
      end
    end
  end
end
