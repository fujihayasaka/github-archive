# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Filters
    module FeatureStatusSummary
      class ByHasSeverity
        include Filter

        SEVERITIES_LOOKUP = T.let({
          "critical" => "critical",
          "high" => "high",
          "medium" => "medium",
          "moderate" => "medium",
          "low" => "low",
          "informational" => "info",
        }, T::Hash[String, String])

        sig { returns(T::Array[String]) }; attr_reader :incl_filters
        sig { returns(T::Array[String]) }; attr_reader :excl_filters

        sig do
          params(
            incl_filters: T.nilable(T::Array[String]),
            excl_filters: T.nilable(T::Array[String]),
          ).void
        end
        def initialize(incl_filters, excl_filters)
          @incl_filters = T.let(incl_filters&.uniq || [], T::Array[String])
          @excl_filters = T.let(excl_filters&.uniq || [], T::Array[String])
        end

        sig { override.params(rel: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
        def apply(rel)
          return rel if is_empty?

          if @incl_filters.present?
            valid_filters = select_valid_filters(@incl_filters)
            return rel.none if valid_filters.empty?
            rel = where(rel, valid_filters, negated: false)
          end

          if @excl_filters.present?
            valid_filters = select_valid_filters(@excl_filters)
            return rel if valid_filters.size < @excl_filters.size
            rel = where(rel, valid_filters, negated: true)
          end

          rel
        end

        sig { override.returns(T::Boolean) }
        def is_empty?
          @incl_filters.blank? && @excl_filters.blank?
        end

        sig { override.returns(T::Boolean) }
        def has_incl_filters?
          @incl_filters.present?
        end

        private

        sig { params(filters: T::Array[String]).returns(T::Array[String]) }
        def select_valid_filters(filters)
          filters.select { |f| SEVERITIES_LOOKUP.key?(f) }
        end

        sig do
          params(
            rel: ActiveRecord::Relation,
            values: T::Array[String],
            negated: T::Boolean,
          ).returns(ActiveRecord::Relation)
        end
        def where(rel, values, negated:)
          or_rels = values.each_with_object([]) do |value, memo|
            db_severity = T.must(SEVERITIES_LOOKUP[value])
            operator = negated ? "=" : ">"
            search_columns = \
              case value
              when "medium"
                # Code scanning calls this "medium" severity
                ["code_scanning_alerts_medium_count"]
              when "moderate"
                # ...while Dependabot calls it "moderate"
                ["dependabot_alerts_medium_count"]
              else
                [
                  "dependabot_alerts_#{db_severity}_count",
                  "code_scanning_alerts_#{db_severity}_count",
                ]
              end

            search_columns.each do |column|
              # not all features have all severities
              next unless FeatureStatus.column_names.include?(column)
              memo << rel.where("`#{FeatureStatus.table_name}`.`#{column}` #{operator} 0")
            end
          end

          if negated
            rel.and(or_rels.reduce { |rel, or_rel| rel.and(or_rel) })
          else
            rel.and(or_rels.reduce { |rel, or_rel| rel.or(or_rel) })
          end
        end
      end
    end
  end
end
