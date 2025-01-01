# typed: true

class AddEventByToSecretScanningTokenRemediationEvents < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)
  def change
    change_table :secret_scanning_token_remediation_events, bulk: true do |t|
      t.bigint :event_by, unsigned: true, null: true, comment: "the user performed the event. If unset, the event was performed by the system"
    end
  end
end
