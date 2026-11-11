# typed: true
# frozen_string_literal: true

class AddIndexToExternalIdentities < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :external_identities, bulk: true do |t|
      t.index [:provider_id, :provider_type, :deleted_at], name: "idx_external_identities_by_provider_and_deleted"
      t.index [:provider_id, :provider_type, :disabled_at], name: "idx_external_identities_by_provider_and_disabled"
    end
  end
end
