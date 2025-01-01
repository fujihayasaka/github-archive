# typed: true
class AddKeepToWorkspaces < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Codespaces)

  def change
    change_table :workspaces, bulk: true do |t|
      t.boolean :keep, default: false, null: false
      t.remove :retention_expires_at
      t.virtual :retention_expires_at,
        type: :datetime,
        precision: 6,
        as: "if(keep = false and shutdown_at is not null and retention_period_minutes is not null, date_add(shutdown_at, interval retention_period_minutes minute), null)"
    end
  end
end
