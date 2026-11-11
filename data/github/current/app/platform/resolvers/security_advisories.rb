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

      argument :epss_percentage, Float,
               "The EPSS percentage to filter advisories by.",
               required: false

      argument :epss_percentile, Float,
               "The EPSS percentile to filter advisories by.",
               required: false

      type Connections.define(Objects::SecurityAdvisory), null: false

      def resolve(identifier: nil, published_since: nil, updated_since: nil, **arguments)
        order_by = arguments[:order_by] || { field: "updated_at", direction: "DESC" }
        scope = ::SecurityAdvisory.disclosed.has_been_reviewed

        if ::CVEEPSS::EPSS_FIELDS.key?(order_by[:field])
          scope = scope.joins(:cve_epss)
          order_field = "cve_epss.#{::CVEEPSS::EPSS_FIELDS[order_by[:field]]}"
        else
          order_field = order_by[:field]
        end
        scope = scope.order(order_field.to_sym => order_by[:direction].to_sym)

        scope = filter_by_classification(scope, arguments[:classifications])
        scope = filter_by_percentage(scope, arguments[:epss_percentage])
        scope = filter_by_percentile(scope, arguments[:epss_percentile])
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

      def filter_by_percentage(scope, percentage)
        if percentage
          scope = scope.joins(:cve_epss).where(cve_epss: { percentage: percentage })
        end
        scope
      end

      def filter_by_percentile(scope, percentile)
        if percentile
          scope = scope.joins(:cve_epss).where(cve_epss: { percentile: percentile })
        end
        scope
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
