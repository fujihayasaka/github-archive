# typed: true
# frozen_string_literal: true

class Businesses::Actions::RunnerGroupsController < Businesses::BusinessController

  include ::Actions::RunnerGroupsHelper
  include Actions::RunnersHelper
  include Actions::LargerRunnersHelper
  include NetworkBundle
  include ApplicationController::VerifiedFetchDependency
  include NetworkConfigurationsHelper

  before_action :business_owner_required
  before_action :ensure_actions_enabled
  before_action :ensure_tenant_exists
  before_action :validate_selected_workflow_refs, only: [:create, :update]
  before_action :business_not_downgraded_to_free_plan_required
  before_action :sudo_filter, only: [:destroy]
  before_action :business_full_plan_required
  allow_verified_fetch only: [:create, :update]

  javascript_bundle :settings

  sig { returns(String) }
  def self.react_bundle_name
    "network-configurations-select-panel"
  end

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:show_menu]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:show_selected_targets]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show_menu, :show_selected_targets], optional: true

  def index
    page = (params.fetch(:page) { 1 }).to_i
    per_page = (params.fetch(:per_page) { 25 }).to_i
    force_launch = should_force_launch?(owner: this_business, params: params)

    runner_groups = Actions::RunnerGroup.for_entity(
      this_business,
      include_runners: true,
      include_runner_scale_sets: true,
      is_ui_read: true,
      force_launch: force_launch,
    )

    runner_groups = runner_groups.select { |group| group.name.downcase.include?(params[:qr].downcase) } if params[:qr].present?
    runner_groups = runner_groups.sort

    if this_business.can_use_larger_runners?
      larger_runners = Actions::LargerRunner.larger_runners_for(entity: this_business)
      larger_runners.each do |larger_runner|
        group = runner_groups.detect { |runner_group| runner_group.id == larger_runner.runner_group_id }
        if group.present?
          group.runners.append(larger_runner)
        end
      end
    end

    disabled_runner_group_ids = begin
      list_disabled_network_configuration_ids(this_business)
    rescue => e
      Failbot.report(e, context: { business_id: this_business.id, action: "list_disabled_network_configuration_ids" })
      []
    end

    paginated_runner_groups = WillPaginate::Collection.create(page, per_page, runner_groups.length) do |group|
      group.replace(runner_groups[((page - 1) * per_page), per_page] || [])
    end

    render "businesses/settings/actions/runner_groups", locals: {
      runner_groups: paginated_runner_groups,
      disabled_runner_group_ids: disabled_runner_group_ids,
      should_display_custom_images_tab: is_custom_images_enabled?(entity: this_business)
    }
  end

  def edit
    runner_group_id = params[:id]&.to_i
    force_launch = should_force_launch?(owner: this_business, params: params)

    runner_group = Actions::RunnerGroup.get(
      this_business,
      id: runner_group_id,
      include_runner_scale_sets: true,
      include_runners: true,
      is_ui_read: true,
      force_launch: force_launch,
    )

    return render_404 unless runner_group.present? && !runner_group.hosted?

    network_config_list = nil
    current_network_config = nil

    if can_view_network_configuration?(this_business)
      # include disabled configurations
      network_config_list = network_config_client.list_configurations(this_business, "actions", "")
      current_network_config_get_compute_resources = network_config_client.get_compute_resources(this_business, "actions", runner_group_id.to_s)

      network_config_list = network_config_list.map(&method(:network_config_to_payload))
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

    if this_business.can_use_larger_runners?
      larger_runners = Actions::LargerRunner.larger_runners_for(entity: this_business)
      larger_runners.each do |larger_runner|
        if runner_group.id == larger_runner.runner_group_id
          if query.blank? || larger_runner.name.include?(query)
            if (label_filters.empty? || label_filters.all? { |filter| larger_runner.labels.any? { |label| label.name.downcase == filter.downcase } }) &&
              (public_ip_filter.nil? || larger_runner.is_public_ip_enabled == public_ip_filter)
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
    render "businesses/settings/actions/runner_group", locals: {
      runner_group: runner_group,
      runners: paginated_runners,
      owner_settings: Actions::EnterpriseRunnersView.new(settings_owner: this_business, current_user: current_user),
      network_configurations: network_config_list,
      current_network_configuration: current_network_config
    }
  end

  def new
    network_config_list = nil
    if can_edit_network_configuration?(this_business)
      network_config_list = network_config_client
        .list_configurations(this_business, "actions", "", true)
        .map(&method(:network_config_to_payload))
    end

    render "businesses/settings/actions/runner_group", locals: {
      runner_group: nil,
      owner_settings: Actions::EnterpriseRunnersView.new(settings_owner: this_business, current_user: current_user),
      network_configurations: network_config_list,
      current_network_configuration: nil,
    }
  end

  def create
    name = params[:name]
    visibility = params[:visibility]&.to_sym

    if name.nil? || visibility.nil?
      flash[:error] = "Failed to create runner group."
      redirect_to settings_actions_add_runner_group_enterprise_path
      return
    end

    selected_organizations = if visibility == Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_SELECTED
      Array(params[:organization_ids])
    else
      []
    end
    selected_target_ids = selected_organizations.map { |global_id| Platform::Helpers::NodeIdentification.from_global_id(global_id)[1] }
    selected_organizations = this_business.organizations.where(id: selected_target_ids).map(&method(:get_global_id))

    allow_public = !!params[:allow_public]

    network_config_id = params[:network_config_id].to_s

    result, destination = create_group_for(
      this_business,
      name: name,
      visibility: visibility,
      selected_targets: selected_organizations,
      allow_public: allow_public,
      selected_workflow_refs: @selected_workflow_refs,
      restricted_to_workflows: @restricted_to_workflows,
      network_configuration_id: network_config_id == "-1" ? "" : network_config_id
    )
    if !result.call_succeeded?
      message = result.options&.fetch(:message, nil) || "Failed to create runner group."
      flash[:error] = message
      redirect_to settings_actions_add_runner_group_enterprise_path
      return
    else
      if can_edit_network_configuration?(this_business)
        runner_group_id = result.value&.runner_group.id.to_s
        runner_group_name = result.value&.runner_group.name.to_s
        if attach_network_configuration?(this_business, network_config_id, runner_group_id, runner_group_name)
          flash[:notice] = "Runner group created."
        else
          flash[:error] = "Failed to create runner group."
        end
      else
        flash[:notice] = "Runner group created."
      end
    end

    redirect_to settings_actions_runner_groups_enterprise_path(written_to: destination)
  end

  def update
    name = params[:name]
    visibility = params[:visibility]&.to_sym

    runner_group_id = params[:id]&.to_i

    if runner_group_id.nil? || name.nil? || visibility.nil?
      flash[:error] = "Failed to update runner group."
      redirect_to settings_actions_runner_group_enterprise_path(id: runner_group_id)
      return
    end

    # filter out selected organizations not owned by this business, favor the next global id format
    selected_organizations = if visibility == Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_SELECTED
      Array(params[:organization_ids])
    else
      []
    end
    selected_target_ids = selected_organizations.map { |global_id| Platform::Helpers::NodeIdentification.from_global_id(global_id)[1] }
    selected_organizations = this_business.organizations.where(id: selected_target_ids).map(&method(:get_global_id))

    allow_public = !!params[:allow_public]

    current_network_config_id = params[:network_config_id].to_s

    result, destination = update_group_for(
      this_business,
      id: runner_group_id,
      name: name,
      visibility: visibility,
      allow_public: allow_public,
      selected_targets: selected_organizations,
      selected_workflow_refs: @selected_workflow_refs,
      restricted_to_workflows: @restricted_to_workflows,
      network_configuration_id: current_network_config_id == "-1" ? "" : current_network_config_id
    )
    if !result.call_succeeded?
      message = result.options&.fetch(:message, nil) || "Failed to update runner group."
      flash[:error] = message
      redirect_to settings_actions_runner_group_enterprise_path(id: runner_group_id)
      return
    else
      if can_edit_network_configuration?(this_business)
        begin
          previous_network_config = network_config_client.get_compute_resources(this_business, "actions", runner_group_id.to_s)
          previous_network_config_id = previous_network_config ? previous_network_config.network_configuration.id.to_s : ""
        rescue NetworkBundle::NetworkConfigurationsException => e
          flash[:error] = "Failed to retrieve network configuration."
        end
        if update_network_configuration?(this_business, current_network_config_id, previous_network_config_id, runner_group_id.to_s, name.to_s)
          flash[:notice] = "Runner group updated."
        else
          flash[:error] = "Failed to update runner group."
        end
      else
        flash[:notice] = "Runner group updated."
      end
    end

    redirect_to settings_actions_runner_group_enterprise_path(id: runner_group_id, written_to: destination)
  end

  def destroy
    runner_group_id = params[:id]&.to_i

    if runner_group_id.nil?
      flash[:error] = "Failed to delete runner group."
      redirect_to settings_actions_runner_groups_enterprise_path
      return
    end

    if can_edit_network_configuration?(this_business)
      begin
        current_network_config = network_config_client.get_compute_resources(this_business, "actions", runner_group_id.to_s)
        current_network_config_id = current_network_config ? current_network_config.network_configuration.id.to_s : ""
        unless current_network_config_id.empty?
          network_config_client.remove_network_configuration_from_runner_group(this_business, current_network_config_id, "actions", runner_group_id.to_s)
        end
      rescue NetworkBundle::NetworkConfigurationsException => e
        flash[:error] = "Failed to delete network configuration."
        redirect_to settings_actions_runner_groups_enterprise_path
        return
      end
    end

    result, destination = delete_group_for(this_business, id: runner_group_id)
    if !result.call_succeeded?
      flash[:error] = "Failed to delete runner group."
    else
      flash[:notice] = "Runner group deleted."
    end

    redirect_to settings_actions_runner_groups_enterprise_path(written_to: destination)
  end

  def show_selected_targets # rubocop:todo GitHub/UseRestfulActions
    runner_group_id = params[:id]&.to_i
    force_launch = should_force_launch?(owner: this_business, params: params)

    runner_group = runner_group_for(this_business, id: runner_group_id, is_ui_read: true, force_launch: force_launch) if runner_group_id.present?

    selected_organizations_ids = []
    if runner_group.present?
      selected_target_global_ids = runner_group.selected_targets.map { |identity| identity.global_id }.to_set
      selected_target_ids = selected_target_global_ids.map { |global_id| Platform::Helpers::NodeIdentification.from_global_id(global_id)[1] }
      selected_organizations = this_business.organizations.where(id: selected_target_ids)

      # OrganizationSelectionComponent uses global_relay_id, not the next gid
      selected_organizations_ids = selected_organizations.map(&:global_relay_id)
    end

    respond_to do |format|
      format.html do
        render(Businesses::Actions::OrganizationSelectionComponent.new(
          business: this_business,
          organizations: this_business.organizations,
          selected_organizations: selected_organizations_ids,
          policy_type: Orgs::ActionsSettings::RepositoryItemsController::RUNNER_GROUPS_POLICY,
          policy_id: runner_group_id,
        ), layout: false)
      end
    end
  end

  def show_menu # rubocop:todo GitHub/UseRestfulActions
    render(Actions::RunnerGroupsMenuItemsComponent.new(
      owner: this_business,
      owner_settings: Actions::EnterpriseRunnersView.new(settings_owner: this_business, current_user: current_user),
      runner_groups: Actions::RunnerGroup.for_entity(this_business, is_ui_read: true),
    ), layout: false)
  end

  def update_runners # rubocop:todo GitHub/UseRestfulActions
    runner_group_id = params[:runner_group_id]&.to_i
    runner_ids = Array(params[:runner_ids]).map(&:to_i)

    unless runner_group_id.present? && runner_ids.any?
      flash[:error] = "Failed to move runners."
      redirect_to settings_actions_runners_enterprise_path
      return
    end

    resp, destination = add_runners_for(this_business, id: runner_group_id, runners_ids: runner_ids)

    if resp.value&.runner_group.present?
      flash[:notice] = "Moved runners to #{resp.value&.runner_group.name}."
    else
      flash[:error] = "Failed to move runners."
    end

    redirect_to settings_actions_runners_enterprise_path(written_to: destination)
  end

  private

  def ensure_actions_enabled
    render_404 unless GitHub.actions_enabled?
  end

  def ensure_tenant_exists
    result = Launch::Twirp.deployer_client.setup_tenant(this_business)
    raise Timeout::Error, "Timeout fetching tenant" unless result.call_succeeded?
  end

  def get_global_id(entity)
    !GitHub.enterprise? ? entity.next_global_id : entity.global_relay_id
  end
end
