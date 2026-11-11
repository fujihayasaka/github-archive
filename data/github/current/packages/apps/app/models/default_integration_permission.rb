# typed: true
# frozen_string_literal: true

class DefaultIntegrationPermission < ApplicationRecord::Domain::Users
  # Module which can be used to extend the association proxy in order to
  # provide some serializable-like methods.
  #
  # This allows you to treat the collection as a serialized Hash of permissions
  # where the keys are resource Strings and the values are permission symbols.
  # The backing records will be persisted/destroyed when the parent is saved.
  #
  # Example:
  #
  #   has_many :default_integration_permissions,
  #     :autosave => true,
  #     :extend => DefaultIntegrationPermission::AssociationExtension
  #
  #   instance.default_integration_permissions.permission_map
  #   # => {"statuses" => :write, "contents" => :read}
  #
  #   instance.default_integration_permissions.permission_map = {
  #       "contents" => :write
  #     }
  #   # => {"contents" => :write}
  #   instance.save
  #   instance.default_integration_permissions.all
  #   # => [#<DefaultIntegrationPermission resource: "contents", action: "write">]
  #
  module AssociationExtension
    extend T::Helpers

    # Public: Returns permissions currently assigned to the integration
    # excluding any permissions which are currently marked for removal.
    #
    # Returns an Hash of resource Strings to permission Symbols.
    def permission_map
      T.bind(self, ActiveRecord::Associations::CollectionProxy)

      active_permissions = select { |record| !record.marked_for_destruction? }
      active_permissions.each_with_object({}) do |record, memo|
        memo[record.resource] = record.action.to_sym
      end
    end

    # Public: Sets the integration's desired permissions. Any existing
    # permissions not included will be marked for removal and destroyed when
    # the integration is saved.
    #
    # assigned_permissions - A Hash of resource Strings to permission Symbols.
    #
    # Returns the assigned Hash of permissions.
    def permission_map=(assigned_permissions)
      assigned_permissions = assigned_permissions.each_with_object({}) do |(k, v), memo|
        memo[k.to_s] = v.to_sym
      end

      if should_apply_mandatory_permissions?
        assigned_permissions = apply_mandatory_permissions(assigned_permissions)
      end

      existing_permissions = permission_map
      permissions_to_add = assigned_permissions.keys - existing_permissions.keys
      permissions_to_remove = existing_permissions.keys - assigned_permissions.keys
      permissions_to_change = existing_permissions.keys.select do |resource|
        existing_permissions[resource] != assigned_permissions[resource]
      end

      permissions_to_add.each do |resource|
        T.bind(self, ActiveRecord::Associations::CollectionProxy)
        build(resource: resource, action: assigned_permissions[resource])
      end

      permissions_to_remove.each do |resource|
        T.bind(self, ActiveRecord::Associations::CollectionProxy)
        permission_to_remove = detect { |record| record.resource == resource }
        permission_to_remove.mark_for_destruction
      end

      permissions_to_change.each do |resource|
        T.bind(self, ActiveRecord::Associations::CollectionProxy)
        permission_to_change = detect { |record| record.resource == resource }
        permission_to_change.action = assigned_permissions[resource]
      end

      assigned_permissions
    end

    private

    # Private: adds resource-specific mandatory permissions to the given
    # assigned_permissions, based on the selected permissions.
    # E.g. selecting _any_ repository resource permission mandates the
    # selection of the "metadata" permission.
    #
    # assigned_permissions - A Hash of resource Strings to permission Symbols.
    #
    # Returns Hash of permissions to be assigned.
    def apply_mandatory_permissions(assigned_permissions)
      if (Repository::Resources.subject_types & assigned_permissions.keys).any?
        assigned_permissions["metadata"] = :read
      end
      assigned_permissions
    end

    def should_apply_mandatory_permissions?
      T.bind(self, ActiveRecord::Associations::CollectionProxy)

      version = proxy_association.owner
      return true unless version.parent_installation.present?

      # For ScopedInstallations we only apply mandatory permissions
      # if the parent installation includes them already. That way
      # we don't accidentally escalate permissions for installations
      # that were created BEFORE we started applying mandatory permissions

      Permission.where(
        actor_id: version.parent_installation.ability_id,
        actor_type: version.parent_installation.ability_type,
        subject_type: Repository::Resources.all_prefixed_subject_types(["metadata"])
      ).exists?
    end
  end

  # Public: String name of the resource (e.g., "issues").
  # column :resource

  enum :action, Ability.actions

  validates_uniqueness_of :resource, scope: :integration_version_id, case_sensitive: false
  validates_inclusion_of :resource, in: :valid_resource_types
  validates :action, presence: true

  validate :validate_readonly_permissions
  validate :validate_writeonly_permissions
  validate :validate_adminable_permissions

  before_create :set_integration

  private

  def set_integration
    self.integration_id = T.must(IntegrationVersion.find_by(id: self.integration_version_id)).integration_id
  end

  def valid_resource_types
    Actions::WorkflowRun::Resources.subject_types + \
      Business::Resources.subject_types + \
      Codespace::Resources.subject_types + \
      Organization::Resources.subject_types + \
      Repository::Resources.subject_types + \
      User::Resources.subject_types
  end

  def validate_readonly_permissions
    if Permissions::ResourceRegistry.readonly_subject_type?(resource)
      if action != "read"
        errors.add(:resource, "(#{resource}) is a read-only permission")
      end
    end
  end

  def validate_writeonly_permissions
    if Permissions::ResourceRegistry.writeonly_subject_type?(resource)
      if action != "write"
        errors.add(:resource, "(#{resource}) is a write-only permission")
      end
    end
  end

  def validate_adminable_permissions
    unless Permissions::ResourceRegistry.adminable_subject_type?(resource)
      if action == "admin"
        errors.add(:resource, "(#{resource}) is not permitted to have admin access")
      end
    end
  end
end
