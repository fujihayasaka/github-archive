# typed: true
# frozen_string_literal: true

class MakeIntegrationTransferTargetPolymorphic < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Integrations)

  def up
    change_table(:integration_transfers, bulk: true) do |t|
      t.string :target_type, null: false, default: "User", limit: 32
      t.index [:target_id, :target_type], name: :index_integration_transfers_on_target_type_and_target_id
      t.remove_index :target_id, name: :index_integration_transfers_on_target_id

      # Changes requested by convention:GitHub/ExistingIdColumnsMustBeBigint 👮‍♀️
      t.change :id, :bigint, unsigned: true
      t.change :integration_id, :bigint, unsigned: true
      t.change :requester_id, :bigint, unsigned: true
      t.change :responder_id, :bigint, unsigned: true
      t.change :target_id, :bigint, unsigned: true
    end
  end

  def down
    change_table(:integration_transfers, bulk: true) do |t|
      t.index :target_id, name: :index_integration_transfers_on_target_id
      t.remove_index [:target_id, :target_type], name: :index_integration_transfers_on_target_type_and_target_id
      t.remove :target_type
      t.change :id, :integer
      t.change :integration_id, :integer
      t.change :requester_id, :integer
      t.change :responder_id, :integer
      t.change :target_id, :integer
    end
  end
end
