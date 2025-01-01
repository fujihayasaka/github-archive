# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Filters
    module FeatureStatusSummary
      class ByFeature
        include Filter

        STATES_LOOKUP = T.let({
          "enabled" => "ENABLED",
          "not-enabled" => "NOT_ENABLED",
          "eligible" => "ELIGIBLE",
          "not-eligible" => "NOT_ELIGIBLE",
        }, T::Hash[String, String])

        NUMERIC_EXPRESSION = %r{
          \A([0-9]+)\z
        }x
        RANGE_EXPRESSION = %r{
          \A([<>]=?)([0-9]+)\z    # optional comparator followed by single numeric value
        }x

        NOOP_FILTER = T.let(["false", {}], T.untyped)

        sig do
          params(
            incl_filters: T.nilable(T::Array[String]),
            excl_filters: T.nilable(T::Array[String]),
            feature: T.any(Symbol, String),
          ).void
        end
        def initialize(incl_filters, excl_filters, feature:)
          @incl_filters = T.let(incl_filters&.uniq || [], T::Array[String])
          @excl_filters = T.let(excl_filters&.uniq || [], T::Array[String])
          @feature = T.let(feature.to_sym, Symbol)

          @status_column = "#{feature}_status"
          @status_column_exists = T.let(FeatureStatus.column_names.include?(@status_column), T::Boolean)
          @status_column = T.let("`#{FeatureStatus.table_name}`.`#{@status_column}`", String)

          @count_column = "#{feature}_total_count"
          @count_column_exists = T.let(FeatureStatus.column_names.include?(@count_column), T::Boolean)
          @count_column = T.let("`#{FeatureStatus.table_name}`.`#{@count_column}`", String)
        end

        sig { override.params(rel: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
        def apply(rel)
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
          filters.select do |f|
            next true if STATES_LOOKUP.key?(f)
            next true if f.match(RANGE_EXPRESSION)
            next true if f.match(NUMERIC_EXPRESSION)
            false
          end
        end

        sig do
          params(
            rel: ActiveRecord::Relation,
            values: T::Array[String],
            negated: T::Boolean,
          ).returns(ActiveRecord::Relation)
        end
        def where(rel, values, negated:)
          or_rels = []
          values.each do |value|
            filter = \
              if STATES_LOOKUP.key?(value)
                state_filter(T.must(STATES_LOOKUP[value]), negated:)
              else
                count_filter(value, negated:)
              end

            or_rels << rel.where(filter)
          end

          if negated
            rel.and(or_rels.reduce { |rel, or_rel| rel.and(or_rel) })
          else
            rel.and(or_rels.reduce { |rel, or_rel| rel.or(or_rel) })
          end
        end

        sig do
          params(state: String, negated: T::Boolean)
            .returns([String, T::Hash[Symbol, String]])
        end
        def state_filter(state, negated:)
          return NOOP_FILTER unless @status_column_exists

          operator = "="
          operator = negate_operator(operator) if negated
          [
            "#{@status_column} #{operator} (:state)",
            { state: }
          ]
        end

        sig do
          params(value: String, negated: T::Boolean)
            .returns([String, T::Hash[Symbol, String]])
        end
        def count_filter(value, negated:)
          return NOOP_FILTER unless @count_column_exists

          match = RANGE_EXPRESSION.match(value)
          if match
            operator = match[1] || ""
            operator = negate_operator(operator) if negated
            count = Integer(match[2] || "")
            [
              "#{@count_column} #{operator} :count",
              { count: }
            ]
          else
            operator = "="
            operator = negate_operator(operator) if negated
            count = Integer(value)
            [
              "#{@count_column} #{operator} :count",
              { count: }
            ]
          end
        rescue ArgumentError
          NOOP_FILTER # Don't return any results for non-numeric values
        end

        sig { params(op: String).returns(String) }
        def negate_operator(op)
          case op
          when ">" then "<="
          when ">=" then "<"
          when "<" then ">="
          when "<=" then ">"
          when "=" then "!="
          when "!=" then "="
          else raise ArgumentError, "Unsupported operator: #{op}"
          end
        end
      end
    end
  end
end
