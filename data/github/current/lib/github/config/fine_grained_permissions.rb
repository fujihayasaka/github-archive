# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module FineGrainedPermissions
      def fine_grained_permissions_config
        config = {}

        Rails.root.join("config/access_control/fine_grained_permissions/user_fgps/")
                  .glob("**/*.yml")
                  .each { |c| config.merge!(YAML.safe_load c.read) }

        config
      end

      def fine_grained_permissions
        @fine_grained_permissions ||= fine_grained_permissions_config
      end
    end
  end

  extend Config::FineGrainedPermissions
end
