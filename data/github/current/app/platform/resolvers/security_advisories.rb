# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class SecurityAdvisories < Resolvers::Base
      argument :order_by, Inputs::SecurityAdvisoryOrder,
               "Ordering options for the returned topics.",
               required: false,
               default_value: { field: "updated_at", direction: "DESC" }

      argument :identifier, Inputs::SecurityAdvisoryIdentifierFilter,
               "Filter advisories by identifier, e.g. GHSA or CVE.",
               required: false

      argument :published_since, Scalars::DateTime,
               "Filter advisories to those published since a time in the past.",
               required: false

      argument :updated_since, Scalars::DateTime,
               "Filter advisories to those updated since a time in the past.",
               required: false

      argument :classifications, [Enums::SecurityAdvisoryClassification],
               "A list of classifications to filter advisories by.",
               required: false

      type Connections.define(Objects::SecurityAdvisory), null: false

      def resolve(identifier: nil, published_since: nil, updated_since: nil, **arguments)
        order_by = arguments[:order_by] || { field: "updated_at", direction: "DESC" }
        scope = ::SecurityAdvisory.disclosed
                                  .has_been_reviewed
                                  .order(order_by[:field].to_sym => order_by[:direction].to_sym)

        scope = filter_by_classification(scope, arguments[:classifications])
        scope = filter_by_identifier(scope, identifier) if identifier.present?
        scope = scope.where("#{table_name}.published_at > ?", published_since) if published_since.present?
        scope = scope.where("#{table_name}.updated_at > ?", updated_since) if updated_since.present?

        scope
      end

      private

      def filter_by_identifier(scope, identifier)
        case identifier[:type]
        when "CVE"
          scope.with_substring("#{table_name}.cve_id", identifier[:value])
        when "GHSA"
          scope.with_substring("#{table_name}.ghsa_id", identifier[:value])
        else
          scope
        end
      end

      def filter_by_classification(scope, classifications)
        if classifications
          scope = scope.where(classification: classifications)
        else
          scope = scope.general_classification
        end
      end

      def table_name
        ::SecurityAdvisory.table_name
      end
    end
  end
end
