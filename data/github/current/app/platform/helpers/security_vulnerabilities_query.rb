# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    # This class mainly serves as a misdirection slight-of-hand to allow us to
    # pass the ordering arguments to ActiveRecord without triggering a SQL
    # Injection Vulnerability alert from code scanning. These values are already
    # enforce via GraphQL enums, but we validate them again here to satisfy the
    # scanner.
    class SecurityVulnerabilitiesQuery
      attr_reader :defaults, :order_by_table_name

      # `defaults` should be a hash with the following keys:
      #   - order_by: { table_name:, field:, direction: }
      def initialize(arguments, defaults:)
        @defaults = defaults
        @order_by_field = arguments[:order_by]&.[](:field)
        @order_by_direction = arguments[:order_by]&.[](:direction)
        @order_by_table_name = defaults[:order_by][:table_name]
      end

      def order_by
        { "#{order_by_table_name}.#{order_by_field}" => "#{order_by_direction}" }
      end

      def order_by_field
        order_by_field_valid? ? @order_by_field : defaults[:order_by][:field]
      end

      def order_by_field_valid?
        return false unless @order_by_field.present?

        Platform::Enums::SecurityVulnerabilityOrderField.
          enum_values.map(&:value).
          include?(@order_by_field)
      end

      def order_by_direction
        order_by_direction_valid? ? @order_by_direction : defaults[:order_by][:direction]
      end

      def order_by_direction_valid?
        return false unless @order_by_direction.present?

        Platform::Enums::OrderDirection.
          enum_values.map(&:value).
          include?(@order_by_direction)
      end

      # Applies severity filtering to a scope, treating "unknown" as NULL in the database.
      def self.apply_severity_filter(scope, severities, advisory_table_name)
        return scope if severities.blank?

        known = severities - ["unknown"]
        includes_unknown = severities.include?("unknown")

        if includes_unknown && known.present?
          scope.where("(#{advisory_table_name}.severity IN (?) OR #{advisory_table_name}.severity IS NULL)", known)
        elsif includes_unknown
          scope.where("#{advisory_table_name}.severity IS NULL")
        else
          scope.where("#{advisory_table_name}.severity IN (?)", known)
        end
      end
    end
  end
end
