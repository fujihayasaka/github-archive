# typed: strict
# frozen_string_literal: true

module Repositories
  # This class serves to provide a Platform::Authorization::Permission object to RepositoriesOrganizationFinder unless
  # it's been specifically told it can bypass the permission check. This is to ensure that if the finder object is
  # used outside GraphQL it's done so with the knowledge that the permission check is not happening.
  class PlatformPermissionSwitch
    sig { params(permission: T.nilable(Platform::Authorization::Permission), override: T::Boolean).void }
    def initialize(permission, override: false)
      @permission = permission
      @override = override
    end

    sig { returns(T.nilable(Platform::Authorization::Permission)) }
    def permission!
      raise ArgumentError, "permission cannot be nil" if @permission.nil? && !@override
      @permission
    end
  end
end
