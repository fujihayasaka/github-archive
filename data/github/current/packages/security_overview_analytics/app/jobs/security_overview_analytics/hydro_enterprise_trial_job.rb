# typed: strict
# frozen_string_literal: true


module SecurityOverviewAnalytics
  class HydroEnterpriseTrialJob < ::HydroMessageJob
    include GitHub::Memoizer
    include LifecycleEventRetryHandler

    queue_as :hydro_security_overview_analytics_enterprse_trial

    retry_on_dirty_exit

    sig { returns(Integer) }
    attr_reader :business_id

    class BusinessNotFoundError < StandardError; end

    resolve_tenant_context do |message|
      biz_id = message.dig(:enterprise, :id)
      ::Business.find_by(id: biz_id)
    end

    sig { params(protobuf: T.untyped, headers: T.untyped, schema: T.untyped, timestamp: T.untyped, timestamp_nano: T.untyped, message: T.untyped, queue: T.untyped).void }
    def initialize(protobuf:, headers:, schema:, timestamp:, timestamp_nano:, message:, queue:)
      super

      enterprise, request_id = message.values_at(
        :enterprise,
        :request_id
      )
      @business_id = T.let(enterprise[:id], Integer)

      GitHub.context.push(business_id:, request_id:)
    end

    sig { returns(::Business) }
    memoize def business
      business = T.let(::Business.find(@business_id), T.nilable(::Business))
      if business.nil?
        raise BusinessNotFoundError, "Business with ID #{@business_id} not found"
      else
        T.let(business, ::Business)
      end
    end

    protected

    sig { override.returns(T.untyped) }
    def logging_context
      super.merge({
        "gh.business.id": business_id
      })
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def failbot_log_context
      super.merge({
        app: "github-security-center",
        "gh.business.id": business_id,
        "gh.business.slug": business.slug
      })
    end

    sig { void }
    def perform
      SecurityOverviewAnalytics::Initialization.for(business).enqueue
      FanoutScheduler.initialize_for(business)
    end
  end
end
