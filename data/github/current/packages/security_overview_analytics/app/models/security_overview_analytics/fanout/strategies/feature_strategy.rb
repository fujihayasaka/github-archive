# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Fanout
    module Strategies
      class FeatureStrategy
        extend T::Helpers
        include GitHub::Memoizer

        abstract!

        sig do
          params(
            tenant: T.any(::User, ::Organization, ::Business),
            owner_type: T.nilable(Types::Owner)
          ).void
        end
        def initialize(tenant:, owner_type: nil)
          @tenant = tenant
          @tenant_type = T.let(Types::TenantScope.from_tenant(tenant), Types::TenantScope)
          @owner_type = owner_type

          raise ArgumentError, "`owner_type` required for business tenant scope." if @tenant_type == Types::TenantScope::Business && @owner_type.nil?
        end

        sig { abstract.returns(Types::Feature) }
        def feature; end

        sig { abstract.returns(T::Boolean) }
        def feature_available?; end

        sig { abstract.returns(T.nilable(Session)) }
        def unlocked_session; end

        sig { abstract.params(action: Types::Action).returns(T.nilable(T.any(T.class_of(TenantBaseJob), T.class_of(RepositoryBaseJob)))) }
        def available_fanout_job(action); end

        sig { abstract.params(action: Types::Action, at: T.nilable(Time)).void }
        def lock_session!(action, at:); end
      end
    end
  end
end
