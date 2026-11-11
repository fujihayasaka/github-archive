# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    module Permissions
      class UserPermissionCheck < Platform::Loader
        include Scientist

        def self.load(user:, target:, permission_name:)
          self.for(user, target).load(permission_name)
        end

        def initialize(user, target)
          @user = user
          @target = target
        end

        def fetch(permission_names)
          result = {}

          if user.user?
            RolePermission.joins(role: [:user_roles]).where(
              action: permission_names,
              user_roles: { target_type: target.class, target_id: target.id, actor_type: "User", actor_id: user.id },
            ).each { |permission| result[permission.action] = true }
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
