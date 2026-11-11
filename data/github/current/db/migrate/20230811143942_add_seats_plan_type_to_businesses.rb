# typed: true

class AddSeatsPlanTypeToBusinesses < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Usersd)

  def change
    add_column :businesses, :seats_plan_type, "tinyint", null: false, default: 0
  end
end
