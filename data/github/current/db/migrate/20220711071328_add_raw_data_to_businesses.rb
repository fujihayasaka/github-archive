# typed: true

class AddRawDataToBusinesses < ActiveRecord::Migration[7.1]
  def change
    add_column :businesses, :raw_data, :blob
  end
end
