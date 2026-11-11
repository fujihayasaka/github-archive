# typed: true

class CreateCustomPropertyUsagesTable < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    create_table :custom_property_usages, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :definition_id, unsigned: true, index: true, null: false
      t.string :consumer_id, null: false, limit: 150
      t.string :consumer_type, null: false, limit: 30
      t.string :property_value, null: false, limit: 75
    end
  end
end
