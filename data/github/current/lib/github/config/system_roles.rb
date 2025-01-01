# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module SystemRoles

      def system_roles_config
        YAML.safe_load Rails.root.join("config/system_roles.yml").read
      end

      def system_roles
        @system_roles ||= Permissions::SystemRoles.new(system_roles_config)
      end
    end
  end

  extend Config::SystemRoles
end
