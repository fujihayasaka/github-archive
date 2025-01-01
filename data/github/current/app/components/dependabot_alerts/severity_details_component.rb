# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class SeverityDetailsComponent < SeverityDetailsBaseComponent

    METRIC_DEFINITIONS = {
      attack_vector: "More severe the more the remote (logically and physically) an attacker can be in order to exploit the vulnerability",
      attack_complexity: "More severe for the least complex attacks",
      privileges_required: "More severe if no privileges are required",
      user_interaction: "More severe when no user interaction is required",
      scope: "More severe when a scope change occurs, e.g. one vulnerable component impacts resources in components beyond its security scope",
      confidentiality: "More severe when loss of data confidentiality is highest, measuring the level of data access available to an unauthorized user",
      integrity: "More severe when loss of data integrity is the highest, measuring the consequence of data modification possible by an unauthorized user",
      availability: "More severe when the loss of impacted component availability is highest",
    }.freeze

    TITLE = "CVSS v3 base metrics".freeze

    def base_metrics
      METRIC_DEFINITIONS.keys
    end

    def title
      TITLE
    end

    def label_for_metric(metric)
      metric.to_s.humanize
    end

    def definition_for_metric(metric)
      METRIC_DEFINITIONS[metric]
    end
  end
end
