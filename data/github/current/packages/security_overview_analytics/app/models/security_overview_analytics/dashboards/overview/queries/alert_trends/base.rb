# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class AlertTrends::Base < Base
          abstract!

          RunQueryOutputAlias = T.type_alias { T::Hash[String, T::Array[AlertTrends::DataPoint::DataPointHashShape]] }
          RunQueryOutput = type_member { { fixed: RunQueryOutputAlias } }

          sig do
            params(
              user: User,
              query_parser: ::Search::Queries::SecurityCenter::QueryParser,
              alerts_filterer: ::SecurityOverviewAnalytics::Dashboards::AlertsFilterer,
              repos_filterer: ::SecurityOverviewAnalytics::Dashboards::ReposFilterer,
              scope: T.any(::Organization, ::Business),
              start_date: ::Date,
              end_date: ::Date,
              security_features: T::Array[String],
              authorized_orgs: T.nilable(T::Array[Organization]),
              user_session: ::UserSession,
              return_alert_count: T::Boolean,
              is_open_selected: T::Boolean,
            ).void
          end
          def initialize(user:, query_parser:, alerts_filterer:, repos_filterer:, scope:, start_date:, end_date:, security_features:, authorized_orgs:, user_session:, return_alert_count:, is_open_selected:)
            super(
              user:,
              query_parser:,
              alerts_filterer:,
              repos_filterer:,
              scope:,
              start_date:,
              end_date:,
              security_features:,
              authorized_orgs:,
              user_session:,
              return_alert_count: false, # No query parallelization as this data comes from a single table.
              is_open_selected:,
            )
          end

          sig { overridable.returns(T::Array[Integer]) }
          memoize def date_ids
            DateHelper.interval_date_ids(start_date, end_date)
          end

          sig { overridable.returns(String) }
          memoize def dates_table_sql
            date_ids.map { |date_id| "SELECT #{date_id} AS id" }.join(" UNION ALL ")
          end
        end
      end
    end
  end
end
