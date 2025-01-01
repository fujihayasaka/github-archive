# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  module CampaignTemplates
    # This class encapsulates a template for creating a new security campaign.
    class Template

      sig { params(name: String, description: String, build_query: T.proc.params(autofix_enabled: T::Boolean).returns(String)).void }
      def initialize(name:, description:, build_query:)
        @name = name
        @description = description
        @build_query = build_query
      end

      sig { returns(String) }
      attr_reader :name

      sig { returns(String) }
      attr_reader :description

      sig { params(autofix_enabled: T::Boolean).returns(String) }
      def build_query(autofix_enabled)
        @build_query.call(autofix_enabled)
      end
    end

    DIALOG = T.let("create-campaign-templates-dialog".freeze, String)

    ALL_TEMPLATES = T.let(
      {
        critical_codeql: Template.new(
          name: "Critical CodeQL alert",
          description: "Address critical alerts before they are exploited to prevent breaches, protect sensitive data, and mitigate financial and reputational damage.",
          build_query: ->(autofix_enabled) {
            "is:open tool:codeql severity:critical autofilter:true#{autofix_filter(autofix_enabled)}"
          }
        ),
        mitre_top_10: Template.new(
          name: "Mitre top 10 KEV",
          description: "Remediate the MITRE Top 10 KEV (Known Exploited Vulnerabilities) to enhance security by addressing vulnerabilities actively exploited by attackers. This reduces risk, prevents breaches and can help protect sensitive data.",
          build_query: -> (autofix_enabled) {
            "is:open autofilter:true#{autofix_filter(autofix_enabled)} tag:external/cwe/cwe-416,external/cwe/cwe-122,external/cwe/cwe-787,external/cwe/cwe-121,external/cwe/cwe-20,external/cwe/cwe-020,external/cwe/cwe-099,external/cwe/cwe-114,external/cwe/cwe-129,external/cwe/cwe-112,external/cwe/cwe-078,external/cwe/cwe-502,external/cwe/cwe-918,external/cwe/cwe-843,external/cwe/cwe-022,external/cwe/cwe-023,external/cwe/cwe-036,external/cwe/cwe-306"
          }
        ),
        sql_injection: Template.new(
          name: "SQL injection (CWE-89)",
          description: "Remediating SQL injection vulnerabilities prevents unauthorized database access, data theft, and manipulation, ensuring regulatory compliance, maintaining application integrity, and enhancing user trust.",
          build_query: ->(autofix_enabled) {
            "is:open autofilter:true#{autofix_filter(autofix_enabled)} tag:external/cwe/cwe-089"
          }
        ),
        cwe_78: Template.new(
          name: "Cross-site scripting (CWE-79)",
          description: "Remediating Cross-Site Scripting (XSS) vulnerabilities prevents data theft, session hijacking, and unauthorized actions, ensuring regulatory compliance, maintaining application integrity, and enhancing user trust.",
          build_query: ->(autofix_enabled) {
            "is:open autofilter:true#{autofix_filter(autofix_enabled)} tag:external/cwe/cwe-79,external/cwe/cwe-079,external/cwe/cwe-080"
          }
        ),
      },
      T::Hash[Symbol, Template],
    )

    sig { params(autofix_enabled: T::Boolean).returns(String) }
    def self.autofix_filter(autofix_enabled)
      autofix_enabled ? " autofix:supported" : ""
    end
  end
end
