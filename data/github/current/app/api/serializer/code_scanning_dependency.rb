# typed: true
# frozen_string_literal: true

module Api::Serializer::CodeScanningDependency
  extend T::Helpers
  requires_ancestor { Api::Serializer::RepositoriesDependency }

  def code_scanning_alerts_hash(data, options = {})
    alerts = data.fetch(:alerts, [])

    options[:resolvers] = get_resolvers_of_alerts(alerts)

    alerts.map do |alert|
      code_scanning_alert_base_hash(alert, options)
    end
  end

  def code_scanning_alert_hash(result, options = {})
    return nil unless result && options[:repo]

    code_scanning_alert_base_hash(result, options, verbose_rules: true)
  end

  def code_scanning_alert_instances_hash(data, options = {})
    return nil unless data && options[:repo]

    exclude_alert_info = options[:repo].feature_enabled?(:code_scanning_instances_experiment)
    instances = data.fetch(:instances, [])
    instances.map do |i|
      # When showing alert instances, we do not expose the resolution of the logical
      # alert, only whether they are open or fixed in the corresponding configuration.
      # We "ignore" the resolution by passing `NO_RESOLUTION` below.
      code_scanning_alert_instance_hash(i, :NO_RESOLUTION, exclude_alert_info, options)
    end
  end

  def code_scanning_suggested_fix_hash(data, options = {})
    fix = data.fetch(:fix, nil)
    csrc = data.fetch(:csrc, nil)
    return nil unless fix && csrc
    {
      alert: {
        title: csrc.alert_title,
        message: strip_placeholder_message_text_links(csrc.alert_message),
        warning_level: csrc.warning_level,
      },
      url: csrc.pull_request_review_comment.pull_request_review.permalink,
      fixes: [{
        description: fix.description,
        files: fix.files.map do |f|
          {
            file_path: f.file_path,
            diff_content: Base64.strict_encode64(f.diff_content),
          }
        end,
        dismissed: fix.dismissed,
      }]
    }
  end

  def code_scanning_analyses_hash(data, options = {})
    analyses = data.fetch(:analyses, [])
    analyses.map do |a|
      code_scanning_analysis_hash(a, options)
    end
  end

  def code_scanning_analysis_hash(data, options = {})
    return nil unless data
    # Returns an analysis object.
    # Notes:
    # - We currently omit the AnalysisID, because no other endpoint can make use of this
    # - The Tool field should be an object with (at least) name and version. Ideally, we
    #   could encompass more of the SARIF specification (Driver Sec. 3.18.2)
    repo = options[:repo]
    {
      ref: data.ref_name_bytes,
      commit_sha: data.commit_oid,
      analysis_key: data.analysis_key,
      environment: data.environment,
      category: data.category,
      error: data.errors, # Using "error" as this is a single string.
      created_at: time(data.created_at),
      results_count: data.results_count,
      rules_count: data.rules_count,
      id: data.id,
      url: url("/repos/#{repo.name_with_owner_for_api(use: options[:serialize_login])}/code-scanning/analyses/#{data.id}"),
      sarif_id: data.sarif_id,
      tool: code_scanning_tool_hash(data.tool_description, options),
      deletable: data.deletable,
      warning: data.process_warning,
    }
  end

  def code_scanning_default_setup_hash(data, options = {})
    {
      state: data.state,
      languages: data.languages.sort,
      query_suite: data.query_suite,
      updated_at: time(data.updated_at),
      schedule: data.schedule,
    }
  end

  # this method is an alternative to code_scanning_default_setup_hash to be used only
  # when the :remove_single_js_ts changeset is not active
  def code_scanning_default_setup_including_single_js_ts_hash(data, options = {})
    languages = data.languages
    if languages.include?("javascript-typescript")
      languages.push("javascript")
      languages.push("typescript")
    end
    {

      state: data.state,
      languages: languages.sort,
      query_suite: data.query_suite,
      updated_at: time(data.updated_at),
      schedule: data.schedule,
    }
  end

  def code_scanning_default_setup_workflow_run_hash(run_id, options = {})
    repo = options[:repo]
    run_url = run_id == 0 ? "" : url("/repos/#{repo.name_with_display_owner}/actions/runs/#{run_id}")
    {
      run_id: run_id,
      run_url: run_url
    }
  end

  def code_scanning_status_hash(data, options = {})
    return nil unless data && options[:repo]
    repo = options[:repo]

    hash = {
      processing_status: data[:processing_status],
      errors: data[:errors],
    }
    sarif_id = data[:sarif_id]
    if data[:processing_status] == "complete"
      hash["analyses_url"] = url("/repos/#{repo.name_with_owner_for_api(use: options[:serialize_login])}/code-scanning/analyses?sarif_id=#{sarif_id}")
    end
    hash
  end

  def code_scanning_advanced_setup_hash(data, options = {})
    {
      enabled: data[:enabled],
    }
  end

  def code_scanning_third_party_tools_hash(data, options = {})
    {
      enabled: data[:enabled],
    }
  end

  def code_scanning_receipt_hash(data, options = {})
    return nil unless data && options[:repo]
    repo = options[:repo]
    {
      id: data[:id],
      url: url("/repos/#{repo.name_with_owner_for_api(use: options[:serialize_login])}/code-scanning/sarifs/#{data[:id]}")
    }
  end

  def org_code_scanning_alerts_hash(data, options = {})
    repo_results = data.fetch(:repo_results, [])
    repos_by_id = data.fetch(:repos_by_id, {})

    options[:resolvers] = get_resolvers_of_alerts(repo_results.map(&:result))

    repo_results.map do |repo_result|
      options[:repo] = repos_by_id[repo_result.repository_id]

      hash = code_scanning_alert_base_hash(repo_result.result, options)

      hash[:repository] = simple_repository_hash(options[:repo], options)
      hash
    end
  end

  def enterprise_code_scanning_alerts_hash(data, options = {})
    repo_results = data.fetch(:repo_results, [])
    repos_by_id = data.fetch(:repos_by_id, {})

    options[:resolvers] = get_resolvers_of_alerts(repo_results.map(&:result))

    repo_results.map do |repo_result|
      repo = repos_by_id[repo_result.repository_id]
      options[:repo] = repo

      code_scanning_alert_base_hash(repo_result.result, options).tap do |hash|
        hash[:repository] = simple_repository_hash(repo, options)
      end
    end
  end

  private

  def code_scanning_alert_instance_hash(i, resolution, exclude_alert_info = false, options = {})
    return nil unless i.present?

    if i.is_fixed
      state = "fixed"
    elsif resolution != :NO_RESOLUTION
      state = "dismissed"
    else
      state = "open"
    end

    output = {
      ref: i.ref_name_bytes,
      analysis_key: i.analysis_key&.analysis_key,
      environment: i.analysis_key&.environment,
      category: i.analysis_key&.category,
      state: state,
      commit_sha: i.commit_oid,
    }
    output = output.merge({
      message: {
        text: strip_placeholder_message_text_links(i.message_text),
      },
      location: code_scanning_location_hash(i.location),
      classifications: i.classification
    }) unless exclude_alert_info
    output
  end

  def code_scanning_alert_base_hash(data, options = {}, verbose_rules: false)
    return nil unless data && options[:repo]
    repo = options[:repo]

    if repo.code_scanning_alert_verbose_rules_enabled?
      verbose_rules = true
    end

    hash = {
      number: data.number,
      created_at: time(data.created_at),
      updated_at: time(data.updated_at),
      url: url("/repos/#{repo.name_with_owner_for_api(use: options[:serialize_login])}/code-scanning/alerts/#{data.number}"),
      html_url: html_url("/#{repo.name_with_owner_for_api(use: options[:serialize_login])}/security/code-scanning/#{data.number}"),
    }

    resolver = options[:resolvers]&.key?(data.resolver_id) ? options[:resolvers][data.resolver_id] : User.find_by(id: data.resolver_id)

    # support old style hydro message that does not contain rule data
    rule_hash = unless data.rule.nil?
      {
        id: data.rule.sarif_identifier,
        severity: data.rule.severity.to_s.downcase,
        description: data.rule.short_description,
        name: data.rule.name,
        tags: data.rule.tags,
      }
    end

    unless rule_hash.nil?
      if verbose_rules
        rule_hash.merge!({ full_description: data.rule.full_description, help: data.rule.help })
        rule_hash[:help_uri] = data.rule.help_uri if data.rule.help_uri.present?
      end
      rule_hash["security_severity_level"] = data.security_severity.to_s.downcase unless data.security_severity == :NO_SECURITY_SEVERITY
    end

    hash.merge(
      {
        state: if data.is_fixed
                 "fixed"
               else
                 (data.resolution != :NO_RESOLUTION ? "dismissed" : "open")
               end,
        fixed_at: data.is_fixed ? time(data.fixed_at) : nil,
        dismissed_by: user_hash(resolver, content_options(options)),
        dismissed_at: time(data.resolved_at),
        dismissed_reason: GitHub::Turboscan.api_resolution_reason(data.resolution),
        dismissed_comment: data.resolution_note.presence,
        rule: rule_hash,
        tool: code_scanning_tool_hash(data.tool, options),
        most_recent_instance: code_scanning_alert_instance_hash(data.most_recent_instance, data.resolution, false, options),
        instances_url: url("/repos/#{repo.name_with_owner_for_api(use: options[:serialize_login])}/code-scanning/alerts/#{data.number}/instances"),
      }
    )
  end

  def code_scanning_tool_hash(data, options = {})
    return unless data.present?
    {
      name: data.name,
      guid: data.guid.presence,
      version: data.version.presence,
    }
  end

  def code_scanning_analysis_deleted_hash(data, options = {})
    return unless data.present? && options[:repo]
    nwo = options[:repo].name_with_owner_for_api(use: options[:serialize_login])
    next_analysis_id = data.new_most_recent_analysis_id
    if next_analysis_id != 0
      next_analysis_url = url("/repos/#{nwo}/code-scanning/analyses/#{next_analysis_id}")
      return {
        next_analysis_url: next_analysis_url,
        confirm_delete_url: next_analysis_url + "?confirm_delete",
      }
    end
    {
      next_analysis_url: nil,
      confirm_delete_url: nil,
    }
  end

  def code_scanning_location_hash(data, options = {})
    return nil unless data
    {
      path: data.file_path,
      start_line: data.start_line,
      end_line: data.end_line,
      start_column: data.start_column,
      end_column: data.end_column,
    }
  end

  # Replace links of the form `[link text](1234)` with `link text`
  def strip_placeholder_message_text_links(message_text)
    return unless message_text
    message_text.gsub(/\[([^\[]+)\](\(\d+\))/, '\1')
  end

  def get_resolvers_of_alerts(alerts)
    User.where(id: alerts.map(&:resolver_id).select(&:nonzero?).uniq).index_by(&:id)
  end
end
