# typed: true
# frozen_string_literal: true

module Actions
  class RunnerGroupComponent < ApplicationComponent
    include ReactHelper
    include NetworkConfigurationsHelper

    ENTERPRISE_VISIBILITIES = {
      Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_SELECTED => {
        label: "Selected organizations",
        description: "Runners can be used by specifically selected organizations.",
      },
      Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_ALL => {
        label: "All organizations",
        description: "Runners can be used by all organizations.",
      }
    }.freeze

    ORG_VISIBILITIES = {
      Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_SELECTED => {
        label: "Selected repositories",
        description: "Runners can be used by specifically selected repositories.",
      },
      Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_ALL => {
        label: "All repositories",
        description: "Runners can be used by public and private repositories.",
      },
    }.freeze

    BUSINESS_ORG_INHERITED_GROUP_VISIBILITIES = ORG_VISIBILITIES.merge(
      Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_ALL => {
        label: "All repositories",
        description: "Runners can be used by private and internal repositories.",
      },
    ).except(Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_PRIVATE).freeze

    def initialize(owner:, owner_settings:, runner_group: nil, has_business: false, network_configurations: nil, current_network_configuration: nil)
      @owner = owner
      @owner_settings = owner_settings
      @runner_group = runner_group
      @has_business = has_business
      @network_configurations = network_configurations
      @current_network_configuration = current_network_configuration
    end

    def aria_id_prefix
      is_update? ? "runner-group-#{@runner_group.id}" : "new-runner-group"
    end

    def is_update?
      @runner_group.present?
    end

    def readonly?
      is_update? && @runner_group.inherited?
    end

    def form_path
      is_update? ? @owner_settings.update_runner_group_path(id: @runner_group.id) : @owner_settings.create_runner_group_path
    end

    def visibility
      Actions::RunnerGroup.visibility_for(@runner_group, @owner)
    end

    def visibilities
      return ENTERPRISE_VISIBILITIES unless @owner.organization?
      return ORG_VISIBILITIES unless @has_business
      BUSINESS_ORG_INHERITED_GROUP_VISIBILITIES
    end

    def selected_visibility
      is_update? ? visibility : default_visibility
    end

    def default_visibility
      Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_SELECTED
    end

    def target_type
      @owner.organization? ? "repository" : "organization"
    end

    def owner_type
      @owner.organization? ? "organization" : "enterprise"
    end

    def disable_allow_public?
      is_update? && @runner_group.inherited? && !@runner_group.inherited_allow_public
    end

    def show_selected_targets?
      !is_update? || visibility == Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_SELECTED
    end

    def selection_component_path
      @owner_settings.runner_group_targets_path(id: @runner_group&.id)
    end

    memoize def selected_targets_count
      is_update? ? @runner_group.selected_targets.count : 0
    end

    def restricted_to_workflows?
      is_update? ? @runner_group.restricted_to_workflows? : false
    end

    def workflow_restrictions_read_only?
      is_update? ? @runner_group.workflow_restrictions_read_only? : false
    end

    def selected_workflow_refs_count
      @runner_group&.selected_workflow_refs&.count || 0
    end

    def selected_network_configuration
      is_update? && !@current_network_configuration.nil? ? @current_network_configuration : "No network configuration"
    end

    def is_current_configuration_disabled?
      @current_network_configuration && (@current_network_configuration[:computeService] == NetworkBundle::ComputeService::None)
    end

    def network_configuration_visible?
      # Only show this UI for new runner groups if it's editable
      return can_edit_network_configuration?(@owner) if !is_update?
      # Show this UI for runner groups inherited from an enterprise
      can_view_network_configuration?(@owner)
    end

    def network_configuration_editable?
      can_edit_network_configuration?(@owner) && !readonly?
    end

    # Renders a list of only the orgs/repos that have been selected.
    # NB: does not include *unselected* orgs/repos, like RunnerGroupsController#show_selected_targets does.
    def selected_targets_component
      selected_target_relay_ids = @runner_group.selected_targets.map(&:global_relay_id).to_set

      if @owner.organization?
        Organizations::Settings::RepositorySelectionComponent.new(
          organization: @owner,
          repositories: @runner_group.selected_targets,
          selected_repositories: selected_target_relay_ids,
          data_url: settings_org_actions_repository_items_path(@owner, page: 1, policy: Orgs::ActionsSettings::RepositoryItemsController::RUNNER_GROUPS_POLICY, policy_id: @runner_group.id),
          aria_id_prefix: "#{Orgs::ActionsSettings::RepositoryItemsController::RUNNER_GROUPS_POLICY}-#{@runner_group.id}",
        )
      else
        Businesses::Actions::OrganizationSelectionComponent.new(
          business: @owner,
          organizations: @runner_group.selected_targets,
          selected_organizations: selected_target_relay_ids,
          policy_type: Orgs::ActionsSettings::RepositoryItemsController::RUNNER_GROUPS_POLICY,
          policy_id: @runner_group.id,
        )
      end
    end
  end
end
