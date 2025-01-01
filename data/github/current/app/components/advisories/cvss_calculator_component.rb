# typed: true
# frozen_string_literal: true

module Advisories
  class CvssCalculatorComponent < ApplicationComponent
    METRICS = [
      { base:
        [
          { exploitability:
            [
              {
                name: "Attack Vector (AV)",
                code: "AV",
                choices: [
                  {
                    name: "Network (N)",
                    code: "N",
                    description: <<~DESCRIPTION
                    The vulnerable system is bound to the network stack and the set of possible attackers extends
                    beyond the other options listed below, up to and including the entire Internet. Such a
                    vulnerability is often termed “remotely exploitable” and can be thought of as an attack being
                    exploitable at the protocol level one or more network hops away (e.g., across one or more routers).
                      DESCRIPTION
                  },
                  {
                    name: "Adjacent (A)",
                    code: "A",
                    description: <<~DESCRIPTION
                    The vulnerable system is bound to a protocol stack, but the attack is limited at the protocol
                    level to a logically adjacent topology. This can mean an attack must be launched from the same
                    shared proximity (e.g., Bluetooth, NFC, or IEEE 802.11) or logical network (e.g., local IP subnet),
                    or from within a secure or otherwise limited administrative domain (e.g., MPLS, secure VPN within
                      an administrative network zone).
                      DESCRIPTION
                  },
                  {
                    name: "Local (L)",
                    code: "L",
                    description: <<~DESCRIPTION
                    The vulnerable system is not bound to the network stack and the attacker's path is via read/write/execute
                    capabilities. Either the attacker exploits the vulnerability by accessing the target system locally
                    (e.g., keyboard, console), or through terminal emulation (e.g., SSH); or the attacker relies on
                    User Interaction by another person to perform actions required to exploit the vulnerability
                    (e.g., using social engineering techniques to trick a legitimate user into opening a malicious document).
                      DESCRIPTION
                  },
                  {
                    name: "Physical (P)",
                    code: "P",
                    description: <<~DESCRIPTION
                    The attack requires the attacker to physically touch or manipulate the vulnerable system. Physical
                     interaction may be brief (e.g., evil maid attack) or persistent.
                      DESCRIPTION
                  },
                ],
                default_choice_code: "N",
                description: <<~DESCRIPTION
                  This metric reflects the context by which vulnerability exploitation is possible. This metric value
                  (and consequently the resulting severity) will be larger the more remote (logically, and physically)
                   an attacker can be in order to exploit the vulnerable system. The assumption is that the number of
                   potential attackers for a vulnerability that could be exploited from across a network is larger
                   than the number of potential attackers that could exploit a vulnerability requiring physical access
                    to a device, and therefore warrants a greater severity.
                  DESCRIPTION
              },
              {
                name: "Attack Complexity (AC)",
                code: "AC",
                choices: [
                  {
                    name: "Low (L)",
                    code: "L",
                    description: <<~DESCRIPTION
                      The attacker must take no measurable action to exploit the vulnerability. The attack requires no
                       target-specific circumvention to exploit the vulnerability. An attacker can expect repeatable
                       success against the vulnerable system."
                      DESCRIPTION
                  },
                  {
                    name: "High (H)",
                    code: "H",
                    description: <<~DESCRIPTION
                      The successful attack depends on the evasion or circumvention of security-enhancing techniques
                      in place that would otherwise hinder the attack. These include: Evasion of exploit mitigation
                      techniques, for example, circumvention of address space randomization (ASLR) or data execution
                      prevention (DEP) must be performed for the attack to be successful; Obtaining target-specific
                      secrets. The attacker must gather some target-specific secret before the attack can be
                      successful. A secret is any piece of information that cannot be obtained through any amount of
                      reconnaissance. To obtain the secret the attacker must perform additional attacks or break
                      otherwise secure measures (e.g. knowledge of a secret key may be needed to break a crypto
                        channel). This operation must be performed for each attacked target.
                      DESCRIPTION
                  },
                ],
                default_choice_code: "L",
                description: <<~DESCRIPTION
                  This metric captures measurable actions that must be taken by the attacker to actively evade or
                  circumvent existing built-in security-enhancing conditions in order to obtain a working exploit.
                  These are conditions whose primary purpose is to increase security and/or increase exploit
                  engineering complexity. A vulnerability exploitable without a target-specific variable has a lower
                  complexity than a vulnerability that would require non-trivial customization. This metric is meant
                  to capture security mechanisms utilized by the vulnerable system.
                  DESCRIPTION
              },
              {
                name: "Attack Requirements (AT)",
                code: "AT",
                choices: [
                  {
                    name: "None (N)",
                    code: "N",
                    description: <<~DESCRIPTION
                      The successful attack does not depend on the deployment and execution conditions of the
                      vulnerable system. The attacker can expect to be able to reach the vulnerability and execute the
                      exploit under all or most instances of the vulnerability.
                      DESCRIPTION
                  },
                  {
                    name: "Present (P)",
                    code: "P",
                    description: <<~DESCRIPTION
                      The successful attack depends on the presence of specific deployment and execution conditions of
                       the vulnerable system that enable the attack. These include: a race condition must be won to
                       successfully exploit the vulnerability (the successfulness of the attack is conditioned on
                        execution conditions that are not under full control of the attacker, or the attack may need to
                        be launched multiple times against a single target before being successful); the attacker must
                        inject themselves into the logical network path between the target and the resource requested
                        by the victim (e.g. vulnerabilities requiring an on-path attacker).
                      DESCRIPTION
                  },
                ],
                default_choice_code: "N",
                description: <<~DESCRIPTION
                  This metric captures the prerequisite deployment and execution conditions or variables of the
                  vulnerable system that enable the attack. These differ from security-enhancing techniques/technologies
                  (ref Attack Complexity) as the primary purpose of these conditions is not to explicitly mitigate
                  attacks, but rather, emerge naturally as a consequence of the deployment and execution of the
                  vulnerable system.
                  DESCRIPTION
              },
              {
                name: "Privileges Required (PR)",
                code: "PR",
                choices: [
                  {
                    name: "None (N)",
                    code: "N",
                    description: <<~DESCRIPTION
                      The attacker is unauthorized prior to attack, and therefore does not require any access to
                      settings or files of the vulnerable system to carry out an attack.
                      DESCRIPTION
                  },
                  {
                    name: "Low (L)",
                    code: "L",
                    description: <<~DESCRIPTION
                      The attacker requires privileges that provide basic capabilities that are typically limited to
                      settings and resources owned by a single low-privileged user. Alternatively, an attacker with
                      Low privileges has the ability to access only non-sensitive resources.
                      DESCRIPTION
                  },
                  {
                    name: "High (H)",
                    code: "H",
                    description: <<~DESCRIPTION
                      The attacker requires privileges that provide significant (e.g., administrative) control over the
                      vulnerable system allowing full access to the vulnerable system's settings and files.
                      DESCRIPTION
                  },
                ],
                default_choice_code: "N",
                description: <<~DESCRIPTION
                  This metric describes the level of privileges an attacker must possess prior to successfully exploiting
                  the vulnerability. The method by which the attacker obtains privileged credentials prior to the attack
                  (e.g., free trial accounts), is outside the scope of this metric. Generally, self-service provisioned
                  accounts do not constitute a privilege requirement if the attacker can grant themselves privileges as
                    part of the attack.
                  DESCRIPTION
              },
              {
                name: "User Interaction (UI)",
                code: "UI",
                choices: [
                  {
                    name: "None (N)",
                    code: "N",
                    description: <<~DESCRIPTION
                      The vulnerable system can be exploited without interaction from any human user, other than the attacker.
                      DESCRIPTION
                  },
                  {
                    name: "Passive (P)",
                    code: "P",
                    description: <<~DESCRIPTION
                      Successful exploitation of this vulnerability requires limited interaction by the targeted user
                      with the vulnerable system and the attacker's payload. These interactions would be considered
                      involuntary and do not require that the user actively subvert protections built into the vulnerable system.
                      DESCRIPTION
                  },
                  {
                    name: "Active (A)",
                    code: "A",
                    description: <<~DESCRIPTION
                      Successful exploitation of this vulnerability requires a targeted user to perform specific,
                      conscious interactions with the vulnerable system and the attacker's payload, or the user's
                      interactions would actively subvert protection mechanisms which would lead to exploitation of
                      the vulnerability.
                      DESCRIPTION
                  },
                ],
                default_choice_code: "N",
                description: <<~DESCRIPTION
                  This metric captures the requirement for a human user, other than the attacker, to participate in
                  the successful compromise of the vulnerable system. This metric determines whether the vulnerability
                  can be exploited solely at the will of the attacker, or whether a separate user (or user-initiated
                    process) must participate in some manner.
                  DESCRIPTION
              },
            ],
            vulnerable_system_impact:
            [
              {
                name: "Confidentiality (VC)",
                code: "VC",
                choices: [
                  {
                    name: "High (H)",
                    code: "H",
                    description: <<~DESCRIPTION
                      There is a total loss of confidentiality, resulting in all information within the Vulnerable
                      System being divulged to the attacker. Alternatively, access to only some restricted information
                      is obtained, but the disclosed information presents a direct, serious impact. For example, an
                      attacker steals the administrator's password, or private encryption keys of a web server.
                      DESCRIPTION
                  },
                  {
                    name: "Low (L)",
                    code: "L",
                    description: <<~DESCRIPTION
                      There is some loss of confidentiality. Access to some restricted information is obtained, but the
                      attacker does not have control over what information is obtained, or the amount or kind of loss
                      is limited. The information disclosure does not cause a direct, serious loss to the Vulnerable System.
                      DESCRIPTION
                  },
                  {
                    name: "None (N)",
                    code: "N",
                    description: <<~DESCRIPTION
                      There is no loss of confidentiality within the Vulnerable System.
                      DESCRIPTION
                  },
                ],
                default_choice_code: "N",
                description: <<~DESCRIPTION
                  This metric measures the impact to the confidentiality of the information managed by the VULNERABLE
                  SYSTEM due to a successfully exploited vulnerability. Confidentiality refers to limiting information
                  access and disclosure to only authorized users, as well as preventing access by, or disclosure to,
                  unauthorized ones.
                  DESCRIPTION
              },
              {
                name: "Integrity (VI)",
                code: "VI",
                choices: [
                  {
                    name: "High (H)",
                    code: "H",
                    description: <<~DESCRIPTION
                    There is a total loss of integrity, or a complete loss of protection. For example, the attacker is
                    able to modify any/all files protected by the vulnerable system. Alternatively, only some files can
                    be modified, but malicious modification would present a direct, serious consequence to the
                    vulnerable system.
                    DESCRIPTION
                  },
                  {
                    name: "Low (L)",
                    code: "L",
                    description: <<~DESCRIPTION
                      Modification of data is possible, but the attacker does not have control over the consequence of a
                      modification, or the amount of modification is limited. The data modification does not have a direct,
                      serious impact to the Vulnerable System.
                      DESCRIPTION
                  },
                  {
                    name: "None (N)",
                    code: "N",
                    description: <<~DESCRIPTION
                      There is no loss of integrity within the Vulnerable System.
                      DESCRIPTION
                  },
                ],
                default_choice_code: "N",
                description: <<~DESCRIPTION
                  This metric measures the impact to integrity of a successfully exploited vulnerability. Integrity
                  refers to the trustworthiness and veracity of information. Integrity of the VULNERABLE SYSTEM is
                  impacted when an attacker makes unauthorized modification of system data. Integrity is also impacted
                  when a system user can repudiate critical actions taken in the context of the system (e.g. due to
                    insufficient logging).
                  DESCRIPTION
              },
              {
                name: "Availability (VA)",
                code: "VA",
                choices: [
                  {
                    name: "High (H)",
                    code: "H",
                    description: <<~DESCRIPTION
                      There is a total loss of availability, resulting in the attacker being able to fully deny access
                      to resources in the Vulnerable System; this loss is either sustained (while the attacker continues
                        to deliver the attack) or persistent (the condition persists even after the attack has completed).
                        Alternatively, the attacker has the ability to deny some availability, but the loss of availability
                        presents a direct, serious consequence to the Vulnerable System (e.g., the attacker cannot disrupt
                          existing connections, but can prevent new connections; the attacker can repeatedly exploit a
                          vulnerability that, in each instance of a successful attack, leaks a only small amount of memory,
                          but after repeated exploitation causes a service to become completely unavailable).
                      DESCRIPTION
                  },
                  {
                    name: "Low (L)",
                    code: "L",
                    description: <<~DESCRIPTION
                      Performance is reduced or there are interruptions in resource availability. Even if repeated
                      exploitation of the vulnerability is possible, the attacker does not have the ability to completely
                      deny service to legitimate users. The resources in the Vulnerable System are either partially
                      available all of the time, or fully available only some of the time, but overall there is no direct,
                      serious consequence to the Vulnerable System.
                      DESCRIPTION
                  },
                  {
                    name: "None (N)",
                    code: "N",
                    description: <<~DESCRIPTION
                      There is no impact to availability within the Vulnerable System.
                      DESCRIPTION
                  },
                ],
                default_choice_code: "N",
                description: <<~DESCRIPTION
                  This metric measures the impact to the availability of the VULNERABLE SYSTEM resulting from a
                  successfully exploited vulnerability. While the Confidentiality and Integrity impact metrics apply to
                  the loss of confidentiality or integrity of data (e.g., information, files) used by the system, this
                  metric refers to the loss of availability of the impacted system itself, such as a networked service
                  (e.g., web, database, email). Since availability refers to the accessibility of information resources,
                  attacks that consume network bandwidth, processor cycles, or disk space all impact the availability
                  of a system.
                  DESCRIPTION
              },
            ],
            subsequent_system_impact:
            [
              {
                name: "Confidentiality (SC)",
                code: "SC",
                choices: [
                  {
                    name: "High (H)",
                    code: "H",
                    description: <<~DESCRIPTION
                      There is a total loss of confidentiality, resulting in all resources within the Subsequent System
                      being divulged to the attacker. Alternatively, access to only some restricted information is
                      obtained, but the disclosed information presents a direct, serious impact. For example, an attacker
                      steals the administrator's password, or private encryption keys of a web server.
                      DESCRIPTION
                  },
                  {
                    name: "Low (L)",
                    code: "L",
                    description: <<~DESCRIPTION
                      There is some loss of confidentiality. Access to some restricted information is obtained, but the
                      attacker does not have control over what information is obtained, or the amount or kind of loss is
                      limited. The information disclosure does not cause a direct, serious loss to the Subsequent System.
                      DESCRIPTION
                  },
                  {
                    name: "None (N)",
                    code: "N",
                    description: <<~DESCRIPTION
                      There is no loss of confidentiality within the Subsequent System or all confidentiality impact is
                      constrained to the Vulnerable System.
                      DESCRIPTION
                  },
                ],
                default_choice_code: "N",
                description: <<~DESCRIPTION
                  This metric measures the impact to the confidentiality of the information managed by the SUBSEQUENT
                  SYSTEM due to a successfully exploited vulnerability. Confidentiality refers to limiting information
                  access and disclosure to only authorized users, as well as preventing access by, or disclosure to,
                  unauthorized ones.
                  DESCRIPTION
              },
              {
                name: "Integrity (SI)",
                code: "SI",
                choices: [
                  {
                    name: "High (H)",
                    code: "H",
                    description: <<~DESCRIPTION
                      There is a total loss of integrity, or a complete loss of protection. For example, the attacker
                      is able to modify any/all files protected by the Subsequent System. Alternatively, only some files
                      can be modified, but malicious modification would present a direct, serious consequence to the
                      Subsequent System.
                      DESCRIPTION
                  },
                  {
                    name: "Low (L)",
                    code: "L",
                    description: <<~DESCRIPTION
                      Modification of data is possible, but the attacker does not have control over the consequence of
                      a modification, or the amount of modification is limited. The data modification does not have a
                      direct, serious impact to the Subsequent System.
                      DESCRIPTION
                  },
                  {
                    name: "None (N)",
                    code: "N",
                    description: <<~DESCRIPTION
                      There is no loss of integrity within the Subsequent System or all integrity impact is constrained
                      to the Vulnerable System.
                      DESCRIPTION
                  },
                ],
                default_choice_code: "N",
                description: <<~DESCRIPTION
                  This metric measures the impact to integrity of a successfully exploited vulnerability. Integrity
                  refers to the trustworthiness and veracity of information. Integrity of the SUBSEQUENT SYSTEM is
                  impacted when an attacker makes unauthorized modification of system data. Integrity is also impacted
                  when a system user can repudiate critical actions taken in the context of the system (e.g. due to
                    insufficient logging).
                  DESCRIPTION
              },
              {
                name: "Availability (SA)",
                code: "SA",
                choices: [
                  {
                    name: "High (H)",
                    code: "H",
                    description: <<~DESCRIPTION
                      There is a total loss of availability, resulting in the attacker being able to fully deny access
                      to resources in the Subsequent System; this loss is either sustained (while the attacker continues
                        to deliver the attack) or persistent (the condition persists even after the attack has completed).
                        Alternatively, the attacker has the ability to deny some availability, but the loss of availability
                        presents a direct, serious consequence to the Subsequent System (e.g., the attacker cannot disrupt
                          existing connections, but can prevent new connections; the attacker can repeatedly exploit a
                          vulnerability that, in each instance of a successful attack, leaks a only small amount of memory,
                          but after repeated exploitation causes a service to become completely unavailable).
                      DESCRIPTION
                  },
                  {
                    name: "Low (L)",
                    code: "L",
                    description: <<~DESCRIPTION
                      Performance is reduced or there are interruptions in resource availability. Even if repeated
                      exploitation of the vulnerability is possible, the attacker does not have the ability to completely
                      deny service to legitimate users. The resources in the Subsequent System are either partially
                      available all of the time, or fully available only some of the time, but overall there is no direct,
                      serious consequence to the Subsequent System.
                      DESCRIPTION
                  },
                  {
                    name: "None (N)",
                    code: "N",
                    description: <<~DESCRIPTION
                      There is no impact to availability within the Subsequent System or all availability impact is
                      constrained to the Vulnerable System.
                      DESCRIPTION
                  },
                ],
                default_choice_code: "N",
                description: <<~DESCRIPTION
                  This metric measures the impact to the availability of the SUBSEQUENT SYSTEM resulting from a
                  successfully exploited vulnerability. While the Confidentiality and Integrity impact metrics apply
                  to the loss of confidentiality or integrity of data (e.g., information, files) used by the system,
                  this metric refers to the loss of availability of the impacted system itself, such as a networked
                  service (e.g., web, database, email). Since availability refers to the accessibility of information
                  resources, attacks that consume network bandwidth, processor cycles, or disk space all impact the
                  availability of a system.
                  DESCRIPTION
              },
            ],
          },
        ],
      },
    ].freeze

    attr_reader :calculator_target

    def initialize(calculator_target:)
      @calculator_target = calculator_target
    end

    def self.sub_category_names_to_string(category)
      case category
      when :exploitability
        "Exploitability metrics"
      when :vulnerable_system_impact
        "Vulnerable system impact metrics"
      when :subsequent_system_impact
        "Subsequent system impact metrics"
      end
    end

    def score_documentation_url
      "https://www.first.org/cvss/v4.0/user-guide"
    end
  end
end
