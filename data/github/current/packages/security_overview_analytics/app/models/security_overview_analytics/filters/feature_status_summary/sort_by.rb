# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Filters
    module FeatureStatusSummary
      class SortBy
        include GitHub::Memoizer

        SORT_OPTIONS = T.let([
          (SORT_BY_LAST_UPDATED = T.let(:"last-updated", Symbol)),
          (SORT_BY_REPO_NAME = T.let(:repos, Symbol)),
          (SORT_BY_DEPENDABOT_ALERTS = T.let(:dependabot, Symbol)),
          (SORT_BY_CODE_SCANNING_ALERTS = T.let(:"code-scanning", Symbol)),
          (SORT_BY_SECRET_SCANNING_ALERTS = T.let(:"secret-scanning", Symbol)),
        ], T::Array[Symbol])

        RISK_SORT_OPTIONS = SORT_OPTIONS

        COVERAGE_SORT_OPTIONS = T.let([
          SORT_BY_LAST_UPDATED,
          SORT_BY_REPO_NAME,
        ], T::Array[Symbol])

        DEFAULT_SORT_OPTION = SORT_BY_LAST_UPDATED

        sig { returns(Symbol) }
        attr_reader :sort_option

        sig { params(sort_option: T.nilable(String)).void }
        def initialize(sort_option)
          # coerce the option into a supported value, or fallback to default
          sort_option = self.class.sort_option_or_default(sort_option)
          @sort_option = T.let(sort_option, Symbol)
        end

        sig { params(rel: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
        def apply(rel)
          case @sort_option
          when SORT_BY_LAST_UPDATED
            rel.order(Arel.sql("`#{Repository.table_name}`.`pushed_at` DESC, `#{Repository.table_name}`.`name` ASC"))
          when SORT_BY_REPO_NAME
            rel.order(Arel.sql("`#{Repository.table_name}`.`name` ASC, `#{Repository.table_name}`.`pushed_at` DESC"))
          when SORT_BY_DEPENDABOT_ALERTS
            rel.order(Arel.sql("`#{FeatureStatus.table_name}`.`dependabot_alerts_total_count` DESC, `#{Repository.table_name}`.`pushed_at` DESC"))
          when SORT_BY_CODE_SCANNING_ALERTS
            rel.order(Arel.sql("`#{FeatureStatus.table_name}`.`code_scanning_alerts_total_count` DESC, `#{Repository.table_name}`.`pushed_at` DESC"))
          when SORT_BY_SECRET_SCANNING_ALERTS
            rel.order(Arel.sql("`#{FeatureStatus.table_name}`.`secret_scanning_alerts_total_count` DESC, `#{Repository.table_name}`.`pushed_at` DESC"))
          else
            GitHub.logger.warn(
              "Unknown sort option. Using default sort instead.",
              "code.namespace": self.class.name,
              "code.function": __method__,
              "gh.security_center.sort_option": @sort_option
            )
            rel.order(Arel.sql("`#{Repository.table_name}`.`pushed_at` DESC, `#{Repository.table_name}`.`name` ASC"))
          end
        end

        sig { params(sort_option: T.nilable(String), valid_options: T::Array[Symbol]).returns(Symbol) }
        def self.sort_option_or_default(sort_option, valid_options: SORT_OPTIONS)
          sort_option = sort_option&.downcase&.to_sym
          valid_options.include?(sort_option) ? T.must(sort_option) : DEFAULT_SORT_OPTION
        end
      end
    end
  end
end
