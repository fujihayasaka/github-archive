# typed: true
# frozen_string_literal: true

module PackageRegistry
  class CollabPackage < SimpleDelegator
    attr_reader :package

    def initialize(package)
      @package = package
      super
    end

    def owner
      return @owner if defined?(@owner)
      @owner = User.find_by(login: @package.namespace)
    end

    def user_role_target_type
      "Package"
    end

    def target_for_conditional_access
      # In the CAP framework, TFCA refers to the entity governing
      # the conditional access rules that grant access to resources they own.
      # If any changes are done to this method, please loop in @github/authorization.
      # https://thehub.github.com/engineering/development-and-ops/dotcom/cap/how-does-cap-evaluation-work/#target-for-conditional-access-tfca

      # There is a known vulnerability where a package can have a nil owner (user/org)
      # if the owner changes their name. Given that a package should always have an owner,
      # we must not use semantics such as: :no_target_for_conditional_access unless owner
      # as that would allow bypassing policy enforcement for org owned packages which may need it.
      # https://github.com/github/c2c-package-registry/issues/2240
      owner
    end

  end
end
