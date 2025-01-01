# typed: true
# frozen_string_literal: true

module RepositoryCodeScanning
  class ShowView < ResultView
    attr_reader :default_query
    attr_reader :alert_instances
    attr_reader :alert_instances_complete
    attr_reader :affected_branches_form_submit_path
    attr_reader :read_only_user
    attr_reader :suggested_fix_alert
    attr_reader :campaigns_with_counts

    CWE_PATTERN = /cwe(?:[- ]*0*)(\d+)/i.freeze
    NUM_BRANCHES_TO_SHOW_ABOVE_FOLD = 5
    NUM_BRANCHES_TO_SHOW_IN_TOTAL = 15

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

    def cwe_id(rule_tag)
      match = CWE_PATTERN.match(rule_tag)
      match.present? ? match[1].to_i : nil
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

    def affected_branches
      return nil if alert_instances.nil?

      @affected_branches ||= begin
        instances_by_branch = Hash.new { |h, k| h[k] = [] }
        alert_instances.each do |instance|
          instances_by_branch[instance.ref_name_bytes.delete_prefix("refs/heads/")].push(instance)
        end

        prots = repository.protected_branches.map(&:name).to_set

        ordered_branches = instances_by_branch.keys.sort do |a, b|
          # default branch first
          next -1 if a == repository.default_branch
          next 1 if b == repository.default_branch

          # then protected branches
          next -1 if prots.include?(a) && prots.none?(b)
          next 1 if prots.include?(b) && prots.none?(a)

          # secondary ordering is name
          a <=> b
        end

        ordered_branches = ordered_branches.select do |branch|
          instances_by_branch[branch] = instances_by_branch[branch].select { |i| !i&.is_outdated } unless branch == repository.default_branch
          !instances_by_branch[branch].empty?
        end

        branches_to_show = ordered_branches.lazy.map do |branch|
          # We are filtering the instances that are marked as outdated so that we don't show them in the UI.
          instances = instances_by_branch[branch].select { |i| !i&.is_outdated }.map do |i|
            {
              is_fixed: i.is_fixed,
              category: i&.analysis_key&.category,
              is_outdated: i&.is_outdated,
              created_at: i&.created_at,
              tool_name: i&.analysis_key&.tool,
            }
          end
          {
            name: branch,
            dismissed?: status == :dismissed,
            instances: instances,
          }
        end

        # only process display data for the visible branches
        branches_to_show = branches_to_show.first(NUM_BRANCHES_TO_SHOW_IN_TOTAL)

        above_fold = branches_to_show&.slice(0, NUM_BRANCHES_TO_SHOW_ABOVE_FOLD)
        below_fold = branches_to_show&.slice(NUM_BRANCHES_TO_SHOW_ABOVE_FOLD, branches_to_show.size) || []
        # Note that the how_many_more only considers branches from fetched instances
        # If we did not get all tips from Turboscan the view will present it as a lower bound
        how_many_more = ordered_branches.size - (branches_to_show&.size || 0)
        {
          all_branches: branches_to_show,
          above_fold: above_fold,
          below_fold: below_fold,
          plus_this_many_more: how_many_more
        }
      end
    end

    def show_more_affected_branches_not_shown_indicator?
      affected_branches[:plus_this_many_more].nonzero? || !alert_instances_complete
    end

    def rule_tag_label(rule_tag)
      # Drop external/cwe/ prefix
      rule_tag = rule_tag.gsub(/\Aexternal\/cwe\/(cwe-[\d]+)\z/, "\\1")

      rule_tag = rule_tag.titleize.downcase

      # Normalize cwe 012 to CWE-12
      rule_tag = rule_tag.gsub(CWE_PATTERN, "CWE-\\1")
    end

    def rule_tags_for_tags_section
      rule_tags - cwe_tags
    end

    def cwe_tags
      rule_tags.filter do |tag|
        rule_tag_label(tag).starts_with? "CWE-"
      end
    end

    def cwe_numbers
      cwe_tags.map do |tag|
        cwe_id(tag)
      end
    end

    def displayable_tracking_issues
      return @displayable_tracking_issues if defined?(@displayable_tracking_issues)
      @displayable_tracking_issues = IssueAlertLink.displayable_tracking_issues(repository: repository, alert_number: result.number, viewer: current_user)
    end

    def show_create_issue_button?
      !result_resolved? && !result_fixed? && !displayable_tracking_issues.present? && repository.has_issues?
    end

    def tracking_issue_title
      @title ||= "Fix code scanning alert - #{result_title(result).truncate(100)}"
    end

    def tracking_issue_body
      return @body if defined?(@body)
      @body = "<!-- Warning: The suggested title contains the alert rule name. This can expose security information. -->\n\n"
      @body += "Tracking issue for:\n"
      @body += "- [ ] #{GitHub.url}/#{repository.name_with_display_owner}/security/code-scanning/#{result.number}\n"
    end

    def show_create_suggested_fix?
      return false unless alerts_writable_by_current_user?
      return false unless autofix_enabled_for_tool? && result_is_for_default_branch?
      return false if suggested_fix_rule_not_supported?

      suggested_fix_alert.nil? # We never attempted to generate a suggested fix for this alert
    end

    def autofix_supported_thirdparty_tool?
      CodeScanning::AutofixThirdPartyTools.is_supported_tool?(tool_name)
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
      if CodeScanning::AutofixThirdPartyTools.is_supported_tool?(tool_name)
        return CodeScanning::AutofixThirdPartyTools.changelog_url
      end
      DocsUrlConfig.url_for("about-autofix")
    end

    def suggested_fix_autofix_query_lists_docs_url
      if CodeScanning::AutofixThirdPartyTools.is_supported_tool?(tool_name)
        return CodeScanning::AutofixThirdPartyTools.changelog_url
      end
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
  end
end
