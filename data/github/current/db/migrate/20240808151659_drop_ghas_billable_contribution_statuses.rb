class DropGhasBillableContributionStatuses < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Collab)

  def change
    drop_table :ghas_billable_contribution_statuses do |t|
      t.bigint :user_id, null: false
      t.datetime :provisioned_at, null: false
      t.datetime :deprovisioned_at
    end
  end
end
