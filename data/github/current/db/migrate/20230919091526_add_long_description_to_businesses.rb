class AddLongDescriptionToBusinesses < ActiveRecord::Migration[7.1]
  def change
    reversible do |direction|
      change_table :businesses, bulk: true do |t|
        direction.up do
          t.mediumblob :long_description, null: true, after: :description
        end

        direction.down do
          t.remove :long_description
        end
      end
    end
  end
end
