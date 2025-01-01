# typed: true
# frozen_string_literal: true

require "github-launch"

class Actions::RunnerGroup
  class RunnerGroupServiceError < Actions::ServiceError; end

  class SelectedTargetsLoader
    def load(owner, selected_targets)
      ids_by_type = self.class.target_ids_by_type(selected_targets)
      if owner.is_a?(Business)
        owner.organizations.where(id: ids_by_type["Organization"].to_a)
      else
        owner.repositories.where(id: ids_by_type["Repository"].to_a, active: true)
      end
    end

    def self.target_ids_by_type(selected_targets)
      selected_targets.each_with_object({}) do |t, targets|
        klass, id = Platform::Helpers::NodeIdentification.from_global_id(t.global_id)
        targets[klass] ||= []
        targets[klass].push(id)
      end
    end
  end

  class SelectedTargetsPreloader
    def initialize(owner, groups)
      preloaded_array = SelectedTargetsLoader.new.load(owner, groups.flat_map(&:selected_targets).uniq)
      @preloaded_targets = preloaded_array.each_with_object({}) do |t, targets|
        targets[t.class.to_s] ||= {}
        targets[t.class.to_s][t.id] = t
      end
    end

    def load(owner, selected_targets)
      ids_by_type = SelectedTargetsLoader.target_ids_by_type(selected_targets)
      ids_by_type.flat_map do |type, ids|
        ids.map do |id|
          @preloaded_targets.dig type, id.to_i
        end
      end.compact
    end
  end

  SELECTED_TARGETS_ONLY = "selected"
  DEFAULT_GROUP_ID = 1 # Id of default runner group. This group always has the same ID = 1 and name "Default" because it is created on Host creation by Actions service

  attr_reader(
    :id,
    :name,
    :size,
    :runners,
    :runner_scale_sets,
    :visibility,
    :allow_public,
    :inherited_allow_public,
    :selected_targets,
    :hosted,
    :default,
    :selected_workflow_refs,
    :restricted_to_workflows,
    :workflow_restrictions_read_only,
    :owner_group_id
  )

  attr_accessor :owner

  def initialize(
    id:,
    name:,
    size: 0,
    owner_id: nil,
    runners: [],
    runner_scale_sets: [],
    visibility: :SELECTED,
    allow_public: false,
    inherited_allow_public: false,
    selected_targets: [],
    selected_workflow_refs: [],
    precreated: false,
    hosted: false,
    restricted_to_workflows: false,
    workflow_restrictions_read_only: false,
    owner_group_id: nil
  )
    @id = id
    @name = name
    @size = size
    @owner_id = owner_id
    @runners = runners
    @runner_scale_sets = runner_scale_sets
    @visibility = visibility
    @allow_public = allow_public
    @inherited_allow_public = inherited_allow_public
    @selected_targets = selected_targets
    @selected_workflow_refs = selected_workflow_refs
    @precreated = precreated
    @hosted = hosted
    @restricted_to_workflows = restricted_to_workflows
    @workflow_restrictions_read_only = workflow_restrictions_read_only
    @owner_group_id = owner_group_id
  end

  def computed_allow_public
    return allow_public unless inherited?
    allow_public && inherited_allow_public
  end

  def self.from_rpc_object(owner, group, targets_loader: SelectedTargetsLoader.new, using_runner_admin: false)
    new(
      id: group.id,
      name: group.name,
      size: using_runner_admin ? 0 : group.size, #Runner Admin's RunnerGroup object doesn't currently contain a size
      owner_id: group.owner_id,
      runners: Actions::Runner.from_rpc_collection(group.runners, using_runner_admin: using_runner_admin),
      runner_scale_sets: using_runner_admin ? [] : Actions::RunnerScaleSet.from_rpc_collection(group.runner_scale_sets), # Runner Admin's RunnerGroup object doesn't currently contain runner_scale_sets
      visibility: group.visibility,
      allow_public: group.allow_public,
      inherited_allow_public: group.inherited_allow_public,
      selected_targets: targets_loader.load(owner, group.selected_targets),
      precreated: group.is_default,
      hosted:  using_runner_admin ? false : group.is_hosted, # Runner Admin's RunnerGroup object doesn't currently contain a hosted flag
      selected_workflow_refs: group.selected_workflow_refs,
      restricted_to_workflows: group.restricted_to_workflows,
      workflow_restrictions_read_only: group.workflow_restrictions_read_only,
      owner_group_id:  using_runner_admin ? nil : group.owner_group_id # Runner Admin's RunnerGroup object doesn't currently contain an owner_group_id
    )
  end
  private_class_method :from_rpc_object

  def self.selected_targets_for_group(group, preloaded_records)
  end
  private_class_method :selected_targets_for_group

  def self.from_rpc_collection(owner, groups, using_runner_admin: false)
    targets_loader = SelectedTargetsPreloader.new(owner, groups)
    groups.map do |runner_group|
      from_rpc_object(owner, runner_group, targets_loader: targets_loader, using_runner_admin: using_runner_admin)
    end
  end
  private_class_method :from_rpc_collection

  def self.for_entity(entity, include_runners: false, propagate_errors: false, include_hosted_runner_groups: false, include_elastic_runners: false, include_runner_scale_sets: false)
    GitHub.tracer.in_span("actions/runner_group.for_entity", kind: :internal, attributes: {
      "entity_type" => entity.class.name,
    }) do |_span|
      if entity.is_a? Repository
        org_runner_groups = self.for_entity(
          entity.owner,
          include_runners: include_runners,
          propagate_errors: propagate_errors,
          include_hosted_runner_groups: include_hosted_runner_groups,
          include_runner_scale_sets: include_runner_scale_sets,
          include_elastic_runners: include_elastic_runners)
        visible_runner_groups = org_runner_groups.select do |runner_group|
          runner_group_visible_to_repo?(runner_group, entity.owner, entity)
        end
        return visible_runner_groups
      end

      if entity.feature_enabled?(:actions_runners_use_runner_admin_service)
        runner_admin_client = GitHub.build_runner_admin_client(entity)
        resp = runner_admin_client.list_runner_groups(
          owner: entity,
          include_runners: include_runners,
        )

        if propagate_errors && !resp.call_succeeded?
          raise RunnerGroupServiceError.new("list_groups failed", status: resp.status, options: resp.options)
        end

        runner_groups = resp.value&.runner_groups || []
        from_rpc_collection(entity, runner_groups, using_runner_admin: true)
      else
        resp = Launch::Twirp.runner_groups_client.list_groups(
          owner: entity,
          include_runners: include_runners,
          include_hosted_runner_groups: include_hosted_runner_groups,
          include_runner_scale_sets: include_runner_scale_sets,
          include_elastic_runners: include_elastic_runners
        )

        if propagate_errors && !resp.call_succeeded?
          raise RunnerGroupServiceError.new("list_groups failed", status: resp.status, options: resp.options)
        end

        runner_groups = resp.value&.runner_groups || []
        from_rpc_collection(entity, runner_groups)
      end
    end
  end

  def self.runner_group_visible_to_repo?(runner_group, org, repo)
    # repo must be included in targets for select visibility
    if runner_group.visibility == Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_SELECTED
      return false unless runner_group.selected_targets.any? { |target| target.global_relay_id == repo.next_global_id || target.global_relay_id == repo.global_relay_id }
    end
    # private repos can use any runner group
    return true unless repo.public?
    # return allow_public
    runner_group.computed_allow_public
  end

  def self.get(owner, id:, include_runners: false, include_hosted_runner_groups: false, include_elastic_runners: false, include_runner_scale_sets: false)
    if owner.feature_enabled?(:actions_runners_use_runner_admin_service)
      runner_admin_client = GitHub.build_runner_admin_client(owner)
      resp = runner_admin_client.get_runner_group(
        owner: owner,
        group_id: id,
        include_runners: include_runners,
      )

      runner_group = resp&.value&.runner_group
      return nil unless runner_group
      result = from_rpc_object(owner, runner_group, using_runner_admin: true)
      result.owner = owner
      result
    else
      resp = Launch::Twirp.runner_groups_client.get_group(
        owner: owner,
        group_id: id,
        include_runners: include_runners,
        include_hosted_runner_groups: include_hosted_runner_groups,
        include_elastic_runners: include_elastic_runners,
        include_runner_scale_sets: include_runner_scale_sets
      )

      runner_group = resp&.value&.runner_group
      return nil unless runner_group
      result = from_rpc_object(owner, runner_group)
      result.owner = owner
      result
    end
  end

  def self.visibility_for(runner_group, owner)
    if owner.feature_enabled?(:actions_runners_use_runner_admin_service)
      return Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_SELECTED if runner_group.visibility == ActionsRunnerAdmin::Twirp::RunnerAdminClient::GROUP_VISIBILITY_SELECTED
      return Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_ALL
    end
    return Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_ALL if runner_group.visibility == Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_PRIVATE
    runner_group.visibility
  end

  # @return Boolean
  def restricted_to_workflows?
    !!@restricted_to_workflows
  end

  def workflow_restrictions_read_only?
    !!@workflow_restrictions_read_only
  end

  # Internal: Compare two runner groups
  # Non-inherited groups are sorted before inherited
  # Default groups are sorted before other groups
  # Otherwise groups are sorted by name, case-insensitive
  #
  # other - Another RunnerGroup
  #
  # Returns the usual tri-state. See Comparable for details.
  def <=>(other)
    return nil unless other.is_a?(self.class)

    return 1 if inherited? && !other.inherited?
    return -1 if !inherited? && other.inherited?

    return -1 if precreated? && !other.precreated?
    return 1 if !precreated? && other.precreated?

    return -1 if default? && !other.default?
    return 1 if !default? && other.default?

    @name.downcase <=> other.name.downcase
  end

  def inherited?
    @owner_id&.global_id.present?
  end

  def owner_global_id
    @owner_id&.global_id
  end

  def precreated?
    # Checks if the group is created by our services rather than by user
    @precreated || default?
  end

  def default?
    # Check if this is a default runner group. There is only ever one default group; new runners are assigned to this group automatically
    @id == DEFAULT_GROUP_ID
  end

  def hosted?
    @hosted
  end
end
