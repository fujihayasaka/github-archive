# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class RepositoryRuleset < Connections::Base
      def self.async_api_can_access?(permission, connection)
        object = connection.parent
        if object.is_a?(::Repository)
          permission.typed_can_access?("Repository", object)
        elsif object.is_a?(::Organization)
          permission.access_allowed?(
            :manage_organization_ref_rules,
            resource: object,
            current_repo: nil,
            current_org: object,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        elsif object.is_a?(Business) || object.is_a?(Platform::Models::Enterprise)
          permission.access_allowed?(
            :administer_business,
            resource: object,
            repo: nil,
            organization: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        else
          false
        end
      end

      total_count_field
    end
  end
end
