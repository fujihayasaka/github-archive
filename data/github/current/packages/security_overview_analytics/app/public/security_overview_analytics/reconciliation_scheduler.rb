# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module ReconciliationScheduler
    extend T::Helpers

    abstract!

    sig { params(scope: T.any(::User, ::Business)).void }
    def self.run_for(scope)
      if scope.is_a?(::Business)
        Reconciliation::BusinessReconciliationJob.perform_later(business_id: T.cast(scope.id, Integer))
        Reconciliation::BusinessReconciliationJob.perform_later(
          business_id: T.cast(scope.id, Integer),
          entity_type: SecurityCenter::Serializers::BusinessReconciliationJobEntityType::EntityType::User
        )
      elsif scope.is_a?(::Organization)
        Reconciliation::OrganizationReconciliationJob.perform_later(organization_id: scope.id)
      elsif scope.is_a?(::User)
        # TODO Safely transition organizations to the owner reconciliation job
        Reconciliation::OwnerReconciliationJob.perform_later(owner_id: scope.id)
      else
        T.absurd(scope)
      end
    end
  end
end
