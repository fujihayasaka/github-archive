# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module FanoutScheduler
    extend T::Helpers

    abstract!

    sig { params(scope: T.any(::User, ::Organization, ::Business)).void }
    def self.initialize_for(scope)
      args = {
        tenant_id: scope.id,
        action: Fanout::Types::Action::Initialize.serialize
      }

      if scope.is_a?(::Business)
        Fanout::BusinessJob.perform_later(**args.merge(
          tenant_scope: Fanout::Types::TenantScope::Business.serialize,
          owner_type: Fanout::Types::Owner::Organization.serialize
        ))
        Fanout::BusinessJob.perform_later(**args.merge(
          tenant_scope: Fanout::Types::TenantScope::Business.serialize,
          owner_type: Fanout::Types::Owner::User.serialize
        ))
      elsif scope.is_a?(::Organization)
        Fanout::RepositoryOwnerJob.perform_later(**args.merge(
          tenant_scope: Fanout::Types::TenantScope::Organization.serialize,
        ))
      elsif scope.is_a?(::User)
        Fanout::RepositoryOwnerJob.perform_later(**args.merge(
          tenant_scope: Fanout::Types::TenantScope::User.serialize,
        ))
      else
        T.absurd(scope)
      end
    end

    sig { params(scope: T.any(::User, ::Organization, ::Business)).void }
    def self.reconcile_for(scope)
      args = {
        tenant_id: scope.id,
        action: Fanout::Types::Action::Reconcile.serialize
      }

      if scope.is_a?(::Business)
        Fanout::BusinessJob.perform_later(**args.merge(
          tenant_scope: Fanout::Types::TenantScope::Business.serialize,
          owner_type: Fanout::Types::Owner::Organization.serialize
        ))
        Fanout::BusinessJob.perform_later(**args.merge(
          tenant_scope: Fanout::Types::TenantScope::Business.serialize,
          owner_type: Fanout::Types::Owner::User.serialize
        ))
      elsif scope.is_a?(::Organization)
        Fanout::RepositoryOwnerJob.perform_later(**args.merge(
          tenant_scope: Fanout::Types::TenantScope::Organization.serialize,
        ))
      elsif scope.is_a?(::User)
        Fanout::RepositoryOwnerJob.perform_later(**args.merge(
          tenant_scope: Fanout::Types::TenantScope::User.serialize,
        ))
      else
        T.absurd(scope)
      end
    end
  end
end
