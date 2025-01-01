class AddGenericExemptionRequestIdToPushProtectionsBypass < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def up
    change_table(:secret_scanning_push_protections_bypass, bulk: true) do |t|
      t.column :exemption_request_id, :bigint, unsigned: true, null: true, comment: "If this bypass was created from a delegated bypass request, this is the bypass request ID (i.e `exemption_requests.id`)"
      t.index [:exemption_request_id], name: "index_exemption_request_id", comment: "Supports lookups by exemption_request_id, for the exemption UI pages"
    end
  end

  def down
    change_table(:secret_scanning_push_protections_bypass, bulk: true) do |t|
      t.remove :exemption_request_id
      t.remove_index name: "index_exemption_request_id"
    end
  end
end
