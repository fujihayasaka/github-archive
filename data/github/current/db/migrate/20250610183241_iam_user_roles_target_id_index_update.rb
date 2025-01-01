# typed: true
# frozen_string_literal: true

class IamUserRolesTargetIdIndexUpdate < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Iam)

  def change
    change_table :user_roles, bulk: true do |t|
      t.index [:target_id, :target_type, :actor_type, :conditions_target], unique: false, name: "index_user_roles_on_target_id_and_target_type_actor_conditions"
      t.remove_index [:target_id, :target_type], name: "index_user_roles_on_target_id_and_target_type"
    end
  end
end
