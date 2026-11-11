# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class ShowComponent < ApplicationComponent
    private

    include BotHelper
    include VulnerabilityHelper
    include DependabotAlerts::AlertsSerializer

    def initialize(alert:, runtime_risks: nil)
      @alert = alert
      @runtime_risks = runtime_risks
    end

    attr_reader :alert, :runtime_risks

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
      to: :alert, prefix: true

    def alert_title
      malware? ? "Malware in #{alert.title}#{innersource_suffix}" : "#{alert.title}#{innersource_suffix}"
    end

    delegate \
      :malware?,
      :innersource?,
      :cve_id,
      :ghsa_id,
      to: :vulnerability

    def render?
      alert.active? && vulnerable_version_range.present?
    end

    def ghas_available?
      Dependabot.ghas_available?(repository.owner)
    end

    memoize def assignees
      alert.assignees.includes(:profile).map { |user| serialized_assignee(user) }
    end

    memoize def current_user_assignee
      serialized_assignee(current_user)
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

    def dismisser_type(actor)
      return nil unless actor

      if actor.is_a?(Bot) || actor.is_a?(PlatformTypes::Bot)
        return "AI" if actor_is_ai?(actor)
        return "bot"
      elsif actor.is_a?(Mannequin) || actor.is_a?(PlatformTypes::Mannequin)
        return "mannequin"
      end

      nil
    end

    def show_dismiss_button?
      return false unless alert.open? && viewer_can_manage_alerts?

      if delegated_closures_enabled?
        return delegated_dismissal.show_request_button?
      end

      true
    end

    def show_reopen_button?
      alert.reopenable? && viewer_can_manage_alerts?
    end

    def user_can_directly_dismiss?
      if delegated_closures_enabled?
        return false unless current_user
        return delegated_dismissal.user_can_bypass_requests?(current_user)
      end

      viewer_can_manage_alerts?
    end

    def show_cancel_dismissal_request_button?
      return false unless delegated_closures_enabled?
      return false unless existing_dismissal_request && !dismissal_request_is_closed?
      can_cancel_dismissal_request?
    end

    def show_request_pending_button?
      return false if alert.dismissed? || alert.fixed?

      # Only show if there's an open request that the user cannot cancel and cannot review
      delegated_closures_enabled? &&
        existing_dismissal_request && !dismissal_request_is_closed? &&
        !can_cancel_dismissal_request? &&
        !can_review_dismissal_request?
    end

    def dismissal_request_is_closed?
      return true unless existing_dismissal_request

      status = existing_dismissal_request.status
      %w[cancelled approved rejected expired completed].include?(status.to_s)
    end


    memoize def delegated_closures_enabled?
      delegated_dismissal.enabled?
    end

    memoize def existing_dismissal_request
      Exemptions::ExemptionRequest.find_by(
        repository: repository,
        request_type: Dependabot::SecurityProduct::DelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE,
        resource_identifier: alert.number.to_s,
        status: "pending"
      )
    end

    memoize def can_cancel_dismissal_request?
      delegated_dismissal.can_cancel_request?(existing_dismissal_request)
    end

    memoize def can_review_dismissal_request?
      return false unless current_user
      delegated_dismissal.user_can_review_closure_requests?(current_user)
    end

    memoize def delegated_dismissal
      Dependabot::SecurityProduct::DelegatedClosures.new(alert.repository, current_user, resource_identifier: alert.number.to_s)
    end

    memoize def related_fixable_alerts
      alert.
        related_fixable_alerts.
        limit(5).
        where.not(id: alert.id).
        joins(:vulnerability).
        merge(Vulnerability.open_source).
        order(Arel.sql(Vulnerability::SEVERITY_RSORT_STR))
    end

    memoize def viewer_can_manage_alerts?
      repository.can_resolve_vulnerability_alerts?(current_user)
    end

    def show_direct_dependency?
      return false unless DependencyGraph::VulnerabilityScanning.relationship_information_available?
      alert.dependency_relationship == "direct"
    end

    def reopen_path
      repository_alerts_reopen_path(
        user_id: repository.owner,
        repository: repository,
        ids: [alert.id],
        redirect_to_alert_number: alert.number,
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

    def show_epss_score?
      alert.open_source_vulnerability&.cve_epss&.present?
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

    memoize def malware_frontend_enabled?
      FeatureFlag.vexi.enabled?(:dependabot_allow_malware_frontend, repository, repository.owner, current_user, default: false)
    end

    def malware_alert?
      malware? && malware_frontend_enabled?
    end

    def back_button_label
      malware_alert? ? "Malware alerts" : "Dependabot alerts"
    end

    def back_button_path
      malware_alert? ? repository_malware_alerts_path : repository_alerts_path
    end

    def dismissal_path
      repository_alerts_dismiss_path(
        user_id: repository.owner,
        repository: repository,
        ids: [alert.id],
        redirect_to_alert_number: alert.number,
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

    # TODO: Once innersource vulns are searchable, add an href to the tag with the appropriate query
    def innersource_tag
      return nil unless innersource?

      {
        title: "Innersource Advisory",
      }
    end

    def sidebar_tags
      tags = []

      tags << alert_dependency_scope_tag
      tags << patch_available_tag
      tags << direct_dependency_tag
      tags << innersource_tag

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

    def innersource_suffix
      return "" unless innersource?

      vulnerability.owner_business_id.present? ? " (Enterprise Advisory)" : " (Organization Advisory)"
    end
  end
end
