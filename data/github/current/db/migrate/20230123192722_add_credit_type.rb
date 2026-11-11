# typed: true

class AddCreditType < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)

  def up
    change_table :advisory_credits, bulk: true do |t|
      # For lint rule GitHub/ExistingIdColumnsMustBeBigint.
      t.change :id, :bigint, unsigned: true
      t.change :creator_id, :bigint, unsigned: true
      t.change :recipient_id, :bigint, unsigned: true

      # Enum defined in model
      t.column :credit_type, :integer, null: false, default: 0
    end
  end

  def down
    change_table :advisory_credits, bulk: true do |t|
      # Original column types are unsigned integer.
      t.change :id, :int, unsigned: false
      t.change :creator_id, :int, unsigned: false
      t.change :recipient_id, :int, unsigned: false

      t.remove :credit_type
    end
  end
end
