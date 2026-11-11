# typed: strict
# frozen_string_literal: true

module Authz
  class Domain
    class RepoPermissionType < T::Enum
      enums do
        # Repository permissions that can be assigned to user roles
        # See: github/github/config/system_roles.yml
        #
        # READ - corresponds to read_repo permission
        # Example usage in: read, triage, all_repo_read, all_repo_triage system roles
        READ = new("read_repo")

        # WRITE - corresponds to write_repo permission
        # Example usage in: write, maintain, all_repo_write, all_repo_maintain system roles
        WRITE = new("write_repo")

        # ADMIN - corresponds to admin_repo permission
        # Example usage in: admin and all_repo_admin system roles
        ADMIN = new("admin_repo")

        # ANY - represents a list of read_repo, write_repo and admin_repo
        # used to query the existance of any permission assigned
        ANY = new("any")
      end

      # Returns the appropriate value for a given permission level
      sig { params(permission: RepoPermissionType).returns(T::Array[String]) }
      def self.for_level(permission)
        case permission
        when ANY
          values.reject { |value| value == ANY }.map(&:serialize)
        else
          [permission.serialize]
        end
      end

      # Helper to convert a symbol of :read, :write or :admin to a RepoPermissionType
      sig { params(action: Symbol).returns(RepoPermissionType) }
      def self.ability_action_to_repo_permission(action)
        case action
        when :read, :write, :admin
          self.deserialize("#{action}_repo")
        else
          raise ArgumentError, "Invalid action: #{action}"
        end
      end

      # Helper to convert a string to a RepoPermissionType; default to read
      sig { params(str: T.nilable(String)).returns(RepoPermissionType) }
      def self.from_string(str)
        str.nil? ? READ : self.deserialize(str)
      end
    end
  end
end
