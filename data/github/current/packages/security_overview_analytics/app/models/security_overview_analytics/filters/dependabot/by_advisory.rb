# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Filters
    module Dependabot
      class ByAdvisory
        include Filter

        sig { returns(T::Array[String]) }
        attr_reader :incl_filters, :excl_filters

        sig { params(incl_filters: T::Array[String], excl_filters: T::Array[String]).void }
        def initialize(incl_filters, excl_filters)
          @incl_filters = incl_filters
          @excl_filters = excl_filters
        end

        sig { override.params(rel: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
        def apply(rel)
          if incl_filters.present?
            rel = rel.where(ghsa_id: incl_filters)
          end

          if excl_filters.present?
            rel = rel.where.not(ghsa_id: excl_filters)
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
