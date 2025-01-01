# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class HistoricalAlertsFixedWithAutofixQuery < Base
          class Result < T::Struct
            const :accepted, T.nilable(Integer)
            const :suggested, T.nilable(Integer)
          end

          RunQueryOutput = type_member { { fixed: Result } }

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
              authorized_orgs_by_action: T.nilable(T::Hash[Symbol, T::Array[Organization]]),
              user_session: ::UserSession,
              is_open_selected: T::Boolean,
            ).void
          end
          def initialize(user:, query_parser:, alerts_filterer:, repos_filterer:, scope:, start_date:, end_date:, security_features:, authorized_orgs_by_action:, user_session:, is_open_selected:)
            security_features -= [
              ::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS,
              ::SecurityCenter::SecurityFeatures::SECRET_SCANNING
            ]

            super(
              user:,
              query_parser:,
              alerts_filterer:,
              repos_filterer:,
              scope:,
              start_date:,
              end_date:,
              security_features:,
              authorized_orgs_by_action:,
              user_session:,
              is_open_selected:,
            )
          end

          private

          class HistoricalAlertsAccumulator < T::Struct
            prop :suggested, Integer, default: 0
            prop :accepted, Integer, default: 0

            sig { params(suggested: Integer, accepted: Integer).void }
            def initialize(suggested: 0, accepted: 0)
              super
            end
          end

          sig { params(union_all_sql_string: String).returns(String) }
          def generate_query(union_all_sql_string)
            %{
              SELECT accepted, suggested
              FROM (#{union_all_sql_string}) AS combined_counts
            }.squish
          end

          sig { override.params(offset: T.nilable(Integer), limit: T.nilable(Integer)).returns(RunQueryOutput) }
          def query(offset:, limit:)
            results_reducer = ->(accumulator, slice_result) {
              return accumulator if slice_result["accepted"] == 0 && slice_result["suggested"] == 0

              accepted = (slice_result["accepted"] || 0).round
              suggested = (slice_result["suggested"] || 0).round

              accumulator.accepted += accepted
              accumulator.suggested += suggested

              accumulator
            }

            # This code path works when using server-side slicing
            result = run_sliced_alert_revisions_query(accumulator: HistoricalAlertsAccumulator.new, results_reducer:) do |union_all_sql_string|
              generate_query(union_all_sql_string)
            end

            Result.new(accepted: result.accepted, suggested: result.suggested)
          end

          sig { override.returns(String) }
          def union_all_fallback_sql
            "SELECT 0 AS accepted, 0 as suggested WHERE FALSE"
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
              .select(
                Arel.sql(%{
                  SUM(IF(
                    `#{table_name}`.`autofix_accepted` = 1
                    AND `#{table_name}`.`alert_resolved` = 1
                    AND `#{table_name}`.`alert_resolution` IS NULL
                  , 1, 0)) as accepted
                }.squish),
                Arel.sql("COUNT(*) as suggested"),
              )
              .where(repository_id: repo_metadata_rel.select(:repository_id))
              .where(date_id: Date.id_from_date(start_date)..Date.id_from_date(end_date))
              .where(has_autofix: true)
              .where("#{table_name}.next_revision_date_id > ?", end_date_id)
          end
        end
      end
    end
  end
end
