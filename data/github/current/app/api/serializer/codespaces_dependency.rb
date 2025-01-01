# typed: true
# frozen_string_literal: true

module Api::Serializer::CodespacesDependency
  extend T::Helpers

  requires_ancestor { Api::Serializer::RepositoriesDependency }

  def codespace_hash(data, options = {})
    codespace = data[:codespace]

    # If :environment is passed through directly, that indicates we need to supply connection data from it for VSCS.
    environment = data[:environment].presence || codespace.environment_data
    vscs_target = codespace.vscs_target || Codespaces::Vscs.default_target

    hash = {
      name: codespace.name,
      guid: codespace.guid,
      state: codespace.state,
      fresh_export_exists: codespace.fresh_export_exists?,
      url: url("/vscs_internal/user/#{codespace.owner.login_for_api(use: options[:serialize_login])}/codespaces/#{codespace.name}"),
      token_url: url("/vscs_internal/user/#{codespace.owner.login_for_api(use: options[:serialize_login])}/codespaces/#{codespace.name}/token")
    }

    if vscs_target != :production
      hash[:vscs_target] = vscs_target
    end

    if codespace.vscs_target_url.present?
      hash[:vscs_target_url] = codespace.vscs_target_url
    else
      hash[:vscs_target_url] = Codespaces::Vscs.config_for_target(vscs_target)[:api_url]
    end

    hash[:devcontainer_path] = codespace.devcontainer_path

    hash.merge(
      last_used_at: codespace.last_used_at&.iso8601,
      created_at: codespace.created_at.iso8601,
      branch: codespace.display_branch,
      owner_login: codespace.owner.login_for_api(use: options[:serialize_login]),
      owner_display_name: codespace.owner.profile_name,
      billable_owner_login: codespace.billable_owner.login_for_api(use: options[:serialize_login]),
      billable_owner_display_name: codespace.billable_owner.profile_name,
      repository_name: codespace.repository.name,
      repository_owner: codespace.repository.owner.login_for_api(use: options[:serialize_login]),
      repository_nwo: codespace.repository.name_with_owner_for_api(use: options[:serialize_login]),
      sku_name: codespace.sku_name, # TODO: Rename this for public API. Name TBD.
      environment: environment,
      environment_data_updated_at: codespace.environment_data_updated_at&.iso8601
    )
  end

  def public_codespace_hash(data, options = {})
    options[:global_id_selection] ||= { user_preference: false, user_opt_out: false }

    codespace = data[:codespace]

    machine = Codespaces::Skus.sku_by_name(codespace.sku_name)
    codespace_api_path = "/user/codespaces/#{codespace.name}"
    repo_path = repo_path(options, codespace)

    hash = {
      id: codespace.id,
      name: codespace.name,
      environment_id: codespace.guid,
      owner: simple_user_hash(codespace.owner, global_id_selection: options[:global_id_selection]),
      billable_owner: simple_user_hash(codespace.billable_owner, global_id_selection: options[:global_id_selection]),
      repository: simple_repository_hash(codespace.repository, global_id_selection: options[:global_id_selection]),
      machine: machine ? machine_hash({ machine: machine }) : nil,
      prebuild: codespace.environment_data&.create_from_prebuild,
      created_at: codespace.created_at&.iso8601,
      updated_at: codespace.updated_at&.iso8601,
      last_used_at: codespace.last_used_at&.iso8601 || codespace.updated_at&.iso8601,
      state: codespace.environment_data&.state || Codespaces::Vscs::State::UNKNOWN,
      url: url(codespace_api_path),
      git_status: {
        ahead: codespace.commits_ahead || 0,
        behind: codespace.commits_behind || 0,
        has_unpushed_changes: !!codespace.has_unpushed_changes?,
        has_uncommitted_changes: !!codespace.has_uncommitted_changes?,
        ref: codespace.display_branch,
      },
      location: codespace.location,
      idle_timeout_minutes: codespace.environment_data&.auto_shutdown_delay_minutes,
      web_url: codespace.web_portal_url,
      machines_url: url("#{codespace_api_path}/machines"),
      start_url: url("#{codespace_api_path}/start"),
      stop_url: url("#{codespace_api_path}/stop"),
      pulls_url: (codespace.pull_request ? url("/repos/#{repo_path}/pulls/#{codespace.pull_request.number}") : nil),
      recent_folders: Array(codespace.environment_data&.recent_folders),
      runtime_constraints: {
        allowed_port_privacy_settings: (codespace.allowed_port_privacy_settings ? Array(codespace.allowed_port_privacy_settings) : nil),
      },
    }

    hash[:connection] = data[:connection] if data[:connection]
    hash[:test_account] = true if codespace.owner.feature_enabled?(:codespaces_automated_testing)
    hash[:container_id] = data[:container_id] if data[:container_id]
    hash[:display_name] = codespace.display_name
    hash[:devcontainer_path] = codespace.devcontainer_path
    hash[:pending_operation] = codespace.blocking_operation?
    hash[:pending_operation_disabled_reason] = codespace.blocking_operation_disabled_text if codespace.blocking_operation?
    hash[:feature_flags] = data[:feature_flags] if data[:feature_flags]
    hash[:failure_reason] = codespace.user_controlled_failure_reason if codespace.user_controlled_failure_reason.present?

    hash[:retention_period_minutes] = codespace.retention_period_minutes
    hash[:retention_expires_at] = codespace.retention_expires_at&.iso8601
    hash[:using_copilot_workspace_config] = codespace.using_copilot_workspace_config if codespace.using_copilot_workspace_config.present?

    if data[:last_known_stop_notice]
      hash[:last_known_stop_notice] = data[:last_known_stop_notice]
    end

    if codespace.auto_push?
      hash[:git_status][:auto_push] = !!codespace.auto_push?
    end

    if Codespaces::MaximumRetentionPeriodPolicy.return_retention_period_notice?(codespace.billable_owner, codespace.id)
      hash[:retention_period_notice] = Codespaces::MaximumRetentionPeriodPolicy.retention_period_notice(codespace.retention_period_minutes)
    end

    if Codespaces::MaximumIdleTimeoutPolicy.return_idle_timeout_notice?(codespace.billable_owner, codespace.id)
      hash[:idle_timeout_notice] = Codespaces::MaximumIdleTimeoutPolicy.idle_timeout_notice(codespace.environment_data.auto_shutdown_delay_minutes)
    end

    if options[:private] # The codespaces_developer is enabled for the viewing user. We use this field because Api::SerializerOptions is picky
      vscs_target = codespace.vscs_target || Codespaces::Vscs.default_target
      hash[:vscs_target] = vscs_target

      if codespace.vscs_target_url.present?
        hash[:vscs_target_url] = codespace.vscs_target_url
      else
        hash[:vscs_target_url] = Codespaces::Vscs.config_for_target(vscs_target)[:api_url]
      end

      hash[:region] = codespace.location
    end

    if codespace.unpublished?
      hash.merge!(
        template: codespace_template_hash(codespace, options),
        publish_url: url("#{codespace_api_path}/publish")
      )
    else
      hash.merge!(template: nil, publish_url: nil)
    end

    hash
  end

  def public_codespace_hash_with_full_repository(data, options = {})
    hash = public_codespace_hash(data, options)
    hash[:repository] = full_repository_hash(data[:codespace].repository, global_id_selection: options[:global_id_selection])
    hash
  end

  def codespace_hash_with_connection(data, options = {})
    codespace_hash(data, options).merge(connection: data[:connection])
  end

  def codespaces_hash(data, options = {})
    codespaces = data[:codespaces]
    total_count = data[:total_count]
    hashed_codespaces = codespaces.map { |c| codespace_hash({ codespace: c }, options) }
    {
      codespaces: hashed_codespaces,
      total_count: total_count,
    }
  end

  def public_codespaces_hash(data, options = {})
    codespaces = data[:codespaces]
    total_count = data[:total_count]

    hashed_codespaces = codespaces.map { |c| public_codespace_hash({ codespace: c }, options) }
    hash = {
      codespaces: hashed_codespaces,
      total_count: total_count,
    }
    hash[:feature_flags] = data[:feature_flags] if data[:feature_flags]
    hash
  end

  def codespaces_billing_policy(data, options = {})
    {
      visibility: data.fetch(:visibility),
    }.tap do |hash|
      if data.fetch(:visibility) == Api::Codespaces::Organization::SELECTED_MEMBERS
        hash[:selected_usernames] = data.fetch(:selected_usernames)
      end
    end
  end

  def user_skus(data, options = {})
    {
      skus: data[:skus].map do |sku|
        {
          name: sku.name,
          display_name: sku.display_name,
          operating_system: sku.operating_system,
          prebuild_availability: sku.prebuild_availability,
        }
      end,
      error: data[:error]
    }
  end

  def machine_hash(data, options = {})
    machine = data[:machine]
    {
      name: machine.name,
      display_name: machine.display_name,
      operating_system: machine.operating_system,
      storage_in_bytes: machine.storage,
      memory_in_bytes: machine.memory,
      cpus: machine.cpus,
      prebuild_availability: machine.prebuild_availability,
    }
  end

  def machines_hash(data, options = {})
    machines = data[:machines]
    total_count = data[:total_count]
    machines_hash = machines.map { |m| machine_hash({ machine: m }, options) }
    {
      machines: machines_hash,
      total_count: total_count,
    }
  end

  def devcontainer_hash(data, options = {})
    devcontainer = data[:devcontainer]
    {
      path: devcontainer.path,
      name: devcontainer.name.presence,
      display_name: devcontainer.display_name
    }.compact
  end

  def devcontainers_hash(data, options = {})
    devcontainers = data[:devcontainers]
    total_count = data[:total_count]

    devcontainers_hash = devcontainers.map { |d| devcontainer_hash({ devcontainer: d }, options) }
    {
      devcontainers: devcontainers_hash,
      total_count: total_count,
    }
  end

  def codespace_fork_repo_result(data, options = {})
    forked_repo = data[:forked_repo]
    ref = data[:ref]

    {
      repository: full_repository_hash(forked_repo, options),
      ref: ref
    }
  end

  def prebuild_hash_simple(prebuild, options = {})
    hash = {
      id: prebuild.id,
      state: prebuild.state,
      oid: prebuild.oid,
      location: prebuild.location,
      sku_name: prebuild.sku_name,
      created_at: prebuild.created_at.iso8601,
    }

    vscs_target = prebuild.vscs_target || Codespaces::Vscs.default_target
    if vscs_target != :production
      hash[:vscs_target] = vscs_target
    end

    if prebuild.vscs_target_url.present?
      hash[:vscs_target_url] = prebuild.vscs_target_url
    else
      hash[:vscs_target_url] = Codespaces::Vscs.config_for_target(vscs_target)[:api_url]
    end

    hash
  end

  def export_details_hash(data, options = {})
    codespace = data[:codespace]
    codespace_api_path = "/user/codespaces/#{codespace.name}"
    {
      state: codespace.export_state,
      completed_at: (get_export_data_on_success codespace.last_export_end_at, codespace.export_state),
      branch: (get_export_data_on_success codespace.export_branch_name, codespace.export_state),
      sha: (get_export_data_on_success codespace.export_sha, codespace.export_state),
      id: "latest",
      export_url: url("#{codespace_api_path}/exports/latest"),
      html_url: codespace.export_branch_exists? ? encoded_html_url("#{GitHub.url}/#{codespace.repository.name_with_owner_for_api(use: options[:serialize_login])}/tree/", codespace.export_branch_name) : nil,
    }
  end

  def accept_permissions_hash(data, options = {})
    repo = data[:repo]
    ref = data[:ref]
    devcontainer_path = data[:devcontainer_path]

    allow_permissions_url = "#{GitHub.url}/#{repo.name_with_owner_for_api(use: options[:serialize_login])}/codespaces/allow_permissions?ref=#{ref}"
    allow_permissions_url += "&devcontainer_path=#{devcontainer_path}" if devcontainer_path

    {
      message: "The codespace is requesting updated permissions. Please visit '#{allow_permissions_url}' to review and authorize the request.",
      allow_permissions_url: allow_permissions_url,
    }
  end

  def codespace_template_hash(codespace, options = {})
    return nil unless template = codespace.template

    # We don't need the repository_nwo from the constant in the base template object because we actually wind up
    # nesting the template's repository inside the template object itself.
    hash = template.slice(:name, :language, :description, :author, :icon, :icon_path)
    hash[:repository] = simple_repository_hash(codespace.template_repository, global_id_selection: options[:global_id_selection])
    hash
  end

  def get_export_data_on_success(data, export_state)
    if export_state == Codespace::EXPORT_STATE_SUCCEEDED
      data
    end
  end

  def codespaces_pre_flight_hash(data, options = {})
    {
      billable_owner: simple_user_hash(data[:billable_owner], global_id_selection: options[:global_id_selection]),
      defaults: data[:defaults]
    }
  end

  def codespaces_permissions_check_hash(data, options = {})
    {
      accepted: data[:accepted]
    }
  end

  def settings_sync_hash(data, options = {})
    options[:user] = data[:current_user]
    response = oauth_access_hash(data[:current_user].oauth_access, options)
    response[:scopes] = data[:scopes]
    response.delete(:scopes) if data[:scopes].nil?
    response
  end
end
