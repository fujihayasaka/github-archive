# typed: true

class AddUserBreadthAdoptionMetrics < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    create_table :user_breadth_adoption_metrics, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.datetime :qualified_at, precision: 6
      t.datetime :last_qualified_at, precision: 6
      t.belongs_to :user, type: :bigint, unsigned: true, null: false, index: { unique: true }

      t.timestamps
    end
  end
end
