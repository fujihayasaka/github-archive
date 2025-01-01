class DropInteractionLimitsIdSeq < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::VT)

  def change
    drop_table :interaction_limits_id_seq
    drop_sequence :interaction_limits_id_seq
  end
end
