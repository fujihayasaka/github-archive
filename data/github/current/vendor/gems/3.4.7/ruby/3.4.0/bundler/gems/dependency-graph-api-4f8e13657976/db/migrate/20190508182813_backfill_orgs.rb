class BackfillOrgs < ActiveRecord::Migration[5.2]
  def change
    create_table :dg_dep_insights_backfills, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.references :github_owner
      t.datetime :last_backfilled_at, index: true
      t.string :source
    end
  end
end
