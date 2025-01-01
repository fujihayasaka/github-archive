# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Filters
    module SecretScanning
      class ByTokenTypeSlug
        include Filter

        sig { returns(T::Array[String]) }
        attr_reader :incl_filters, :excl_filters

        sig { params(incl_filters: T::Array[String], excl_filters: T::Array[String]).void }
        def initialize(incl_filters, excl_filters)
          @incl_filters = T.let(incl_filters.uniq, T::Array[String])
          @excl_filters = T.let(excl_filters.uniq, T::Array[String])
        end

        sig { override.params(rel: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
        def apply(rel)
          if incl_filters.present?
            rel = rel.where(alert_type_slug: incl_filters)
          end

          if excl_filters.present?
            return rel.where.not(alert_type_slug: excl_filters)
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
