# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class SecurityVulnerabilities < Resolvers::Base
      argument :order_by, Inputs::SecurityVulnerabilityOrder,
                          "Ordering options for the returned topics.",
                          required: false,
                          default_value: { field: "updated_at", direction: "DESC" }

      argument :ecosystem, Enums::SecurityAdvisoryEcosystem,
                           "An ecosystem to filter vulnerabilities by.",
                           required: false

      argument :package, String,
                         "A package name to filter vulnerabilities by.",
                         required: false

      argument :severities, [Enums::SecurityAdvisorySeverity],
                            "A list of severities to filter vulnerabilities by.",
                            required: false

      argument :classifications,
        [Enums::SecurityAdvisoryClassification],
        "A list of advisory classifications to filter vulnerabilities by.",
        required: false

      type Connections.define(Objects::SecurityVulnerability), null: false

      def resolve(**arguments)
        defaults = { order_by: { table_name:, field: "updated_at", direction: "DESC" } }
        helper = Helpers::SecurityVulnerabilitiesQuery.new(arguments, defaults:)
        case object
        when SecurityAdvisory
          return empty_relation unless advisory_within_filter?(object, arguments)

          # We are calling .all in order to get a
          # ActiveRecord_AssociationRelation. If we don't we get a
          # ActiveRecord_Associations_CollectionProxy instead. For some reason I
          # don't totally understand that class gets a
          # Platform::Errors::AssociationRefused when .map is called on it, but
          # the Platform::Errors::AssociationRefused does not. So to workaround
          # that issue, we force the class that works by using .all
          scope = object.vulnerabilities.all

          if arguments[:ecosystem].present?
            scope = scope.where(ecosystem: arguments[:ecosystem])
          end
        else
          scope = filtered_base_scope(arguments)
        end

        if arguments[:package].present?
          scope = scope.where("#{table_name}.affects = ?", arguments[:package])
        end

        scope.order(helper.order_by)
      end

      private

      # Applies filters specific to resolutions against all vulnerability
      # objects
      def filtered_base_scope(arguments)
        return base_scope.general_classification if arguments.empty?

        scope = base_scope

        if arguments[:classifications].present?
          scope = scope.where("#{advisory_table_name}.classification IN (?)", arguments[:classifications])
        else
          scope = scope.general_classification
        end

        if arguments[:ecosystem].present?
          scope = scope.where(ecosystem: arguments[:ecosystem])
        end

        if arguments[:severities].present?
          scope = scope.where("#{advisory_table_name}.severity IN (?)", arguments[:severities])
        end

        scope
      end

      # Several vulnerability properties are delegates on the parent object due
      # to the way we facade our existing data. This means that instead of
      # scoping we need to check if the parent object falls outside the filter.
      def advisory_within_filter?(advisory, arguments)
        advisory.matches_ecosystem?(arguments[:ecosystem]) && advisory.matches_severities?(arguments[:severities])
      end

      def empty_relation
        ::SecurityVulnerability.none
      end

      # We should never be returning security vulnerabilities for a security
      # advisory that is not reviewed and disclosed
      def base_scope
        ::SecurityVulnerability.disclosed_and_reviewed
      end

      def table_name
        ::SecurityVulnerability.table_name
      end

      def advisory_table_name
        ::SecurityAdvisory.table_name
      end
    end
  end
end
