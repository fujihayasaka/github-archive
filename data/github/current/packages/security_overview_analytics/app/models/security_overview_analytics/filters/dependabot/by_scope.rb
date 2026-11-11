# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Filters
    module Dependabot
      class ByScope
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
            valid_filters = select_valid_filters(incl_filters)
            return rel.none if valid_filters.empty?
            rel = rel.where(dependency_scope: valid_filters)
          end

          if excl_filters.present?
            valid_filters = select_valid_filters(excl_filters)
            return rel if valid_filters.size < excl_filters.size
            rel = rel.where.not(dependency_scope: excl_filters)
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

        sig { params(filters: T::Array[String]).returns(T::Array[String]) }
        def select_valid_filters(filters)
          ::RepositoryVulnerabilityAlert.dependency_scopes.keys.map(&:to_s) & filters
        end
      end
    end
  end
end
