# typed: true
# frozen_string_literal: true

class AddConditionsToUserRoles < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Iam)

  def change
    change_table :user_roles, bulk: true do |t|
      t.column :conditions, :json, null: true
      t.column :conditions_target, :virtual, type: "varchar(16)", as: "(COALESCE(`conditions`->>'$.target','direct'))", stored: false
      t.column :conditions_target_ids, :virtual, type: "json", null: true, as: "(COALESCE(`conditions`->'$.target_ids'))", stored: false
    end
  end
end
