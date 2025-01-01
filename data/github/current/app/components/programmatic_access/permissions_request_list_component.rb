# typed: true
# frozen_string_literal: true

class ProgrammaticAccess::PermissionsRequestListComponent < ApplicationComponent
  def initialize(grant: nil, grant_request:, type:)
    @grant = grant || ProgrammaticAccessGrant.null_grant(
      grant_request.user_programmatic_access, grant_request.target
    )

    @grant_request = grant_request
    @type = type
  end

  memoize def permissions_differ
    PermissionsDiffer.new(
      previous_permissions: @grant&.permissions_of_type(@type.constantize) || {},
      new_permissions: @grant_request.permissions_of_type(@type.constantize)
    )
  end

  delegate :upgraded_permissions, :downgraded_permissions, :added_permissions, :removed_permissions, to: :permissions_differ

  def upgraded_permissions?
    !upgraded_permissions.empty?
  end

  def upgraded_write_permissions
    fetch_permissions_by_action(upgraded_permissions, action: :write)
  end

  def upgraded_write_permissions?
    !upgraded_write_permissions.empty?
  end

  def downgraded_permissions?
    !downgraded_permissions.empty?
  end

  def downgraded_read_permissions
    fetch_permissions_by_action(downgraded_permissions, action: :read)
  end

  def downgraded_read_permissions?
    !downgraded_permissions.empty?
  end

  def added_permissions?
    !added_permissions.empty?
  end

  def added_read_permissions
    fetch_permissions_by_action(added_permissions, action: :read)
  end

  def added_read_permissions?
    !added_read_permissions.empty?
  end

  def added_write_permissions
    fetch_permissions_by_action(added_permissions, action: :write)
  end

  def added_write_permissions?
    !added_write_permissions.empty?
  end

  def removed_permissions?
    !removed_permissions.empty?
  end

  def removed_read_permissions
    fetch_permissions_by_action(removed_permissions, action: :read)
  end

  def removed_read_permissions?
    !removed_read_permissions.empty?
  end

  def removed_write_permissions
    fetch_permissions_by_action(removed_permissions, action: :write)
  end

  def removed_write_permissions?
    !removed_write_permissions.empty?
  end

  def fetch_permissions_by_action(permissions, action:)
    permissions.select { |_, value| value == action }
  end

  def format_permission_names(keys)
    names = Permissions::FineGrainedResources::Metadata.human_readable_resource_names.values_at(*keys)
    names.compact.sort.to_sentence
  end

  def has_any_changes?
    # TODO: we may need to distinguish between a grant request
    # that has no changes and a grant and request that has no permissions
    upgraded_permissions? || downgraded_permissions? || added_permissions? || removed_permissions?
  end
end
