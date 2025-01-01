# typed: true
# frozen_string_literal: true

module Api::Serializer::CodeScanningDependency
  extend T::Helpers
  requires_ancestor { Api::Serializer::RepositoriesDependency }

  def code_scanning_alerts_hash(data, options = {})
    alerts = data.fetch(:alerts, [])

    options[:resolvers] = get_resolvers_of_alerts(alerts)
    options[:dismissal_approvers] = get_dismissal_approvers_of_alerts(alerts)

    alerts.map do |alert|
      code_scanning_alert_base_hash(alert, options)
    end
  end

  def code_scanning_alert_hash(result, options = {})
    return nil unless result && options[:repo]

    base_hash = code_scanning_alert_base_hash(result, options)
    on_default = result.most_recent_instance&.ref_name_bytes == options[:repo].default_code_scanning_ref_names_bytes[0]
    if base_hash[:state] != "dismissed" && !on_default
      base_hash[:state] = nil
      base_hash[:fixed_at] = nil
    end
    base_hash
  end

  def code_scanning_alert_instances_hash(data, options = {})
    return nil unless data && options[:repo]

    instances = data.fetch(:instances, [])
    instances.map do |i|
      # When showing alert instances, we do not expose the resolution of the logical
      # alert, only whether they are open or fixed in the corresponding configuration.
      # We "ignore" the resolution by passing `NO_RESOLUTION` below.
      code_scanning_alert_instance_hash(i, :NO_RESOLUTION, options)
    end
  end

  sig { params(dismissal_request: Exemptions::ExemptionRequest, options: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
  def code_scanning_dismissal_request_hash(dismissal_request, options = {})
    # strict loading of response.reviewer
    GitHub::PrefillAssociations.prefill_associations(dismissal_request, [:responses])
    responses = dismissal_request.responses.map do |response|
      {
        id: response.id,
        reviewer: {
          actor_id: response.reviewer&.id,
          actor_name: response.reviewer&.display_login,
        },
        status: response.status == "rejected" ? "denied" : response.status,
        created_at: response.created_at,
      }
    end

    # using custom data hash, cannot use dismissal_request.exemption_data_hash as its being used by webhook and there is a gap between the two
    data = dismissal_request_data_hash(dismissal_request)
    repo = dismissal_request.repository
    org = repo&.organization

    hash = {
      id: dismissal_request.id,
      number: dismissal_request.number,
      repository: simple_repo_hash(repo),
      organization: simple_org_hash(org),
      requester: actor_hash(dismissal_request.requester),
      request_type: dismissal_request.request_type,
      data: data[:data],
      resource_identifier: dismissal_request.resource_identifier,
      status: determine_request_status(dismissal_request, false),
      requester_comment: dismissal_request.requester_comment,
      expires_at: dismissal_request.expires_at&.iso8601,
      created_at: dismissal_request.created_at&.iso8601,
      responses: responses,
      url: "#{GitHub.api_url}/repos/#{repo&.name_with_display_owner}/dismissal-requests/code-scanning/#{dismissal_request.number}",
      html_url: dismissal_request.permalink,
    }

    hash
  end

  def dismissal_request_data_hash(dismissal_request)
    resolution_symbol = T.let(T.must(Turboscan::Proto::ResultResolution.lookup(dismissal_request.metadata["resolution"].to_i)), Symbol)
    data_hash = {
      reason: GitHub::Turboscan.api_resolution_reason(resolution_symbol),
      alert_number: dismissal_request.metadata["alert_number"],
    }
    if dismissal_request.metadata["pr_review_thread_id"].present?
      data_hash[:pr_review_thread_id] = dismissal_request.metadata["pr_review_thread_id"]
    end

    {
      type: CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE,
      data: [data_hash],
    }
  end

  def code_scanning_autofix_hash(data, options = {})
    h = {
      status: data[:status],
      description: data[:description],
      started_at: data[:started_at],
    }
    if data[:validations_summary].present?
      h.merge!(validations_summary: data[:validations_summary])
    end
    h
  end

  def code_scanning_autofix_commit_hash(data, options = {})
    {
      target_ref: data[:target_ref],
      sha: data[:sha]
    }
  end

  def code_scanning_autofix_validation_check(data, options = {})
    {
      status: data[:status]
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

  sig { params(data: CodeScanning::AutoCodeqlConfig, options: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
  def code_scanning_runner_hash(data, options = {})
    {
      runner_type: data.runner_type,
      runner_label: data.runner_label,
    }
  end


  sig { params(data: CodeScanning::AutoCodeqlConfig, options: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
  def code_scanning_default_setup_hash(data, options = {})
    {
      state: data.state,
      languages: data.languages.sort,
      query_suite: data.query_suite,
      threat_model: data.threat_model,
      updated_at: time(data.updated_at),
      schedule: data.schedule,
    }.merge(code_scanning_runner_hash(data, options))
  end

  # this method is an alternative to code_scanning_default_setup_hash to be used only
  # when the :remove_single_js_ts changeset is not active
  sig { params(data: CodeScanning::AutoCodeqlConfig, options: T.untyped).returns(T.untyped) }
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
      threat_model: data.threat_model,
      updated_at: time(data.updated_at),
      schedule: data.schedule,
    }.merge(code_scanning_runner_hash(data, options))
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

    alerts = repo_results.map(&:result)
    options[:resolvers] = get_resolvers_of_alerts(alerts)
    options[:dismissal_approvers] = get_dismissal_approvers_of_alerts(alerts)

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

  def code_scanning_alert_instance_hash(i, resolution, options = {})
    return nil unless i.present?

    if resolution != :NO_RESOLUTION
      state = "dismissed"
    elsif i.is_fixed
      state = "fixed"
    else
      state = "open"
    end

    {
      ref: i.ref_name_bytes,
      analysis_key: i.analysis_key&.analysis_key,
      environment: i.analysis_key&.environment,
      category: i.analysis_key&.category,
      state: state,
      commit_sha: i.commit_oid,
      message: {
        text: strip_placeholder_message_text_links(i.message_text),
      },
      location: code_scanning_location_hash(i.location),
      classifications: i.classification
    }
  end

  def code_scanning_alert_base_hash(data, options = {})
    return nil unless data && options[:repo]
    repo = options[:repo]

    hash = {
      number: data.number,
      created_at: time(data.created_at),
      updated_at: time(data.updated_at),
      url: url("/repos/#{repo.name_with_owner_for_api(use: options[:serialize_login])}/code-scanning/alerts/#{data.number}"),
      html_url: html_url("/#{repo.name_with_owner_for_api(use: options[:serialize_login])}/security/code-scanning/#{data.number}"),
    }

    resolver = options[:resolvers]&.key?(data.resolver_id) ? options[:resolvers][data.resolver_id] : User.find_by(id: data.resolver_id)
    dismissal_approver = options[:dismissal_approvers]&.key?(data.dismissal_approver_id) ? options[:dismissal_approvers][data.dismissal_approver_id] : User.find_by(id: data.dismissal_approver_id)

    # support old style hydro message that does not contain rule data
    rule_hash = unless data.rule.nil?
      {
        id: data.rule.sarif_identifier,
        severity: data.rule.severity.to_s.downcase,
        description: data.rule.short_description,
        name: data.rule.name,
        tags: data.rule.tags,
        full_description: data.rule.full_description,
        help: data.rule.help,
      }.tap do |h|
        h[:help_uri] = data.rule.help_uri if data.rule.help_uri.present?
        h[:security_severity_level] = data.security_severity.to_s.downcase unless data.security_severity == :NO_SECURITY_SEVERITY
      end
    end

    hash.merge(
      {
        state: if data.resolution != :NO_RESOLUTION
                 "dismissed"
               else
                 (data.is_fixed ? "fixed" : "open")
               end,
        fixed_at: data.is_fixed ? time(data.fixed_at) : nil,
        dismissed_by: user_hash(resolver, content_options(options)),
        dismissed_at: time(data.resolved_at),
        dismissed_reason: GitHub::Turboscan.api_resolution_reason(data.resolution),
        dismissed_comment: data.resolution_note.presence,
        rule: rule_hash,
        tool: code_scanning_tool_hash(data.tool, options),
        most_recent_instance: code_scanning_alert_instance_hash(data.most_recent_instance, data.resolution, options),
        instances_url: url("/repos/#{repo.name_with_owner_for_api(use: options[:serialize_login])}/code-scanning/alerts/#{data.number}/instances"),
        dismissal_approved_by: user_hash(dismissal_approver, content_options(options)),
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

  def get_dismissal_approvers_of_alerts(alerts)
    User.where(id: alerts.map(&:dismissal_approver_id).select(&:nonzero?).uniq).index_by(&:id)
  end
end
