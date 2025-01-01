# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module CodeScanningMetrics
      class PullRequestAlertsFilterer

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
            .where(tool: "CodeQL")
            .where(alert_severity: %w[critical high medium low])
            .then { |rel| filters.reduce(rel) { |r, filter| filter.apply(r) } }
        end

        private

        sig { returns T::Array[T.untyped] }
        def filters
          [
            Filters::BySeverity.new(*@query.get_positive_and_negative_qualified_values("severity")),
            Filters::CodeScanning::ByRule.new(*@query.get_positive_and_negative_qualified_values(CodeScanningAlertRevision::QUALIFIER_CODEQL_RULE)),
            Filters::ByResolution.new(*@query.get_positive_and_negative_qualified_values("resolution")),
            Filters::CodeScanning::ByAutofixStatus.new(*@query.get_positive_and_negative_qualified_values("codeql.autofix")),
            Filters::CodeScanning::ByState.new(*@query.get_positive_and_negative_qualified_values("state")),
          ].compact
        end
      end
    end
  end
end
