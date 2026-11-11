# typed: true

class AddIndexToAbilitiesSubjectActorIds < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::IamAbilities)
  def change
    add_index :abilities,
              [:subject_id, :subject_type, :action, :actor_type, :priority, :actor_id],
              name: "subject_and_action_and_actor_type_and_priority_and_actor_id"
  end
end
