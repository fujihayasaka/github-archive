class AddFailedManifestMessages < ActiveRecord::Migration[5.2]
  def change
    create_table :dg_failed_manifest_messages, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.string :source
      t.integer :github_repository_id, index: true
      t.text :message
    end
  end
end
