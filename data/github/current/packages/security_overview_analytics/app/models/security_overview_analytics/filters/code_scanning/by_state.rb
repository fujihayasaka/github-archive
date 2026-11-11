# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Filters
    module CodeScanning
      class ByState
        include Filter

        VALID_STATES = T.let(%w[unresolved dismissed fixed].freeze, T::Array[String])
        DISMISSED_RESOLUTIONS = T.let(CodeScanningAlertRevision::RESOLUTIONS_MAPPING.values.flatten.compact, T::Array[Integer])

        sig { params(incl_filters: T::Array[String], excl_filters: T::Array[String]).void }
        def initialize(incl_filters, excl_filters)
          @incl_filters = T.let(incl_filters.map(&:downcase).uniq, T::Array[String])
          @excl_filters = T.let(excl_filters.map(&:downcase).uniq, T::Array[String])
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
            return rel if valid_filters.empty?
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
          filters.select { |f| VALID_STATES.include?(f) }
        end

        sig do
          params(
            rel: ActiveRecord::Relation,
            values: T::Array[String],
            negated: T::Boolean,
          ).returns(ActiveRecord::Relation)
        end
        def where(rel, values, negated:)
          filter_rels = []
          values.each do |value|
            filter = case value
            when "unresolved"
              { alert_resolved: false }
            when "dismissed"
              "`alert_resolved` = 1 AND `alert_resolution` IS NOT NULL"
            when "fixed"
              { alert_resolved: true, alert_resolution: nil }
            else
              next
            end

            filter_rels << if negated
              rel.where.not(filter)
            else
              rel.where(filter)
            end
          end

          if negated
            rel.and(filter_rels.reduce { |rel, filter_rel| rel.and(filter_rel) })
          else
            rel.and(filter_rels.reduce { |rel, filter_rel| rel.or(filter_rel) })
          end
        end
      end
    end
  end
end
