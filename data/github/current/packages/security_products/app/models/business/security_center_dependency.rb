# typed: strict
# frozen_string_literal: true

module Business::SecurityCenterDependency
  extend ActiveSupport::Concern

  sig { void }
  def trigger_security_center_reconciliation
    T.bind(self, ::Business)

    SecurityCenter::BusinessReconciliationJob.perform_later(
      business_id: self.id,
      source_event: SecurityCenter::BusinessReconciliationJob::RECONCILIATION_EVENT,
      entity_type: SecurityCenter::BusinessReconciliationJob::EntityType::Organization
    )
    SecurityCenter::BusinessReconciliationJob.perform_later(
      business_id: self.id,
      source_event: SecurityCenter::BusinessReconciliationJob::RECONCILIATION_EVENT,
      entity_type: SecurityCenter::BusinessReconciliationJob::EntityType::User
    )
  rescue => exception # rubocop:disable Lint/GenericRescue
    # Reports exception but does not block caller if fails to attempt the backfill
    Failbot.report(exception, {
      "gh.business.id": self.id,
    })
  end
end
