class AddIndexForServiceNameOnProximaServiceIdentities < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Integrations)

  def change
    change_table :proxima_service_identities, bulk: true do |t|
      t.index [:service_name], unique: false
    end
  end
end
