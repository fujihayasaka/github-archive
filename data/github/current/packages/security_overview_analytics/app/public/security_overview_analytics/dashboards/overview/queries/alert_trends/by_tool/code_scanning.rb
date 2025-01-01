# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class AlertTrends::ByTool::CodeScanning < AlertTrends::Base
          MAX_NUM_TOP_TOOLS = 3
          TOOL_CODEQL = T.let(::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser::TOOL_CODEQL, String)

          RunQueryOutput = type_member { { fixed: RunQueryOutputAlias } }

          class DateWithCounts < T::Struct
            extend T::Sig

            const :date, ::Date
            prop :codeql_count, T.nilable(Integer)
            prop :third_party_tool_counts, T::Hash[String, Integer]
            prop :other_third_party_tool_count, T.nilable(Integer)
          end

          class Result < T::Struct
            extend T::Sig
            include AlertTrends::Resultable

            const :dates_with_counts, T::Array[DateWithCounts]

            # Example output:
            # {
            #   "CodeQL" => [
            #     { x: ::Date.new(2024, 4, 24), y: 100 }
            #   ],
            #   "Tool 1" => [
            #     { x: ::Date.new(2024, 4, 24), y: 200 }
            #   ],
            #   "Tool 2" => [
            #     { x: ::Date.new(2024, 4, 24), y: 300 }
            #   ],
            #   "Other third-party tools" => [
            #     { x: ::Date.new(2024, 4, 24), y: 400 }
            #   ]
            # }
            sig { override.returns(AlertTrends::Base::RunQueryOutputAlias) }
            def to_h
              dates_with_counts.each_with_object({}) do |dwc, res|
                date = dwc.date

                if dwc.codeql_count.present?
                  (res["CodeQL"] ||= []) << { x: date, y: dwc.codeql_count }
                end

                dwc.third_party_tool_counts.each do |tool, count|
                  (res[tool] ||= []) << { x: date, y: count }
                end

                if dwc.other_third_party_tool_count.present?
                  (res["Other third-party tools"] ||= []) << { x: date, y: dwc.other_third_party_tool_count }
                end
              end
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
              authorized_orgs:,
              user_session:,
              return_alert_count:,
              is_open_selected:,
            )
          end

          private

          sig { override.returns(RunQueryOutput) }
          def query
            Result.new(dates_with_counts: get_dates_to_counts.values).to_h
          end

          # NOTE: Unused since we're directly using the tool-specific relation in `query`.
          sig { override.returns(String) }
          def union_all_fallback_sql
            %{
              SELECT
                NULL AS #{unique_date_id_name},
                NULL AS tool,
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
              .select("dates.id AS #{unique_date_id_name}", :tool, "COUNT(*) AS alert_count")
              .joins("JOIN (#{dates_table_sql}) AS dates ON #{table_name}.next_revision_date_id > dates.id AND #{table_name}.date_id <= dates.id")
              .where(alert_resolved: !is_open_selected, repository_id: repo_metadata_rel.select(:repository_id))
              .group(unique_date_id_name, :tool)
          end

          # A unique name to avoid conflicting with a code scanning tool name.
          sig { returns(String) }
          memoize def unique_date_id_name
            "date_id_#{SecureRandom.uuid}".gsub("-", "_")
          end

          sig { returns(T::Set[String]) }
          memoize def requested_third_party_tools
            security_features - [TOOL_CODEQL]
          end

          sig { returns(T::Hash[::Date, DateWithCounts]) }
          def initialize_dates_to_counts
            date_ids.each_with_object({}) do |date_id, acc|
              date = ::Date.parse(date_id.to_s)
              acc[date] = DateWithCounts.new(date: date, third_party_tool_counts: {})

              if security_features.include?(TOOL_CODEQL)
                acc[date].codeql_count = 0
              end

              if requested_third_party_tools.size > MAX_NUM_TOP_TOOLS
                acc[date].other_third_party_tool_count = 0
              end
            end
          end

          sig { returns(T::Hash[::Date, DateWithCounts]) }
          memoize def get_dates_to_counts
            dates_to_counts = code_scanning_rel.each_with_object(initialize_dates_to_counts) do |row, acc|
              date = ::Date.parse(row[unique_date_id_name].to_s)
              date_with_counts = acc.fetch(date)

              if row.tool.downcase == TOOL_CODEQL
                date_with_counts.codeql_count = row.alert_count
              else
                date_with_counts.third_party_tool_counts[row.tool] = row.alert_count
              end
            end

            remove_and_sum_non_top_tools(dates_to_counts)
          end

          # Remove and sum alerts from non-top third-party tools into `other_third_party_tool_count`.
          sig { params(dates_to_counts: T::Hash[::Date, DateWithCounts]).returns(T::Hash[::Date, DateWithCounts]) }
          def remove_and_sum_non_top_tools(dates_to_counts)
            new_dates_to_counts = T.let(dates_to_counts.deep_dup, T::Hash[::Date, DateWithCounts])

            top_tools = get_top_tools(new_dates_to_counts)
            include_other_third_party_tool_count = requested_third_party_tools.size > MAX_NUM_TOP_TOOLS || top_tools.size >= MAX_NUM_TOP_TOOLS

            new_dates_to_counts.each do |_, res|
              # Earlier dates may not have had an entry for the top tools, so initialize their counts to 0.
              top_tools.each { |tool| res.third_party_tool_counts[tool] ||= 0 }

              res.third_party_tool_counts.each do |tool, alert_count|
                next if top_tools.include?(tool)
                res.third_party_tool_counts.delete(tool)

                if include_other_third_party_tool_count
                  res.other_third_party_tool_count = (res.other_third_party_tool_count || 0) + alert_count
                end
              end
            end

            new_dates_to_counts
          end

          # Top tools with the most alerts on the end_date.
          sig { params(dates_to_counts: T::Hash[::Date, DateWithCounts]).returns(T::Set[String]) }
          def get_top_tools(dates_to_counts)
            dates_to_counts
              .fetch(end_date)
              .third_party_tool_counts
              .sort_by { |_, v| -v }
              .first(MAX_NUM_TOP_TOOLS)
              .map(&:first)
              .to_set
          end
        end
      end
    end
  end
end
