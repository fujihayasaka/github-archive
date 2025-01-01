# typed: true
# frozen_string_literal: true

class IntegrationVersion
  class PermissionsExpander
    # Public: Map the given permissions to their Ability subjects.
    #
    # permissions - The Hash of permissions that are being prefixed.
    #
    # Example:
    #
    #   expand({ "statuses" => :read })
    #   # => ["User/repositories/statuses", "Repository/statuses"]
    #
    #   expand({ "members" => :write })
    #   # => ["Organization/members"]
    #
    #   expand({})
    #   # => []
    #
    # Returns an Array of Strings otherwise an empty Array.
    def self.expand(permissions = {})
      return [] if permissions.empty?

      expanded_permissions = []

      permissions.each_key do |permission|
        if Business::Resources.subject_types.include?(permission)
          expanded_permissions << "#{Business::Resources::ABILITY_TYPE_PREFIX}/#{permission}"
        end

        if Organization::Resources.subject_types.include?(permission)
          expanded_permissions << "#{Organization::Resources::ABILITY_TYPE_PREFIX}/#{permission}"
        end

        if Repository::Resources.subject_types.include?(permission)
          expanded_permissions << "#{Repository::Resources::ALL_ABILITY_TYPE_PREFIX}/#{permission}"
          expanded_permissions << "#{Repository::Resources::INDIVIDUAL_ABILITY_TYPE_PREFIX}/#{permission}"
        end

        if User::Resources.subject_types.include?(permission)
          expanded_permissions << "#{User::Resources::ABILITY_TYPE_PREFIX}/#{permission}"
        end
      end

      expanded_permissions
    end
  end
end
