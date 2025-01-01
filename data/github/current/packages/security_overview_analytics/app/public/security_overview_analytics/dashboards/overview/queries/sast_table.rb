# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class SastTable < Base
          include GitHub::SecurityCenter::LoggingHelper

          RunQueryOutput = type_member { { fixed: T::Array[Result] } }

          class Result < T::Struct

            const :count_open_alerts, Integer
            const :cwes, T::Array[String]
            const :name, String
            const :rule_sarif_id, String, default: ""
            const :severity, String

            sig { returns(T::Hash[Symbol, T.untyped]) }
            def to_h
              {
                count_open_alerts:,
                cwes:,
                name:,
                rule_sarif_id:,
                severity:
              }
            end

            sig { params(other: Result).returns(T::Boolean) }
            def ==(other)
              self.serialize == other.serialize
            end
          end

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

          sig { override.params(offset: T.nilable(Integer), limit: T.nilable(Integer)).returns(RunQueryOutput) }
          def query(offset:, limit:)
            return [] if security_features.empty?

            if run_sliced_queries?
              # Run the query in parallel for each rule_slice4
              # Then re-order by open_alerts and take the first 10 rules
              # Note that same rule can not get into multiple slices by definition, so rows are unique
              # The slice4 is calculated as crc of the rule_sarif_identifier, which is a stable function,
              # and so same rule will always get into the same slice
              db_results = (0..3).map do |rule_slice4|
                sql = %{
                  SELECT
                    COUNT(*) AS count_open_alerts,
                    rev.alert_severity AS severity,
                    rev.rule_sarif_identifier AS rule_sarif_id,
                    MAX(rev.repository_id) AS sample_repo_id
                  FROM
                    (#{union_all_sql(slice_by: SliceBy.new(value_4_slices: rule_slice4, dimension: :by_rule))}) AS rev
                  GROUP BY
                    rev.rule_sarif_identifier
                  ORDER BY
                    count_open_alerts DESC,
                    rev.rule_sarif_identifier ASC
                  LIMIT 10
                }.squish

                ApplicationRecord::SecurityOverviewAnalytics.connection.select_all(sql, async: true)
              end
              # Async queries return above end up returning array of promise-like ActiveRecord::FutureResult objects
              # The objects have .then method which return completed promises with values
              .map { |promise| promise.then(&:rows) }
              .flat_map(&:value)
              .sort_by { |row| [-row[0], row[2]] }
              .first(10)
              .map do |row|
                {
                  count_open_alerts: row[0],
                  severity: row[1],
                  rule_sarif_id: row[2],
                  sample_repo_id: row[3],
                }
              end
            else
              sql = %{
                SELECT
                  COUNT(*) AS count_open_alerts,
                  rev.alert_severity AS severity,
                  rev.rule_sarif_identifier AS rule_sarif_id,
                  MAX(rev.repository_id) AS sample_repo_id
                FROM
                  (#{union_all_sql}) AS rev
                GROUP BY
                  rev.rule_sarif_identifier
                ORDER BY
                  count_open_alerts DESC,
                  rev.rule_sarif_identifier ASC
                LIMIT 10
              }.squish

              db_results = ApplicationRecord::SecurityOverviewAnalytics.connection.select_all(sql)
                .map { |row| row.to_hash.symbolize_keys }
            end

            res = hydrate_from_turboscan(db_results).map do |result|
              Result.new(
                count_open_alerts: result.fetch(:count_open_alerts),
                cwes: result.fetch(:cwes),
                name: result.fetch(:name),
                rule_sarif_id: result.fetch(:rule_sarif_id),
                severity: result.fetch(:severity).downcase
              )
            end

            # Sort the results by count_open_alerts descending, then by name ascending.
            res.sort_by { |result| [-result.count_open_alerts, result.name] }
          end

          sig { override.returns(String) }
          def union_all_fallback_sql
            %{
              SELECT
                NULL AS alert_severity,
                NULL AS rule_sarif_identifier,
                NULL AS repository_id
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
              .where(alert_resolved: false, repository_id: repo_metadata_rel.select(:repository_id))
              .where("next_revision_date_id > ?", end_date_id)
              .where("date_id <= ?", end_date_id)
          end

          sig { params(db_results: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
          def hydrate_from_turboscan(db_results)
            sample_repo_ids = db_results.map { |db_result| db_result.fetch(:sample_repo_id) }.uniq
            repo_owners_ids = if scope.is_a?(Organization)
              [scope.id]
            else
              Repository.where(repository_id: sample_repo_ids).pluck(:owner_id).uniq
            end

            log(
              step: "hydrate_from_turboscan",
              "code.namespace": self.class.name,
              "gh.org.ids": repo_owners_ids.join(",")
            ) do
              GitHub.dogstats.distribution_time("security_overview_analytics.dashboards.overview.queries.sast_table.hydrate_from_turboscan") do
                rule_sarif_ids = db_results.map { |db_result| db_result.fetch(:rule_sarif_id) }.uniq
                return [] if rule_sarif_ids.empty? || sample_repo_ids.empty?

                rules_by_sarif_id = (
                  GitHub::Turboscan.rules_for_org(
                    Turboscan::Proto::RulesForOrgRequest.new({
                      filter: Turboscan::Proto::AlertsFilter.new({
                        rule_sarif_identifiers: rule_sarif_ids
                      }).to_h,
                      owner_ids: repo_owners_ids,
                      repository_ids: sample_repo_ids
                    }).to_h
                  ).try(:data).try(:rules) || []
                ).index_by(&:sarif_identifier)

                db_results.each_with_object([]) do |db_result, acc|
                  rule = rules_by_sarif_id[db_result.fetch(:rule_sarif_id)]
                  next log_warn("No rule in GetRulesForOrg response") if rule.blank?
                  rule = T.cast(rule, Turboscan::Proto::OrgRule)

                  acc << {
                    count_open_alerts: db_result.fetch(:count_open_alerts),
                    cwes: cwes_from_tags(rule.tags.map(&:to_s)),
                    name: rule.short_description,
                    rule_sarif_id: db_result.fetch(:rule_sarif_id),
                    severity: db_result.fetch(:severity)
                  }
                end
              end
            end
          end

          sig { params(tags: T::Array[String]).returns(T::Array[String]) }
          def cwes_from_tags(tags)
            tags.each_with_object([]) do |tag, acc|
              normalized_tag = RepositoryCodeScanning::ShowView.new.rule_tag_label(tag)
              next unless normalized_tag.starts_with?("CWE-")

              acc << normalized_tag
            end
          end
        end
      end
    end
  end
end
