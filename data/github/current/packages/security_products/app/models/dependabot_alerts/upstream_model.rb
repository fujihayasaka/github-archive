# typed: true
# frozen_string_literal: true

module DependabotAlerts::UpstreamModel
  extend ActiveSupport::Concern

  VULNERABILITY_CHANGE_TRIGGERS = %w(
    cwe_ids
    severity
    epss
  ).freeze

  VULNERABLE_VERSION_RANGE_CHANGE_TRIGGERS = %w(
    fixed_in
  ).freeze

  sig { params(event: Symbol, changes: T::Array[String]).returns(T::Boolean) }
  def instrument_dependabot_alerts_upstream_change(event:, changes:)
    triggered_instrumentation = false

    case self
    when Vulnerability, ScopedVulnerability
      if changes.any? { |i| VULNERABILITY_CHANGE_TRIGGERS.include?(i) }
        vulnerable_version_ranges.each do |vulnerable_version_range|
          RefreshDependabotAlertsStateJob.perform_later(vulnerable_version_range_id: vulnerable_version_range.id, changes: changes) # default repo rules job
          RefreshDependabotAlertsStateJob.perform_later(vulnerable_version_range_id: vulnerable_version_range.id, changes: changes, org_rules: true)
        end
        triggered_instrumentation = true
      end
    when VulnerableVersionRange
      if changes.any? { |i| VULNERABLE_VERSION_RANGE_CHANGE_TRIGGERS.include?(i) }
        RefreshDependabotAlertsStateJob.perform_later(vulnerable_version_range_id: self.id) # default repo rules job
        RefreshDependabotAlertsStateJob.perform_later(vulnerable_version_range_id: self.id, org_rules: true)
        triggered_instrumentation = true
      end
    end

    triggered_instrumentation
  end
end
