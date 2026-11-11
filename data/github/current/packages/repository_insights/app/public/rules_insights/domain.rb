# typed: strict
# frozen_string_literal: true

require "monolith-twirp-rulesinsights-rulesinsights"

module RulesInsights
  class Domain < GH::Domain::Base
    Source = T.type_alias { T.any(Repositories::IRepository, Orgs::IOrganization, Admin::IBusiness) }

    EVALUATE_STATUSES = T.let(%i[active all evaluate].freeze, T::Array[Symbol])

    # should conceptually match the type from the Twirp client: MonolithTwirp::RulesInsights::RulesInsights::V1::Period
    class Period < T::Struct
      const :from, Time
      const :to, Time
    end

    # should conceptually match the type from the Twirp client: MonolithTwirp::RulesInsights::RulesInsights::V1::Filters
    class Filters < T::Struct
      const :evaluate_status, Symbol
      const :ref, T.nilable(String), default: nil
      const :ruleset_id, T.nilable(Integer), default: nil
    end

    # Fetches Rules Insights dashboard statistics for the given source.
    sig { params(source: Source, period: Period, filters: Filters).returns(T::Hash[Symbol, T.untyped]) }
    def get_dashboard_stats(source:, period:, filters:)
      raise ArgumentError, "period `from` must be before `to`" if period.from >= period.to
      unless EVALUATE_STATUSES.include?(filters.evaluate_status)
        raise ArgumentError, "evaluate_status must be one of: #{EVALUATE_STATUSES.join(", ")}"
      end

      scope = build_scope(source)
      filter = {
        evaluate_status: filters.evaluate_status,
        ref: filters.ref,
        ruleset_id: filters.ruleset_id,
      }.compact

      request = MonolithTwirp::RulesInsights::RulesInsights::V1::GetDashboardStatsRequest.new(
        scope:,
        period: MonolithTwirp::RulesInsights::RulesInsights::V1::Period.new(
          from: Google::Protobuf::Timestamp.new(seconds: period.from.to_i),
          to: Google::Protobuf::Timestamp.new(seconds: period.to.to_i),
        ),
        filters: MonolithTwirp::RulesInsights::RulesInsights::V1::Filters.new(**filter),
      )

      RulesInsights::Twirp.rules_client.get_dashboard_stats(request).to_h
    rescue RulesInsights::Twirp::Error, Faraday::Error => error
      raise RulesInsights::TwirpError, error.message
    end

    private

    sig { params(source: Source).returns(MonolithTwirp::RulesInsights::RulesInsights::V1::Scope) }
    def build_scope(source)
      case source
      when Repositories::IRepository
        org = T.cast(T.must(source.owner), Orgs::IOrganization)
        MonolithTwirp::RulesInsights::RulesInsights::V1::Scope.new(
          business_id: org.business&.id,
          org_id: T.must(org.id),
          repo_id: T.must(source.id),
        )
      when Orgs::IOrganization
        MonolithTwirp::RulesInsights::RulesInsights::V1::Scope.new(
          business_id: source.business&.id,
          org_id: T.must(source.id),
        )
      when Admin::IBusiness
        MonolithTwirp::RulesInsights::RulesInsights::V1::Scope.new(
          business_id: T.must(source.id),
        )
      end
    end
  end
end
