# typed: false
# frozen_string_literal: true

class Api::EnterpriseRunnerGroups < Api::Enterprise::App
  include Api::App::TwirpHelpers
  include Api::App::HostedRunnersHelper
  include NetworkConfigurationsHelper
  include Api::App::ActionsRunnersHelper

  # List runner groups
  get "/enterprises/:enterprise_id/actions/runner-groups", operation_id: "enterprise-admin/list-self-hosted-runner-groups-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)

    attempt_runner_registration_login(enterprise)

    control_access :read_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant!(enterprise)

    if enterprise.feature_enabled?(:actions_runners_use_runner_admin_service)
      runner_admin_client = GitHub.build_runner_admin_client(enterprise)
      resp = handle_twirp_errors do
        runner_admin_client.list_runner_groups(owner: enterprise)
      end
    else
      resp = handle_twirp_errors do
        Launch::Twirp.runner_groups_client.list_groups(
          owner: enterprise,
        )
      end
    end

    validate_runner_groups_response!(resp&.runner_groups)

    if params[:visible_to_organization].present?
      visible_to_organization = enterprise.organizations.find_by_login(params[:visible_to_organization])
      # We map to an Array so pagination works
      runner_groups = paginate_rel(resp&.runner_groups.select { |runner_group| runner_group_visible_to_org?(runner_group, visible_to_organization) })
    else
      # We map to an Array so pagination works
      runner_groups = paginate_rel(resp&.runner_groups.map { |runner_group| runner_group })
    end

    network_configurations = network_config_client.list_configurations(enterprise, "actions") if can_view_network_configuration?(enterprise) && enterprise.feature_enabled?(:actions_network_configuration_api)

    deliver :actions_enterprise_runner_groups_hash, {
      runner_groups: runner_groups,
      total_count: runner_groups.total_entries,
      enterprise: enterprise,
      network_configurations: network_configurations,
    }
  end

  # Get a single runner group
  get "/enterprises/:enterprise_id/actions/runner-groups/:runner_group_id", operation_id: "enterprise-admin/get-self-hosted-runner-group-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)

    control_access :read_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant!(enterprise)

    if enterprise.feature_enabled?(:actions_runners_use_runner_admin_service)
      runner_admin_client = GitHub.build_runner_admin_client(enterprise)
      resp = handle_twirp_errors do
        runner_admin_client.get_runner_group(owner: enterprise, group_id: params[:runner_group_id].to_i)
      end
    else
      resp = handle_twirp_errors do
        Launch::Twirp.runner_groups_client.get_group(
          owner: enterprise,
          group_id: params[:runner_group_id].to_i,
        )
      end
    end

    runner_group = resp&.runner_group
    deliver_error! 404 unless runner_group

    network_configuration = network_config_client.list_configurations(enterprise, "actions", runner_group.id.to_s).first if can_view_network_configuration?(enterprise) && enterprise.feature_enabled?(:actions_network_configuration_api)

    deliver :actions_enterprise_runner_group_hash, {
      runner_group: runner_group,
      enterprise: enterprise,
      network_configuration: network_configuration
    }
  end

  # Create a runner group
  post "/enterprises/:enterprise_id/actions/runner-groups", operation_id: "enterprise-admin/create-self-hosted-runner-group-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)

    control_access :write_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant!(enterprise)

    data = receive_with_schema("enterprise-runner-group", "create-group")
    name = data["name"]
    runner_ids = data["runners"]
    visibility = Launch::Twirp::RunnerGroupsClient::FROM_VISIBILITY_MAP[data["visibility"]]
    selected_organization_ids = data["selected_organization_ids"]
    allow_public = data["allows_public_repositories"]
    restricted_to_workflows = data["restricted_to_workflows"]
    selected_workflow_refs = data["selected_workflows"]

    selected_workflow_refs = selected_workflow_refs&.map do |raw_pattern|
      validated_pattern = Actions::WorkflowPattern.new(raw_pattern, owner: enterprise).tap(&:validate)
      if validated_pattern.errors.any?
        deliver_error! 400, message: validated_pattern.errors.first.message
      end
      validated_pattern.disambiguated_ref
    end

    # Don't create the group if the network configuration can't be set
    network_configuration_id = data["network_configuration_id"] if enterprise.feature_enabled?(:actions_network_configuration_api)
    if network_configuration_id.present? && !can_edit_network_configuration?(enterprise)
      deliver_error! 422, message: "The network configuration cannot be changed: #{edit_prevention_reason(enterprise)}."
    end

    # Filter organizations within the enterprise
    enterprise_org_ids = enterprise.organizations.where(id: selected_organization_ids).map(&method(:get_global_id))

    if enterprise.feature_enabled?(:actions_runners_use_runner_admin_service)
      runner_admin_client = GitHub.build_runner_admin_client(enterprise)
      result = handle_twirp_errors do
        runner_admin_client.add_runner_group(
          actor: current_user,
          owner: enterprise,
          name: name,
          runner_ids: runner_ids,
          visibility: visibility,
          selected_targets: enterprise_org_ids,
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
          owner: enterprise,
          name: name,
          runner_ids: runner_ids,
          visibility: visibility,
          selected_targets: enterprise_org_ids,
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
        network_config_client.configure_compute_resource(enterprise, network_configuration_id, "actions", runner_group.id.to_s, name)
        network_configuration = network_config_client.get_configuration(enterprise, network_configuration_id)
      rescue NetworkBundle::NetworkConfigurationsException => e
        deliver_error! 422, message: "The network configuration with ID #{network_configuration_id} could not be found." if e.code == "NotFound"
        deliver_error! 422, message: "The network configuration with ID #{network_configuration_id} could not be associated with the runner group: #{e.message}."
      end
    end

    deliver :actions_enterprise_runner_group_hash, {
      runner_group: runner_group,
      enterprise: enterprise,
      network_configuration: network_configuration,
    }, status: 201
  end

  # Delete a runner group
  delete "/enterprises/:enterprise_id/actions/runner-groups/:runner_group_id", operation_id: "enterprise-admin/delete-self-hosted-runner-group-from-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)

    control_access :write_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant!(enterprise)

    runner_group_id = params[:runner_group_id].to_i
    ensure_no_runners_in_group(enterprise, runner_group_id)

    receive_with_schema("enterprise-runner-group", "delete-group")

    # Delete the network configuration association first. If this fails, the runner group will still remain and the user should expect to try again.
    if can_edit_network_configuration?(enterprise) && enterprise.feature_enabled?(:actions_network_configuration_api)
      begin
        current_network_config = network_config_client.get_compute_resources(enterprise, "actions", runner_group_id.to_s)
        unless current_network_config.nil?
          network_config_client.remove_network_configuration_from_runner_group(enterprise, current_network_config.network_configuration.id, "actions", runner_group_id.to_s)
        end
      rescue NetworkBundle::NetworkConfigurationsException => e
        deliver_error! 422, message: "The network configuration could not be removed from the runner group: #{e.message}."
      end
    end

    if enterprise.feature_enabled?(:actions_runners_use_runner_admin_service)
      runner_admin_client = GitHub.build_runner_admin_client(enterprise)
      result = handle_twirp_errors do
        runner_admin_client.delete_runner_group(actor: current_user, owner: enterprise, group_id: runner_group_id)
      end
    else
      result = handle_twirp_errors do
        Launch::Twirp.runner_groups_client.delete_group(
          actor: current_user,
          owner: enterprise,
          group_id: runner_group_id,
        )
      end
    end

    deliver_error! 404 unless result
    deliver_empty status: 204
  end

  # Update a runner group
  patch "/enterprises/:enterprise_id/actions/runner-groups/:runner_group_id", operation_id: "enterprise-admin/update-self-hosted-runner-group-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)

    control_access :write_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant!(enterprise)

    data = receive_with_schema("enterprise-runner-group", "update-group")
    name = data["name"]
    visibility = Launch::Twirp::RunnerGroupsClient::FROM_VISIBILITY_MAP[data["visibility"]]
    allow_public = data["allows_public_repositories"]
    restricted_to_workflows = data["restricted_to_workflows"]
    selected_workflow_refs = data["selected_workflows"]
    runner_group_id = params[:runner_group_id].to_i

    selected_workflow_refs = selected_workflow_refs&.map do |raw_pattern|
      validated_pattern = Actions::WorkflowPattern.new(raw_pattern, owner: enterprise).tap(&:validate)
      if validated_pattern.errors.any?
        deliver_error! 400, message: validated_pattern.errors.first.message
      end
      validated_pattern.disambiguated_ref
    end

    # Don't update the group if the network configuration can't be set
    network_configuration_id = data["network_configuration_id"] if enterprise.feature_enabled?(:actions_network_configuration_api)
    if network_configuration_id.present? && !can_edit_network_configuration?(enterprise)
      deliver_error! 422, message: "The network configuration cannot be changed: #{edit_prevention_reason(enterprise)}."
    end

    if enterprise.feature_enabled?(:actions_runners_use_runner_admin_service)
      runner_admin_client = GitHub.build_runner_admin_client(enterprise)
      resp = handle_twirp_errors do
        runner_admin_client.update_runner_group(
          actor: current_user,
          owner: enterprise,
          group_id: runner_group_id,
          name: name,
          visibility: visibility,
          allow_public: allow_public,
          selected_workflow_refs: selected_workflow_refs,
          restricted_to_workflows: restricted_to_workflows,
          network_configuration_id: network_configuration_id
        )
      end
    else
      resp = handle_twirp_errors do
        Launch::Twirp.runner_groups_client.update_group(
          actor: current_user,
          owner: enterprise,
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
          current_network_config = network_config_client.get_compute_resources(enterprise, "actions", runner_group_id.to_s)
          unless current_network_config.nil?
            network_config_client.remove_network_configuration_from_runner_group(enterprise, current_network_config.network_configuration.id, "actions", runner_group_id.to_s)
          end
        rescue NetworkBundle::NetworkConfigurationsException => e
          deliver_error! 422, message: "The network configuration could not be removed from the runner group: #{e.message}."
        end
      else
        # Add/change the network configuration association
        begin
          network_config_client.configure_compute_resource(enterprise, network_configuration_id, "actions", runner_group.id.to_s, name)
          network_configuration = network_config_client.get_configuration(enterprise, network_configuration_id)
        rescue NetworkBundle::NetworkConfigurationsException => e
          deliver_error! 422, message: "The network configuration with ID #{network_configuration_id} could not be found." if e.code == "NotFound"
          deliver_error! 422, message: "The network configuration with ID #{network_configuration_id} could not be associated with the runner group: #{e.message}."
        end
      end
    end

    deliver :actions_enterprise_runner_group_hash, {
      runner_group: runner_group,
      enterprise: enterprise,
      network_configuration: network_configuration,
    }
  end

  # Get hosted runners in a runner group
  get "/enterprises/:enterprise_id/actions/runner-groups/:runner_group_id/hosted-runners", operation_id: "enterprise-admin/list-github-hosted-runners-in-group-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)

    control_access :read_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant_and_confirm_api_enabled!(enterprise)

    # Verify the group exists
    resp = handle_twirp_errors do
      Launch::Twirp.runner_groups_client.get_group(
        owner: enterprise,
        group_id: int_id_param!(key: :runner_group_id, halt: true)
      )
    end
    runner_group = resp&.runner_group
    deliver_error! 404 unless runner_group

    resp = handle_twirp_errors do
      Launch::Twirp::larger_runners_client.list_pools(enterprise, entity: enterprise)
    end

    validate_runner_groups_response!(resp&.pools)

    # We map to an Array so pagination works
    pools = paginate_rel(resp&.pools.filter { |runner| runner.runner_group_id == runner_group.id })

    # Load all images for the enterprise
    image_sources = pools.map { |p| p.image.source }.uniq
    images = []
    images = images.chain(Actions::Image.curated_images_for(enterprise)) if image_sources.include?(:Curated)
    images = images.chain(Actions::Image.marketplace_images_for(enterprise)) if image_sources.include?(:Marketplace)

    deliver :larger_runners_hash, { pools: pools, images: images }
  end

  # Get runners in a runner group
  get "/enterprises/:enterprise_id/actions/runner-groups/:runner_group_id/runners", operation_id: "enterprise-admin/list-self-hosted-runners-in-group-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)

    control_access :read_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant!(enterprise)

    resp = handle_twirp_errors do
      Launch::Twirp.runner_groups_client.get_group(
        owner: enterprise,
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
  put "/enterprises/:enterprise_id/actions/runner-groups/:runner_group_id/runners", operation_id: "enterprise-admin/set-self-hosted-runners-in-group-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)

    control_access :write_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant!(enterprise)

    data = receive_with_schema("enterprise-runner-group", "update-runners")
    runner_ids = data["runners"]

    result = handle_twirp_errors do
      ::Launch::Twirp.runner_groups_client.update_runners(
        actor: current_user,
        owner: enterprise,
        group_id: params[:runner_group_id].to_i,
        runner_ids: runner_ids,
      )
    end

    deliver_error! 404 unless result
    deliver_empty status: 204
  end

  # Add a runner to a runner group
  put "/enterprises/:enterprise_id/actions/runner-groups/:runner_group_id/runners/:runner_id", operation_id: "enterprise-admin/add-self-hosted-runner-to-group-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)

    control_access :write_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant!(enterprise)

    receive_with_schema("enterprise-runner-group", "add-runner")

    result = handle_twirp_errors do
      ::Launch::Twirp.runner_groups_client.add_runners(
        actor: current_user,
        owner: enterprise,
        group_id: params[:runner_group_id].to_i,
        runner_ids: [params[:runner_id].to_i],
      )
    end

    deliver_error! 404 unless result
    deliver_empty status: 204
  end

  # Remove a runner from a runner group
  delete "/enterprises/:enterprise_id/actions/runner-groups/:runner_group_id/runners/:runner_id", operation_id: "enterprise-admin/remove-self-hosted-runner-from-group-for-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)

    control_access :write_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant!(enterprise)

    receive_with_schema("enterprise-runner-group", "remove-runner")

    result = handle_twirp_errors do
      ::Launch::Twirp.runner_groups_client.remove_runner(
        actor: current_user,
        owner: enterprise,
        group_id: params[:runner_group_id].to_i,
        runner_id: params[:runner_id].to_i,
      )
    end

    deliver_error! 404 unless result
    deliver_empty status: 204
  end

  # List the organizations that have access to a runner group
  get "/enterprises/:enterprise_id/actions/runner-groups/:runner_group_id/organizations", operation_id: "enterprise-admin/list-org-access-to-self-hosted-runner-group-in-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)

    control_access :read_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant!(enterprise)

    resp = handle_twirp_errors do
      Launch::Twirp.runner_groups_client.get_group(
        owner: enterprise,
        group_id: params[:runner_group_id].to_i,
      )
    end

    runner_group = resp&.runner_group
    deliver_error! 404 unless runner_group

    organization_targets = runner_group.selected_targets.map { |identity| identity.global_id }.to_set
    organization_ids = organization_targets.map { |global_id| Platform::Helpers::NodeIdentification.from_global_id(global_id)[1] }
    filtered_organizations = enterprise.organizations.where(id: organization_ids).order(:login)
    paginated_organizations = paginate_rel(filtered_organizations)

    deliver :actions_runner_group_organizations_hash, { organizations: paginated_organizations, total_count: filtered_organizations.size }
  end

  # Update organizations that have access to a runner group
  put "/enterprises/:enterprise_id/actions/runner-groups/:runner_group_id/organizations", operation_id: "enterprise-admin/set-org-access-to-self-hosted-runner-group-in-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)

    control_access :write_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant!(enterprise)

    data = receive_with_schema("enterprise-runner-group", "set-organizations")

    selected_organization_ids = data["selected_organization_ids"]

    # Filter organizations within the enterprise
    enterprise_org_ids = enterprise.organizations.where(id: selected_organization_ids).map(&method(:get_global_id))

    result = handle_twirp_errors do
      ::Launch::Twirp.runner_groups_client.update_targets(
        actor: current_user,
        owner: enterprise,
        group_id: params[:runner_group_id].to_i,
        selected_targets: enterprise_org_ids
      )
    end

    deliver_error! 404 unless result
    deliver_empty status: 204
  end

  # Add an organization to a runner group
  put "/enterprises/:enterprise_id/actions/runner-groups/:runner_group_id/organizations/:organization_id", operation_id: "enterprise-admin/add-org-access-to-self-hosted-runner-group-in-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)

    control_access :write_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant!(enterprise)

    receive_with_schema("enterprise-runner-group", "add-organization")

    org = find_org_by_parameter
    deliver_error! 404 unless org
    deliver_error! 422 unless org.business&.id == enterprise.id

    result = handle_twirp_errors do
      ::Launch::Twirp.runner_groups_client.add_target(
        actor: current_user,
        owner: enterprise,
        group_id: params[:runner_group_id].to_i,
        selected_target: get_global_id(org)
      )
    end

    deliver_error! 404 unless result
    deliver_empty status: 204
  end

  # Remove an organization from a runner group
  delete "/enterprises/:enterprise_id/actions/runner-groups/:runner_group_id/organizations/:organization_id", operation_id: "enterprise-admin/remove-org-access-to-self-hosted-runner-group-in-enterprise" do
    enterprise = find_enterprise!
    deliver_error! 404 unless enterprise_runners_enabled?(enterprise)

    control_access :write_enterprise_self_hosted_runners,
      resource: enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    ensure_tenant!(enterprise)

    receive_with_schema("enterprise-runner-group", "remove-organization")

    org = find_org_by_parameter
    deliver_error! 404 unless org
    deliver_error! 422 unless org.business&.id == enterprise.id

    result = handle_twirp_errors do
      Launch::Twirp.runner_groups_client.remove_target(
        actor: current_user,
        owner: enterprise,
        group_id: params[:runner_group_id].to_i,
        selected_target: get_global_id(org)
      )
    end

    deliver_error! 404 unless result
    deliver_empty status: 204
  end

  private

  # The standard find_org! resolves the current user from the environment first
  # This will resolve to the enterprise, resulting in find_org_by_id returning nil
  def find_org_by_parameter
    if (id = params[:organization_id])
      Organization.find_by_id(id.to_i)
    else
      nil
    end
  end

  def runner_group_visible_to_org?(runner_group, org)
    # org exists
    return false unless org

    # org must be included in targets for select visibility
    if runner_group.visibility == Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_SELECTED
      return false unless runner_group.selected_targets.any? { |identity| identity.global_id == org.next_global_id || identity.global_id == org.global_relay_id }
    end

    # org can use any runner group
    true
  end
end
