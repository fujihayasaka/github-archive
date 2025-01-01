# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Filters
    class ByResolution
      include Filter

      RESOLUTION_FILTERS = T.let([:fixed_or_revoked, :auto_dismissed, :false_positive, :risk_accepted], T::Array[Symbol])

      sig { params(incl_filters: T::Array[String], excl_filters: T::Array[String]).void }
      def initialize(incl_filters, excl_filters)
        @incl_filters = T.let(incl_filters.uniq.map(&:underscore).map(&:to_sym), T::Array[Symbol])
        @excl_filters = T.let(excl_filters.uniq.map(&:underscore).map(&:to_sym), T::Array[Symbol])
      end

      sig { override.params(rel: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
      def apply(rel)
        # Important context:
        # - Resolved code scanning alert stores `nil` in `alert_resolution` to represent "fixed" state

        if @incl_filters.present?
          valid_filters = select_valid_filters(@incl_filters, rel)
          return rel.none if valid_filters.empty?
          rel = if valid_filters.include?(nil)
            rel.where(alert_resolved: true).then do |rel|
              rel.where(alert_resolution: valid_filters.compact).or(rel.where(alert_resolution: nil))
            end
          else
            rel.where(alert_resolved: true, alert_resolution: valid_filters)
          end
        end

        if @excl_filters.present?
          valid_filters = select_valid_filters(@excl_filters, rel)
          valid_fiters_string = "(#{valid_filters.join(',')})"
          rel = if valid_filters.include?(nil)
            rel
              .where.not(alert_resolution: valid_filters.compact)
              .where.not(alert_resolution: nil)
              .or(rel.where(alert_resolved: false))
          else
            rel
              .where.not(alert_resolution: valid_filters)
              .or(rel.where(alert_resolution: nil))
          end
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

      sig { params(filters: T::Array[Symbol], rel: ActiveRecord::Relation).returns(T::Array[Integer]) }
      def select_valid_filters(filters, rel)
        filters = filters.select { |f| RESOLUTION_FILTERS.include?(f) }

        if rel.klass == DependabotAlertRevision
          DependabotAlertRevision.to_closure_reasons(filters)
        elsif rel.klass == CodeScanningAlertRevision || rel.klass == CodeScanningPullRequestAlert
          CodeScanningAlertRevision.to_closure_reasons(filters)
        elsif rel.klass == SecretScanningAlertRevision
          SecretScanningAlertRevision.to_closure_reasons(filters)
        else
          []
        end
      end
    end
  end
end
