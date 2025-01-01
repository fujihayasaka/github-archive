class TransitivePackageDependencies < ActiveRecord::Migration[5.2]
  def change
    create_table :dg_transitive_package_dependencies, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.references :package, null: false
      t.references :dependency, index: { name: "index_dg_transitive_package_dependenices_on_deps" }, null: false
    end
  end
end
