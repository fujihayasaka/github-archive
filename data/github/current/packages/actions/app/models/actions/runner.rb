# typed: true
# frozen_string_literal: true

require "github/launch_client"

class Actions::Runner
  extend Actions::RunnersClientHelper

  class RunnerServiceError < Actions::ServiceError; end

  ONLINE = "online"
  OFFLINE = "offline"
  IDLE = "idle"
  ACTIVE = "active"
  DISABLED = "disabled"

  SYSTEM_LABEL_TYPE = "system"
  CUSTOM_LABEL_TYPE = "user"

  attr_reader :id, :name, :os, :current_parallelism, :arch, :labels, :check_run_global_id, :runner_group_id, :owner
  attr_accessor :group_name, :inherited, :is_in_default_group, :scoped_runner_group_id, :group

  sig { params(entity: T.untyped, propagate_errors: T::Boolean, is_ui_read: T::Boolean, is_api_read: T::Boolean, is_write: T::Boolean).returns(T.untyped) }
  def self.for_entity(entity, propagate_errors: false, is_ui_read: false, is_api_read: false, is_write: false)
    resp = list_runners_helper(entity, use_runner_admin: use_runner_admin?(entity, is_ui_read: is_ui_read, is_api_read: is_api_read, is_write: is_write), do_experiment: do_runner_admin_experiment?(entity))

    if propagate_errors && !resp.call_succeeded?
      raise RunnerServiceError.new("list_runners failed", status: resp.status, options: resp.options)
    end

    from_rpc_collection(Array(resp.value&.runners), owner: entity)
  end

  sig { params(owner: T.untyped, id: T.untyped, is_ui_read: T::Boolean, is_api_read: T::Boolean, is_write: T::Boolean).returns(T.untyped) }
  def self.get!(owner, id, is_ui_read: false, is_api_read: false, is_write: false)
    resp = get_runner(owner, id, use_runner_admin: use_runner_admin?(owner, is_ui_read: is_ui_read, is_api_read: is_api_read, is_write: is_write), do_experiment: do_runner_admin_experiment?(owner))

    message = resp.options[:message] if resp.options.present? && resp.options.key?(:message)
    raise RunnerServiceError.new(message, status: resp.status, options: resp.options) unless resp.call_succeeded
    from_rpc_object(resp.value&.runner, owner: owner)
  end

  sig { params(owner: T.untyped, id: T.untyped, is_ui_read: T::Boolean, is_api_read: T::Boolean, is_write: T::Boolean, force_launch: T::Boolean).returns(T.untyped) }
  def self.get(owner, id, is_ui_read: false, is_api_read: false, is_write: false, force_launch: false)
    resp = get_runner(owner, id, use_runner_admin: !force_launch && use_runner_admin?(owner, is_ui_read: is_ui_read, is_api_read: is_api_read, is_write: is_write), do_experiment: do_runner_admin_experiment?(owner))

    from_rpc_object(resp.value&.runner, owner: owner)
  end

  def self.from_rpc_collection(entities, owner: nil)
    entities.map { |entity| from_rpc_object(entity, owner: owner) }
  end

  def self.from_rpc_object(entity, owner: nil)
    return nil if entity.nil?

    # With the upgrade to RA, we will get rid of the 'online' status entirely and use 'active' and 'idle' instead.
    # However, we're handling this for backwards compat with pipelines.
    status = entity.status
    if FeatureFlag.vexi.enabled_or_raise?(:actions_runner_use_status_online_for_api) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      if status == Actions::Runner::ONLINE
        if entity.current_parallelism > 0 || entity.assigned_request.present?
          status = Actions::Runner::ACTIVE
        else
          status = Actions::Runner::IDLE
        end
      end
    end
    new(
      id: entity.id,
      name: entity.name,
      os: entity.os,
      status: status,
      current_parallelism: entity.current_parallelism,
      labels: entity.labels,
      arch: entity.arch,
      check_run_global_id: entity.assigned_request&.check_run_id,
      runner_group_id: entity.runner_group_id,
      owner: owner,
    )
  end

  def initialize(id:, name:, os:, status:, current_parallelism: 0, labels: [], group_name: nil, inherited: false, arch: nil, check_run_global_id: nil, runner_group_id: nil, scoped_runner_group_id: nil, is_in_default_group: false, owner: nil, group: nil)
    @id = id
    @name = name
    @os = os
    @status = status
    @current_parallelism = current_parallelism
    @labels = labels
    @group_name = group_name
    @inherited = inherited
    @arch = arch
    @check_run_global_id = check_run_global_id
    @runner_group_id = runner_group_id
    @scoped_runner_group_id = scoped_runner_group_id
    @is_in_default_group = is_in_default_group
    @owner = owner
    @group = group
  end

  def status
    return DISABLED if @owner&.repo_self_hosted_runners_disabled_by_owner?

    if @status == ONLINE
      return @current_parallelism.zero? ? IDLE : ACTIVE
    end
    @status
  end

  def inherited?
    @inherited
  end

  def is_in_default_group?
    @is_in_default_group
  end

  def offline?
    status == OFFLINE
  end

  def view_priority
    case status
    when OFFLINE then 4
    when ONLINE then 3
    when IDLE then 2
    when ACTIVE then 1
    else
      5
    end
  end

  def system_labels
    @labels.select { |label| label.type == SYSTEM_LABEL_TYPE }
  end

  def custom_labels
    @labels.select { |label| label.type == CUSTOM_LABEL_TYPE }
  end

  def custom_label_ids
    custom_labels.map { |l| l.respond_to?(:id) ? l.id : l.name }
  end

  def label_ids
    @labels.map { |l| l.respond_to?(:id) ? l.id : l.name }
  end

  #
  # IMPORTANT: This note applies to all of the following label mutation methods!
  #
  # The REST API controllers expects any gRPC errors within the BANG METHODS to
  # propagate directly. If refactoring in the future to rescue errors here, the
  # relevant API controllers will also need to be updated to handle re-raised
  # `RunnerServiceError` objects instead of `GRPC::*` error objects.
  #

  def add_custom_labels!(label_names)
    # Throw if @owner is not set
    raise RunnerServiceError.new("Cannot identify runner's owning entity", status: 500) if @owner.nil?

    if self.class.use_runner_admin?(@owner, is_write: true)
      updated = update_labels_by_name!(
        labels_to_add: label_names,
        error_message: "Failed to add labels: #{label_names.join(', ')}",
      )
      return true if updated
    end

    # Return immediately if no labels were requested
    return true if label_names.nil? || label_names.empty?

    # Filter out any labels that are already on the runner
    lower_existing_label_names = custom_labels.map { |label| label.name.downcase }
    label_names_to_add = label_names.reject { |name| lower_existing_label_names.include?(name.downcase) }

    # If the runner already has all of these labels, no need for further action
    return true if label_names_to_add.empty?

    # Find any labels that are duplicates of existing system labels
    lower_existing_system_label_names = system_labels.map { |label| label.name.downcase }
    duplicate_system_label_names = label_names_to_add.filter { |name| lower_existing_system_label_names.include?(name.downcase) }

    # Throw if attempting to add a duplicate of an existing system label
    unless duplicate_system_label_names.empty?
      raise RunnerServiceError.new(
        "Cannot add labels that duplicate existing read-only labels: #{duplicate_system_label_names.join(', ')}",
        status: 422
      )
    end

    resp = Launch::Twirp.self_hosted_runners_client.list_labels(@owner)

    message = resp.options[:message] if resp.options.present? && resp.options.key?(:message)
    raise RunnerServiceError.new(message, status: resp.status, options: resp.options) unless resp.call_succeeded
    defined_labels = resp.value&.labels || []

    # Find labels to add that are already created on the owning entity
    lower_label_names_to_add = label_names_to_add.map(&:downcase)
    labels_to_append = defined_labels.select { |label| lower_label_names_to_add.include?(label.name.downcase) }

    # Find labels that must first be created on the owning entity before they can be added
    defined_label_names = defined_labels.map { |label| label.name.downcase }
    label_names_to_create = label_names_to_add.reject { |label| defined_label_names.include?(label.downcase) }

    # Create any undefined labels on the owning entity
    label_names_to_create.each do |label|
      created_label = create_label!(label)
      labels_to_append.push(created_label)
    end

    # Add the missing labels to the runner
    update_labels!(
      additions: labels_to_append.map(&:id),
      error_message: "Failed to add labels: #{labels_to_append.map(&:name).join(', ')}",
    )

    true
  end

  def replace_all_custom_labels!(label_names)
    # Throw if @owner is not set
    raise RunnerServiceError.new("Cannot identify runner's owning entity", status: 500) if @owner.nil?

    if self.class.use_runner_admin?(@owner, is_write: true)
      replaced = set_labels_by_name!(
        labels: label_names,
        error_message: "Failed to set labels: #{label_names.join(', ')}",
      )
      return true if replaced
    end

    label_names ||= []

    # Determine which labels need to be removed from the runner
    lower_label_names = label_names.map(&:downcase)
    labels_to_remove = custom_labels.reject { |label| lower_label_names.include?(label.name.downcase) }

    # Determine which label names need to be added to the runner
    lower_existing_label_names = custom_labels.map { |label| label.name.downcase }
    label_names_to_add = label_names.reject { |name| lower_existing_label_names.include?(name.downcase) }

    # If the runner already has this exact set of custom labels, no need for further action
    return true if labels_to_remove.empty? && label_names_to_add.empty?

    # Find any labels that are duplicates of existing system labels
    lower_existing_system_label_names = system_labels.map { |label| label.name.downcase }
    duplicate_system_label_names = label_names_to_add.filter { |name| lower_existing_system_label_names.include?(name.downcase) }

    # Throw if attempting to add a duplicate of an existing system label
    unless duplicate_system_label_names.empty?
      raise RunnerServiceError.new(
        "Cannot set labels that duplicate existing read-only labels: #{duplicate_system_label_names.join(', ')}",
        status: 422
      )
    end

    # Start with an empty array
    labels_to_append = []

    unless label_names_to_add.empty?
      # Get a list of all of the labels already created on the owning entity
      resp = Launch::Twirp.self_hosted_runners_client.list_labels(@owner)
      message = resp.options[:message] if resp.options.present? && resp.options.key?(:message)
      raise RunnerServiceError.new(message, status: resp.status, options: resp.options) unless resp.call_succeeded
      defined_labels = resp.value&.labels || []

      # Find labels to add that are already created on the owning entity
      lower_label_names_to_add = label_names_to_add.map(&:downcase)
      labels_to_append = defined_labels.select { |label| lower_label_names_to_add.include?(label.name.downcase) }

      # Find labels that must first be created on the owning entity before they can be added
      defined_label_names = defined_labels.map { |label| label.name.downcase }
      label_names_to_create = label_names_to_add.reject { |label| defined_label_names.include?(label.downcase) }

      # Create any undefined labels on the owning entity
      label_names_to_create.each do |label|
        created_label = create_label!(label)
        labels_to_append.push(created_label)
      end
    end

    # Update the labels for the runner
    update_labels!(
      additions: labels_to_append.map(&:id),
      removals: labels_to_remove.map(&:id),
      error_message: "Failed to set labels: #{label_names.join(', ')}",
    )

    true
  end

  def remove_all_custom_labels!
    # Throw if @owner is not set
    raise RunnerServiceError.new("Cannot identify runner's owning entity", status: 500) if @owner.nil?

    if self.class.use_runner_admin?(@owner, is_write: true)
      replaced = set_labels_by_name!(
        labels: [],
        error_message: "Failed to remove labels",
      )
      return true if replaced
    end

    # If the runner already has zero custom labels, no need for further action
    return true if custom_labels.empty?

    # Update the labels for the runner
    update_labels!(
      removals: custom_labels.map(&:id),
      error_message: "Failed to remove all labels",
    )

    true
  end

  def remove_custom_label!(label_name)
    # Throw if @owner is not set
    raise RunnerServiceError.new("Cannot identify runner's owning entity", status: 500) if @owner.nil?

    # Throw if label is not provided
    raise RunnerServiceError.new("Label name not provided", status: 422) if label_name.blank?

    if self.class.use_runner_admin?(@owner, is_write: true)
      updated = update_labels_by_name!(
        labels_to_remove: [label_name],
        error_message: "Failed to remove label: #{label_name}",
      )
      return true if updated
    end

    # Determine which label needs to be removed from the runner
    lower_label_name = label_name.downcase
    labels_to_remove = @labels.filter { |label| label.name.downcase == label_name.downcase }

    # Throw if this label is not present on the runner
    raise RunnerServiceError.new("Runner does not have that label", status: 404) if labels_to_remove.empty?

    # Throw if, somehow, more than one label was found
    raise RunnerServiceError.new("Found more than one matching label", status: 500) if labels_to_remove.length > 1

    # Throw if attempting to remove a system label
    if labels_to_remove.any? { |label| label.type == SYSTEM_LABEL_TYPE }
      raise RunnerServiceError.new("Cannot remove read-only label", status: 422)
    end

    # Update the labels for the runner
    update_labels!(
      removals: labels_to_remove.map(&:id),
      error_message: "Failed to remove label: #{label_name}",
    )

    true
  end

  private

  sig { params(resp: TwirpResponse, default_error: String).void }
  def validate_twirp_response!(resp, default_error)
    return if resp.call_succeeded?

    raise RunnerServiceError.new(
      resp.options[:message] || default_error,
      status: resp.status,
      options: resp.options
    )
  end

  sig { params(label: String).returns(GitHub::Launch::Services::Selfhostedrunners::Label) }
  def create_label!(label)

    resp = Launch::Twirp.self_hosted_runners_client.create_label(@owner, label)
    validate_twirp_response!(resp, "Failed to create label: #{label}")

    created_label = resp.value&.label

    unless created_label
      raise RunnerServiceError.new("Failed to create label: #{label}", status: 500)
    end

    created_label
  end

  sig { params(error_message: String, additions: T::Array[Integer], removals: T::Array[Integer]).void }
  def update_labels!(error_message:, additions: [], removals: [])
    resp = Launch::Twirp.self_hosted_runners_client.bulk_update_labels(
      @owner,
      runner_ids: [@id.to_i],
      additions:,
      removals:
    )
    validate_twirp_response!(resp, error_message)
    updated_runner = resp.value.runners&.first

    # Verify we received an updated runner response
    raise RunnerServiceError.new(error_message, status: 500) unless updated_runner

    # Only update the labels
    @labels = updated_runner.labels
  end

  sig { params(error_message: String, labels_to_add: T::Array[String], labels_to_remove: T::Array[String]).returns(T::Boolean) }
  def update_labels_by_name!(error_message:, labels_to_add: [], labels_to_remove: [])
    runner_admin_client = GitHub.build_runner_admin_client(@owner)
    resp = runner_admin_client.update_labels(owner: @owner, runner_id: @id.to_i, labels_to_add: labels_to_add, labels_to_remove: labels_to_remove)

    # Check for 403 status as that means we should fall back to pipelines
    if resp.status == 403
      return false
    end

    validate_twirp_response!(resp, error_message)
    updated_runner = resp.value.runner

    # Verify we received an updated runner response
    raise RunnerServiceError.new(error_message, status: 500) unless updated_runner

    # Only update the labels
    @labels = updated_runner.labels
    true
  end

  sig { params(error_message: String, labels: T::Array[String]).returns(T::Boolean) }
  def set_labels_by_name!(error_message:, labels: [])
    runner_admin_client = GitHub.build_runner_admin_client(@owner)
    resp = runner_admin_client.set_labels(owner: @owner, runner_id: @id.to_i, labels: labels)

    if resp.status == 403
      return false
    end

    validate_twirp_response!(resp, error_message)
    updated_runner = resp.value.runner

    # Verify we received an updated runner response
    raise RunnerServiceError.new(error_message, status: 500) unless updated_runner

    # Only update the labels
    @labels = updated_runner.labels
    true
  end
end
