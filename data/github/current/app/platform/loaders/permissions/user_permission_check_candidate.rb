# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    module Permissions
      class UserPermissionCheckCandidate < Platform::Loader
        include Scientist

        def self.load(user:, target:, permission_name:)
          self.for(user, permission_name, target.class).load(target)
        end

        def initialize(user, permission_name, target_class)
          @user = user
          @permission_name = permission_name
          @target_class = target_class
        end

        def fetch(targets)
          result = {}
          targets_by_id = targets.index_by(&:id)
          if user.user?
            RolePermission.joins(role: [:user_roles]).where(
              action: @permission_name,
              user_roles: { target_type: @target_class, target_id: targets, actor_type: "User", actor_id: user.id },
            ).select("user_roles.target_id").each { |permission| result[targets_by_id[permission.attributes["target_id"]]] = true }
          end

          result.default = false
          result
        end

        private

        attr_reader :user, :target
      end
    end
  end
end
