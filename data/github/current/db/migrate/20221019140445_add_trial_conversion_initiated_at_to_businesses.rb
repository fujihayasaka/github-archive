# typed: true
class AddTrialConversionInitiatedAtToBusinesses < ActiveRecord::Migration[7.1]
  def change
    change_table :businesses, bulk: true do |t|
      t.column :trial_conversion_initiated_at, :datetime, precision: 6, null: true, after: :trial_completion_status
      t.index :trial_conversion_initiated_at
    end
  end
end
