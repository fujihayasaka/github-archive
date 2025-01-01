# typed: true
# frozen_string_literal: true

require "github-launch"

class Actions::RunnerScaleSet
  ONLINE = "online"
  OFFLINE = "offline"
  ACTIVE = "active"
  DISABLED = "disabled"

  attr_reader :id, :name, :runner_group_id, :group_name, :statistics, :labels

  attr_accessor :owner, :is_in_default_group, :inherited

  def initialize(
    id:,
    name:,
    runner_group_id:,
    group_name:,
    status:,
    statistics:,
    labels: [],
    is_in_default_group: false,
    inherited: false
  )
    @id = id
    @name = name
    @runner_group_id = runner_group_id
    @group_name = group_name
    @status = status
    @statistics = statistics
    @labels = labels
    @is_in_default_group = is_in_default_group
    @inherited = inherited
  end

  def self.from_rpc_collection(entities)
    entities.map { |entity| from_rpc_object(entity) }
  end

  def self.from_rpc_object(entity)
    new(
      id: entity.id,
      name: entity.name,
      runner_group_id: entity.runner_group_id,
      group_name: entity.runner_group_name,
      status: entity.status,
      statistics: Actions::RunnerScaleSetStatistics.from_rpc_object(entity.statistics),
      labels: entity.labels
    )
  end

  def self.for_entity(owner)
    GitHub.tracer.in_span("actions/runner_scale_set.list", kind: :internal, attributes: {
      "entity_type" => "RunnerScaleSet",
    }) do
      if owner.feature_enabled?(:actions_runners_use_runner_admin_service)
        resp = GitHub.build_runner_admin_client(owner).list_runner_scale_sets(owner: owner)

        scale_sets = resp.value&.runner_scale_sets
        return [] unless scale_sets

        return scale_sets.map do |scale_set|
          result = from_rpc_object(scale_set)
          result.owner = owner
          result
        end
      end

      resp = Launch::Twirp::runner_scale_sets_client.list_scale_sets(owner, exclude_elastic_runners: true)

      scale_sets = resp.value&.runner_scale_sets
      return [] unless scale_sets

      scale_sets.map do |scale_set|
        result = from_rpc_object(scale_set)
        result.owner = owner
        result
      end
    end
  end

  def self.get(owner, id:)
    GitHub.tracer.in_span("actions/runner_scale_set.get", kind: :internal, attributes: {
      "entity_type" => "RunnerScaleSet",
    }) do
      if owner.feature_enabled?(:actions_runners_use_runner_admin_service)
        resp = GitHub.build_runner_admin_client(owner).get_runner_scale_set(owner: owner, scale_set_id: id)

        scale_set = resp.value&.runner_scale_set
        return nil unless scale_set
        result = from_rpc_object(scale_set)
        result.owner = owner
        return result
      end
      resp = Launch::Twirp::runner_scale_sets_client.get_scale_set(owner, id)

      scale_set = resp.value&.runner_scale_set
      return nil unless scale_set
      result = from_rpc_object(scale_set)
      result.owner = owner
      result
    end
  end

  def is_in_default_group?
    @is_in_default_group
  end

  def status
    return DISABLED if @owner&.repo_self_hosted_runners_disabled_by_owner?
    @status
  end

  def view_priority
    case status
    when OFFLINE then 3
    when ONLINE then 2
    when ACTIVE then 1
    else
      4
    end
  end

  def inherited?
    @inherited
  end

  def os
    "arc"
  end

  def runner_group_path(owner_settings)
    group_id = @runner_group_id
    owner_settings.update_runner_group_path(id: group_id)
  end
end
