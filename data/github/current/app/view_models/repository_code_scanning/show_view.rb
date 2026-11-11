# typed: true
# frozen_string_literal: true

module RepositoryCodeScanning
  class ShowView < ResultView
    attr_reader :default_query
    attr_reader :alert_links
    attr_reader :assignees
    attr_reader :alert_tracking_links
    attr_reader :runtime_risks
    attr_reader :current_user_assignee
    attr_reader :linked_branches
    attr_reader :linked_pull_requests
    attr_reader :read_only_user
    attr_reader :suggested_fix_alert
    attr_reader :campaigns_with_counts
    attr_reader :pending_dismissal_request
    attr_reader :config_statuses
    attr_reader :config_statuses_complete
    attr_reader :assignable_to_copilot
    attr_reader :use_agentic_autofix
    attr_reader :is_copilot_assigned
    attr_reader :copilot_pull_request

    def rule_help
      response&.data&.result&.rule&.help
    end

    def has_rule_help?
      rule_help.present?
    end

    def has_code_paths?
      response&.data&.has_code_paths || false
    end

    def classifications
      classifications_for_alert_instance(selected_alert_instance)
    end

    def rule_description
      return @rule_description if defined?(@rule_description)
      @rule_description = if has_rule_help?
        GitHub.cache.fetch(rule_description_cache_key) do
          rule_help_html[:description]
        end
      end
    end

    def rule_description_markdown_without_overview
      return "" unless has_rule_help?
      lines = rule_help.split("\n")
      overview_index = lines.find_index("## Overview")
      if overview_index.present?
        lines[overview_index + 1..-1].join("\n").strip
      elsif lines[0].start_with?("#")
        lines[1..-1].join("\n").strip
      else
        rule_help
      end
    end
    private :rule_description_markdown_without_overview

    def rule_description_cache_key
      @rule_description_cache_key ||= [
        "code_scanning",
        "rule_description",
        "v1",
        rule_sarif_identifier,
        tool_name,
        Digest::SHA256.hexdigest(rule_help),
      ].join(":")
    end

    def rule_intro
      return @rule_intro if defined?(@rule_intro)
      @rule_intro = if has_rule_help?
        GitHub.cache.fetch(rule_intro_cache_key) do
          rule_help_html[:intro]
        end
      end
    end

    def rule_intro_cache_key
      @rule_intro_cache_key ||= [
        "code_scanning",
        "rule_intro",
        "v1",
        rule_sarif_identifier,
        tool_name,
        Digest::SHA256.hexdigest(rule_help),
      ].join(":")
    end

    def rule_help_html
      return @rule_help_html if defined?(@rule_help_html)

      rule_help_result = {}
      pipeline_result = {}

      description = GitHub::Goomba::CodeScanningRuleHelpMarkdownPipeline.to_html(rule_description_markdown_without_overview, {}, pipeline_result)

      rule_help_result[:description] = description
      rule_help_result[:intro] = pipeline_result[:first_paragraph]

      @rule_help_html = rule_help_result
    end

    def rule_help_expandable?
      return @rule_help_expandable if defined?(@rule_help_expandable)
      @rule_help_expandable = rule_intro.strip != rule_description.strip
    end

    def blob
      blob_for(location)
    end

    def page_title
      if turboscan_unavailable?
        "Code scanning alerts · #{repository.name_with_display_owner}"
      else
        "#{result_title(result)} · Code scanning alert ##{result&.number} · #{repository.name_with_display_owner}"
      end
    end

    def timeline_path
      urls.repository_code_scanning_show_timeline_path(repository.owner, repository, { number: result.number, ref: alert_instance&.ref_name_bytes })
    end

    def ref_selected?(ref)
      alert_instance.ref_name_bytes == ref
    end

    def code_snippet_path_link
      blob_path(
        commit_oid: alert_instance.commit_oid,
        file_path: alert_instance.location.file_path,
        start_line: alert_instance.location.start_line,
        end_line: alert_instance.location.end_line,
      )
    end

    def result_fixed?
      super(result)
    end

    def result_resolved?
      super(result)
    end

    def result_is_for_default_branch?
      response&.data&.ref_name_bytes == repository.default_branch_ref.qualified_name
    end

    def status
      return @status if defined?(@status)

      @status =
        if result_resolved?
          :dismissed
        elsif !result_is_for_default_branch?
          if response&.data&.ref_name_bytes&.starts_with?("refs/pull/")
            :in_pr
          elsif response&.data&.ref_name_bytes&.starts_with?("refs/heads/")
            :in_branch
          else
            # I think this should never happen, but perhaps people can upload analysis with other refs?
            :unknown
          end
        elsif result_fixed?
          :fixed
        else
          :open
        end
    end

    def status_badge_title_override
      case status
      when :dismissed then "Status: Dismissed as #{alert_closure_reason_description(result)}"
      when :fixed then "Status: Fixed in #{alert_instance.ref_name_bytes}"
      else nil
      end
    end

    def status_branch_name
      response&.data&.ref_name_bytes&.delete_prefix("refs/heads/")&.force_encoding("utf-8")&.scrub!
    end

    def status_should_show_branch_name?
      status != :dismissed
    end

    def status_date
      case status
      when :dismissed then return result&.resolved_at&.to_time
      when :fixed then return result&.fixed_at&.to_time
      end

      # A fixed alert only present in a non-default branch
      # will have a status of :in_branch or :in_pr
      # But should still be considered fixed as far as date is concerned.
      return result&.fixed_at&.to_time if result_fixed?

      result&.most_recent_instance&.created_at&.to_time
    end

    def show_dismiss_alert_button?
      return false unless alerts_writable_by_current_user?
      return false if result_resolved?

      true
    end

    def has_pending_request?
      CodeScanning::AlertDismissalService.has_pending_request?(repository: repository, alert_number: result.number)
    end

    def dismiss_alert_button_label
      return "Submit request" if code_scanning_alert_dismissal_enabled?

      "Dismiss alert"
    end

    def dismiss_alert_path
      return urls.repository_code_scanning_dismissal_request_create_path(repository.owner, repository) if code_scanning_alert_dismissal_enabled?

      urls.repository_code_scanning_dismissal_close_alerts_path(repository.owner, repository)
    end

    def show_reopen_alert_button?
      alerts_writable_by_current_user? && result_resolved?
    end

    def show_create_suggested_fix?
      return false unless alerts_writable_by_current_user?
      return false unless autofix_enabled_for_tool? && result_is_for_default_branch?
      return false if suggested_fix_rule_not_supported?

      suggested_fix_alert.nil? # We never attempted to generate a suggested fix for this alert
    end

    def show_create_agentic_fix?
      return false unless use_agentic_autofix
      return false unless alerts_writable_by_current_user?
      return false unless repository.writable_by?(current_user)
      return false unless repository.copilot_swe_agent_enabled?(current_user)
      return false unless result_is_for_default_branch?
      return false if agentic_autofix_pending?

      copilot_pull_request.nil? # We don't already have a Copilot-authored PR for this alert
    end

    # For now, we define the pending state for agentic autofix as when
    # Copilot is assigned, but there is no Copilot-authored PR linked to
    # the alert yet. We may change this to be more precise in the future.
    def agentic_autofix_pending?
      use_agentic_autofix && is_copilot_assigned && copilot_pull_request.nil?
    end

    def code_scanning_alert_dismissal_enabled?
      CodeScanning::AlertDismissalService.new(repository).delegated_dismissal_enabled?
    end

    def copilot_autofix_for_tool_name
      "Copilot Autofix for #{tool_display_name}"
    end

    def show_alert_with_suggested_fix?
      autofix_enabled_for_tool? && suggested_fix_alert? && suggested_fix_alert&.state == :SUGGESTED_FIX_ALERT_STATE_VALID &&
        !suggested_fix.outdated
    end

    def suggested_fix_alert?
      suggested_fix_alert.present?
    end

    def suggested_fix_alert_pending?
      suggested_fix_alert&.state == :SUGGESTED_FIX_ALERT_STATE_PENDING
    end

    def suggested_fix_alert_error?
      suggested_fix_alert&.state == :SUGGESTED_FIX_ALERT_STATE_ERROR
    end

    def suggested_fix_alert_invalid?
      suggested_fix_alert&.state == :SUGGESTED_FIX_ALERT_STATE_INVALID
    end

    def suggested_fix_rule_not_supported?
      return false unless autofix_enabled_for_tool?

      return suggested_fix_alert&.state == :SUGGESTED_FIX_ALERT_STATE_RULE_NOT_SUPPORTED if suggested_fix_alert

      # If we don't have a suggested fix alert, we check the sarif rule identifier of the alert
      return false if result.rule.nil?
      !CodeScanning::Autofix::is_rule_supported?(repository, tool_name, result.rule.sarif_identifier)
    end

    def suggested_fix_outdated?
      suggested_fix&.outdated
    end

    def suggested_fix_not_supported
      CodeScanning::Autofix.suggested_autofix_not_supported_message(
        suggested_fix_rule_name || result.rule&.sarif_identifier
      )
    end

    def suggested_fix_autofix_docs_url
      DocsUrlConfig.url_for("about-autofix")
    end

    def suggested_fix_autofix_query_lists_docs_url
      DocsUrlConfig.url_for("autofix-query-lists")
    end

    memoize def suggested_fix
      suggested_fix_alert&.suggested_fix
    end

    def ref_names
      Array(selected_alert_instance&.ref_name_bytes)
    end

    def ref_names_b64
      ref_names.map { |ref_name| Base64.strict_encode64(ref_name) }
    end

    def suggested_fix_rule_name
      suggested_fix_alert&.rule_sarif_identifier
    end

    def autofix_enabled_for_tool?
      CodeScanning::Autofix.enabled_for_tool?(repository, tool_name)
    end

    def pending_dismissal_request?
      pending_dismissal_request.present?
    end

    def pending_dismissal_requester
      pending_dismissal_request&.requester
    end

    def pending_dismissal_resolution
      alert_closure_reasons[Turboscan::Proto::ResultResolution.lookup(pending_dismissal_request&.metadata["resolution"].to_i)].downcase
    end

    def pending_dismissal_requested_at
      Google::Protobuf::Timestamp.new(seconds: pending_dismissal_request&.created_at.to_i)
    end
  end
end
