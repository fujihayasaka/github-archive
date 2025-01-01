# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Filters
    module CodeScanning
      class ByRule
        extend T::Sig
        include Filter

        sig { returns(T::Array[String]) }
        attr_reader :incl_filters, :excl_filters

        sig { returns(T::Boolean) }
        attr_reader :codeql_rule

        sig { params(incl_filters: T::Array[String], excl_filters: T::Array[String], codeql_rule: T::Boolean).void }
        def initialize(incl_filters, excl_filters, codeql_rule: true)
          @incl_filters = T.let(incl_filters.uniq, T::Array[String])
          @excl_filters = T.let(excl_filters.uniq, T::Array[String])
          @codeql_rule = T.let(codeql_rule, T::Boolean)
        end

        sig { override.params(rel: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
        def apply(rel)
          return rel if is_empty?

          rel = if codeql_rule
            rel.where(tool: "CodeQL")
          else
            rel.where.not(tool: "CodeQL")
          end

          if incl_filters.present?
            rel = rel.where(rule_sarif_identifier: incl_filters)
          end

          if excl_filters.present?
            rel = rel.where.not(rule_sarif_identifier: excl_filters)
          end

          rel
        end

        sig { override.returns(T::Boolean) }
        def is_empty?
          incl_filters.blank? && excl_filters.blank?
        end

        sig { override.returns(T::Boolean) }
        def has_incl_filters?
          incl_filters.present?
        end
      end
    end
  end
end
