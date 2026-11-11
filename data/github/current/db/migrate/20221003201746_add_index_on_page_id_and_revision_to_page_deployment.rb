# typed: true

# frozen _string _literal: true

class AddIndexOnPageIdAndRevisionToPageDeployment < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    add_index :page_deployments, [:page_id, :revision], unique: false,
      name: "index_page_deployments_on_page_id_and_revision"
  end
end
