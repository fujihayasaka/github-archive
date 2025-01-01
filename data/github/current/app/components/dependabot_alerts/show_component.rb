# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class ShowComponent < ApplicationComponent
    private

    include BotHelper
    include VulnerabilityHelper

    def initialize(alert:)
      @alert = alert
    end

    attr_reader :alert

    delegate \
      :repository,
      :vulnerability,
      :vulnerable_version_range,
      to: :alert

    delegate \
      :auto_dismissed?,
      :dismiss_reason,
      :dismissed_at,
      :dismissed?,
      :dismisser,
      :fix_reason,
      :fixed_at,
      :fixed?,
      :last_state_change_at,
      :number,
      :title,
      to: :alert, prefix: true

    delegate \
      :malware?,
      :cve_id,
      :ghsa_id,
      to: :vulnerability

    def render?
      alert.active? && vulnerable_version_range.present?
    end

    def alert_severity
      alert.severity&.humanize
    end

    def alert_opened_at
      alert.created_at
    end

    def show_dismiss_metadata?
      alert_dismissed? && (alert_dismisser || alert_dismissed_at)
    end

    def show_auto_dismiss_metadata?
      alert_auto_dismissed? && alert_last_state_change_at
    end

    def show_fixed_metadata?
      alert_fixed? && alert_fixed_at
    end

    def show_dismiss_button?
      alert.open? && viewer_can_manage_alerts?
    end

    def show_reopen_button?
      alert.reopenable? && viewer_can_manage_alerts?
    end

    memoize def related_fixable_alerts
      alert.
        related_fixable_alerts.
        limit(5).
        where.not(id: alert.id).
        joins(:vulnerability).
        order(Arel.sql(Vulnerability::SEVERITY_RSORT_STR))
    end

    memoize def viewer_can_manage_alerts?
      repository.can_resolve_vulnerability_alerts?(current_user)
    end

    def show_direct_dependency?
      return false unless repository.feature_enabled?(DependencyGraph::VulnerableDependencyProvider::DGP_NPM_FEATURE_FLAG)

      alert.dependency_relationship == "direct"
    end

    def show_vulnerable_function_references?
      # VEA is not supported on GitHub Enterprise Server
      !GitHub.enterprise? &&
      repository.vea_on_public_repo_or_advanced_security_enabled? &&
      vulnerable_function_references.present? && show_references_for_ecosystem?
    end

    # Returns true if ecosystem references are from is public
    # or if the ecosystem is in preview and user has access to see preview data
    def show_references_for_ecosystem?
      vulnerable_function_references.first.public_ecosystem? ||
        (GitHub.flipper[:user_can_see_vea_preview_data].enabled?(current_user) &&
          vulnerable_function_references.first.preview_ecosystem?)
    end

    memoize def vulnerable_function_references
      alert.current_vulnerable_function_references
    end

    def reopen_path
      reopen_repository_alert_path(
        number: alert.number,
        user_id: repository.owner,
        repository: repository
      )
    end

    def package_name
      vulnerable_version_range.affects
    end

    def ecosystem
      vulnerable_version_range.ecosystem && ::AdvisoryDB::Ecosystems.label(vulnerable_version_range.ecosystem)
    end

    def affected_versions
      vulnerable_version_range.requirements.presence
    end

    def patched_version
      vulnerable_version_range.fixed_in.presence
    end

    def vulnerability_markdown
      helpers.vulnerability_markdown(vulnerability)
    end

    memoize def cwes
      vulnerability.cwes.to_a
    end

    def cvss_v3_vector
      vulnerability.cvss_v3
    end

    def cvss_v4_vector
      vulnerability.cvss_v4
    end

    def manifest_path
      alert.vulnerable_manifest_path
    end

    def manifest_blob_path
      default_branch_blob_path(
        user_id: repository.owner,
        repository: repository,
        path: manifest_path,
      )
    end

    def dismissal_path
      dismiss_repository_alert_path(
        user_id: repository.owner,
        repository: repository,
        number: alert.number,
      )
    end

    def contribute_url(ghsa_id)
      host = GitHub.single_or_multi_tenant_enterprise? ? "#{GitHub.dotcom_host_protocol}://#{GitHub.dotcom_host_name}" : ""

      host + new_global_advisory_improvement_path(vulnerability.ghsa_id)
    end

    def contribute_analytic_attributes
      analytics_click_attributes(category: "Dependabot", action: "contribute_advisory", label: "ref_loc:alert")
    end

    def build_filtered_query(qualifier, value)
      Search::Queries::SecurityCenter::DependabotAlertsQuery.add_or_replace("is:open", qualifier, value)
    end

    memoize def alert_dependency_scope_tag
      return nil unless alert.dependency_scope.present?

      query = build_filtered_query("scope", alert.dependency_scope)
      href = repository_alerts_path(q: query)

      case alert.dependency_scope
      when "development"
        { title: "Development dependency", href: }
      when "runtime"
        { title: "Runtime dependency", href: }
      else # Default to nil when scope doesn't match dev/runtime.
        nil
      end
    end

    def vulnerable_calls_tag
      return nil unless show_vulnerable_function_references?

      {
        title: "Vulnerable calls",
        href: repository_alerts_path(q: build_filtered_query("has", "vulnerable-calls"))
      }
    end

    def patch_available_tag
      return nil unless patched_version

      {
        title: "Patch available",
        href: repository_alerts_path(q: build_filtered_query("has", "patch"))
      }
    end

    def direct_dependency_tag
      return nil unless show_direct_dependency?
      {
        title: "Direct",
        href: repository_alerts_path(q: build_filtered_query("relationship", "direct"))
      }
    end

    def sidebar_tags
      tags = []

      tags << alert_dependency_scope_tag
      tags << vulnerable_calls_tag
      tags << patch_available_tag
      tags << direct_dependency_tag

      tags.compact
    end

    def related_alert_link_attributes(alert)
      {
        href: repository_alert_path(number: alert.number),
        scheme: :secondary,
        underline: false,
        test_selector: "related-alert-link",
        classes: "Truncate-text",
        data: hovercard_data_attributes_for_dependabot_alert(repository.owner_display_login, repository.name, alert.number)
      }
    end
  end
end
