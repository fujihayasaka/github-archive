# typed: true
# frozen_string_literal: true

module CodeScanning
  class Autofix
    FEEDBACK_OPTIONS = [
      :CODE_SCANNING_AUTOFIX_FEEDBACK_ALERT_NOT_RELEVANT,
      :CODE_SCANNING_AUTOFIX_FEEDBACK_FIX_HAS_ERRORS,
      :CODE_SCANNING_AUTOFIX_FEEDBACK_FIX_IS_UNHELPFUL,
      :CODE_SCANNING_AUTOFIX_FEEDBACK_FIX_WONT_ADDRESS_PROBLEM,
      :CODE_SCANNING_AUTOFIX_FEEDBACK_FIX_WILL_BREAK_FUNCTIONALITY,
      :CODE_SCANNING_AUTOFIX_FEEDBACK_OTHER
    ]

    def self.available_in_environment?
      GitHub.code_scanning_enabled? && !GitHub.enterprise?
    end

    def self.any_enabled_for_repo?(repo)
      CodeScanning::AutofixCodeql.enabled_for_repo?(repo) || CodeScanning::AutofixThirdPartyTools.enabled_for_repo?(repo)
    end

    def self.any_enabled_for_org?(org)
      CodeScanning::AutofixCodeql.enabled_for_org?(org) || CodeScanning::AutofixThirdPartyTools.enabled_for_org?(org)
    end

    def self.any_allowed_by_business?(business)
      CodeScanning::AutofixCodeql.allowed_by_business?(business) || CodeScanning::AutofixThirdPartyTools.allowed_by_business?(business)
    end

    def self.enabled_for_tool?(repo, tool_name)
      return true if repo.code_scanning_autofix_all_queries_enabled? # Allow all _tools_ and queries to generate autofixes if the (repo-level) FF code_scanning_suggested_all_queries is enabled

      if tool_name == CodeScanning::AutofixCodeql::CODEQL_TOOL_NAME
        CodeScanning::AutofixCodeql.enabled_for_repo?(repo)
      elsif CodeScanning::AutofixThirdPartyTools.is_supported_tool?(tool_name)
        CodeScanning::AutofixThirdPartyTools.enabled_for_repo?(repo)
      else
        false
      end
    end

    def self.is_rule_supported?(repo, tool_name, rule_id)
      return true if repo.code_scanning_autofix_all_queries_enabled? # Allow all _tools_ and rules if the (repo-level) FF code_scanning_suggested_all_queries is enabled

      return false unless Turboscan::SuggestedFix::ENABLED_TOOLS.include?(tool_name)
      Turboscan::SuggestedFix::SUPPORTED_RULES_PER_TOOL[tool_name].include?(rule_id)
    end

    sig { params(repo: Repository, alert_numbers: T::Array[Integer], ref: T.nilable(Git::Ref), head_commit: T.nilable(::Commit)).returns(T::Hash[Integer, Turboscan::Proto::SuggestedFix]) }
    def self.suggested_fixes_for_alerts(repo, alert_numbers, ref: nil, head_commit: nil)
      return {} if alert_numbers.empty?

      ref ||= repo.default_branch_ref
      head_commit ||= ref.commit

      begin
        suggested_fixes_alerts = CodeScanning::AutofixSuggestion.fetch_all_suggested_fix_alerts(
          repository: repo,
          alert_numbers: alert_numbers,
          head_commit_oid: head_commit.oid,
          ref_names_bytes: [ref.qualified_name.b]
        )
      rescue CodeScanning::AutofixError
        return {}
      end

      suggested_fixes_alerts.each_with_object({}) do |(number, sfa), out|
        suggested_fix = sfa.suggested_fix
        if !suggested_fix.nil?
          GitHub.dogstats.increment("security_campaigns.suggested_fix.outdated", tags: ["outdated:#{suggested_fix.outdated}"])
        end
        unless suggested_fix.nil? || suggested_fix.outdated
          out[number] = suggested_fix
        end
      end
    end

    def self.can_dismiss_code_scanning_suggested_fix?(repo, user)
      repo.pushable_by?(user)
    end

    def self.suggested_autofix_not_supported_message(suggested_fix_rule_name)
      "Rule #{suggested_fix_rule_name}"
    end
  end
end
