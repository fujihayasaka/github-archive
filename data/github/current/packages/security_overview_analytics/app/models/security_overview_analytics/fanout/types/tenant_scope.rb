# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Fanout
    module Types
      class TenantScope < T::Enum
        enums do
          Business = new("business")
          Organization = new("organization")
          User = new("user")
        end

        sig { params(tenant: T.any(::User, ::Organization, ::Business)).returns(TenantScope) }
        def self.from_tenant(tenant)
          case tenant
          when ::Business
            TenantScope::Business
          when ::Organization
            TenantScope::Organization
          when ::User
            TenantScope::User
          else
            T.absurd(tenant)
          end
        end
      end
    end
  end
end
