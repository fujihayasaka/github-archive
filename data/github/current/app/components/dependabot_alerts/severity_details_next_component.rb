# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class SeverityDetailsNextComponent < SeverityDetailsBaseComponent

    METRIC_DEFINITIONS = {
      attack_vector: {
        label: "Attack Vector",
        definition: "This metric reflects the context by which vulnerability exploitation is possible. This metric value (and consequently the resulting severity) will be larger the more remote (logically, and physically) an attacker can be in order to exploit the vulnerable system. The assumption is that the number of potential attackers for a vulnerability that could be exploited from across a network is larger than the number of potential attackers that could exploit a vulnerability requiring physical access to a device, and therefore warrants a greater severity."
      },
      attack_complexity: {
        label: "Attack Complexity",
        definition: "This metric captures measurable actions that must be taken by the attacker to actively evade or circumvent existing built-in security-enhancing conditions in order to obtain a working exploit. These are conditions whose primary purpose is to increase security and/or increase exploit engineering complexity. A vulnerability exploitable without a target-specific variable has a lower complexity than a vulnerability that would require non-trivial customization. This metric is meant to capture security mechanisms utilized by the vulnerable system."
      },
      attack_requirements: {
        label: "Attack Requirements",
        definition: "This metric captures the prerequisite deployment and execution conditions or variables of the vulnerable system that enable the attack. These differ from security-enhancing techniques/technologies (ref Attack Complexity) as the primary purpose of these conditions is not to explicitly mitigate attacks, but rather, emerge naturally as a consequence of the deployment and execution of the vulnerable system."
      },
      privileges_required: {
        label: "Privileges Required",
        definition: "This metric describes the level of privileges an attacker must possess prior to successfully exploiting the vulnerability. The method by which the attacker obtains privileged credentials prior to the attack (e.g., free trial accounts), is outside the scope of this metric. Generally, self-service provisioned accounts do not constitute a privilege requirement if the attacker can grant themselves privileges as part of the attack."
      },
      user_interaction: {
        definition: "This metric captures the requirement for a human user, other than the attacker, to participate in the successful compromise of the vulnerable system. This metric determines whether the vulnerability can be exploited solely at the will of the attacker, or whether a separate user (or user-initiated process) must participate in some manner."
      },
      vulnerable_system_confidentiality: {
        label: "Confidentiality",
        definition: "This metric measures the impact to the confidentiality of the information managed by the VULNERABLE SYSTEM due to a successfully exploited vulnerability. Confidentiality refers to limiting information access and disclosure to only authorized users, as well as preventing access by, or disclosure to, unauthorized ones."
      },
      vulnerable_system_integrity: {
        label: "Integrity",
        definition: "This metric measures the impact to integrity of a successfully exploited vulnerability. Integrity refers to the trustworthiness and veracity of information. Integrity of the VULNERABLE SYSTEM is impacted when an attacker makes unauthorized modification of system data. Integrity is also impacted when a system user can repudiate critical actions taken in the context of the system (e.g. due to insufficient logging)."
      },
      vulnerable_system_availability: {
        label: "Availability",
        definition: "This metric measures the impact to the availability of the VULNERABLE SYSTEM resulting from a successfully exploited vulnerability. While the Confidentiality and Integrity impact metrics apply to the loss of confidentiality or integrity of data (e.g., information, files) used by the system, this metric refers to the loss of availability of the impacted system itself, such as a networked service (e.g., web, database, email). Since availability refers to the accessibility of information resources, attacks that consume network bandwidth, processor cycles, or disk space all impact the availability of a system."
      },
      subsequent_system_confidentiality: {
        label: "Confidentiality",
        definition: "This metric measures the impact to the confidentiality of the information managed by the SUBSEQUENT SYSTEM due to a successfully exploited vulnerability. Confidentiality refers to limiting information access and disclosure to only authorized users, as well as preventing access by, or disclosure to, unauthorized ones."
      },
      subsequent_system_integrity: {
        label: "Integrity",
        definition: "This metric measures the impact to integrity of a successfully exploited vulnerability. Integrity refers to the trustworthiness and veracity of information. Integrity of the SUBSEQUENT SYSTEM is impacted when an attacker makes unauthorized modification of system data. Integrity is also impacted when a system user can repudiate critical actions taken in the context of the system (e.g. due to insufficient logging)."
      },
      subsequent_system_availability: {
        label: "Availability",
        definition: "This metric measures the impact to the availability of the SUBSEQUENT SYSTEM resulting from a successfully exploited vulnerability. While the Confidentiality and Integrity impact metrics apply to the loss of confidentiality or integrity of data (e.g., information, files) used by the system, this metric refers to the loss of availability of the impacted system itself, such as a networked service (e.g., web, database, email). Since availability refers to the accessibility of information resources, attacks that consume network bandwidth, processor cycles, or disk space all impact the availability of a system."
      }
    }.freeze

    SECTION_DEFINITIONS = {
      vulnerable_system: "Vulnerable System Impact",
      subsequent_system: "Subsequent System Impact",
    }.freeze

    METRIC_SECTIONS = {
      exploitability: %i[attack_vector attack_complexity attack_requirements privileges_required user_interaction],
      vulnerable_system: %i[vulnerable_system_confidentiality vulnerable_system_integrity vulnerable_system_availability],
      subsequent_system: %i[subsequent_system_confidentiality subsequent_system_integrity subsequent_system_availability],
    }

    def metric_sections
      METRIC_SECTIONS
    end

    def base_metrics
      METRIC_DEFINITIONS.keys
    end

    def label_for_metric(metric)
      METRIC_DEFINITIONS[metric][:label] || metric.to_s.humanize
    end

    def definition_for_metric(metric)
      METRIC_DEFINITIONS[metric][:definition]
    end

    def definition_for_section(section)
      SECTION_DEFINITIONS[section]
    end
  end
end
