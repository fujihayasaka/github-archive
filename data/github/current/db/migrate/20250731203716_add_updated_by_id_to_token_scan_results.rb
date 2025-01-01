# typed: true

class AddUpdatedByIdToTokenScanResults < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::TokenScanningService)

  def change
    change_table(:token_scan_results, bulk: true) do |t|
      t.column :updated_by_id, :bigint, null: true, unsigned: true, comment: "id of the actor who updated the alert"
    end
  end
end
