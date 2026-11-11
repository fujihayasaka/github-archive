# typed: true
# frozen_string_literal: true

module Launch
  module Twirp
    class ConcurrencyLimitOverridesClient < Launch::Twirp::BaseClient
      Owner = T.type_alias { T.any(Organization, Business) }

      sig { params(owner: Owner).returns(T::Hash[Symbol, T.nilable(Integer)]) }
      def get_concurrency_limit_overrides(owner:)
        response = rescue_rpc do
          client.get_concurrency_limit_overrides(build_get_request(owner: owner))
        end

        return {} unless response.call_succeeded?

        parse_limits_response(response.value.limits)
      end

      sig do
        params(
          owner: Owner,
          total_limit: T.nilable(Integer),
          macos_limit: T.nilable(Integer)
        ).returns(T::Boolean)
      end
      def update_concurrency_limit_overrides(owner:, total_limit: nil, macos_limit: nil)
        response = rescue_rpc do
          client.update_concurrency_limit_overrides(
            build_update_request(owner: owner, total_limit: total_limit, macos_limit: macos_limit)
          )
        end

        response.call_succeeded? && response.value.success
      end

      private

      sig { returns(T.class_of(::Twirp::Client)) }
      def twirp_class
        GitHub::Launch::Services::Concurrencylimitoverrides::ConcurrencyLimitOverridesClient
      end

      sig { params(owner: T.any(Organization, Business)).returns(T.untyped) }
      def build_get_request(owner:)
        GitHub::Launch::Services::Concurrencylimitoverrides::GetConcurrencyLimitOverridesRequest.new(
          owner_id: identity(owner)
        )
      end

      sig do
        params(
          owner: T.any(Organization, Business),
          total_limit: T.nilable(Integer),
          macos_limit: T.nilable(Integer)
        ).returns(T.untyped)
      end
      def build_update_request(owner:, total_limit:, macos_limit:)
        limits = []
        if total_limit
          limits << GitHub::Launch::Services::Concurrencylimitoverrides::ConcurrencyLimit.new(
            platform: "total",
            concurrency: total_limit
          )
        end
        if macos_limit
          limits << GitHub::Launch::Services::Concurrencylimitoverrides::ConcurrencyLimit.new(
            platform: "macos",
            concurrency: macos_limit
          )
        end

        GitHub::Launch::Services::Concurrencylimitoverrides::UpdateConcurrencyLimitOverridesRequest.new(
          owner_id: identity(owner),
          limits: limits
        )
      end

      sig { params(limits: T.untyped).returns(T::Hash[Symbol, T.nilable(Integer)]) }
      def parse_limits_response(limits)
        result = {}
        limits.each do |limit|
          case limit.platform
          when "total"
            result[:total] = limit.concurrency
          when "macos"
            result[:macos] = limit.concurrency
          end
        end
        result
      end
    end
  end
end
