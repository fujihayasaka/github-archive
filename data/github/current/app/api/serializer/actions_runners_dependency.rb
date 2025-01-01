# typed: false
# frozen_string_literal: true

module Api::Serializer::ActionsRunnersDependency
  # Creates a hash to be serialized to JSON
  #
  # data - Must be a hash with token and url keys
  #
  def actions_runner_registration_hash(data, options = {})
    hash = {
      token: data[:token],
      token_schema: data[:token_schema],
      url: data[:url]
    }

    if data[:use_v2_flow] == true
      hash[:use_v2_flow] = data[:use_v2_flow]
    end

    hash
  end

  def actions_runner_admin_registration_hash(data, options = {})

    runner = data[:runner]
    authorization = data[:authorization]

    {
      id: runner[:id],
      group_id: runner[:group_id],
      name: runner[:name],
      version: runner[:version],
      updates_disabled: runner[:updates_disabled],
      ephemeral: runner[:ephemeral],
      labels: runner[:labels],
      authorization: authorization
    }
  end

  def actions_runner_jitconfig_hash(data, options = {})
    runner_hash = actions_runner_hash(data[:runner], options)
    runner_hash[:runner_group_id] = data[:runner].runner_group_id.presence
    {
      runner: runner_hash,
      encoded_jit_config: data[:encoded_jit_config],
    }
  end

  def actions_runner_scale_set_runner_jitconfig_hash(resp, options = {})
    {
      runner: actions_runner_scale_set_runner_hash(resp.runner, options),
      encodedJitConfig: resp.encoded_jit_config,
    }
  end

  def actions_runners_hash(data, options = {})
    data[:runners] ||= []
    runner_hashes = data[:runners].map do |runner|
      actions_runner_hash(runner, options)
    end

    {
      total_count: data[:total_count],
      runners: runner_hashes,
    }
  end

  def actions_runner_hash(runner, options = {})
    payload = { id: runner.id, name: runner.name, os: runner.os, status: runner.status, busy: runner.current_parallelism != 0 || runner.assigned_request.present? }
    if GitHub.flipper[:actions_runner_include_ephemeral_flag].enabled?
      payload[:ephemeral] = runner.ephemeral
    end
    payload[:labels] = runner.labels.map do |label|
      actions_runner_label_hash(label)
    end

    payload
  end

  def actions_runner_scale_sets_hash(data, options = {})
    runner_scale_set_hashes = data.runner_scale_sets&.map do |runner_scale_set|
      actions_runner_scale_set_hash(runner_scale_set, options)
    end

    {
      count: data.count,
      value: runner_scale_set_hashes,
    }
  end

  def actions_runner_scale_set_hash(runner_scale_set, options = {})
    {
      id: runner_scale_set.id,
      name: runner_scale_set.name,
      runnerGroupId: runner_scale_set.group_id,
      labels: actions_runner_scale_set_labels_hash(runner_scale_set.labels),
    }
  end

  def actions_runner_scale_set_labels_hash(labels, options = {})
    labels&.map do |label|
      actions_runner_scale_set_label_hash(label, options)
    end
  end

  def actions_runner_scale_set_label_hash(label, options = {})
    {
      name: label.name,
    }
  end

  def actions_runner_scale_set_session_hash(session_response, options = {})
    {
      sessionId: session_response.session_id,
      ownerName: session_response.owner_name,
      runnerScaleSet: actions_runner_scale_set_hash(session_response.runner_scale_set, options),
      messageQueueAccessToken: session_response.token,
      messageQueueUrl: session_response.message_url,
      statistics: actions_runner_scale_set_statistics_hash(session_response.statistics, options),
    }
  end

  def actions_runner_scale_set_statistics_hash(statistics, options = {})
    {
      totalAvailableJobs: statistics.total_available_jobs,
      totalAcquiredJobs: statistics.total_acquired_jobs,
      totalAssignedJobs: statistics.total_assigned_jobs,
      totalRunningJobs: statistics.total_running_jobs,
      totalRegisteredRunners: statistics.total_registered_runners,
      totalBusyRunners: statistics.total_busy_runners,
      totalIdleRunners: statistics.total_idle_runners,
    }
  end

  def actions_runner_scale_set_runner_hash(runner, options = {})
    payload = { id: runner.id, name: runner.name, status: runner.status, scaleSetId: runner.scale_set_id, runnerGroupId: runner.group_id }
    if GitHub.flipper[:actions_runner_include_ephemeral_flag].enabled?
      payload[:ephemeral] = runner.ephemeral
    end
    payload
  end

  def actions_runnerpools_hash(data, options = {})
    data[:pools] ||= []
    runnerpool_hashes = data[:pools].map do |pool|
      actions_runnerpool_hash(pool, options)
    end

    {
      total_count: data[:total_count],
      pools: runnerpool_hashes,
    }
  end

  def actions_runnerpool_hash(pool, options = {})
    image_key = actions_image_key_hash(pool.image, options)
    public_ips_hash = (pool.public_ips || []).map do |public_ip|
      actions_public_ip_hash(public_ip, options)
    end

    {
      id: pool.id,
      name: pool.name,
      state: pool.state,
      platform: pool.platform,
      runner_group: pool.runner_group_id,
      labels: pool.labels,
      ephemeral: pool.ephemeral,
      runner_count: pool.runner_count,
      image: image_key,
      machine_spec_id: pool.machine_spec_id,
      public_ip_enabled: pool.public_ip_enabled,
      public_ips: public_ips_hash,
      last_active_on: pool.last_active_on,
      maximum_runners: pool.maximum_runners,
    }
  end

  def actions_public_ip_hash(public_ip, options = {})
    { enabled: public_ip.enabled, prefix: public_ip.prefix, length: public_ip.length }
  end

  def actions_image_key_hash(image_key, options = {})
    {
      source: image_key.source,
      id: image_key.id,
      version: image_key.version,
    }
  end

  LABEL_TYPE_MAPPING = {
    "user" => "custom",
    "system" => "read-only"
  }

  def actions_runner_labels_hash(data, options = {})
    data[:labels] ||= []
    runner_label_hashes = data[:labels].map do |label|
      actions_runner_label_hash(label, options)
    end
    data[:total_count] ||= runner_label_hashes.size

    {
      total_count: data[:total_count],
      labels: runner_label_hashes,
    }
  end

  def actions_runner_label_hash(label, _options = {})
    if GitHub.flipper[:actions_runner_label_remove_id].enabled?
      { name: label.name, type: LABEL_TYPE_MAPPING[label.type] }
    else
      { id: 0, name: label.name, type: LABEL_TYPE_MAPPING[label.type] }
    end
  end

  def actions_enterprise_runner_groups_hash(data, options = {})
    data[:runner_groups] ||= []
    data[:network_configurations] ||= []
    runner_group_hashes = data[:runner_groups].map do |runner_group|
      network_configuration = data[:network_configurations].find { |c| c.runner_groups.any? { |g| g["id"] == runner_group.id.to_s } }
      actions_enterprise_runner_group_hash({ runner_group: runner_group, enterprise: data[:enterprise], network_configuration: network_configuration }, options)
    end

    {
      total_count: data[:total_count],
      runner_groups: runner_group_hashes,
    }
  end

  def actions_enterprise_runner_group_hash(data, options = {})
    runner_group = data[:runner_group]
    enterprise = data[:enterprise]

    visibility = Actions::RunnerGroup.visibility_for(runner_group, enterprise)

    runner_group_hash = actions_runner_group_hash(runner_group, visibility, enterprise, options)
    return nil unless runner_group_hash

    runner_group_hash.tap do |hash|
      if visibility == Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_SELECTED
        hash[:selected_organizations_url] = url("#{enterprise_runner_group_path(enterprise, runner_group)}/organizations", options)
      end

      hash[:runners_url] = url("#{enterprise_runner_group_path(enterprise, runner_group)}/runners", options)
      if hosted_runners_api_available?(enterprise)
        hash[:hosted_runners_url] = url("#{enterprise_runner_group_path(enterprise, runner_group)}/hosted-runners", options)
      end

      network_configuration = data.fetch(:network_configuration, nil)
      hash[:network_configuration_id] = network_configuration.id if network_configuration.present?
    end
  end

  def actions_org_runner_groups_hash(data, options = {})
    data[:runner_groups] ||= []
    data[:network_configurations] ||= []
    runner_group_hashes = data[:runner_groups].map do |runner_group|
      network_configuration = data[:network_configurations].find { |c| c.runner_groups.any? { |g| g["id"] == runner_group.id.to_s } }
      actions_org_runner_group_hash({ runner_group: runner_group, org: data[:org], network_configuration: network_configuration }, options)
    end

    {
      total_count: data[:total_count],
      runner_groups: runner_group_hashes,
    }
  end

  def actions_org_runner_group_hash(data, options = {})
    runner_group = data[:runner_group]
    org = data[:org]

    runner_group_hash = actions_runner_group_hash(runner_group, runner_group.visibility, org, options)
    return nil unless runner_group_hash

    runner_group_hash.tap do |hash|
      if runner_group.visibility == Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_SELECTED
        hash[:selected_repositories_url] = url("#{org_runner_group_path(org, runner_group)}/repositories", options)
      end

      hash[:runners_url] = url("#{org_runner_group_path(org, runner_group)}/runners", options)
      if hosted_runners_api_available?(org)
        hash[:hosted_runners_url] = url("#{org_runner_group_path(org, runner_group)}/hosted-runners", options)
      end

      hash[:inherited] = runner_group.owner_id.present? && runner_group.owner_id.global_id != ""

      if runner_group.owner_id.present? && runner_group.owner_id.global_id != ""
        hash[:inherited_allows_public_repositories] = runner_group.inherited_allow_public
      end

      network_configuration = data.fetch(:network_configuration, nil)
      hash[:network_configuration_id] = network_configuration.id if network_configuration.present?
    end
  end

  def actions_runner_group_organizations_hash(data, options = {})
    organization_hashes = (data[:organizations] || []).map do |organization|
      organization_hash(organization, options)
    end

    {
      total_count: data[:total_count],
      organizations: organization_hashes
    }
  end

  def actions_runner_group_repositories_hash(data, options = {})
    repository_hashes = (data[:repositories] || []).map do |repository|
      simple_repository_hash(repository, options)
    end

    {
      total_count: data[:total_count],
      repositories: repository_hashes,
    }
  end

  def actions_runner_custom_images_hash(image, options = {})
    { id: image.id.to_i, name: image.display_name, platform: image.platform, source: image.source, versions_count: image.versions_count, total_versions_size: image.total_versions_size, latest_version: image.latest_version, state: image.state }
  end

  def actions_runner_images_hash(data, options = {})
    images_hash = (data[:images] || []).map do |image|
      actions_runner_custom_images_hash(image)
    end

    {
      total_count: images_hash.count,
      images: images_hash
    }
  end

  def actions_runner_custom_image_version_hash(image_version, options = {})
    { version: image_version.version, state: image_version.state, size_gb: image_version.size, created_on: image_version.created_on, state_details: image_version.failure_reason }
  end

  def actions_runner_custom_image_versions_hash(data, options = {})
    image_versions_hash = (data[:versions] || []).map do |image_version|
      actions_runner_custom_image_version_hash(image_version)
    end

    {
      total_count: data[:versions].count,
      image_versions: image_versions_hash,
    }
  end

  def actions_runner_ims_custom_image_version_hash(image_version, options = {})
    { version: image_version.version, state: "Ready", size_gb: image_version.size_gb, created_on: "", state_details: image_version.state_details }
  end

  def actions_runner_ims_custom_image_versions_hash(data, options = {})
    image_versions_hash = (data[:versions] || []).map do |image_version|
      actions_runner_ims_custom_image_version_hash(image_version)
    end

    {
      total_count: data[:versions].count,
      image_versions: image_versions_hash,
    }
  end

  private

  def actions_runner_group_hash(runner_group, visibility, owner, options = {})
    return nil unless runner_group

    hash = {
      id: runner_group.id,
      name: runner_group.name,
      visibility: actions_runner_group_visibility(visibility),
      allows_public_repositories: runner_group.allow_public,
      default: runner_group.is_default || runner_group.id == 1,
    }


    hash[:workflow_restrictions_read_only] = !!runner_group.workflow_restrictions_read_only
    hash[:restricted_to_workflows] = !!runner_group.restricted_to_workflows
    hash[:selected_workflows] = runner_group.selected_workflow_refs || []

    hash
  end

  def actions_runner_group_visibility(visibility)
    launch_visibility = Launch::Twirp::RunnerGroupsClient::TO_VISIBILITY_MAP[visibility]
    return launch_visibility unless launch_visibility.nil?

    ActionsRunnerAdmin::Twirp::RunnerAdminClient::TO_DISPLAY_VISIBILITY_MAP[visibility]
  end

  def actions_repo_runner_groups_hash(data, options = {})
    data[:runner_groups] ||= []
    runner_group_hashes = data[:runner_groups].map do |runner_group|
      actions_repo_runner_group_hash({ runner_group: runner_group, repo: data[:repo] }, options)
    end

    {
      total_count: data[:total_count],
      runner_groups: runner_group_hashes,
    }
  end

  def actions_repo_runner_group_hash(data, options = {})
    runner_group = data[:runner_group]
    repo = data[:repo]

    actions_runner_group_hash(runner_group, runner_group.visibility, repo, options)
  end

  def enterprise_runner_group_path(enterprise, runner_group)
    "/enterprises/#{enterprise.to_param}/actions/runner-groups/#{runner_group.id}"
  end

  def org_runner_group_path(org, runner_group)
    "/orgs/#{org.display_login}/actions/runner-groups/#{runner_group.id}"
  end

  def hosted_runners_api_available?(owner)
    GitHub.actions_larger_runners_enabled?
  end
end
