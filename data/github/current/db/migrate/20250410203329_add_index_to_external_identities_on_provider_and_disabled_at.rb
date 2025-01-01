# typed: true
# frozen_string_literal: true

class AddIndexToExternalIdentitiesOnProviderAndDisabledAt < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  sig { void }
  def up
    connection.execute "ALTER TABLE `external_identities` ADD `active` TINYINT(1) GENERATED ALWAYS AS (IF(disabled_at IS NULL AND deleted_at IS NULL, 1, 0)) STORED;"
    change_table(:external_identities, bulk: true) do |t|
      t.index [:provider_id, :provider_type, :active], name: "index_on_provider_id_and_provider_type_and_active"
    end
  end

  sig { void }
  def down
    change_table(:external_identities, bulk: true) do |t|
      t.remove :active
      t.remove_index [:provider_id, :provider_type, :active], name: "index_on_provider_id_and_provider_type_and_active"
    end
  end
end
