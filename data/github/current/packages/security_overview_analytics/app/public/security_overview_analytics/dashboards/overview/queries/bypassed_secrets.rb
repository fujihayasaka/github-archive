# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class BypassedSecrets < Base
          extend T::Sig

          QueryParser = ::Search::Queries::SecurityCenter::QueryParser

          RunQueryOutput = type_member { { fixed: [T::Hash[Symbol, Integer], T::Boolean] } }

          sig { override.returns(RunQueryOutput) }
          def perform
            return [no_data_response, false] unless @security_features.include?(::SecurityCenter::SecurityFeatures::SECRET_SCANNING)
            # Return no data if severities other than 'critical' are selected
            return [no_data_response, false] if !alerts_filterer.selected_severities.include?("critical")
            # Skip calling TSS if other tool filters are applied
            return [no_data_response, false] unless alerts_filterer.should_run_secret_scanning_query?

            allowed_secret_scanning_repo_ids = nil
            if @scope.is_a?(Organization)
              allowed_repo_ids_by_feature = T.cast(repos_filterer, OrgReposFilterer).allowed_repo_ids_by_feature
              allowed_secret_scanning_repo_ids = allowed_repo_ids_by_feature&.dig(::SecurityCenter::SecurityFeatures::SECRET_SCANNING)
            end

            response, err = ::SecurityCenter::QueryServices::SecretScanningMetrics.new(
              scope:,
              user:,
              user_session:,
              query_parser:,
              start_date:,
              end_date:,
              allowed_repo_ids: allowed_secret_scanning_repo_ids,
              authorized_orgs:
            ).get_push_protection_metrics_for_repos

            if response.is_a?(::SecurityCenter::QueryServices::SecretScanningMetrics::NoDataResponse)
              return [no_data_response, false]
            end

            if err.present? || response.nil?
              report_error(error: err)
              return [empty_response, true]
            end

            [{
              bypassed_alerts_count: response.bypassed_alert_count,
              successful_blocks_count: response.successful_block_count,
              total_blocks_count: response.total_block_count
            }, false]
          end

          sig { returns(T::Hash[Symbol, Integer]) }
          def empty_response
            {
              bypassed_alerts_count: 0,
              successful_blocks_count: 0,
              total_blocks_count: 0
            }
          end

          sig { returns(T::Hash[Symbol, Integer]) }
          def no_data_response
            {
              no_data: "No repositories found"
            }
          end

          sig { params(error: T.nilable(T.any(StandardError, T::Boolean, Twirp::Error))).void }
          def report_error(error: nil)
            scope_info =
            if scope.is_a? ::Business
              {
                "gh.business.id": scope.id,
                "gh.business.name": scope.name,
              }
            else
              {
                "gh.org.id": scope.id,
                "gh.org.login": scope.display_login,
              }
            end

            log_hash = {
              "code.namespace": self.class.name,
              "code.function": __method__,
              "gh.security_overview_analytics.start_date": start_date,
              "gh.security_overview_analytics.end_date": end_date,
              "gh.user.id": user.id,
              "gh.user.login": user.display_login,
              **scope_info,
            }

            if error.is_a?(StandardError) || error.is_a?(Twirp::Error)
              Failbot.report(error, log_hash)

              log_hash["exception.message"] =
                if error.is_a?(StandardError)
                  error.message
                elsif error.is_a?(Twirp::Error)
                  error.msg
                end
            end
            GitHub.logger.info("Failed to get push protection metrics", log_hash)
          end

          # NOTE:
          # The below methods are not used because we're reaching out to TSS instead of querying our tables,
          # but they are required by the Base class

          sig do
            override.params(
              rel: ActiveRecord::Relation,
              repo_metadata_rel: ActiveRecord::Relation,
              table_name: String
            ).returns(ActiveRecord::Relation)
          end
          def common_clauses_rel(rel, repo_metadata_rel, table_name)
            rel
          end

          sig { override.returns(RunQueryOutput) }
          def query
            [{ unused: 0 }, true]
          end

          sig { override.returns(String) }
          def union_all_fallback_sql
            ""
          end
        end
      end
    end
  end
end
