# typed: true
# frozen_string_literal: true

class ProgrammaticAccess::PermissionsListComponent < ApplicationComponent
  def initialize(grant:, type:)
    @grant = grant
    @type = type
  end

  def read_access?
    !!read_access
  end

  def write_access?
    !!write_access
  end

  def admin_access?
    !!admin_access
  end

  def any_access?
    read_access? || write_access? || admin_access?
  end

  memoize def read_access
    # for this type what read access does this grant have?
    read_permissions = fetch_permissions(:read)
    return nil if read_permissions.empty?
    format_permission_names(read_permissions.keys)
  end

  memoize def write_access
    # For this type, what write access does the grant have?
    write_permissions = fetch_permissions(:write)
    return nil if write_permissions.empty?
    format_permission_names(write_permissions.keys)
  end

  memoize def admin_access
    # For this type, what admin access does the grant have?
    admin_permissions = fetch_permissions(:admin)
    return nil if admin_permissions.empty?
    format_permission_names(admin_permissions.keys)
  end

  def fetch_permissions(action)
    permissions = @grant.permissions_of_type(@type.constantize)
    permissions.select { |_, value| value == action }
  end

  def format_permission_names(keys)
    names = Permissions::FineGrainedResources::Metadata.human_readable_resource_names.values_at(*keys)
    names.compact.sort.to_sentence
  end

  def heading
    t("personal_access_tokens.permission_selection.heading", permission_type: @type)
  end

  def no_permissions_text
    t("personal_access_tokens.permission_selection.none.granted", permission_type: @type.downcase)
  end
end
