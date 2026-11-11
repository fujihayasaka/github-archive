# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      class PreventionDataFilterer

        TOOLS_WITH_CODEQL = T.let(%w[codeql github], T::Array[String])
        INVALID_QUALIFIERS = T.let(%w[
            dependabot.ecosystem
            dependabot.package
            dependabot.scope
            secret-scanning.provider
            secret-scanning.secret-type
            secret-scanning.validity
            secret-scanning.bypassed
            third-party.rule
          ],
          T::Array[String]
        )

        sig { params(query: ::Search::Queries::SecurityCenter::QueryParser).void }
        def initialize(query)
          @query = query
        end

        sig { params(rel: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
        def apply(rel)
          rel
            .joins(%{
              JOIN `#{FeatureStatusRevision.table_name}`
              ON `#{FeatureStatusRevision.table_name}`.`repository_id` = `#{rel.klass.table_name}`.`repository_id`
              AND `#{FeatureStatusRevision.table_name}`.`next_revision_date_id` = #{Date::FUTURE_DATE_ID}
              AND `#{FeatureStatusRevision.table_name}`.`code_scanning_enabled` = 1
            }.squish)
            .where(tool: "CodeQL") # TODO - we're only supporting CodeQL for now
            .where(alert_severity: %w[critical high medium low])
            .then { |rel| filters.reduce(rel) { |r, filter| filter.apply(r) } }
        end

        sig { returns(T::Boolean) }
        def has_valid_filters?
          # TODO - the requirement for valid filters will change as we add more features into the Prevention page
          codeql_selected? && (@query.parsed_query.keys & INVALID_QUALIFIERS).empty?
        end

        private

        sig { returns(T::Boolean) }
        def codeql_selected?
          codeql_excluded = (excluded_tools & TOOLS_WITH_CODEQL).any?
          codeql_included = included_tools.empty? || (included_tools & TOOLS_WITH_CODEQL).any?
          codeql_included && !codeql_excluded
        end

        sig { returns(T::Array[String]) }
        def included_tools
          @query.get_positive_and_negative_qualified_values("tool").deep_dup.first.map(&:downcase)
        end

        sig { returns(T::Array[String]) }
        def excluded_tools
          @query.get_positive_and_negative_qualified_values("tool").deep_dup.last.map(&:downcase)
        end

        sig { returns T::Array[T.untyped] }
        def filters
          [
            Filters::BySeverity.new(*@query.get_positive_and_negative_qualified_values("severity")),
            Filters::CodeScanning::ByRule.new(*@query.get_positive_and_negative_qualified_values(CodeScanningAlertRevision::QUALIFIER_CODEQL_RULE)),
            Filters::CodeScanning::ByAutofixStatus.new(*@query.get_positive_and_negative_qualified_values("codeql.autofix")),
            Filters::CodeScanning::ByState.new(*@query.get_positive_and_negative_qualified_values("state")),
          ].compact
        end
      end
    end
  end
end
