# typed: true
# frozen_string_literal: true

require "actions-runner-admin"

class Api::OrganizationRunnerGroups < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::App::TwirpHelpers
  include Actions::RunnerGroupsHelper
  include Api::App::HostedRunnersHelper
  include NetworkConfigurationsHelper
  include Api::App::ActionsRunnersHelper

  # List runner groups
  get "/organizations/:organization_id/actions/runner-groups", operation_id: "actions/list-self-hosted-runner-groups-for-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org) && !restricted_plan_for_runner_groups?(org)

    attempt_runner_registration_login(org)

    control_access :read_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    if org.feature_enabled?(:actions_runners_use_runner_admin_service)
      runner_admin_client = GitHub.build_runner_admin_client(org)
      resp = handle_twirp_errors do
        runner_admin_client.list_runner_groups(owner: org)
      end
    else
      ensure_org_tenant!(org)

      resp = handle_twirp_errors do
        Launch::Twirp.runner_groups_client.list_groups(
          owner: org,
        )
      end
    end

    validate_runner_groups_response!(resp&.runner_groups)

    if params[:visible_to_repository].present?
      visible_to_repository = org.repositories.find_by(name: params[:visible_to_repository])
      runner_groups = paginate_rel(resp&.runner_groups.select { |runner_group| runner_group_visible_to_repo?(runner_group, visible_to_repository) })
    else
      # We map to an Array so pagination works
      runner_groups = paginate_rel(resp&.runner_groups.map { |runner_group| runner_group })
    end

    network_configurations = network_config_client.list_configurations(org, "actions") if can_view_network_configuration?(org) && org.feature_enabled?(:actions_network_configuration_api)

    deliver :actions_org_runner_groups_hash, {
      runner_groups: runner_groups,
      total_count: runner_groups.total_entries,
      org: org,
      network_configurations: network_configurations
    }
  end

  # Get a single runner group
  get "/organizations/:organization_id/actions/runner-groups/:runner_group_id", operation_id: "actions/get-self-hosted-runner-group-for-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)

    control_access :read_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    if org.feature_enabled?(:actions_runners_use_runner_admin_service)
      runner_admin_client = GitHub.build_runner_admin_client(org)
      resp = handle_twirp_errors do
        runner_admin_client.get_runner_group(owner: org, group_id: params[:runner_group_id].to_i, include_runners: false)
      end
    else
      ensure_org_tenant!(org)

      resp = handle_twirp_errors do
        Launch::Twirp.runner_groups_client.get_group(
          owner: org,
          group_id: params[:runner_group_id].to_i,
        )
      end
    end

    runner_group = resp&.runner_group
    deliver_error! 404 unless runner_group

    network_configuration = network_config_client.list_configurations(org, "actions", runner_group.id.to_s).first if can_view_network_configuration?(org) && org.feature_enabled?(:actions_network_configuration_api)

    deliver :actions_org_runner_group_hash, {
      runner_group: runner_group,
      org: org,
      network_configuration: network_configuration
    }
  end

  # Create a single runner group
  post "/organizations/:organization_id/actions/runner-groups", operation_id: "actions/create-self-hosted-runner-group-for-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)
    deliver_error! 404 unless !restricted_plan_for_runner_groups?(org)

    control_access :write_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_org_tenant!(org)

    data = receive_with_schema("organization-runner-group", "create-group")
    name = data["name"]
    runner_ids = data["runners"]
    visibility = Launch::Twirp::RunnerGroupsClient::FROM_VISIBILITY_MAP[data["visibility"]]
    selected_repository_ids = data["selected_repository_ids"]
    allow_public = data["allows_public_repositories"]
    restricted_to_workflows = data["restricted_to_workflows"]
    selected_workflow_refs = data["selected_workflows"]

    if runner_group_name_exists_in_ent?(org, name)
      deliver_error! 409, message: "Runner group #{name} already exists at the Enterprise level."
    end

    selected_workflow_refs = selected_workflow_refs&.map do |raw_pattern|
      validated_pattern = Actions::WorkflowPattern.new(raw_pattern, owner: org).tap(&:validate)
      if validated_pattern.errors.any?
        deliver_error! 400, message: validated_pattern.errors.first.message
      end
      validated_pattern.disambiguated_ref
    end

    # Don't create the group if the network configuration can't be set
    network_configuration_id = data["network_configuration_id"] if org.feature_enabled?(:actions_network_configuration_api)
    if network_configuration_id.present? && !can_edit_network_configuration?(org)
      deliver_error! 422, message: "The network configuration cannot be changed: #{edit_prevention_reason(org)}."
    end

    # Filter repositories within the organization
    org_repository_ids = org.repositories.where(id: selected_repository_ids).map(&method(:get_global_id))

    if org.feature_enabled?(:actions_runners_use_runner_admin_service)
      runner_admin_client = GitHub.build_runner_admin_client(org)
      result = handle_twirp_errors do
        runner_admin_client.add_runner_group(
          actor: current_user,
          owner: org,
          name: name,
          runner_ids: runner_ids,
          visibility: visibility,
          selected_targets: org_repository_ids,
          allow_public: allow_public,
          selected_workflow_refs: selected_workflow_refs,
          restricted_to_workflows: restricted_to_workflows,
          network_configuration_id: network_configuration_id
        )
      end
    else
      result = handle_twirp_errors do
        Launch::Twirp.runner_groups_client.create_group(
          actor: current_user,
          owner: org,
          name: name,
          runner_ids: runner_ids,
          visibility: visibility,
          selected_targets: org_repository_ids,
          allow_public: allow_public,
          restricted_to_workflows: restricted_to_workflows,
          selected_workflow_refs: selected_workflow_refs,
        )
      end
    end

    runner_group = result&.runner_group
    validate_runner_groups_response!(runner_group)

    # Write the network configuration association, pre-conditions were checked above
    if network_configuration_id.present?
      begin
        network_config_client.configure_compute_resource(org, network_configuration_id, "actions", runner_group.id.to_s, name)
        network_configuration = network_config_client.get_configuration(org, network_configuration_id)
      rescue NetworkBundle::NetworkConfigurationsException => e
        deliver_error! 422, message: "The network configuration with ID #{network_configuration_id} could not be found." if e.code == "NotFound"
        deliver_error! 422, message: "The network configuration with ID #{network_configuration_id} could not be associated with the runner group: #{e.message}."
      end
    end

    deliver :actions_org_runner_group_hash, {
      runner_group: runner_group,
      org: org,
      network_configuration: network_configuration
    }, status: 201
  end

  # Delete a runner group
  delete "/organizations/:organization_id/actions/runner-groups/:runner_group_id", operation_id: "actions/delete-self-hosted-runner-group-from-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)

    control_access :write_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_org_tenant!(org)

    runner_group_id = params[:runner_group_id].to_i
    ensure_no_runners_in_group(org, runner_group_id)

    receive_with_schema("organization-runner-group", "delete-group")

    # Delete the network configuration association first. If this fails, the runner group will still remain and the user should expect to try again.
    if can_edit_network_configuration?(org) && org.feature_enabled?(:actions_network_configuration_api)
      begin
        current_network_config = network_config_client.get_compute_resources(org, "actions", runner_group_id.to_s)
        unless current_network_config.nil?
          network_config_client.remove_network_configuration_from_runner_group(org, current_network_config.network_configuration.id, "actions", runner_group_id.to_s)
        end
      rescue NetworkBundle::NetworkConfigurationsException => e
        deliver_error! 422, message: "The network configuration could not be removed from the runner group: #{e.message}."
      end
    end

    if org.feature_enabled?(:actions_runners_use_runner_admin_service)
      runner_admin_client = GitHub.build_runner_admin_client(org)
      result = handle_twirp_errors do
        runner_admin_client.delete_runner_group(actor: current_user, owner: org, group_id: runner_group_id)
      end
    else
      result = handle_twirp_errors do
        Launch::Twirp.runner_groups_client.delete_group(
          actor: current_user,
          owner: org,
          group_id: runner_group_id,
        )
      end
    end

    deliver_error! 404 unless result
    deliver_empty status: 204
  end

  # Update a runner group
  patch "/organizations/:organization_id/actions/runner-groups/:runner_group_id", operation_id: "actions/update-self-hosted-runner-group-for-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)

    control_access :write_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_org_tenant!(org)

    data = receive_with_schema("organization-runner-group", "update-group")
    name = data["name"]
    visibility = Launch::Twirp::RunnerGroupsClient::FROM_VISIBILITY_MAP[data["visibility"]]
    allow_public = data["allows_public_repositories"]
    restricted_to_workflows = data["restricted_to_workflows"]
    selected_workflow_refs = data["selected_workflows"]
    runner_group_id = params[:runner_group_id].to_i

    runner_group = Actions::RunnerGroup.get(org, id: runner_group_id)
    if !runner_group&.inherited? && runner_group&.name != name && runner_group_name_exists_in_ent?(org, name)
      deliver_error! 409, message: "Runner group #{name} already exists at the Enterprise level."
    end

    selected_workflow_refs = selected_workflow_refs&.map do |raw_pattern|
      validated_pattern = Actions::WorkflowPattern.new(raw_pattern, owner: org).tap(&:validate)
      if validated_pattern.errors.any?
        deliver_error! 400, message: validated_pattern.errors.first.message
      end
      validated_pattern.disambiguated_ref
    end

    # Don't create the group if the network configuration can't be set
    if org.feature_enabled?(:actions_network_configuration_api) && data.key?("network_configuration_id") && !can_edit_network_configuration?(org)
      deliver_error! 422, message: "The network configuration cannot be changed: #{edit_prevention_reason(org)}."
    end

    if org.feature_enabled?(:actions_runners_use_runner_admin_service)
      runner_admin_client = GitHub.build_runner_admin_client(org)
      resp = handle_twirp_errors do
        runner_admin_client.update_runner_group(
          actor: current_user,
          owner: org,
          group_id: runner_group_id,
          name: name,
          visibility: visibility,
          allow_public: allow_public,
          selected_workflow_refs: selected_workflow_refs,
          restricted_to_workflows: restricted_to_workflows,
        )
      end
    else
      resp = handle_twirp_errors do
        Launch::Twirp.runner_groups_client.update_group(
          actor: current_user,
          owner: org,
          group_id: runner_group_id,
          name: name,
          visibility: visibility,
          allow_public: allow_public,
          restricted_to_workflows: restricted_to_workflows,
          selected_workflow_refs: selected_workflow_refs,
        )
      end
    end

    runner_group = resp&.runner_group
    deliver_error! 404 unless runner_group

    # Update the network configuration association, pre-conditions were checked above
    if data.key?("network_configuration_id")
      network_configuration_id = data["network_configuration_id"]
      if network_configuration_id.nil?
        # Remove the network configuration association
        begin
          current_network_config = network_config_client.get_compute_resources(org, "actions", runner_group_id.to_s)
          unless current_network_config.nil?
            network_config_client.remove_network_configuration_from_runner_group(org, current_network_config.network_configuration.id, "actions", runner_group_id.to_s)
          end
        rescue NetworkBundle::NetworkConfigurationsException => e
          deliver_error! 422, message: "The network configuration could not be removed from the runner group: #{e.message}."
        end
      else
        # Add/change the network configuration association
        begin
          network_config_client.configure_compute_resource(org, network_configuration_id, "actions", runner_group.id.to_s, name)
          network_configuration = network_config_client.get_configuration(org, network_configuration_id)
        rescue NetworkBundle::NetworkConfigurationsException => e
          deliver_error! 422, message: "The network configuration with ID #{network_configuration_id} could not be found." if e.code == "NotFound"
          deliver_error! 422, message: "The network configuration with ID #{network_configuration_id} could not be associated with the runner group: #{e.message}."
        end
      end
    end

    deliver :actions_org_runner_group_hash, {
      runner_group: runner_group,
      org: org,
      network_configuration: network_configuration
    }
  end

  # Get hosted runners in a runner group
  get "/organizations/:organization_id/actions/runner-groups/:runner_group_id/hosted-runners", operation_id: "actions/list-github-hosted-runners-in-group-for-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!

    control_access :read_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_tenant_and_confirm_api_enabled!(org)

    # Verify the group exists
    runner_group_id = int_id_param!(key: :runner_group_id, halt: true)
    resp = handle_twirp_errors do
      Launch::Twirp.runner_groups_client.get_group(
        owner: org,
        group_id: runner_group_id
      )
    end
    runner_group = resp&.runner_group
    deliver_error! 404 unless runner_group

    # A group either:
    # - is shared by the enterprise (is a "shadow group" and "inherited") and only has enterprise-level hosted runners in it
    #   - in this case the runner will come back with the _enterprise_ group ID (different than the one given here)
    # - is owned by the org and only has org-level hosted runners in it
    #   - in this case the runner will come back with the given group ID
    if is_group_inherited?(runner_group)
      # Get the enterprise-level runners
      deliver_error! 422 unless org.business
      resp = handle_twirp_errors do
        Launch::Twirp::larger_runners_client.list_pools(org.business, entity: org.business)
      end
      validate_runner_groups_response!(resp&.pools)
      # There won't be any inherited runners, we queried at the business/enterprise level
      pools = resp.pools
      # Use the enterprise group ID since that's what they'll come back from list_pools with (LHR service translates this)
      runner_group_id = runner_group.owner_group_id
    else
      # This call returns inherited runners with their enterprise group ID (not the "shadow group" created in the org).
      resp = handle_twirp_errors do
        Launch::Twirp::larger_runners_client.list_pools(org, entity: org)
      end
      validate_runner_groups_response!(resp&.pools)
      # Remove any inherited runners since they can't be in this group
      pools = resp.pools.reject { |runner| runner.inherited }
    end

    pools = paginate_rel(pools.filter { |runner| runner.runner_group_id == runner_group_id })

    # Load all images for the enterprise
    image_sources = pools.map { |p| p.image.source }.uniq
    images = []
    images = images.chain(Actions::Image.curated_images_for(org)) if image_sources.include?(:Curated)
    images = images.chain(Actions::Image.marketplace_images_for(org)) if image_sources.include?(:Marketplace)

    deliver :larger_runners_hash, { pools: pools, images: images }
  end

  # Get runners in a runner group
  get "/organizations/:organization_id/actions/runner-groups/:runner_group_id/runners", operation_id: "actions/list-self-hosted-runners-in-group-for-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)

    attempt_runner_registration_login(org)

    control_access :read_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    if org.feature_enabled?(:actions_runners_use_runner_admin_service)
      runner_admin_client = GitHub.build_runner_admin_client(org)
      result = runner_admin_client.list_runners_for_group(
        owner: org,
        group_id: params[:runner_group_id].to_i,
        page: pagination[:page],
        per_page: pagination[:per_page],
      )

      if result.call_succeeded?
        runners = result.value.runners

        deliver! :actions_runners_hash, {
          runners: runners,
          total_count: runners.count,
        }
      else
        deliver_error!(result.status, message: result.options[:message])
      end
    end

    ensure_org_tenant!(org)

    resp = handle_twirp_errors do
      Launch::Twirp.runner_groups_client.get_group(
        owner: org,
        group_id: params[:runner_group_id].to_i,
        include_runners: true,
      )
    end

    validate_runner_groups_response!(resp&.runner_group&.runners)

    # We map to an Array so pagination works
    runners = paginate_rel(resp&.runner_group&.runners&.map { |runner| runner })
    deliver :actions_runners_hash, { runners: runners, total_count: runners.total_entries }
  end

  # Update runners in a runner group
  put "/organizations/:organization_id/actions/runner-groups/:runner_group_id/runners", operation_id: "actions/set-self-hosted-runners-in-group-for-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)

    control_access :write_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_org_tenant!(org)

    data = receive_with_schema("organization-runner-group", "update-runners")
    runner_ids = data["runners"]

    result = handle_twirp_errors do
      ::Launch::Twirp.runner_groups_client.update_runners(
        actor: current_user,
        owner: org,
        group_id: params[:runner_group_id].to_i,
        runner_ids: runner_ids,
      )
    end

    deliver_error! 404 unless result
    deliver_empty status: 204
  end

  # Add a runner to a runner group
  put "/organizations/:organization_id/actions/runner-groups/:runner_group_id/runners/:runner_id", operation_id: "actions/add-self-hosted-runner-to-group-for-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)

    control_access :write_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_org_tenant!(org)

    receive_with_schema("organization-runner-group", "add-runner")

    result = handle_twirp_errors do
      ::Launch::Twirp.runner_groups_client.add_runners(
        actor: current_user,
        owner: org,
        group_id: params[:runner_group_id].to_i,
        runner_ids: [params[:runner_id].to_i],
      )
    end

    deliver_error! 404 unless result
    deliver_empty status: 204
  end

  # Remove a runner from a runner group
  delete "/organizations/:organization_id/actions/runner-groups/:runner_group_id/runners/:runner_id", operation_id: "actions/remove-self-hosted-runner-from-group-for-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)

    control_access :write_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_org_tenant!(org)

    receive_with_schema("organization-runner-group", "remove-runner")

    result = handle_twirp_errors do
      ::Launch::Twirp.runner_groups_client.remove_runner(
        actor: current_user,
        owner: org,
        group_id: params[:runner_group_id].to_i,
        runner_id: params[:runner_id].to_i,
      )
    end

    deliver_error! 404 unless result
    deliver_empty status: 204
  end

  # List the repositories that have access to a runner group
  get "/organizations/:organization_id/actions/runner-groups/:runner_group_id/repositories", operation_id: "actions/list-repo-access-to-self-hosted-runner-group-in-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)

    control_access :read_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_org_tenant!(org)

    resp = handle_twirp_errors do
      Launch::Twirp.runner_groups_client.get_group(
        owner: org,
        group_id: params[:runner_group_id].to_i,
      )
    end

    runner_group = resp&.runner_group
    deliver_error! 404 unless runner_group

    repository_targets = runner_group.selected_targets.map { |identity| identity.global_id }.to_set
    repository_ids = repository_targets.map { |global_id| Platform::Helpers::NodeIdentification.from_global_id(global_id)[1] }
    filtered_repositories = org.repositories.where(id: repository_ids)
    paginated_repositories = paginate_rel(filtered_repositories.sorted_by(:full_name, "asc"))

    deliver :actions_runner_group_repositories_hash, { repositories: paginated_repositories, total_count: filtered_repositories.size }
  end

  # Update repositories that have access to a runner group
  put "/organizations/:organization_id/actions/runner-groups/:runner_group_id/repositories", operation_id: "actions/set-repo-access-to-self-hosted-runner-group-in-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)

    control_access :write_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_org_tenant!(org)

    data = receive_with_schema("organization-runner-group", "set-repositories")
    selected_repository_ids = data["selected_repository_ids"]

    # Filter repositories to org repositories
    org_repository_ids = org.repositories.where(id: selected_repository_ids).map(&method(:get_global_id))

    result = handle_twirp_errors do
      ::Launch::Twirp.runner_groups_client.update_targets(
        actor: current_user,
        owner: org,
        group_id: params[:runner_group_id].to_i,
        selected_targets: org_repository_ids
      )
    end

    deliver_error! 404 unless result
    deliver_empty status: 204
  end

  # Add a repository to a runner group
  put "/organizations/:organization_id/actions/runner-groups/:runner_group_id/repositories/:repository_id", operation_id: "actions/add-repo-access-to-self-hosted-runner-group-in-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)

    control_access :write_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_org_tenant!(org)

    receive_with_schema("organization-runner-group", "add-repository")

    # Validate repository
    repo = find_repo!
    deliver_error! 422 unless repo.organization_id == org.id

    result = handle_twirp_errors do
      ::Launch::Twirp.runner_groups_client.add_target(
        actor: current_user,
        owner: org,
        group_id: params[:runner_group_id].to_i,
        selected_target: get_global_id(repo)
      )
    end

    deliver_error! 404 unless result
    deliver_empty status: 204
  end

  # Remove a repository from a runner group
  delete "/organizations/:organization_id/actions/runner-groups/:runner_group_id/repositories/:repository_id", operation_id: "actions/remove-repo-access-to-self-hosted-runner-group-in-org" do
    deliver_error! 404 unless org_runners_enabled?

    org = find_org!
    deliver_error! 404 unless can_use_org_runners?(org)

    control_access :write_org_self_hosted_runners_or_runners_and_runner_groups,
      resource: org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_RUNNERS_AND_RUNNER_GROUPS_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    ensure_org_tenant!(org)

    receive_with_schema("organization-runner-group", "remove-repository")

    # Validate repository
    repo = find_repo!
    deliver_error! 422 unless repo.organization_id == org.id

    result = handle_twirp_errors do
      Launch::Twirp.runner_groups_client.remove_target(
        actor: current_user,
        owner: org,
        group_id: params[:runner_group_id].to_i,
        selected_target: get_global_id(repo)
      )
    end

    deliver_error! 404 unless result
    deliver_empty status: 204
  end

  private

  def ensure_org_tenant!(org)
    handle_twirp_errors do
      Launch::Twirp.deployer_client.setup_tenant(org.business) if org.business
      Launch::Twirp.deployer_client.setup_tenant(org)
    end
  end

  def runner_group_visible_to_repo?(runner_group, repo)
    # repository exists
    return false unless repo

    # repo must be included in targets for select visibility
    if runner_group.visibility == Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_SELECTED
      return false unless runner_group.selected_targets.any? { |identity| identity.global_id == repo.next_global_id || identity.global_id == repo.global_relay_id }
    end

    # private repos can use any runner group
    return true unless repo.public?

    # return allow_public
    return runner_group.allow_public unless runner_group.owner_id.present? && runner_group.owner_id.global_id != ""
    runner_group.allow_public && runner_group.inherited_allow_public
  end

  def runner_group_name_exists_in_ent?(org, name)
    return false unless name
    return false unless org.business
    ent_runner_groups = Actions::RunnerGroup.for_entity(org.business)
    ent_runner_group_names = ent_runner_groups.map { |group| group.name.downcase }
    ent_runner_group_names.include? name.downcase
  end

  def is_group_inherited?(runner_group)
    runner_group.owner_id&.global_id.present?
  end
end
