# typed: true
# frozen_string_literal: true

module Codespaces
  class WriteAllowedPermissions < Command
    attr_reader :current_user, :current_repo, :ref, :repository_permissions, :owner_permissions, :opt_out, :is_prebuild, :prebuild_configuration_id

    class PermissionDifferenceError < Codespaces::Error; end

    def initialize(user:, repository:, owner_permissions:, repository_permissions:, ref: nil, devcontainer_path: nil, opt_out: false, category: nil, is_prebuild: false, prebuild_configuration_id: nil)
      @current_user = user
      @current_repo = repository
      @ref = ref.presence || current_repo.default_branch
      @devcontainer_path = devcontainer_path
      @repository_permissions = repository_permissions ? repository_permissions.as_json.to_h : nil
      @owner_permissions = owner_permissions ? owner_permissions.as_json.to_h : nil
      @opt_out = opt_out
      @category = category
      @is_prebuild = is_prebuild
      @prebuild_configuration_id = prebuild_configuration_id
    end

    def perform
      return clear_permissions if opt_out

      clear_invalid_target_permissions

      records_to_add = []
      diff_permissions = build_permissions_diff
      diff_permissions.unconsented.each do |target, target_permissions|
        target_permissions.each do |resource, action|
          records_to_add << {
            user_id: current_user.id,
            repository_id: current_repo.id,
            target_id: target.id,
            target_type: target.class.base_class.name,
            resource: resource,
            action: is_prebuild ? downgrade_action(action) : action,
            is_prebuild: is_prebuild,
            codespace_prebuild_configuration_id: prebuild_configuration_id
          }
        end
      end

      records_to_delete = {
        user_id: current_user.id,
        repository_id: current_repo.id,
        target_id: [],
        target_type: [],
        resource: [],
        action: []
      }

      diff_permissions.revoked.each do |target, target_permissions|
        records_to_delete[:target_id] << target.id
        records_to_delete[:target_type] << target.class.base_class.name
        target_permissions.each do |resource, action|
          records_to_delete[:resource] << resource
          records_to_delete[:action] << action
        end
      end

      Codespaces::AllowedPermission.transaction do
        Codespaces::AllowedPermission.where(records_to_delete).delete_all if diff_permissions.revoked.any?
        Codespaces::AllowedPermission.insert_all!(records_to_add) unless records_to_add.empty?
      end
      GitHub.dogstats.increment("codespaces.allow_permissions.success.count", tags: ["category:#{@category}", "action:accept_permissions"])
      GitHub.instrument("codespaces.allow_permissions", {
        origin_repository: current_repo.name_with_display_owner,
        requested_permissions: diff_permissions.requested.transform_keys { |k| k.respond_to?(:name_with_display_owner) ? k.name_with_display_owner : k.display_login },
        revoked_permissions: diff_permissions.revoked.transform_keys { |k| k.respond_to?(:name_with_display_owner) ? k.name_with_display_owner : k.display_login },
      })
    rescue Codespaces::DevContainer::ReadError
      return if !opt_out && owner_permissions.nil? && repository_permissions.nil?
      raise
    end

    private

    def downgrade_action(action)
      action == "write" ? "read" : action
    end

    def clear_permissions
      if is_prebuild
        Codespaces::AllowedPermission.where(repository: current_repo, is_prebuild: true, codespace_prebuild_configuration_id: prebuild_configuration_id).delete_all
      else
        Codespaces::AllowedPermission.where(user: current_user, repository: current_repo).delete_all
      end

      GitHub.dogstats.increment("codespaces.allow_permissions.success.count", tags: ["category:#{@category}", "action:opt_out"])
    end

    def clear_invalid_target_permissions
      scope = if is_prebuild
        Codespaces::AllowedPermission.where(repository: current_repo, is_prebuild: true, codespace_prebuild_configuration_id: prebuild_configuration_id)
      else
        Codespaces::AllowedPermission.where(user: current_user, repository: current_repo)
      end
      invalid_targets = scope.includes(:target).select { |permission| permission.target.nil? }
      Codespaces::AllowedPermission.where(id: invalid_targets.map(&:id)).delete_all
    end

    def build_permissions_diff
      ref_obj = Codespaces::GetTargetRef.call(repository: current_repo, name_or_oid: ref)

      # TODO: pass in custom filepath from codespace params once that is added
      devcontainer = Codespaces::DevContainer.new(repository: current_repo, oid: ref_obj&.target_oid, filepath: @devcontainer_path, user: current_user, is_prebuild: is_prebuild)

      diff_permissions = devcontainer.diff_all_permissions(prebuild_configuration_id: prebuild_configuration_id)

      return diff_permissions if diff_permissions.unconsented.blank? #Nothing to add so we can return early

      unless validate_repository_permissions(devcontainer) && validate_owner_permissions(devcontainer)
        raise PermissionDifferenceError, "The permissions in the devcontainer.json file do not match the requested permissions."
      end

      diff_permissions
    end

    def validate_repository_permissions(devcontainer)
      existing_permissions = devcontainer.repository_permissions.transform_keys { |k| k.name_with_display_owner }
      (repository_permissions.blank? && existing_permissions.blank?) || repository_permissions == existing_permissions
    end

    def validate_owner_permissions(devcontainer)
      existing_permissions = devcontainer.all_repository_permissions.transform_keys { |k| k.display_login }
      (owner_permissions.blank? && existing_permissions.blank?) || owner_permissions == existing_permissions
    end
  end
end
