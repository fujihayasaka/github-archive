# typed: strict
# frozen_string_literal: true

module CustomRoles
  class EnterpriseRolePermissionsComponent < ApplicationComponent
    include GitHub::Memoizer

    sig { returns(EnterpriseRole) }
    attr_reader :role

    sig { params(role: EnterpriseRole).void }
    def initialize(role:)
      @role = role
    end

    private

    sig { returns(T::Hash[String, T::Array[String]]) }
    memoize def enterprise_fgp_metadata
      EnterpriseFgpMetadata.for_role(role)
    end
  end
end
