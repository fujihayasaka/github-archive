class CreateInteractionLimits < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)

  def change
    create_table :interaction_limits, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      # Limits can target a repo/set of repos or a user
      t.column :target, :tinyint, null: false, unsigned: true

      t.column :user_id, :bigint, null: false, unsigned: true
      t.column :repository_id, :bigint, null: true, unsigned: true

      # Limits that target repo(s) can apply different types of restrictions
      t.column :restriction, :tinyint, null: true, unsigned: true

      t.datetime :expires_at, null: false, precision: 3

      # For user_or_repo.interaction_limit to find the current limit for a user/repo
      t.index [:target, :user_id, :repository_id], unique: true

      # For InteractionLimit.expired to clean up the expired ones
      t.index [:expires_at]

      t.timestamps
    end
  end
end
