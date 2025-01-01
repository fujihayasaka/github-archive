# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      class SecurityFeaturesParser
        include GitHub::Memoizer
        include Scientist
        include GitHub::SecurityCenter::LoggingHelper

        TOOL_CODEQL = "codeql"

        sig { returns(::Search::Queries::SecurityCenter::QueryParser) }
        attr_reader :query

        sig { returns(T.any(::Organization, ::Business)) }
        attr_reader :scope

        sig { returns(T.nilable(T::Array[Integer])) }
        attr_reader :allowed_code_scanning_repo_ids

        sig { returns(T.nilable(T::Array[Organization])) }
        attr_reader :authorized_code_scanning_orgs

        sig do
          params(
            query: ::Search::Queries::SecurityCenter::QueryParser,
            scope: T.any(::Organization, ::Business),
            allowed_code_scanning_repo_ids: T.nilable(T::Array[Integer]),
            authorized_code_scanning_orgs: T.nilable(T::Array[::Organization]),
          ).void
        end
        def initialize(query:, scope:, allowed_code_scanning_repo_ids: nil, authorized_code_scanning_orgs: nil)
          # Enterprise scope must always supply authorized orgs
          raise ArgumentError if scope.is_a?(Business) && authorized_code_scanning_orgs.nil?

          @query = query
          @scope = scope
          @authorized_code_scanning_orgs = authorized_code_scanning_orgs
          @allowed_code_scanning_repo_ids = allowed_code_scanning_repo_ids
        end

        sig { returns(T::Hash[String, String]) }
        memoize def backend_to_frontend_tool_map
          {
            ::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS => "dependabot",
            TOOL_CODEQL => TOOL_CODEQL,
            ::SecurityCenter::SecurityFeatures::SECRET_SCANNING => "secret-scanning"
          }
        end

        sig { returns(T::Hash[String, String]) }
        memoize def frontend_to_backend_tool_map
          T.unsafe(backend_to_frontend_tool_map).invert
        end

        sig { returns(T::Array[String]) }
        memoize def selected_backend_security_features
          pos_requested_security_features = pos_requested_features
          neg_requested_security_features = neg_requested_features
          available_third_party_tools = nil # don't fetch these unless we need to

          if neg_requested_security_features.include?("github")
            neg_requested_security_features.delete("github")
            neg_requested_security_features += visible_frontend_security_features
          end

          if pos_requested_security_features.include?("github")
            pos_requested_security_features.delete("github")
            pos_requested_security_features += visible_frontend_security_features
          end

          if neg_requested_security_features.include?("third-party")
            neg_requested_security_features.delete("third-party")

            # !third-party is the same as [dependabot, secret-scanning, codeql]
            # so add those to the positives instead of reaching out to turboscan
            if pos_requested_security_features.empty?
              pos_requested_security_features = visible_frontend_security_features
            else
              pos_requested_security_features = pos_requested_security_features & visible_frontend_security_features
            end
          elsif neg_requested_security_features.present?
            # if the user is not excluding third-party tools but does have exclusions,
            # we need to fetch third-party tools so that they're included in `all_allowed_features`
            available_third_party_tools ||= allowed_third_party_tools.map(&:downcase)
          end

          if pos_requested_security_features.include?("third-party")
            pos_requested_security_features.delete("third-party")

            available_third_party_tools ||= allowed_third_party_tools.map(&:downcase)
            pos_requested_security_features += available_third_party_tools

            return [] if pos_requested_security_features.empty?
          elsif pos_requested_security_features.empty?
            # if there are no positive features, then we need all features, which requires
            # fetching third-party tools from turboscan
            available_third_party_tools ||= allowed_third_party_tools.map(&:downcase)
          end

          # if we don't have `available_third_party_tools`, then use the 3rd party tools from the query
          all_allowed_third_party_tools = available_third_party_tools || (pos_requested_security_features - visible_frontend_security_features)

          all_allowed_features = visible_frontend_security_features + all_allowed_third_party_tools

          if pos_requested_security_features.any? && (pos_requested_security_features & all_allowed_features).empty?
            return []
          end

          pos_features = all_allowed_features & pos_requested_security_features
          neg_features = all_allowed_features & neg_requested_security_features

          features = all_allowed_features
          features &= pos_features if pos_features.present?
          features -= neg_features if neg_features.present?

          T.unsafe(frontend_to_backend_tool_map).slice(*features).values + (all_allowed_third_party_tools & features)
        end

        sig { returns(T::Array[String]) }
        memoize def visible_backend_security_features
          features = ::SecurityCenter::SecurityFeatures.visible_features(scope).deep_dup

          # If "code_scanning" is visible, replace it with "codeql".
          if features.include?(::SecurityCenter::SecurityFeatures::CODE_SCANNING)
            features.delete(::SecurityCenter::SecurityFeatures::CODE_SCANNING)
            features << TOOL_CODEQL
          end

          features
        end

        sig { returns(T::Array[String]) }
        memoize def visible_frontend_security_features
          T.unsafe(backend_to_frontend_tool_map)
            .slice(*visible_backend_security_features)
            .values
        end

        sig { returns(T::Array[String]) }
        memoize def allowed_third_party_tools
          return [] if allowed_code_scanning_repo_ids&.empty?
          owner_ids = scope.is_a?(Organization) ? [scope.id] : authorized_code_scanning_orgs&.map(&:id)

          repos_rel = ::SecurityOverviewAnalytics::Repository
            .where(organization_id: owner_ids)
            .joins(:feature_status_revisions)
            .where(feature_status_revisions: { next_revision_date_id: ::SecurityOverviewAnalytics::Date::FUTURE_DATE_ID })
            .where(feature_status_revisions: { code_scanning_enabled: true })

          repos_rel = repos_rel.where(repository_id: allowed_code_scanning_repo_ids) if allowed_code_scanning_repo_ids

          rel = SecurityOverviewAnalytics::CodeScanningAlertRevision
            .where(
              repository_id: repos_rel.select(:repository_id),
              next_revision_date_id: ::SecurityOverviewAnalytics::Date::FUTURE_DATE_ID,
              alert_severity: %w[critical high medium low],
            )
            .distinct

          GitHub.dogstats.distribution_time("security_overview_analytics.dashboards.allowed_third_party_tools.perform.dist") do
            if !GitHub.enterprise?
              tool_names = (0..3).map do |alerts_slice4|
                rel.where(slice4: alerts_slice4).async_pluck(:tool)
              end.flat_map(&:value).uniq
            else
              tool_names = rel.pluck(:tool)
            end

            # The not-equal query consumes the mysql range for index seeks, so doing that in memory instead
            tool_names.excluding("CodeQL")
          end
        end

        sig { returns(T::Array[String]) }
        memoize def pos_requested_features
          query.get_positive_and_negative_qualified_values("tool").deep_dup.first.map(&:downcase)
        end

        sig { returns(T::Array[String]) }
        memoize def neg_requested_features
          query.get_positive_and_negative_qualified_values("tool").deep_dup.last.map(&:downcase)
        end

        instrument_method \
          :selected_backend_security_features,
          :allowed_third_party_tools
      end
    end
  end
end
