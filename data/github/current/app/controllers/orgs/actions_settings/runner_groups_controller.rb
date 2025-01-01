# typed: true
# frozen_string_literal: true

class Orgs::ActionsSettings::RunnerGroupsController < Orgs::Controller

  include Actions::RunnersHelper
  include Actions::RunnerGroupsHelper
  include Actions::LargerRunnersHelper
  include NetworkBundle
  include ApplicationController::VerifiedFetchDependency
  include NetworkConfigurationsHelper

  before_action :login_required
  before_action :ensure_user_has_runners_and_runner_groups_access
  before_action :ensure_actions_enabled
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :ensure_can_use_org_runners
  before_action :ensure_tenant_exists
  before_action :ensure_can_create_runner_groups, only: [:create, :new]
  before_action :validate_selected_workflow_refs, only: [:create, :update]
  before_action :sudo_filter, only: [:destroy]
  allow_verified_fetch only: [:create, :update]

  javascript_bundle :settings

  sig { returns(String) }
  def self.react_bundle_name
    "network-configurations-select-panel"
  end

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:edit],
    optional: true

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:show_menu]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show_selected_targets]

  def index
    page = (params.fetch(:page) { 1 }).to_i
    enterprise_page = (params.fetch(:enterprise_page) { 1 }).to_i
    per_page = (params.fetch(:per_page) { 25 }).to_i

    force_launch = should_force_launch?(owner: current_organization, params: params)

    runner_groups = Actions::RunnerGroup.for_entity(current_organization, include_runners: true, include_runner_scale_sets: true, is_ui_read: true, force_launch: force_launch)
    runner_groups = runner_groups.select { |group| group.name.downcase.include?(params[:qr].downcase) } if params[:qr].present?
    org_groups = []
    inherited_groups = []
    runner_groups.each do |group|
      if group.inherited?
        inherited_groups.push(group)
      else
        org_groups.push(group)
      end
    end

    org_groups = org_groups.sort

    if current_organization.can_use_larger_runners?
      larger_runners = Actions::LargerRunner.larger_runners_for(entity: current_organization)
      larger_runners.each do |larger_runner|
        group = nil
        if larger_runner.inherited
          group = inherited_groups.detect do |runner_group|
            runner_group.id == larger_runner.runner_group_id
          end
        else
          group = org_groups.detect do |runner_group|
            runner_group.id == larger_runner.runner_group_id
          end
        end

        if group.present?
          group.runners.append(larger_runner)
        end
      end
    end

    # list the runner groups in this org whose network configurations are disabled
    disabled_runner_group_ids = begin
      can_view_network_configuration?(current_organization) ? list_disabled_network_configuration_ids(current_organization) : []
    rescue => e
      Failbot.report(e, context: { org_id: current_organization.id, action: "list_disabled_network_configuration_ids" })
      []
    end

    # list the runner groups in this org's enterprise whose network configurations are disabled
    disabled_owner_runner_group_ids = can_view_network_configuration?(current_organization) && current_organization.business.present? ? list_disabled_network_configuration_ids(current_organization.business) : []

    paginated_runner_groups = WillPaginate::Collection.create(page, per_page) do |group|
      group.replace(org_groups[((page - 1) * per_page), per_page] || [])
      group.total_entries = org_groups.length
    end

    paginated_inherited_runner_groups = WillPaginate::Collection.create(enterprise_page, per_page) do |group|
      group.replace(inherited_groups[((enterprise_page - 1) * per_page), per_page] || [])
      group.total_entries = inherited_groups.length
    end

    render "settings/organization/actions/runner_groups", locals: {
      runner_groups: paginated_runner_groups,
      inherited_runner_groups: paginated_inherited_runner_groups,
      restricted_plan: restricted_plan_for_runner_groups?(current_organization),
      disabled_runner_group_ids: disabled_runner_group_ids,
      disabled_owner_runner_group_ids: disabled_owner_runner_group_ids
    }
  end

  def edit
    runner_group_id = params[:id]&.to_i
    force_launch = should_force_launch?(owner: current_organization, params: params)

    runner_group = Actions::RunnerGroup.get(current_organization, id: runner_group_id, include_runners: true, include_runner_scale_sets: true, is_ui_read: true, force_launch: force_launch)

    return render_404 unless runner_group.present? && !runner_group.hosted?

    network_config_list = nil
    current_network_config = nil

    # Changing the network config is controlled by the component. Check only visibility here
    # so we can show which network configuration is in use.
    if can_view_network_configuration?(current_organization)
      # the network configuration is stored with the owner's group ID
      use_business = runner_group.inherited? && current_organization.business.present?
      network_owner = use_business ? current_organization.business : current_organization
      compute_resource_id = use_business ? runner_group.owner_group_id : runner_group_id

      network_config_list = network_config_client
        .list_configurations(network_owner, "actions", "")
        .map(&method(:network_config_to_payload))

      current_network_config_get_compute_resources = network_config_client.get_compute_resources(network_owner, "actions", compute_resource_id.to_s)
      current_network_config_id = current_network_config_get_compute_resources ? current_network_config_get_compute_resources.network_configuration.id : nil
      current_network_config = current_network_config_id ? network_config_list.find { |config| config[:id] == current_network_config_id } : nil
    end

    page = (params.fetch(:page) { 1 }).to_i
    per_page = (params.fetch(:per_page) { 25 }).to_i
    query, label_filters = get_labels_from_query(params[:qr])
    query, public_ip_filter = get_public_ip_filter_from_query(query)

    runners = []
    runner_group.runners.each do |runner|
      if query.blank? || runner.name.include?(query)
        if label_filters.empty? || label_filters.all? { |filter| runner.labels.any? { |label| label.name.downcase == filter.downcase } }
          runner.inherited = true if runner_group.inherited?
          runners.append(runner)
        end
      end
    end

    runner_group.runner_scale_sets.each do |scale_set|
      if query.blank? || scale_set.name.downcase.include?(query.downcase)
        if label_filters.empty? || label_filters.all? { |filter| scale_set.labels.any? { |label| label.name.downcase == filter.downcase } }
          runners.append(scale_set)
        end
      end
    end

    if current_organization.can_use_larger_runners?
      larger_runners = Actions::LargerRunner.larger_runners_for(entity: current_organization)

      larger_runners.each do |larger_runner|
        if query.blank? || larger_runner.name.include?(query)
          if (label_filters.empty? || label_filters.all? { |filter| larger_runner.labels.any? { |label| label.name.downcase == filter.downcase } }) &&
            (public_ip_filter.nil? || larger_runner.is_public_ip_enabled == public_ip_filter)
            if larger_runner.runner_group_id == runner_group.id
              larger_runner.group = runner_group
              runners.append(larger_runner)
              runner_group.runners.append(larger_runner)
            end
          end
        end
      end
    end

    runners = runners.sort_by { |runner| runner.view_priority }

    paginated_runners = WillPaginate::Collection.create(page, per_page, runners.length) do |runner|
      runner.replace(runners[((page - 1) * per_page), per_page] || [])
    end

    if !runner_group.inherited? && runner_group_name_exists_in_ent?(runner_group.name)
      flash.now[:warn] = "Runner group #{runner_group.name} already exists at the Enterprise level. Please consider renaming this group."
    end

    render "settings/organization/actions/runner_group",
      locals: {
        runner_group: runner_group,
        runners: paginated_runners,
        owner: current_organization,
        owner_settings: Actions::OrgRunnersView.new(settings_owner: current_organization, current_user: current_user),
        has_business: current_organization.business.present?,
        network_configurations: network_config_list,
        current_network_configuration: current_network_config
      }
  end

  def new
    network_config_list = nil

    if can_edit_network_configuration?(current_organization)
      network_config_list = network_config_client
        .list_configurations(current_organization, "actions", "", true)
        .map(&method(:network_config_to_payload))
    end
    render "settings/organization/actions/runner_group",
      locals: {
        runner_group: nil,
        owner: current_organization,
        owner_settings: Actions::OrgRunnersView.new(settings_owner: current_organization, current_user: current_user),
        has_business: current_organization.business.present?,
        network_configurations: network_config_list,
        current_network_configuration: nil,
      }
  end

  def create
    name = params[:name]
    visibility = params[:visibility]&.to_sym

    if name.nil? || visibility.nil?
      flash[:error] = "Failed to create runner group."
      redirect_to settings_org_actions_add_runner_group_path
      return
    end

    if runner_group_name_exists_in_ent?(name)
      flash[:error] = "Runner group #{name} already exists at the Enterprise level."
      redirect_to settings_org_actions_add_runner_group_path
      return
    end

    selected_repositories = if visibility == Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_SELECTED
      Array(params[:repository_ids])
    else
      []
    end
    selected_target_ids = selected_repositories.map { |global_id| Platform::Helpers::NodeIdentification.from_global_id(global_id)[1] }
    selected_repositories = current_organization.repositories.where(id: selected_target_ids).map(&method(:get_global_id))

    allow_public = !!params[:allow_public]

    network_config_id = params[:network_config_id].to_s

    result, destination = create_group_for(
      current_organization,
      name: name,
      visibility: visibility,
      allow_public: allow_public,
      selected_targets: selected_repositories,
      selected_workflow_refs: @selected_workflow_refs,
      restricted_to_workflows: @restricted_to_workflows,
      network_configuration_id: network_config_id == "-1" ? "" : network_config_id
    )
    if !result.call_succeeded?
      message = result.options&.fetch(:message, nil) || "Failed to create runner group."
      if message.start_with?("Already exists - ")
        message = "Runner group #{name} already exists in this Organization."
      end
      flash[:error] = message
      redirect_to settings_org_actions_add_runner_group_path
      return
    else
      if can_edit_network_configuration?(current_organization)
        runner_group_id = result.value&.runner_group.id.to_s
        runner_group_name = result.value&.runner_group.name.to_s
        if attach_network_configuration?(current_organization, network_config_id, runner_group_id, runner_group_name)
          flash[:notice] = "Runner group created."
        else
          flash[:error] = "Failed to create runner group."
        end
      else
        flash[:notice] = "Runner group created."
      end
    end

    redirect_to settings_org_actions_runner_groups_path(written_to: destination)
  end

  def update
    name = params[:name]
    visibility = params[:visibility]&.to_sym

    runner_group_id = params[:id]&.to_i
    runner_group = Actions::RunnerGroup.get(current_organization, id: runner_group_id, is_ui_read: true)

    if runner_group_id.nil? || visibility.nil? || runner_group.nil?
      flash[:error] = "Failed to update runner group."
      redirect_to settings_org_actions_runner_group_path(id: runner_group_id)
      return
    end

    if !runner_group.inherited? && name != runner_group.name && runner_group_name_exists_in_ent?(name)
      flash[:error] = "Runner group #{name} already exists at the Enterprise level."
      redirect_to settings_org_actions_runner_group_path(id: runner_group_id)
      return
    end

    selected_repositories = if visibility == Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_SELECTED
      Array(params[:repository_ids])
    else
      []
    end
    selected_target_ids = selected_repositories.map { |global_id| Platform::Helpers::NodeIdentification.from_global_id(global_id)[1] }
    selected_repositories = current_organization.repositories.where(id: selected_target_ids).map(&method(:get_global_id))

    allow_public = !!params[:allow_public]

    current_network_config_id = params[:network_config_id].to_s

    result, destination = update_group_for(
      current_organization,
      id: runner_group_id,
      name: name,
      visibility: visibility,
      allow_public: allow_public,
      selected_targets: selected_repositories,
      selected_workflow_refs: @selected_workflow_refs,
      restricted_to_workflows: @restricted_to_workflows,
      network_configuration_id: current_network_config_id == "-1" ? "" : current_network_config_id
    )
    if !result.call_succeeded?
      message = result.options&.fetch(:message, nil) || "Failed to update runner group."
      if message.start_with?("Already exists - ")
        message = "Runner group #{name} already exists in this Organization."
      end
      flash[:error] = message
      redirect_to settings_org_actions_runner_group_path(id: runner_group_id)
      return
    else
      # Don't update inherited runner groups
      if can_edit_network_configuration?(current_organization) && !runner_group.inherited?
        begin
          previous_network_config = network_config_client.get_compute_resources(current_organization, "actions", runner_group_id.to_s)
          previous_network_config_id = previous_network_config ? previous_network_config.network_configuration.id.to_s : ""
        rescue NetworkBundle::NetworkConfigurationsException => e
          flash[:error] = "Failed to retrieve network configuration."
        end
        if update_network_configuration?(current_organization, current_network_config_id, previous_network_config_id, runner_group_id.to_s, name.to_s)
          flash[:notice] = "Runner group updated."
        else
          flash[:error] = "Failed to update runner group."
        end
      else
        flash[:notice] = "Runner group updated."
      end
    end

    redirect_to settings_org_actions_runner_group_path(id: runner_group_id, written_to: destination)
  end

  def destroy
    runner_group_id = params[:id]&.to_i

    if runner_group_id.nil?
      flash[:error] = "Failed to delete runner group."
      redirect_to settings_org_actions_runner_groups_path
      return
    end

    if can_edit_network_configuration?(current_organization)
      begin
        current_network_config = network_config_client.get_compute_resources(current_organization, "actions", runner_group_id.to_s)
        current_network_config_id = current_network_config ? current_network_config.network_configuration.id.to_s : ""
        unless current_network_config_id.empty?
          network_config_client.remove_network_configuration_from_runner_group(current_organization, current_network_config_id, "actions", runner_group_id.to_s)
        end
      rescue NetworkBundle::NetworkConfigurationsException => e
        flash[:error] = "Failed to delete network configuration."
        redirect_to settings_org_actions_runner_groups_path
        return
      end
    end

    result, destination = delete_group_for(current_organization, id: runner_group_id)
    if !result.call_succeeded?
      flash[:error] = "Failed to delete runner group."
    else
      flash[:notice] = "Runner group deleted."
    end

    redirect_to settings_org_actions_runner_groups_path(written_to: destination)
  end

  def show_selected_targets # rubocop:todo GitHub/UseRestfulActions
    runner_group_id = params[:id]&.to_i
    force_launch = should_force_launch?(owner: current_organization, params: params)
    runner_group = runner_group_for(current_organization, id: runner_group_id, is_ui_read: true, force_launch: force_launch) if runner_group_id.present?

    selected_repositories = []
    if runner_group.present?
      selected_target_global_ids = runner_group.selected_targets.map { |identity| identity.global_id }.to_set
      selected_target_ids = selected_target_global_ids.map { |global_id| Platform::Helpers::NodeIdentification.from_global_id(global_id)[1] }
      selected_repositories = current_organization.repositories.where(id: selected_target_ids)
    end

    # RepositorySelectionComponent uses global_relay_id by default, not the next gid
    selected_repository_ids = selected_repositories.map(&:global_relay_id)

    respond_to do |format|
      format.html do
        render(Organizations::Settings::RepositorySelectionComponent.new(
          organization: current_organization,
          repositories: selected_repositories,
          selected_repositories: selected_repository_ids,
          data_url: repository_items_data_url(runner_group_id),
          aria_id_prefix: repository_items_aria_id_prefix(runner_group_id),
        ), layout: false)
      end
    end
  end

  def show_menu # rubocop:todo GitHub/UseRestfulActions
    render(Actions::RunnerGroupsMenuItemsComponent.new(
      owner: current_organization,
      owner_settings: Actions::OrgRunnersView.new(settings_owner: current_organization, current_user: current_user),
      runner_groups: Actions::RunnerGroup.for_entity(current_organization, is_ui_read: true),
    ), layout: false)
  end

  def update_runners # rubocop:todo GitHub/UseRestfulActions
    runner_group_id = params[:runner_group_id]&.to_i
    runner_ids = Array(params[:runner_ids]).map(&:to_i)

    unless runner_group_id.present? && runner_ids.any?
      flash[:error] = "Failed to move runners."
      redirect_to settings_org_actions_runners_path
      return
    end

    resp, destination = add_runners_for(current_organization, id: runner_group_id, runners_ids: runner_ids)
    runner_group = resp.value&.runner_group
    if runner_group.present?
      flash[:notice] = "Moved runners to #{runner_group.name}."
    else
      flash[:error] = "Failed to move runners."
    end

    redirect_to settings_org_actions_runners_path(written_to: destination)
  end

  private

  def ensure_actions_enabled
    render_404 unless GitHub.actions_enabled?
  end

  def ensure_tenant_exists
    if current_organization.business
      result = Launch::Twirp.deployer_client.setup_tenant(current_organization.business)
      raise Timeout::Error, "Timeout fetching tenant" unless result.call_succeeded?
    end

    result = Launch::Twirp.deployer_client.setup_tenant(current_organization)
    raise Timeout::Error, "Timeout fetching tenant" unless result.call_succeeded?
  end

  def ensure_can_create_runner_groups
    render_404 if restricted_plan_for_runner_groups?(current_organization)
  end

  def repository_items_data_url(runner_group_id)
    settings_org_actions_repository_items_path(current_organization, page: 1, policy: Orgs::ActionsSettings::RepositoryItemsController::RUNNER_GROUPS_POLICY, policy_id: runner_group_id)
  end

  def repository_items_aria_id_prefix(runner_group_id)
    "#{Orgs::ActionsSettings::RepositoryItemsController::RUNNER_GROUPS_POLICY}-#{runner_group_id}"
  end

  def runner_group_name_exists_in_ent?(name)
    return false unless current_organization.business
    ent_runner_groups = Actions::RunnerGroup.for_entity(current_organization.business, is_ui_read: true)
    ent_runner_group_names = ent_runner_groups.map { |group| group.name.downcase }
    ent_runner_group_names.include? name.downcase
  end

  def get_global_id(entity)
    !GitHub.enterprise? ? entity.next_global_id : entity.global_relay_id
  end
end
