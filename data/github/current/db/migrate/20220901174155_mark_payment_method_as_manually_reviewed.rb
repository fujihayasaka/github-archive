# typed: true
class MarkPaymentMethodAsManuallyReviewed < ActiveRecord::Migration[7.1]
  def change
    change_table(:payment_methods, bulk: true) do |t|
      t.column :manually_reviewed_at, :datetime, limit: 6
      t.column :manually_reviewed_by_id, :bigint, unsigned: true
      t.index :manually_reviewed_at
    end
  end
end
