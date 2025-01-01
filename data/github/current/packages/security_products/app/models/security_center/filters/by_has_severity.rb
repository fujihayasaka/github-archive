# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Filters
    class ByHasSeverity

      VALID_SEVERITIES = T.let(%w[
        critical
        high
        medium
        moderate
        low
        informational
      ].freeze, T::Array[String])

      INFORMATIONAL_SEVERITIES = T.let(%w[error warning note].freeze, T::Array[String])

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

      sig { params(rel: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
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

      sig { returns(T::Boolean) }
      def is_empty?
        @incl_filters.blank? && @excl_filters.blank?
      end

      private

      sig { params(filters: T::Array[String]).returns(T::Array[String]) }
      def select_valid_filters(filters)
        filters
          .select { |f| VALID_SEVERITIES.include?(f) }
          .flat_map { |f| f == "informational" ? INFORMATIONAL_SEVERITIES : f }
          .map &:to_s
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
          SecurityCenterAlertSeverity
            .where("#{SecurityCenterAlertSeverity.table_name}.repository_id = #{RepositorySecurityCenterConfig.table_name}.repository_id")
            .where(
              severity: values,
              alert_count: 1..,
            )
            .select(:repository_id)

        if negated
          rel.where.not(repository_id: filter_subquery_rel)
        else
          rel.where(repository_id: filter_subquery_rel)
        end
      end
    end
  end
end
