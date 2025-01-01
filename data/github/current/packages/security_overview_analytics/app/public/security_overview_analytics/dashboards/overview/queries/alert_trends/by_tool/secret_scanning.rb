# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class AlertTrends::ByTool::SecretScanning < AlertTrends::Base
          RunQueryOutput = type_member { { fixed: RunQueryOutputAlias } }

          class Result < T::Struct
            extend T::Sig
            include AlertTrends::Resultable

            const :data_points, T::Array[AlertTrends::DataPoint], default: []

            sig { override.returns(AlertTrends::Base::RunQueryOutputAlias) }
            def to_h
              {
                "Secret scanning" => data_points.sort_by { |dp| dp.x }.map { |r| r.to_h }
              }
            end
          end

          sig do
            override.params(
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
              security_features: [::SecurityCenter::SecurityFeatures::SECRET_SCANNING],
              authorized_orgs:,
              user_session:,
              return_alert_count:,
              is_open_selected:,
            )
          end

          private

          sig { override.returns(RunQueryOutput) }
          def query
            secret_scanning_rel
              .each_with_object(initialize_db_results) do |row, res|
                date = ::Date.parse(row.date_id.to_s)
                data_point = res.data_points.find { |dp| dp.x == date }
                next unless data_point

                data_point.y = row.alert_count
              end
              .to_h
          end

          # NOTE: Unused since we're directly using the tool-specific relation in `query`.
          sig { override.returns(String) }
          def union_all_fallback_sql
            %{
              SELECT
                NULL AS date_id,
                NULL AS alert_count
              WHERE FALSE
            }.squish
          end

          sig do
            override.params(
              rel: ActiveRecord::Relation,
              repo_metadata_rel: ActiveRecord::Relation,
              table_name: String
            ).returns(ActiveRecord::Relation)
          end
          def common_clauses_rel(rel, repo_metadata_rel, table_name)
            rel
              .select("dates.id AS date_id", "COUNT(*) AS alert_count")
              .joins("JOIN (#{dates_table_sql}) AS dates ON #{table_name}.next_revision_date_id > dates.id AND #{table_name}.date_id <= dates.id")
              .where(alert_resolved: !is_open_selected, repository_id: repo_metadata_rel.select(:repository_id))
              .group("dates.id")
              .order("dates.id")
          end

          sig { returns(Result) }
          def initialize_db_results
            date_ids.each_with_object(Result.new) do |date_id, res|
              date = ::Date.parse(date_id.to_s)
              res.data_points << AlertTrends::DataPoint.new(x: date, y: 0)
            end
          end
        end
      end
    end
  end
end
