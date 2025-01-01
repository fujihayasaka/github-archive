# typed: true
# rubocop:disable GitHub/AvoidTypeBeforeId
class DropUserroleUniqueActor < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Iam)

  def up
    change_table(:user_roles, bulk: true) do |t|
      t.remove_index [:actor_id, :actor_type, :target_id, :target_type], unique: true, name: :idx_user_roles_actor_and_target
      t.index [:actor_id, :actor_type, :target_id, :target_type], name: :index_user_roles_on_actor_and_target
      t.remove_index [:role_id, :target_id, :target_type, :actor_type, :actor_id], name: :index_user_roles_on_role_target_type_actor
      t.index [:role_id, :target_id, :target_type, :actor_type, :actor_id], unique: true, name: :index_user_roles_on_role_target_type_actor
    end
  end

  def down
    change_table(:user_roles, bulk: true) do |t|
      t.remove_index [:actor_id, :actor_type, :target_id, :target_type], name: :index_user_roles_on_actor_and_target
      t.index  [:actor_id, :actor_type, :target_id, :target_type], unique: true, name: :idx_user_roles_actor_and_target
      t.remove_index [:role_id, :target_id, :target_type, :actor_type, :actor_id], unique: true, name: :index_user_roles_on_role_target_type_actor
      # the actor_type before actor_id is intentional. See https://github.com/github/github/pull/123226
      t.index [:role_id, :target_id, :target_type, :actor_type, :actor_id], name: :index_user_roles_on_role_target_type_actor
    end
  end
end
