# typed: strict
# frozen_string_literal: true
module SecurityProduct
  class PullRequestAlert
    extend T::Sig

    class TurboscanApiError < StandardError; end

    sig { returns(Integer) }; attr_accessor :alert_number
    sig { returns(Integer) }; attr_accessor :analysis_id
    sig { returns(T::Boolean) }; attr_accessor :autofix_accepted
    sig { returns(Time) }; attr_accessor :created_at
    sig { returns(T::Boolean) }; attr_accessor :has_autofix
    sig { returns(String) }; attr_accessor :ref
    sig { returns(T::Boolean) }; attr_accessor :fixed
    sig { returns(T.nilable(Time)) }; attr_accessor :fixed_at
    sig { returns(T.any(Symbol, Integer)) }; attr_accessor :resolution
    sig { returns(T.nilable(Time)) }; attr_accessor :resolved_at
    sig { returns(String) }; attr_accessor :rule_sarif_identifier
    sig { returns(T.any(Symbol, Integer)) }; attr_accessor :severity
    sig { returns(String) }; attr_accessor :tool
    sig { returns(Time) }; attr_accessor :updated_at
    sig { returns(T::Boolean) }; attr_accessor :has_dfa
    sig { returns(T::Boolean) }; attr_accessor :has_dfa_comments

    sig do
      params(
        alert_number: Integer,
        analysis_id: Integer,
        autofix_accepted: T::Boolean,
        created_at: Time,
        has_autofix: T::Boolean,
        ref: String,
        fixed: T::Boolean,
        fixed_at: T.nilable(Time),
        resolution: T.any(Symbol, Integer),
        resolved_at: T.nilable(Time),
        rule_sarif_identifier: String,
        severity: T.any(Symbol, Integer),
        tool: String,
        updated_at: Time
      ).void
    end
    def initialize(
      alert_number:,
      analysis_id:,
      autofix_accepted:,
      created_at:,
      has_autofix:,
      ref:,
      fixed:,
      fixed_at:,
      resolution:,
      resolved_at:,
      rule_sarif_identifier:,
      severity:,
      tool:,
      updated_at:
    )
      @alert_number = alert_number
      @analysis_id = analysis_id
      @autofix_accepted = autofix_accepted
      @created_at = created_at
      @has_autofix = has_autofix
      @ref = ref
      @fixed = fixed
      @fixed_at = fixed_at
      @resolution = resolution
      @resolved_at = resolved_at
      @rule_sarif_identifier = rule_sarif_identifier
      @severity = severity
      @tool = tool
      @updated_at = updated_at
      @has_dfa = T.let(false, T::Boolean)
      @has_dfa_comments = T.let(false, T::Boolean)
    end

    sig { params(pull_request: PullRequest).returns(T::Array[SecurityProduct::PullRequestAlert]) }
    def self.codeql_introduced_alerts(pull_request)
      response = GitHub::Turboscan.pull_request_introduced_alerts(
        repository_id: pull_request.repository_id,
        tool: "CodeQL",
        pr_number: pull_request.number,
        head_commit_oid: pull_request.head_sha,
        merge_commit_oid: pull_request.merge_commit_sha,
        base_ref_bytes: "refs/heads/#{pull_request.base_ref_name}".b,
        file_changes: ::CodeScanning::PullRequestAlertSummaryGenerator.changed_lines(pull_request.diffs, include_deletions: false)
      )

      response_data = T.let(response.try(:data), T.nilable(Turboscan::Proto::PullRequestIntroducedAlertsResponse))
      if response.nil? || response.error.present? || response_data.nil?
        GitHub.logger.error("Error getting Turboscan alerts", {
          "gh.turboscan.error.code": response&.error&.code,
          "gh.turboscan.error.message": response&.error&.msg,
        })
        raise TurboscanApiError
      end

      return [] if (alerts = response_data.alerts).blank?

      alert_numbers = alerts.map(&:alert_number)
      alerts_with_dfas = CodeScanningReviewComment
        .includes(pull_request_review_comment: :replies)
        .where(repository: pull_request.repository_id, pull_request: pull_request, alert_number: alert_numbers)

      dfas_indexed_by_alert_number = alerts_with_dfas.index_by(&:alert_number)

      alerts.map do |alert|
        alert_instance = self.build(alert)
        if dfa = dfas_indexed_by_alert_number[alert.alert_number]
          alert_instance.has_dfa = true
          alert_instance.has_dfa_comments = !!dfa.pull_request_review_comment&.replies&.any?
        end
        alert_instance
      end
    end

    sig { params(proto_instance: Turboscan::Proto::AlertInPullRequest).returns(SecurityProduct::PullRequestAlert) }
    def self.build(proto_instance)
      new(
        alert_number: proto_instance.alert_number,
        analysis_id: proto_instance.analysis_id,
        autofix_accepted: proto_instance.autofix_accepted,
        has_autofix: proto_instance.has_autofix,
        ref: proto_instance.ref_name_bytes,
        fixed: proto_instance.fixed,
        fixed_at: proto_instance.fixed_at&.to_time,
        resolution: proto_instance.resolution,
        resolved_at: proto_instance.resolved_at&.to_time,
        rule_sarif_identifier: proto_instance.rule_sarif_identifier,
        severity: proto_instance.severity,
        tool: proto_instance.tool,
        created_at: proto_instance.created_at&.to_time,
        updated_at: proto_instance.updated_at&.to_time
      )
    end
  end
end
