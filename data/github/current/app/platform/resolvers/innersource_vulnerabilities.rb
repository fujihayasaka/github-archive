# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class InnersourceVulnerabilities < Resolvers::Base
      argument :order_by, Inputs::SecurityVulnerabilityOrder,
                          "Ordering options for the returned vulnerabilities.",
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

      type Connections.define(Objects::SecurityVulnerability), null: false

      def resolve(**arguments)
        org = object
        viewer = context[:viewer]

        return ::SecurityVulnerability.none unless viewer
        return ::SecurityVulnerability.none unless can_view_innersource_vulnerabilities?(org, viewer)

        defaults = { order_by: { table_name:, field: "updated_at", direction: "DESC" } }
        helper = Helpers::SecurityVulnerabilitiesQuery.new(arguments, defaults:)

        scope = ::SecurityVulnerability
          .has_public_ecosystem
          .joins(:vulnerability)
          .merge(Vulnerability.innersource_for_org(org.id).not_simulation.has_been_reviewed)

        if arguments[:ecosystem].present?
          scope = scope.where(ecosystem: arguments[:ecosystem])
        end

        if arguments[:package].present?
          scope = scope.where("#{table_name}.affects = ?", arguments[:package])
        end

        if arguments[:severities].present?
          scope = scope.joins(:security_advisory)
          scope = Helpers::SecurityVulnerabilitiesQuery.apply_severity_filter(scope, arguments[:severities], advisory_table_name)
        end

        scope.order(helper.order_by)
      end

      private

      def can_view_innersource_vulnerabilities?(org, viewer)
        is_admin, is_security_manager = Promise.all([
          org.async_adminable_by?(viewer),
          SecurityProduct::Permissions::OrgAuthz.new(org, actor: viewer).async_can_manage_org_security_products?,
        ]).sync

        is_admin || is_security_manager
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
