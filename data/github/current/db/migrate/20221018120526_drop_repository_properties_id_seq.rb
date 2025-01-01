# typed: true
class DropRepositoryPropertiesIdSeq < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::VT)

  def change
    drop_table :repository_properties_id_seq
  end
end
