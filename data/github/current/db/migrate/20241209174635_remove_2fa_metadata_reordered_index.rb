# typed: true

class Remove2faMetadataReorderedIndex < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :two_factor_requirement_metadata, bulk: true do |t|
      t.remove_index [:user_id, :state], name: "index_two_factor_requirement_metadata_on_user_id_and_state"
    end
  end
end
