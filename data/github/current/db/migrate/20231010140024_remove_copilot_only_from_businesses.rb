class RemoveCopilotOnlyFromBusinesses < ActiveRecord::Migration[7.2]
  def change
    reversible do |direction|
      change_table :businesses, bulk: true do |t|
        direction.up do
          t.remove :copilot_only
          t.index :seats_plan_type
        end

        direction.down do
          t.boolean :copilot_only, null: false, default: false
          t.remove_index :seats_plan_type
        end
      end
    end
  end
end
