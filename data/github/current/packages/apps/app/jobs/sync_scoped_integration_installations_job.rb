# typed: true
# frozen_string_literal: true

class SyncScopedIntegrationInstallationsJob < ApplicationJob
  queue_as :sync_scoped_integration_installations

  discard_on ActiveRecord::RecordNotFound

  retry_on_dirty_exit

  ACTOR_TYPE = "ScopedIntegrationInstallation"
  BATCH_SIZE = 1000
  XXL_BATCH_SIZE = 5000

  attr_reader :parent

  def perform(installation, action:, **options)
    @parent = installation

    return true if active_scoped_integration_installation_ids.none?

    case action
    when :permissions_updated
      update_permissions(options[:old_version], options[:new_version], options[:entry_point])
    when :repositories_removed
      uninstall_repositories(options[:repository_ids], entry_point: options[:entry_point])
    end
  end

  private

  def active_scoped_integration_installation_ids
    return @active_scoped_integration_installation_ids if defined?(@active_scoped_integration_installation_ids)
    active_scoped_integration_installation_ids = T.let([], T::Array[Integer])

    parent.children.where(authorization_details: nil).in_batches(of: XXL_BATCH_SIZE) do |relation|
      active_scoped_integration_installation_installation_ids = active_scoped_integration_installation_ids.concat(relation.pluck(:id))
    end

    @active_scoped_integration_installation_installation_ids = active_scoped_integration_installation_ids
  end

  def downgrade_permissions(permissions, entry_point)
    # This transforms a set of permissions
    #
    # { "pull_requests" => :read, "issues" => :write, "repository_projects" => :write }
    #
    # and groups the resources by the action
    #
    # { :read => ["pull_requests"], :write => ["issues", "repository_projects"] }
    permissions = permissions.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(resource, access), out|
      out[access] << resource
    end

    permissions.each_pair do |access, resources|
      Permissions::Service.update_action_for_permissions(
        actor_ids: active_scoped_integration_installation_ids,
        actor_type: ACTOR_TYPE,
        subject_types: subject_types_from(resources),
        action: access,
        entry_point: entry_point
      )
    end
  end

  def subject_types_from(resources)
    if resources.is_a?(Array)
      Repository::Resources.all_prefixed_subject_types(resources) + \
        Organization::Resources.all_prefixed_subject_types(resources)
    elsif resources.is_a?(Hash)
      subject_types_from(resources.keys)
    end
  end

  def remove_permissions(permissions, entry_point)
    subject_types = subject_types_from(permissions)
    return if subject_types.empty?

    Permissions::Service.revoke_permissions_granted_on_actors(
      actor_ids: active_scoped_integration_installation_ids,
      actor_type: ACTOR_TYPE,
      subject_types: subject_types,
      entry_point: entry_point
    )
  end

  # Internal: Uninstall a set of repositories from all active ScopedIntegrationInstallation
  # records.
  #
  # Returns nil.
  def uninstall_repositories(repository_ids, entry_point:)
    return if repository_ids.empty?

    # Limit the query to the permissions we know are granted on the installation
    subject_types = subject_types_from(parent.version.permissions_of_type(Repository))
    return if subject_types.empty?

    ActiveRecord::Base.connected_to(role: :writing) do
      Permissions::Service.revoke_permissions_granted_on_subjects(
        actor_ids: active_scoped_integration_installation_ids,
        actor_type: ACTOR_TYPE,
        subject_ids: repository_ids,
        subject_types: subject_types,
        entry_point: entry_point,
      )
    end
  end

  def update_permissions(old_version, new_version, entry_point)
    diff = new_version.diff(old_version)

    ActiveRecord::Base.connected_to(role: :writing) do
      ApplicationRecord::Permissions.transaction do
        downgrade_permissions(diff.permissions_downgraded, entry_point)
        remove_permissions(diff.permissions_removed, entry_point)
      end
    end
  end
end
