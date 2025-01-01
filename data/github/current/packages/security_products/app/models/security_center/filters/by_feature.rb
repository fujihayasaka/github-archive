# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Filters
    class ByFeature

      STATES_LOOKUP = T.let({
        "enabled" => "enrolled",
        "not-enabled" => "not_enrolled",
        "eligible" => "eligible",
        "not-eligible" => "not_eligible",
      }, T::Hash[String, String])

      NUMERIC_EXPRESSION = %r{
        \A([0-9]+)\z
      }x
      RANGE_EXPRESSION = %r{
        \A([<>]=?)([0-9]+)\z    # optional comparator followed by single numeric value
      }x

      SCANNING_STATUS_COLUMN = T.let("`#{RepositorySecurityCenterStatus.table_name}`.`scanning_status`", String)
      SCANNING_COUNT_COLUMN = T.let("`#{RepositorySecurityCenterStatus.table_name}`.`scanning_count`", String)

      sig { returns(T::Array[String]) }; attr_reader :incl_filters
      sig { returns(T::Array[String]) }; attr_reader :excl_filters
      sig { returns(Symbol) }; attr_reader :feature

      sig do
        params(
          incl_filters: T.nilable(T::Array[String]),
          excl_filters: T.nilable(T::Array[String]),
          feature: T.any(Symbol, String),
          scope: T.nilable(T.any(Organization, Business)),
        ).void
      end
      def initialize(incl_filters, excl_filters, feature:, scope: nil)
        @incl_filters = T.let(incl_filters&.uniq || [], T::Array[String])
        @excl_filters = T.let(excl_filters&.uniq || [], T::Array[String])
        @feature = T.let(feature.to_sym, Symbol)
        @scope = scope
      end

      sig { params(rel: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
      def apply(rel)
        return rel if is_empty?

        if incl_filters.present?
          valid_filters = select_valid_filters(incl_filters)
          return rel.none if valid_filters.empty?
          rel = where(rel, valid_filters, negated: false)
        end

        if excl_filters.present?
          valid_filters = select_valid_filters(excl_filters)
          return rel if valid_filters.empty?
          rel = where(rel, valid_filters, negated: true)
        end

        rel
      end

      sig { returns(T::Boolean) }
      def is_empty?
        incl_filters.blank? && excl_filters.blank?
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
        filter_subquery_rel =
          RepositorySecurityCenterStatus
            .where("repository_security_center_statuses.owner_id = repository_security_center_configs.owner_id")
            .where("repository_security_center_statuses.repository_id = repository_security_center_configs.repository_id")
            .where(feature_type: feature)
            .select(:repository_id)

        if @scope.present? && @scope.is_a?(Business)
          filter_subquery_rel = filter_subquery_rel.where(business_id: @scope.id)
        end

        or_rels = values.map do |value|
          if (state = STATES_LOOKUP[value])
            filter_subquery_rel
              .where(state_filter(state, negated:))
          else
            filter_subquery_rel
              .where(count_filter(value, negated:))
              .where(state_filter("enrolled", negated: false)) # only consider enabled repos in count filters
          end
        end

        if negated
          filter_subquery_rel = filter_subquery_rel.and(or_rels.reduce { |rel, or_rel| rel.and(or_rel) })
        else
          filter_subquery_rel = filter_subquery_rel.and(or_rels.reduce { |rel, or_rel| rel.or(or_rel) })
        end

        rel.where(repository_id: filter_subquery_rel)
      end

      sig do
        params(state: String, negated: T::Boolean)
          .returns([String, T::Hash[Symbol, String]])
      end
      def state_filter(state, negated:)
        operator = "="
        operator = negate_operator(operator) if negated
        [
          "#{SCANNING_STATUS_COLUMN} #{operator} (:state)",
          { state: }
        ]
      end

      sig do
        params(value: String, negated: T::Boolean)
          .returns([String, T::Hash[Symbol, String]])
      end
      def count_filter(value, negated:)
        match = RANGE_EXPRESSION.match(value)
        if match
          operator = match[1] || ""
          operator = negate_operator(operator) if negated
          count = Integer(match[2] || "")
          [
            "#{SCANNING_COUNT_COLUMN} #{operator} :count",
            { count: }
          ]
        else
          count = Integer(value)
          operator = "="
          operator = negate_operator(operator) if negated
          [
            "#{SCANNING_COUNT_COLUMN} #{operator} :value",
            { value: }
          ]
        end
      rescue ArgumentError
        ["false", {}] # Don't return any results for non-numeric values
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
