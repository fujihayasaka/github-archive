# typed: true

class AddTrialDeletionDateToBusinesses < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :businesses, bulk: true do |t|
      t.column :trial_deleted_at, :datetime, precision: 6, null: true, after: :trial_expires_at
      t.index :trial_deleted_at
    end
  end
end
