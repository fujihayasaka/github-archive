# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Filters
    class BySeverity
      extend T::Sig
      include Filter

      VALID_SEVERITIES = T.let(%w[
        critical
        high
        medium
        low
      ].freeze, T::Array[String])

      sig { params(incl_filters: T::Array[String], excl_filters: T::Array[String]).void }
      def initialize(incl_filters, excl_filters)
        @incl_filters = T.let(incl_filters.uniq, T::Array[String])
        @excl_filters = T.let(excl_filters.uniq, T::Array[String])
      end

      sig { override.params(rel: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
      def apply(rel)
        if @incl_filters.present?
          valid_filters = select_valid_filters(@incl_filters, rel)
          return rel.none if valid_filters.empty?
          # For SS, we know that 'critical' is applied by the time we get here, so we fetch everything because
          # all alerts are considered critical.
          rel = rel.where(alert_severity: valid_filters) unless rel.klass == SecretScanningAlertRevision
        end

        if @excl_filters.present?
          valid_filters = select_valid_filters(@excl_filters, rel)
          return rel.where.not(alert_severity: valid_filters) unless rel.klass == SecretScanningAlertRevision
          # For SS, all alerts are considered critical. If we negate critical alerts, then we get nothing.
          # If we negate anything else, then we get everything.
          return valid_filters.include?("critical") ? rel.none : rel
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

      sig { returns(T::Array[String]) }
      def selected_filters
        # Consider all severities if nothing is selected
        return VALID_SEVERITIES if is_empty?
        net_filters = if @incl_filters.present?
          @incl_filters - @excl_filters
        else
          VALID_SEVERITIES - @excl_filters
        end
        net_filters.select { |f| VALID_SEVERITIES.include?(f) }
      end

      private

      sig { params(filters: T::Array[String], rel: ActiveRecord::Relation).returns(T::Array[String]) }
      def select_valid_filters(filters, rel)
        filters = filters.select { |f| VALID_SEVERITIES.include?(f) }

        # Dbot and SS need further validation because their severity mappings aren't 1:1 with the defaults.
        if rel.klass == DependabotAlertRevision
          filters = DependabotAlertRevision.to_valid_severities(filters)
        elsif rel.klass == SecretScanningAlertRevision
          filters = SecretScanningAlertRevision.to_valid_severities(filters)
        end

        filters
      end
    end
  end
end
