# typed: true

class AddClientIndexToAuthenticationRecords < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::UsersBallast)

  def change
    change_table :authentication_records, bulk: true do |t|
      # replace existing index
      t.index [:user_id, :country_code, :client, :created_at], name:  "index_on_user_id_country_code_client_and_created_at"
      t.remove_index [:user_id, :country_code, :created_at], name: "authentication_records_on_user_id_country_code_and_created_at"
      # remove additional unneeded index
      t.remove_index [:user_id, :created_at], name: "index_authentication_records_on_user_id_and_created_at"
    end
  end
end
