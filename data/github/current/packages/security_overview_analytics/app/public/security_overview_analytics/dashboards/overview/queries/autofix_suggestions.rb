# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class AutofixSuggestions < Base
          extend T::Sig

          class Result < T::Struct
            prop :suggestion_count, Integer, default: 0
          end

          class NoDataResult < T::Struct
            const :no_data, String, default: "No repositories found."
          end

          class ErrorResult < T::Struct
          end

          RunQueryOutput = type_member { { fixed: T.any(Result, NoDataResult, ErrorResult) } }

          BATCH_SIZE = 1_000

          sig { override.returns(RunQueryOutput) }
          def perform
            return NoDataResult.new unless security_features.include?(SecurityFeaturesParser::TOOL_CODEQL)
            return NoDataResult.new unless alerts_filterer.should_run_code_scanning_query?
            # This widget only applies to CodeQL
            return NoDataResult.new if alerts_filterer.third_party_rule_filters_applied?

            owner_ids =
              case @repos_filterer
              when OrgReposFilterer
                [@repos_filterer.organization.id]
              when EnterpriseReposFilterer
                # Autofix suggestions are only supported for orgs for now, and backend requires at least one org
                # This happens if user has no orgs allowed
                return NoDataResult.new if @repos_filterer.organizations.empty?
                @repos_filterer.organizations.map(&:id)
              else
                raise "Unsupported filterer type"
              end

            rule_ids = alerts_filterer.code_scanning_rule_filters.codeql.incl_filters
            exclude_rule_ids = alerts_filterer.code_scanning_rule_filters.codeql.excl_filters

            req = ::Turboscan::Proto::GetSuggestedFixStatisticsRequest.new(
              owner_ids:,
              severities: alerts_filterer.selected_severities
                .map { |v| ::GitHub::Turboscan.to_severity(v) } # to number
                .map { |v| ::Turboscan::Proto::Severity.lookup(v || 0) } # to symbol
                .compact,
              rule_ids:,
              exclude_rule_ids:,
              start: to_proto_timestamp(start_date),
              end: to_proto_timestamp(end_date),
            )

            result = Result.new
            found_repos = T.let(false, T::Boolean)

            batch_handler = proc do |repository_ids|
              found_repos = true
              req.clear_repository_ids
              req.repository_ids.concat(repository_ids) if repository_ids.present?

              res = ::GitHub::Turboscan::SuggestedFixes.suggested_fix_statistics(req.to_h)
              res_data = T.let(res.try(:data), T.nilable(Turboscan::Proto::GetSuggestedFixStatisticsResponse))

              if res.nil? || res.error.present? || res_data.nil?
                # If we get an error calling turboscan, just exit.
                # Don't bother finishing the repo batches.
                report_error(error: res&.error, repository_ids:)
                return ErrorResult.new
              end

              result.suggestion_count += res_data.suggested
            end

            if repos_filterer.filters_applied?
              # If there are any repository filters, or if the user has a limited view of
              # repositories in their org, we have to pass those repository ids to turboscan.
              # To mitigate performance issues, we do this in batches and aggregate the results.
              repos_filterer.cs_repo_metadata_rel.pluck(:repository_id).each_slice(BATCH_SIZE) do |repository_ids|
                batch_handler.call(repository_ids)
              end
            else
              # If there are no applicable repository filters, and the user is not limited
              # on which / how many repositories they can see, we can save time and make
              # a single call to turboscan.
              batch_handler.call([])
            end

            return NoDataResult.new unless found_repos

            result
          end

          private

          sig { params(value: ::Date).returns(::Google::Protobuf::Timestamp) }
          def to_proto_timestamp(value)
            timestamp = ::Google::Protobuf::Timestamp.new
            timestamp.from_time(value.to_time)
            timestamp
          end

          sig do
            params(
              error: T.nilable(T.any(StandardError, Twirp::Error)),
              repository_ids: T::Array[Integer]
            ).void
          end
          def report_error(error: nil, repository_ids: [])
            actor_hash = {
              'gh.actor.id': user.id,
              'gh.actor.login': user.display_login,
            }

            scope_hash = case scope
            when ::Business
              {
                'gh.business.id': scope.id,
              }
            when ::Organization
              {
                'gh.org.id': scope.id,
                'gh.org.login': scope.display_login,
              }
            end

            log_hash = {
              "code.namespace": self.class.name,
              "code.function": __method__,
              **actor_hash,
              **scope_hash,
              "gh.security_overview_analytics.repo_id_count": repository_ids.size,
              "gh.security_overview_analytics.start_date": start_date,
              "gh.security_overview_analytics.end_date": end_date
            }

            if error.is_a?(StandardError)
              Failbot.report(error, **actor_hash, **scope_hash)
              log_hash["exception.message"] = error.message
            end

            if error.is_a?(Twirp::Error)
              Failbot.report(StandardError.new(error.msg), **actor_hash, **scope_hash)
              log_hash["exception.message"] = error.msg
            end

            GitHub.logger.error("Failed to get autofix suggestion metrics", log_hash)
          end

          # NOTE:
          # The below methods are not used because we're reaching out to Turboscan instead of querying our tables,
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
            NoDataResult.new
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
