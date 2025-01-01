# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Filters
    module SecretScanning
      class ByBypassed
        extend T::Sig
        include Filter

        sig { returns(T::Array[Symbol]) }
        attr_reader :incl_filters, :excl_filters

        sig { params(incl_filters: T::Array[String], excl_filters: T::Array[String]).void }
        def initialize(incl_filters, excl_filters)
          @incl_filters = T.let(incl_filters.uniq.map(&:to_sym), T::Array[Symbol])
          @excl_filters = T.let(excl_filters.uniq.map(&:to_sym), T::Array[Symbol])
        end

        sig { override.params(rel: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
        def apply(rel)
          if incl_filters.present?
            valid_filters = select_valid_filters(incl_filters)
            return rel.none if valid_filters.empty?
            rel = rel.where(alert_bypassed: valid_filters)
          end

          if excl_filters.present?
            valid_filters = select_valid_filters(excl_filters)
            return rel if valid_filters.empty?
            rel = rel.where.not(alert_bypassed: valid_filters)
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

        private

        sig { params(filters: T::Array[Symbol]).returns(T::Array[Symbol]) }
        def select_valid_filters(filters)
          filters.select { |f| [:true, :false].include?(f) }
        end
      end
    end
  end
end
